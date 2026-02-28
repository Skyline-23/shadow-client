import AVFoundation
import Foundation
import ShadowClientFeatureHome
import SwiftOpus

public enum ShadowClientNativeAudioDecodingPlugin {
    private static let lock = NSLock()
    private static var isRegistered = false
    private static let compatibilityProfile = ShadowClientNativeOpusCompatibilityProfile.detect()

    static var currentCompatibilityProfile: ShadowClientNativeOpusCompatibilityProfile {
        compatibilityProfile
    }

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
                    channels: track.channelCount,
                    compatibilityProfile: compatibilityProfile
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
    let requiresPlaybackSafetyGuard = true

    private let decoder: OpusDecoder
    private let maximumSamplesPerChannel: Int
    private let minimumSamplesPerChannelStep: Int
    private let maximumDecodedSamplesPerChannel: Int
    private let maximumPayloadBytes: Int

    init(
        sampleRate: Int,
        channels: Int,
        compatibilityProfile: ShadowClientNativeOpusCompatibilityProfile
    ) throws {
        self.sampleRate = sampleRate
        self.channels = channels
        maximumPayloadBytes = max(512, compatibilityProfile.maximumSupportedPayloadBytes)

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
            guard compatibilityProfile.supportsSurroundDecoding(channelCount: channels) else {
                throw NSError(
                        domain: "ShadowClientNativeOpusDecoder",
                        code: 3,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Runtime libopus tag \(compatibilityProfile.resolvedRuntimeLibopusTag?.rawValue ?? "unresolved") does not support surround decode for \(channels) channels.",
                        ]
                    )
                }
            multistreamLayout = try OpusChannelLayout.standardSurround(for: channels)
        } else {
            multistreamLayout = nil
        }

        let configuration = try OpusDecoderConfiguration(
            sampleRate: opusSampleRate,
            channels: channels,
            pcmFormat: .float32,
            multistreamLayout: multistreamLayout
        )
        decoder = try OpusDecoder(configuration: configuration)
        maximumSamplesPerChannel = configuration.maximumSamplesPerChannel
        minimumSamplesPerChannelStep = max(1, sampleRate / 400)
        maximumDecodedSamplesPerChannel = min(
            maximumSamplesPerChannel,
            minimumSamplesPerChannelStep * 48
        )
        self.outputFormat = decoder.outputFormat
    }

    func decode(payload: Data) throws -> AVAudioPCMBuffer? {
        guard !payload.isEmpty else {
            return nil
        }
        return try decode(payload: payload, decodeFEC: false)
    }

    func decode(payload: Data, decodeFEC: Bool) throws -> AVAudioPCMBuffer? {
        guard !payload.isEmpty else {
            return nil
        }
        guard payload.count <= maximumPayloadBytes else {
            return nil
        }

        guard let decodedBuffer = try decoder.decodeToPCMBuffer(
            payload: payload,
            decodeFEC: decodeFEC
        ) else {
            return nil
        }

        let decodedFrameCount = Int(decodedBuffer.frameLength)
        guard decodedFrameCount > 0,
              decodedFrameCount <= maximumSamplesPerChannel,
              isLikelySupportedFrameCount(decodedFrameCount)
        else {
            return nil
        }
        return decodedBuffer
    }

    func decodePacketLossConcealment(samplesPerChannel: Int) throws -> AVAudioPCMBuffer? {
        let normalizedFrameCount = normalizedConcealmentFrameCount(samplesPerChannel)
        guard normalizedFrameCount > 0 else {
            return nil
        }

        if let concealmentBuffer = try decoder.concealToPCMBuffer(
            samplesPerChannel: normalizedFrameCount
        ) {
            let concealmentFrameCount = Int(concealmentBuffer.frameLength)
            guard concealmentFrameCount > 0,
                  concealmentFrameCount <= maximumSamplesPerChannel,
                  isLikelySupportedFrameCount(concealmentFrameCount)
            else {
                return makeSilentConcealmentBuffer(frameCount: normalizedFrameCount)
            }
            return concealmentBuffer
        }
        return makeSilentConcealmentBuffer(frameCount: normalizedFrameCount)
    }

    private func makeSilentConcealmentBuffer(frameCount requestedFrameCount: Int) -> AVAudioPCMBuffer? {
        let frameCount = min(requestedFrameCount, maximumDecodedSamplesPerChannel)
        guard frameCount > 0, isLikelySupportedFrameCount(frameCount) else {
            return nil
        }
        let frameCapacity = AVAudioFrameCount(frameCount)
        guard let concealmentBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: frameCapacity
        ) else {
            return nil
        }
        concealmentBuffer.frameLength = frameCapacity
        return concealmentBuffer
    }

    private func normalizedConcealmentFrameCount(_ requestedSamplesPerChannel: Int) -> Int {
        guard requestedSamplesPerChannel > 0 else {
            return 0
        }
        let bounded = min(maximumDecodedSamplesPerChannel, requestedSamplesPerChannel)
        let step = max(1, minimumSamplesPerChannelStep)
        let normalized = (bounded / step) * step
        return max(step, normalized)
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
