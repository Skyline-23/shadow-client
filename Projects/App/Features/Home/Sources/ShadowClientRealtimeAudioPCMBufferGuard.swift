import AVFoundation
import Foundation

enum ShadowClientRealtimeAudioPCMBufferGuard {
    private static let hardExtremeMagnitude: Float = 16.0
    private static let maximumNonFiniteRatio = 0.01
    private static let maximumExtremeRatio = 0.25
    private static let maximumClippedRatio = 0.995
    private static let clippedSampleGrace = 256

    static func isSafeForPlayback(_ pcmBuffer: AVAudioPCMBuffer) -> Bool {
        guard pcmBuffer.format.commonFormat == .pcmFormatFloat32 else {
            return false
        }

        let frameLength = Int(pcmBuffer.frameLength)
        let channelCount = Int(pcmBuffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return false
        }
        guard let channelData = pcmBuffer.floatChannelData else {
            return false
        }

        var nonFiniteSampleCount = 0
        var extremeSampleCount = 0
        var clippedSampleCount = 0
        let totalSampleCount = frameLength * channelCount

        for channelIndex in 0 ..< channelCount {
            let samples = channelData[channelIndex]
            for frameIndex in 0 ..< frameLength {
                var value = samples[frameIndex]
                if !value.isFinite {
                    nonFiniteSampleCount += 1
                    samples[frameIndex] = 0
                    continue
                }

                let magnitude = abs(value)
                if magnitude > hardExtremeMagnitude {
                    extremeSampleCount += 1
                    samples[frameIndex] = value.sign == .minus ? -1.0 : 1.0
                    continue
                }

                if magnitude > 1.0 {
                    clippedSampleCount += 1
                    value = max(-1.0, min(1.0, value))
                    samples[frameIndex] = value
                }
            }
        }

        let safeTotalSampleCount = Double(max(totalSampleCount, 1))
        let nonFiniteRatio = Double(nonFiniteSampleCount) / safeTotalSampleCount
        let extremeRatio = Double(extremeSampleCount) / safeTotalSampleCount
        if nonFiniteRatio > maximumNonFiniteRatio || extremeRatio > maximumExtremeRatio {
            return false
        }

        let clippedRatio = Double(clippedSampleCount) / safeTotalSampleCount
        let clippedGraceRatio = min(0.1, Double(clippedSampleGrace) / safeTotalSampleCount)
        let clippedThreshold = min(
            0.9995,
            maximumClippedRatio + (clippedGraceRatio * 0.05)
        )
        if clippedRatio > clippedThreshold {
            return false
        }

        return true
    }

    static func replaceWithSilence(_ pcmBuffer: AVAudioPCMBuffer) {
        let frameLength = Int(pcmBuffer.frameLength)
        let channelCount = Int(pcmBuffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return
        }
        guard let channelData = pcmBuffer.floatChannelData else {
            return
        }

        for channelIndex in 0 ..< channelCount {
            let samples = channelData[channelIndex]
            for frameIndex in 0 ..< frameLength {
                samples[frameIndex] = 0
            }
        }
    }
}
