import AVFoundation
import Foundation

enum ShadowClientRealtimeAudioPCMBufferGuard {
    private static let hardExtremeMagnitude: Float = 16.0
    private static let loudClipMagnitude: Float = 4.0
    private static let maximumNonFiniteRatio = 0.01
    private static let maximumExtremeRatio = 0.25
    private static let maximumLoudClipRatio = 0.2
    private static let minimumLikelyInt16ScaledMagnitude: Float = 8.0
    private static let minimumIntegerLikeRatio = 0.9
    private static let integerLikeEpsilon: Float = 0.0001

    static func isSafeForPlayback(_ pcmBuffer: AVAudioPCMBuffer) -> Bool {
        switch pcmBuffer.format.commonFormat {
        case .pcmFormatFloat32:
            return isSafeFloat32Buffer(pcmBuffer)
        case .pcmFormatInt16:
            return isSafeInt16Buffer(pcmBuffer)
        default:
            return false
        }
    }

    static func prepareForPlayback(_ pcmBuffer: AVAudioPCMBuffer) {
        switch pcmBuffer.format.commonFormat {
        case .pcmFormatFloat32:
            normalizeLikelyInt16ScaledFloat32BufferIfNeeded(pcmBuffer)
        case .pcmFormatInt16:
            break
        default:
            break
        }
    }

    static func replaceWithSilence(_ pcmBuffer: AVAudioPCMBuffer) {
        let frameLength = Int(pcmBuffer.frameLength)
        let channelCount = Int(pcmBuffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return
        }
        switch pcmBuffer.format.commonFormat {
        case .pcmFormatFloat32:
            replaceFloat32WithSilence(pcmBuffer)
        case .pcmFormatInt16:
            replaceInt16WithSilence(pcmBuffer)
        default:
            break
        }
    }

    private static func isSafeFloat32Buffer(_ pcmBuffer: AVAudioPCMBuffer) -> Bool {
        let frameLength = Int(pcmBuffer.frameLength)
        let channelCount = Int(pcmBuffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return false
        }
        normalizeLikelyInt16ScaledFloat32BufferIfNeeded(pcmBuffer)

        var nonFiniteSampleCount = 0
        var extremeSampleCount = 0
        var loudClipSampleCount = 0
        var totalSampleCount = 0

        if let channelData = pcmBuffer.floatChannelData {
            totalSampleCount = frameLength * channelCount
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

                    if magnitude > loudClipMagnitude {
                        loudClipSampleCount += 1
                        value = max(-1.0, min(1.0, value))
                        samples[frameIndex] = value
                        continue
                    }

                    if magnitude > 1.0 {
                        value = max(-1.0, min(1.0, value))
                        samples[frameIndex] = value
                    }
                }
            }
        } else {
            let audioBufferList = UnsafeMutableAudioBufferListPointer(
                pcmBuffer.mutableAudioBufferList
            )
            guard !audioBufferList.isEmpty else {
                return false
            }
            for audioBuffer in audioBufferList {
                guard let rawData = audioBuffer.mData else {
                    continue
                }
                let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
                guard sampleCount > 0 else {
                    continue
                }
                totalSampleCount += sampleCount
                let samples = rawData.assumingMemoryBound(to: Float.self)
                for sampleIndex in 0 ..< sampleCount {
                    var value = samples[sampleIndex]
                    if !value.isFinite {
                        nonFiniteSampleCount += 1
                        samples[sampleIndex] = 0
                        continue
                    }

                    let magnitude = abs(value)
                    if magnitude > hardExtremeMagnitude {
                        extremeSampleCount += 1
                        samples[sampleIndex] = value.sign == .minus ? -1.0 : 1.0
                        continue
                    }

                    if magnitude > loudClipMagnitude {
                        loudClipSampleCount += 1
                        value = max(-1.0, min(1.0, value))
                        samples[sampleIndex] = value
                        continue
                    }

                    if magnitude > 1.0 {
                        value = max(-1.0, min(1.0, value))
                        samples[sampleIndex] = value
                    }
                }
            }
            guard totalSampleCount > 0 else {
                return false
            }
        }

        let safeTotalSampleCount = Double(max(totalSampleCount, 1))
        let nonFiniteRatio = Double(nonFiniteSampleCount) / safeTotalSampleCount
        let extremeRatio = Double(extremeSampleCount) / safeTotalSampleCount
        let loudClipRatio = Double(loudClipSampleCount) / safeTotalSampleCount
        if nonFiniteRatio > maximumNonFiniteRatio ||
            extremeRatio > maximumExtremeRatio ||
            loudClipRatio > maximumLoudClipRatio
        {
            return false
        }
        return true
    }

    private static func normalizeLikelyInt16ScaledFloat32BufferIfNeeded(
        _ pcmBuffer: AVAudioPCMBuffer
    ) {
        let stats = float32Stats(pcmBuffer)
        guard stats.totalSampleCount > 0 else {
            return
        }

        let nonFiniteRatio = Double(stats.nonFiniteSampleCount) / Double(stats.totalSampleCount)
        guard nonFiniteRatio <= maximumNonFiniteRatio else {
            return
        }

        let finiteSampleCount = stats.totalSampleCount - stats.nonFiniteSampleCount
        guard finiteSampleCount > 0 else {
            return
        }
        let integerLikeRatio = Double(stats.nearIntegerSampleCount) / Double(finiteSampleCount)
        guard integerLikeRatio >= minimumIntegerLikeRatio else {
            return
        }

        let maximumMagnitude = stats.maximumMagnitude
        guard maximumMagnitude >= minimumLikelyInt16ScaledMagnitude else {
            return
        }
        guard maximumMagnitude <= Float(Int16.max) * 2.0 else {
            return
        }

        let scale = 1.0 / Float(Int16.max)
        applyScaleToFloat32Buffer(pcmBuffer, scale: scale)
    }

    private static func float32Stats(
        _ pcmBuffer: AVAudioPCMBuffer
    ) -> (
        totalSampleCount: Int,
        nonFiniteSampleCount: Int,
        nearIntegerSampleCount: Int,
        maximumMagnitude: Float
    ) {
        var totalSampleCount = 0
        var nonFiniteSampleCount = 0
        var nearIntegerSampleCount = 0
        var maximumMagnitude: Float = 0

        if let channelData = pcmBuffer.floatChannelData {
            let frameLength = Int(pcmBuffer.frameLength)
            let channelCount = Int(pcmBuffer.format.channelCount)
            totalSampleCount = frameLength * channelCount
            for channelIndex in 0 ..< channelCount {
                let samples = channelData[channelIndex]
                for frameIndex in 0 ..< frameLength {
                    let value = samples[frameIndex]
                    if !value.isFinite {
                        nonFiniteSampleCount += 1
                        continue
                    }
                    if abs(value.rounded() - value) <= integerLikeEpsilon {
                        nearIntegerSampleCount += 1
                    }
                    maximumMagnitude = max(maximumMagnitude, abs(value))
                }
            }
            return (totalSampleCount, nonFiniteSampleCount, nearIntegerSampleCount, maximumMagnitude)
        }

        let audioBufferList = UnsafeMutableAudioBufferListPointer(
            pcmBuffer.mutableAudioBufferList
        )
        guard !audioBufferList.isEmpty else {
            return (0, 0, 0, 0)
        }
        for audioBuffer in audioBufferList {
            guard let rawData = audioBuffer.mData else {
                continue
            }
            let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
            guard sampleCount > 0 else {
                continue
            }
            totalSampleCount += sampleCount
            let samples = rawData.assumingMemoryBound(to: Float.self)
            for sampleIndex in 0 ..< sampleCount {
                let value = samples[sampleIndex]
                if !value.isFinite {
                    nonFiniteSampleCount += 1
                    continue
                }
                if abs(value.rounded() - value) <= integerLikeEpsilon {
                    nearIntegerSampleCount += 1
                }
                maximumMagnitude = max(maximumMagnitude, abs(value))
            }
        }
        return (totalSampleCount, nonFiniteSampleCount, nearIntegerSampleCount, maximumMagnitude)
    }

    private static func applyScaleToFloat32Buffer(
        _ pcmBuffer: AVAudioPCMBuffer,
        scale: Float
    ) {
        guard scale.isFinite, scale > 0 else {
            return
        }

        if let channelData = pcmBuffer.floatChannelData {
            let frameLength = Int(pcmBuffer.frameLength)
            let channelCount = Int(pcmBuffer.format.channelCount)
            for channelIndex in 0 ..< channelCount {
                let samples = channelData[channelIndex]
                for frameIndex in 0 ..< frameLength {
                    let value = samples[frameIndex]
                    guard value.isFinite else {
                        continue
                    }
                    samples[frameIndex] = value * scale
                }
            }
            return
        }

        let audioBufferList = UnsafeMutableAudioBufferListPointer(
            pcmBuffer.mutableAudioBufferList
        )
        for audioBuffer in audioBufferList {
            guard let rawData = audioBuffer.mData else {
                continue
            }
            let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
            guard sampleCount > 0 else {
                continue
            }
            let samples = rawData.assumingMemoryBound(to: Float.self)
            for sampleIndex in 0 ..< sampleCount {
                let value = samples[sampleIndex]
                guard value.isFinite else {
                    continue
                }
                samples[sampleIndex] = value * scale
            }
        }
    }

    private static func isSafeInt16Buffer(_ pcmBuffer: AVAudioPCMBuffer) -> Bool {
        let frameLength = Int(pcmBuffer.frameLength)
        let channelCount = Int(pcmBuffer.format.channelCount)
        guard frameLength > 0, channelCount > 0 else {
            return false
        }

        if let channelData = pcmBuffer.int16ChannelData {
            for channelIndex in 0 ..< channelCount {
                let samples = channelData[channelIndex]
                for frameIndex in 0 ..< frameLength {
                    _ = samples[frameIndex]
                }
            }
            return true
        }

        let audioBufferList = UnsafeMutableAudioBufferListPointer(
            pcmBuffer.mutableAudioBufferList
        )
        guard !audioBufferList.isEmpty else {
            return false
        }
        var totalSampleCount = 0
        for audioBuffer in audioBufferList {
            guard let rawData = audioBuffer.mData else {
                continue
            }
            let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Int16>.size
            guard sampleCount > 0 else {
                continue
            }
            totalSampleCount += sampleCount
            let samples = rawData.assumingMemoryBound(to: Int16.self)
            for sampleIndex in 0 ..< sampleCount {
                _ = samples[sampleIndex]
            }
        }
        return totalSampleCount > 0
    }

    private static func replaceFloat32WithSilence(_ pcmBuffer: AVAudioPCMBuffer) {
        let frameLength = Int(pcmBuffer.frameLength)
        let channelCount = Int(pcmBuffer.format.channelCount)
        if let channelData = pcmBuffer.floatChannelData {
            for channelIndex in 0 ..< channelCount {
                let samples = channelData[channelIndex]
                for frameIndex in 0 ..< frameLength {
                    samples[frameIndex] = 0
                }
            }
            return
        }

        let audioBufferList = UnsafeMutableAudioBufferListPointer(
            pcmBuffer.mutableAudioBufferList
        )
        for audioBuffer in audioBufferList {
            guard let rawData = audioBuffer.mData else {
                continue
            }
            let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Float>.size
            guard sampleCount > 0 else {
                continue
            }
            let samples = rawData.assumingMemoryBound(to: Float.self)
            for sampleIndex in 0 ..< sampleCount {
                samples[sampleIndex] = 0
            }
        }
    }

    private static func replaceInt16WithSilence(_ pcmBuffer: AVAudioPCMBuffer) {
        let frameLength = Int(pcmBuffer.frameLength)
        let channelCount = Int(pcmBuffer.format.channelCount)
        if let channelData = pcmBuffer.int16ChannelData {
            for channelIndex in 0 ..< channelCount {
                let samples = channelData[channelIndex]
                for frameIndex in 0 ..< frameLength {
                    samples[frameIndex] = 0
                }
            }
            return
        }

        let audioBufferList = UnsafeMutableAudioBufferListPointer(
            pcmBuffer.mutableAudioBufferList
        )
        for audioBuffer in audioBufferList {
            guard let rawData = audioBuffer.mData else {
                continue
            }
            let sampleCount = Int(audioBuffer.mDataByteSize) / MemoryLayout<Int16>.size
            guard sampleCount > 0 else {
                continue
            }
            let samples = rawData.assumingMemoryBound(to: Int16.self)
            for sampleIndex in 0 ..< sampleCount {
                samples[sampleIndex] = 0
            }
        }
    }
}
