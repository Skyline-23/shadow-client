import AVFoundation
import Foundation
import ShadowClientFeatureHome
import SwiftOpus
import os

public enum ShadowClientNativeAudioDecodingPlugin {
    private static let compatibilityProfile = ShadowClientNativeOpusCompatibilityProfile.detect()
    static let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "NativeAudioDecoding"
    )
    private actor RegistrationState {
        private var didRegister = false

        func ensureRegistered() async {
            guard !didRegister else {
                return
            }
            didRegister = true
            ShadowClientNativeAudioDecodingPlugin.logger.notice(
                "Registering native audio decoders runtime-libopus=\(compatibilityProfile.runtimeLibopusVersionString, privacy: .public) resolved-tag=\(compatibilityProfile.resolvedRuntimeLibopusTag?.rawValue ?? "unresolved", privacy: .public) surround=\(compatibilityProfile.supportsMultistreamLayout, privacy: .public)"
            )
            await ShadowClientRealtimeCustomAudioDecoderRegistry.register(
                provider: { track in
                    guard track.codec == .opus, track.channelCount > 0 else {
                        return nil
                    }
                    ShadowClientNativeAudioDecodingPlugin.logger.notice(
                        "Native Opus decoder requested sampleRate=\(track.sampleRate, privacy: .public) channels=\(track.channelCount, privacy: .public)"
                    )
                    return try ShadowClientNativeOpusDecoder(
                        sampleRate: track.sampleRate,
                        channels: track.channelCount,
                        compatibilityProfile: compatibilityProfile
                    )
                }
            )
        }
    }

    private static let registrationState = RegistrationState()

    static var currentCompatibilityProfile: ShadowClientNativeOpusCompatibilityProfile {
        compatibilityProfile
    }

    public static func ensureDefaultDecodersRegistered() async {
        await registrationState.ensureRegistered()
    }

    static func requiresPlaybackSafetyGuard(channels: Int) -> Bool {
        channels > 2
    }
}

enum ShadowClientNativeOpusStereoDecodePathHeuristics {
    static func shouldPreferInt16PromotedToFloat(
        floatPeak: Float,
        int16PeakNormalized: Float
    ) -> Bool {
        guard int16PeakNormalized >= 0.002 else {
            return false
        }
        return floatPeak <= 0.0005 && int16PeakNormalized >= max(floatPeak * 32, 0.002)
    }

    static func shouldPreferFloat32(
        floatPeak: Float,
        int16PeakNormalized: Float
    ) -> Bool {
        guard floatPeak >= 0.002 else {
            return false
        }
        return floatPeak >= int16PeakNormalized * 0.5
    }
}

private final class ShadowClientNativeOpusDecoder: ShadowClientRealtimeCustomAudioDecoder {
    private enum StereoDecodePath {
        case undecided(remainingComparisons: Int)
        case float32
        case int16PromotedToFloat
    }

    let codec: ShadowClientAudioCodec = .opus
    let sampleRate: Int
    let channels: Int
    let outputFormat: AVAudioFormat
    let requiresPlaybackSafetyGuard: Bool

    private let floatDecoder: OpusDecoder
    private let int16Decoder: OpusDecoder?
    private let maximumSamplesPerChannel: Int
    private let minimumSamplesPerChannelStep: Int
    private let maximumDecodedSamplesPerChannel: Int
    private let maximumPayloadBytes: Int
    private var stereoDecodePath: StereoDecodePath

    init(
        sampleRate: Int,
        channels: Int,
        compatibilityProfile: ShadowClientNativeOpusCompatibilityProfile
    ) throws {
        self.sampleRate = sampleRate
        self.channels = channels
        self.requiresPlaybackSafetyGuard =
            ShadowClientNativeAudioDecodingPlugin.requiresPlaybackSafetyGuard(
                channels: channels
            )
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

        let floatConfiguration = try OpusDecoderConfiguration(
            sampleRate: opusSampleRate,
            channels: channels,
            pcmFormat: .float32,
            multistreamLayout: multistreamLayout
        )
        floatDecoder = try OpusDecoder(configuration: floatConfiguration)
        if channels <= 2 {
            let int16Configuration = try OpusDecoderConfiguration(
                sampleRate: opusSampleRate,
                channels: channels,
                pcmFormat: .int16,
                multistreamLayout: multistreamLayout
            )
            int16Decoder = try OpusDecoder(configuration: int16Configuration)
            stereoDecodePath = .undecided(remainingComparisons: 12)
        } else {
            int16Decoder = nil
            stereoDecodePath = .float32
        }
        maximumSamplesPerChannel = floatConfiguration.maximumSamplesPerChannel
        minimumSamplesPerChannelStep = max(1, sampleRate / 400)
        maximumDecodedSamplesPerChannel = min(
            maximumSamplesPerChannel,
            minimumSamplesPerChannelStep * 48
        )
        self.outputFormat = floatDecoder.outputFormat
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

        guard let decodedBuffer = try decodePreferredPCMBuffer(
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

        if let concealmentBuffer = try concealPreferredPCMBuffer(
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

    private func decodePreferredPCMBuffer(
        payload: Data,
        decodeFEC: Bool
    ) throws -> AVAudioPCMBuffer? {
        switch stereoDecodePath {
        case .float32:
            return try floatDecoder.decodeToPCMBuffer(payload: payload, decodeFEC: decodeFEC)
        case .int16PromotedToFloat:
            guard let int16Buffer = try int16Decoder?.decodeToPCMBuffer(payload: payload, decodeFEC: decodeFEC) else {
                return nil
            }
            return Self.promoteInt16PCMBufferToFloat(int16Buffer, outputFormat: outputFormat)
        case let .undecided(remainingComparisons):
            let floatBuffer = try floatDecoder.decodeToPCMBuffer(payload: payload, decodeFEC: decodeFEC)
            let int16Buffer = try int16Decoder?.decodeToPCMBuffer(payload: payload, decodeFEC: decodeFEC)
            evaluateStereoDecodePath(
                floatBuffer: floatBuffer,
                int16Buffer: int16Buffer,
                decodeFEC: decodeFEC,
                payloadLength: payload.count,
                remainingComparisons: remainingComparisons
            )
            switch stereoDecodePath {
            case .int16PromotedToFloat:
                guard let int16Buffer else {
                    return floatBuffer
                }
                return Self.promoteInt16PCMBufferToFloat(int16Buffer, outputFormat: outputFormat)
            case .float32, .undecided:
                return floatBuffer
            }
        }
    }

    private func concealPreferredPCMBuffer(samplesPerChannel: Int) throws -> AVAudioPCMBuffer? {
        switch stereoDecodePath {
        case .float32:
            return try floatDecoder.concealToPCMBuffer(samplesPerChannel: samplesPerChannel)
        case .int16PromotedToFloat:
            guard let int16Buffer = try int16Decoder?.concealToPCMBuffer(samplesPerChannel: samplesPerChannel) else {
                return nil
            }
            return Self.promoteInt16PCMBufferToFloat(int16Buffer, outputFormat: outputFormat)
        case let .undecided(remainingComparisons):
            let floatBuffer = try floatDecoder.concealToPCMBuffer(samplesPerChannel: samplesPerChannel)
            let int16Buffer = try int16Decoder?.concealToPCMBuffer(samplesPerChannel: samplesPerChannel)
            evaluateStereoDecodePath(
                floatBuffer: floatBuffer,
                int16Buffer: int16Buffer,
                decodeFEC: false,
                payloadLength: 0,
                remainingComparisons: remainingComparisons,
                source: "plc"
            )
            switch stereoDecodePath {
            case .int16PromotedToFloat:
                guard let int16Buffer else {
                    return floatBuffer
                }
                return Self.promoteInt16PCMBufferToFloat(int16Buffer, outputFormat: outputFormat)
            case .float32, .undecided:
                return floatBuffer
            }
        }
    }

    private func evaluateStereoDecodePath(
        floatBuffer: AVAudioPCMBuffer?,
        int16Buffer: AVAudioPCMBuffer?,
        decodeFEC: Bool,
        payloadLength: Int,
        remainingComparisons: Int,
        source: StaticString = "packet"
    ) {
        let floatPeak = Self.peakAbsFloat(floatBuffer)
        let int16Peak = Self.peakAbsInt16(int16Buffer)
        let int16PeakNormalized = Float(int16Peak) / Float(Int16.max)

        ShadowClientNativeAudioDecodingPlugin.logger.notice(
            "Native Opus stereo path compare source=\(source, privacy: .public) decodeFEC=\(decodeFEC, privacy: .public) payload-bytes=\(payloadLength, privacy: .public) remaining=\(remainingComparisons, privacy: .public) float-peak=\(floatPeak, privacy: .public) int16-peak=\(int16Peak, privacy: .public) int16-normalized=\(int16PeakNormalized, privacy: .public)"
        )

        if floatBuffer == nil, int16Buffer != nil {
            stereoDecodePath = .int16PromotedToFloat
            ShadowClientNativeAudioDecodingPlugin.logger.notice(
                "Native Opus stereo decode path selected int16-promoted-to-float because float decode returned nil"
            )
            return
        }

        if int16Buffer == nil, floatBuffer != nil {
            stereoDecodePath = .float32
            ShadowClientNativeAudioDecodingPlugin.logger.notice(
                "Native Opus stereo decode path kept float32 because int16 probe returned nil"
            )
            return
        }

        if ShadowClientNativeOpusStereoDecodePathHeuristics.shouldPreferInt16PromotedToFloat(
            floatPeak: floatPeak,
            int16PeakNormalized: int16PeakNormalized
        ) {
            stereoDecodePath = .int16PromotedToFloat
            ShadowClientNativeAudioDecodingPlugin.logger.notice(
                "Native Opus stereo decode path selected int16-promoted-to-float after energy comparison"
            )
            return
        }

        if ShadowClientNativeOpusStereoDecodePathHeuristics.shouldPreferFloat32(
            floatPeak: floatPeak,
            int16PeakNormalized: int16PeakNormalized
        ) {
            stereoDecodePath = .float32
            ShadowClientNativeAudioDecodingPlugin.logger.notice(
                "Native Opus stereo decode path kept float32 after energy comparison"
            )
            return
        }

        if remainingComparisons <= 1 {
            stereoDecodePath = .float32
            ShadowClientNativeAudioDecodingPlugin.logger.notice(
                "Native Opus stereo decode path defaulted to float32 after exhausting comparison budget"
            )
        } else {
            stereoDecodePath = .undecided(remainingComparisons: remainingComparisons - 1)
        }
    }

    private static func peakAbsFloat(_ pcmBuffer: AVAudioPCMBuffer?) -> Float {
        guard let pcmBuffer,
              pcmBuffer.format.commonFormat == .pcmFormatFloat32,
              let channelData = pcmBuffer.floatChannelData
        else {
            return 0
        }

        let frameCount = Int(pcmBuffer.frameLength)
        let channelCount = Int(pcmBuffer.format.channelCount)
        var peak: Float = 0
        for channel in 0 ..< channelCount {
            for frame in 0 ..< frameCount {
                peak = max(peak, abs(channelData[channel][frame]))
            }
        }
        return peak
    }

    private static func peakAbsInt16(_ pcmBuffer: AVAudioPCMBuffer?) -> Int {
        guard let pcmBuffer,
              pcmBuffer.format.commonFormat == .pcmFormatInt16,
              let channelData = pcmBuffer.int16ChannelData
        else {
            return 0
        }

        let frameCount = Int(pcmBuffer.frameLength)
        let channelCount = Int(pcmBuffer.format.channelCount)
        var peak = 0
        for channel in 0 ..< channelCount {
            for frame in 0 ..< frameCount {
                peak = max(peak, Int(abs(Int(channelData[channel][frame]))))
            }
        }
        return peak
    }

    private static func promoteInt16PCMBufferToFloat(
        _ pcmBuffer: AVAudioPCMBuffer,
        outputFormat: AVAudioFormat
    ) -> AVAudioPCMBuffer? {
        guard pcmBuffer.format.commonFormat == .pcmFormatInt16,
              let sourceChannels = pcmBuffer.int16ChannelData,
              let floatBuffer = AVAudioPCMBuffer(
                  pcmFormat: outputFormat,
                  frameCapacity: pcmBuffer.frameCapacity
              ),
              let destinationChannels = floatBuffer.floatChannelData
        else {
            return nil
        }

        let frameCount = Int(pcmBuffer.frameLength)
        let channelCount = Int(pcmBuffer.format.channelCount)
        let scale = 1.0 / Float(Int16.max)
        for channel in 0 ..< channelCount {
            let source = sourceChannels[channel]
            let destination = destinationChannels[channel]
            for frame in 0 ..< frameCount {
                destination[frame] = Float(source[frame]) * scale
            }
        }
        floatBuffer.frameLength = pcmBuffer.frameLength
        return floatBuffer
    }
}
