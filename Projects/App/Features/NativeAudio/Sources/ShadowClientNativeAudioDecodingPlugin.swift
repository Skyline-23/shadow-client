import AVFoundation
import Foundation
import ShadowClientFeatureHome
import SwiftOpus

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
                guard track.codec == .opus, track.channelCount > 0 else {
                    return nil
                }
                return try ShadowClientNativeOpusDecoder(
                    sampleRate: track.sampleRate,
                    channels: track.channelCount
                )
            }
        )
    }
}

private final class ShadowClientNativeOpusDecoder: ShadowClientRealtimeCustomAudioDecoder {
    let codec: ShadowClientAudioCodec = .opus
    let sampleRate: Int
    let channels: Int
    let outputFormat: AVAudioFormat
    let requiresPlaybackSafetyGuard = false

    private let decoder: OpusDecoder
    private let maximumSamplesPerChannel: Int
    private let expectedFrameSizesPerChannel: Set<Int>
    private let decodeLock = NSLock()
    private var int16DecodeScratch: [Int16]
    private let int16ToFloatScale = 1.0 / Float(Int16.max)

    init(sampleRate: Int, channels: Int) throws {
        self.sampleRate = sampleRate
        self.channels = channels

        guard let opusSampleRate = OpusSampleRate(exactly: sampleRate) else {
            throw NSError(
                domain: "ShadowClientNativeOpusDecoder",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Unsupported Opus sample rate: \(sampleRate)",
                ]
            )
        }

        let multistreamLayout: OpusChannelLayout?
        if channels > 2 {
            multistreamLayout = try OpusChannelLayout.standardSurround(for: channels)
        } else {
            multistreamLayout = nil
        }

        let configuration = try OpusDecoderConfiguration(
            sampleRate: opusSampleRate,
            channels: channels,
            pcmFormat: .int16,
            multistreamLayout: multistreamLayout
        )
        decoder = try OpusDecoder(configuration: configuration)
        maximumSamplesPerChannel = configuration.maximumSamplesPerChannel
        expectedFrameSizesPerChannel = Self.expectedFrameSizesPerChannel(sampleRate: sampleRate)
        int16DecodeScratch = [Int16](
            repeating: 0,
            count: max(1, maximumSamplesPerChannel * max(1, channels))
        )
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(max(1, channels)),
            interleaved: false
        ) else {
            throw NSError(
                domain: "ShadowClientNativeOpusDecoder",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Failed to create Float32 output format.",
                ]
            )
        }
        self.outputFormat = outputFormat
    }

    func decode(payload: Data) throws -> AVAudioPCMBuffer? {
        guard !payload.isEmpty else {
            return nil
        }
        guard isLikelyValidOpusPayload(payload) else {
            return nil
        }

        return try decodeLock.withLock {
            let decodedFrameCount = try int16DecodeScratch.withUnsafeMutableBufferPointer { scratchBuffer in
                try decoder.decodeInterleavedInt16(
                    payload: payload,
                    decodeFEC: false,
                    into: scratchBuffer
                )
            }
            guard decodedFrameCount > 0 else {
                return nil
            }
            guard decodedFrameCount <= maximumSamplesPerChannel else {
                return nil
            }
            guard expectedFrameSizesPerChannel.contains(decodedFrameCount) else {
                return nil
            }

            let frameCapacity = AVAudioFrameCount(decodedFrameCount)
            guard let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: frameCapacity
            ), let channelData = pcmBuffer.floatChannelData
            else {
                return nil
            }

            let channelCount = max(1, channels)
            for channelIndex in 0 ..< channelCount {
                let destination = channelData[channelIndex]
                var sourceIndex = channelIndex
                for frameIndex in 0 ..< decodedFrameCount {
                    destination[frameIndex] = Float(int16DecodeScratch[sourceIndex]) * int16ToFloatScale
                    sourceIndex += channelCount
                }
            }

            pcmBuffer.frameLength = frameCapacity
            return pcmBuffer
        }
    }

    private func isLikelyValidOpusPayload(_ payload: Data) -> Bool {
        guard !payload.isEmpty else {
            return false
        }
        guard payload.count <= 1_500 else {
            return false
        }

        let toc = payload[payload.startIndex]
        switch toc & 0x03 {
        case 0, 1, 2:
            return true
        case 3:
            guard payload.count >= 2 else {
                return false
            }
            let encodedFrameCount = Int(payload[payload.startIndex + 1] & 0x3F)
            return encodedFrameCount > 0 && encodedFrameCount <= 48
        default:
            return false
        }
    }

    private static func expectedFrameSizesPerChannel(sampleRate: Int) -> Set<Int> {
        let durationsMs = [2.5, 5.0, 10.0, 20.0, 40.0, 60.0]
        return Set(
            durationsMs.map { duration in
                max(1, Int((Double(sampleRate) * (duration / 1_000.0)).rounded()))
            }
        )
    }
}
