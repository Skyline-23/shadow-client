import AVFoundation
import Foundation

enum ShadowClientRealtimeAudioPCMBufferGuard {
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
                if magnitude > 4.0 {
                    extremeSampleCount += 1
                    samples[frameIndex] = 0
                    continue
                }

                if magnitude > 1.0 {
                    clippedSampleCount += 1
                    value = max(-1.0, min(1.0, value))
                    samples[frameIndex] = value
                }
            }
        }

        if nonFiniteSampleCount > 0 || extremeSampleCount > 0 {
            return false
        }

        let clippedRatio = Double(clippedSampleCount) / Double(max(totalSampleCount, 1))
        if clippedRatio > 0.9 {
            return false
        }

        return true
    }
}
