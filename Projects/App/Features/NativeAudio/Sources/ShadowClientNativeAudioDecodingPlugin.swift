import AVFoundation
import Darwin
import Foundation
import ShadowClientFeatureHome

public enum ShadowClientNativeAudioDecodingPlugin {
    private static let lock = NSLock()
    private static var isRegistered = false

    public static func registerDefaultDecoders() {
        lock.lock()
        defer { lock.unlock() }
        guard !isRegistered else {
            return
        }
        isRegistered = true

        ShadowClientRealtimeCustomAudioDecoderRegistry.register(
            provider: { track in
                guard track.codec == .opus, track.channelCount > 2 else {
                    return nil
                }
                return try ShadowClientNativeOpusMultistreamDecoder(
                    sampleRate: track.sampleRate,
                    channels: track.channelCount
                )
            }
        )
    }
}

private enum ShadowClientNativeAudioDecodingError: Error {
    case libraryUnavailable
    case missingSymbol(String)
}

private final class ShadowClientNativeLibOpus: @unchecked Sendable {
    typealias SurroundDecoderCreateFn = @convention(c) (
        Int32,
        Int32,
        Int32,
        UnsafeMutablePointer<Int32>?,
        UnsafeMutablePointer<Int32>?,
        UnsafeMutablePointer<UInt8>?,
        UnsafeMutablePointer<Int32>?
    ) -> OpaquePointer?

    typealias DecodeFloatFn = @convention(c) (
        OpaquePointer?,
        UnsafePointer<UInt8>?,
        Int32,
        UnsafeMutablePointer<Float>?,
        Int32,
        Int32
    ) -> Int32

    typealias DestroyFn = @convention(c) (OpaquePointer?) -> Void
    typealias ErrorStringFn = @convention(c) (Int32) -> UnsafePointer<CChar>?

    let handle: UnsafeMutableRawPointer
    let surroundDecoderCreate: SurroundDecoderCreateFn
    let decodeFloat: DecodeFloatFn
    let destroy: DestroyFn
    let errorString: ErrorStringFn?

    init() throws {
        guard let handle = Self.loadLibraryHandle() else {
            throw ShadowClientNativeAudioDecodingError.libraryUnavailable
        }
        self.handle = handle
        surroundDecoderCreate = try Self.loadSymbol(
            named: "opus_multistream_surround_decoder_create",
            from: handle
        )
        decodeFloat = try Self.loadSymbol(
            named: "opus_multistream_decode_float",
            from: handle
        )
        destroy = try Self.loadSymbol(
            named: "opus_multistream_decoder_destroy",
            from: handle
        )
        errorString = try? Self.loadSymbol(
            named: "opus_strerror",
            from: handle
        )
    }

    deinit {
        dlclose(handle)
    }

    static let shared: ShadowClientNativeLibOpus? = {
        try? ShadowClientNativeLibOpus()
    }()

    private static func loadLibraryHandle() -> UnsafeMutableRawPointer? {
        let candidates = [
            "libopus.dylib",
            "/opt/homebrew/lib/libopus.dylib",
            "/opt/homebrew/opt/opus/lib/libopus.dylib",
            "/usr/local/lib/libopus.dylib",
        ]
        for candidate in candidates {
            if let handle = dlopen(candidate, RTLD_NOW | RTLD_LOCAL) {
                return handle
            }
        }
        return nil
    }

    private static func loadSymbol<T>(
        named name: String,
        from handle: UnsafeMutableRawPointer
    ) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            throw ShadowClientNativeAudioDecodingError.missingSymbol(name)
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}

private enum ShadowClientNativeAudioFormatFactory {
    static func pcmFloatOutputFormat(
        sampleRate: Int,
        channels: Int
    ) -> AVAudioFormat? {
        if channels <= 2 {
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRate),
                channels: AVAudioChannelCount(channels),
                interleaved: false
            )
        }

        guard let channelLayoutData = channelLayoutData(for: channels) else {
            return nil
        }
        return AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
            AVChannelLayoutKey: channelLayoutData,
        ])
    }

    private static func channelLayoutData(for channels: Int) -> Data? {
        guard let channelLayout = AVAudioChannelLayout(
            layoutTag: channelLayoutTag(for: channels)
        ) else {
            return nil
        }
        return Data(
            bytes: channelLayout.layout,
            count: MemoryLayout<AudioChannelLayout>.size
        )
    }

    private static func channelLayoutTag(
        for channels: Int
    ) -> AudioChannelLayoutTag {
        switch channels {
        case 1:
            return kAudioChannelLayoutTag_Mono
        case 2:
            return kAudioChannelLayoutTag_Stereo
        case 6:
            return kAudioChannelLayoutTag_MPEG_5_1_D
        case 8:
            return kAudioChannelLayoutTag_MPEG_7_1_C
        default:
            return kAudioChannelLayoutTag_DiscreteInOrder | AudioChannelLayoutTag(channels)
        }
    }
}

private final class ShadowClientNativeOpusMultistreamDecoder: ShadowClientRealtimeCustomAudioDecoder {
    let codec: ShadowClientAudioCodec = .opus
    let sampleRate: Int
    let channels: Int
    let outputFormat: AVAudioFormat

    private let libopus: ShadowClientNativeLibOpus
    private let decoder: OpaquePointer
    private let maxFrameSamplesPerChannel: Int32 = 5_760
    private var interleavedScratch: [Float]

    init(sampleRate: Int, channels: Int) throws {
        self.sampleRate = sampleRate
        self.channels = channels

        guard let outputFormat = ShadowClientNativeAudioFormatFactory.pcmFloatOutputFormat(
            sampleRate: sampleRate,
            channels: channels
        ) else {
            throw NSError(
                domain: "ShadowClientNativeOpusMultistreamDecoder",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not create multichannel Opus output format.",
                ]
            )
        }
        self.outputFormat = outputFormat

        guard let libopus = ShadowClientNativeLibOpus.shared else {
            throw NSError(
                domain: "ShadowClientNativeOpusMultistreamDecoder",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "libopus is not available for multichannel Opus decoding.",
                ]
            )
        }
        self.libopus = libopus

        var streamCount: Int32 = 0
        var coupledStreamCount: Int32 = 0
        var mapping = [UInt8](repeating: 0, count: max(1, channels))
        var errorCode: Int32 = 0
        let decoder = mapping.withUnsafeMutableBufferPointer { mappingBuffer in
            libopus.surroundDecoderCreate(
                Int32(sampleRate),
                Int32(channels),
                1,
                &streamCount,
                &coupledStreamCount,
                mappingBuffer.baseAddress,
                &errorCode
            )
        }

        guard let decoder, errorCode == 0 else {
            throw NSError(
                domain: "ShadowClientNativeOpusMultistreamDecoder",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not create multichannel Opus decoder (\(Self.opusErrorDescription(code: errorCode, libopus: libopus))).",
                ]
            )
        }
        self.decoder = decoder
        interleavedScratch = [Float](
            repeating: 0,
            count: Int(maxFrameSamplesPerChannel) * channels
        )
    }

    deinit {
        libopus.destroy(decoder)
    }

    func decode(payload: Data) throws -> AVAudioPCMBuffer? {
        guard !payload.isEmpty else {
            return nil
        }

        let decodedFrameCount = payload.withUnsafeBytes { payloadBytes in
            let dataPointer = payloadBytes.bindMemory(to: UInt8.self).baseAddress
            return libopus.decodeFloat(
                decoder,
                dataPointer,
                Int32(payload.count),
                &interleavedScratch,
                maxFrameSamplesPerChannel,
                0
            )
        }

        if decodedFrameCount < 0 {
            throw NSError(
                domain: "ShadowClientNativeOpusMultistreamDecoder",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Multichannel Opus decode failed (\(Self.opusErrorDescription(code: decodedFrameCount, libopus: libopus))).",
                ]
            )
        }
        guard decodedFrameCount > 0 else {
            return nil
        }

        let frameCount = Int(decodedFrameCount)
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ), let channelData = pcmBuffer.floatChannelData
        else {
            return nil
        }

        for frameIndex in 0..<frameCount {
            let baseIndex = frameIndex * channels
            for channelIndex in 0..<channels {
                channelData[channelIndex][frameIndex] = interleavedScratch[baseIndex + channelIndex]
            }
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        return pcmBuffer
    }

    private static func opusErrorDescription(
        code: Int32,
        libopus: ShadowClientNativeLibOpus
    ) -> String {
        guard let errorString = libopus.errorString?(code) else {
            return "error code \(code)"
        }
        return String(cString: errorString)
    }
}
