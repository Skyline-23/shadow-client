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
    private let minimumSamplesPerChannelStep: Int
    private let maximumDecodedSamplesPerChannel: Int
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
        minimumSamplesPerChannelStep = max(1, sampleRate / 400)
        maximumDecodedSamplesPerChannel = min(
            maximumSamplesPerChannel,
            minimumSamplesPerChannelStep * 48
        )
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
        guard payload.count <= 4_096 else {
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
            guard isLikelySupportedFrameCount(decodedFrameCount) else {
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

    private func isLikelySupportedFrameCount(_ decodedFrameCount: Int) -> Bool {
        guard decodedFrameCount > 0 else {
            return false
        }
        guard decodedFrameCount <= maximumDecodedSamplesPerChannel else {
            return false
        }
        return decodedFrameCount.isMultiple(of: minimumSamplesPerChannelStep)
    }
}
