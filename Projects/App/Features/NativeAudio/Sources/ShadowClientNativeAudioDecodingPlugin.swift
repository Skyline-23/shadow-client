import AVFoundation
import Accelerate
import Foundation
import ShadowClientFeatureHome

@_silgen_name("opus_multistream_decoder_create")
private func shadowClientOpusMultistreamDecoderCreate(
    _ sampleRate: Int32,
    _ channels: Int32,
    _ streamCount: Int32,
    _ coupledStreamCount: Int32,
    _ mapping: UnsafePointer<UInt8>?,
    _ errorCode: UnsafeMutablePointer<Int32>?
) -> OpaquePointer?

@_silgen_name("opus_multistream_decode_float")
private func shadowClientOpusMultistreamDecodeFloat(
    _ decoder: OpaquePointer?,
    _ data: UnsafePointer<UInt8>?,
    _ dataLength: Int32,
    _ pcm: UnsafeMutablePointer<Float>?,
    _ frameSize: Int32,
    _ decodeFEC: Int32
) -> Int32

@_silgen_name("opus_multistream_decoder_destroy")
private func shadowClientOpusMultistreamDecoderDestroy(_ decoder: OpaquePointer?)

@_silgen_name("opus_strerror")
private func shadowClientOpusStrError(_ errorCode: Int32) -> UnsafePointer<CChar>?

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

        let layout = Self.opusStreamLayout(for: channels)
        var errorCode: Int32 = 0
        let decoder = layout.mapping.withUnsafeBufferPointer { mappingBuffer in
            shadowClientOpusMultistreamDecoderCreate(
                Int32(sampleRate),
                Int32(channels),
                Int32(layout.streamCount),
                Int32(layout.coupledStreamCount),
                mappingBuffer.baseAddress,
                &errorCode
            )
        }

        guard let decoder, errorCode == 0 else {
            throw NSError(
                domain: "ShadowClientNativeOpusMultistreamDecoder",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not create multichannel Opus decoder (\(Self.opusErrorDescription(code: errorCode))).",
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
        shadowClientOpusMultistreamDecoderDestroy(decoder)
    }

    func decode(payload: Data) throws -> AVAudioPCMBuffer? {
        guard !payload.isEmpty else {
            return nil
        }

        let decodedFrameCount = payload.withUnsafeBytes { payloadBytes in
            let dataPointer = payloadBytes.bindMemory(to: UInt8.self).baseAddress
            return interleavedScratch.withUnsafeMutableBufferPointer { outputBuffer in
                shadowClientOpusMultistreamDecodeFloat(
                    decoder,
                    dataPointer,
                    Int32(payload.count),
                    outputBuffer.baseAddress,
                    maxFrameSamplesPerChannel,
                    0
                )
            }
        }

        if decodedFrameCount < 0 {
            throw NSError(
                domain: "ShadowClientNativeOpusMultistreamDecoder",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Multichannel Opus decode failed (\(Self.opusErrorDescription(code: decodedFrameCount))).",
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

        interleavedScratch.withUnsafeBufferPointer { sourceBuffer in
            guard let source = sourceBuffer.baseAddress else {
                return
            }
            for channelIndex in 0..<channels {
                cblas_scopy(
                    Int32(frameCount),
                    source.advanced(by: channelIndex),
                    Int32(channels),
                    channelData[channelIndex],
                    1
                )
            }
        }
        pcmBuffer.frameLength = AVAudioFrameCount(frameCount)
        return pcmBuffer
    }

    private static func opusErrorDescription(
        code: Int32
    ) -> String {
        guard let errorString = shadowClientOpusStrError(code) else {
            return "error code \(code)"
        }
        return String(cString: errorString)
    }

    private static func opusStreamLayout(
        for channels: Int
    ) -> (streamCount: Int, coupledStreamCount: Int, mapping: [UInt8]) {
        switch channels {
        case 6:
            // Standard Opus 5.1 mapping (RFC 7845 / mapping family 1).
            return (4, 2, [0, 4, 1, 2, 3, 5])
        case 8:
            // Standard Opus 7.1 mapping (mapping family 1).
            return (5, 3, [0, 6, 1, 2, 3, 4, 5, 7])
        default:
            let mappedChannels = max(1, channels)
            let mapping = (0..<mappedChannels).map { UInt8($0 & 0xFF) }
            return (mappedChannels, 0, mapping)
        }
    }
}
