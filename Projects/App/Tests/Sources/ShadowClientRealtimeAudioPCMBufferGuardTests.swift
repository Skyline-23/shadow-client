import AVFoundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Audio PCM guard rejects buffers with non-finite samples")
func audioPCMGuardRejectsNonFiniteSamples() {
    let buffer = makePCMBuffer(frames: [Float.nan, 0.25, -0.1, 0.05])

    let accepted = ShadowClientRealtimeAudioPCMBufferGuard.isSafeForPlayback(buffer)

    #expect(accepted == false)
    #expect(buffer.floatChannelData?[0][0] == 0)
}

@Test("Audio PCM guard rejects severe overrange float buffers")
func audioPCMGuardRejectsSevereOverrangeFloatBuffers() {
    let buffer = makePCMBuffer(frames: Array(repeating: 8.25, count: 256))

    let accepted = ShadowClientRealtimeAudioPCMBufferGuard.isSafeForPlayback(buffer)

    #expect(accepted == false)
}

@Test("Audio PCM guard normalizes likely int16-scaled float buffers")
func audioPCMGuardNormalizesLikelyInt16ScaledFloatBuffer() {
    let frames: [Float] = (0 ..< 512).map { index in
        index.isMultiple(of: 2) ? 12_000.0 : -9_000.0
    }
    let buffer = makePCMBuffer(frames: frames)

    let accepted = ShadowClientRealtimeAudioPCMBufferGuard.isSafeForPlayback(buffer)

    #expect(accepted == true)
    if let channelData = buffer.floatChannelData {
        #expect(abs(channelData[0][0]) <= 1.0)
        #expect(abs(channelData[0][1]) <= 1.0)
    } else {
        #expect(Bool(false))
    }
}

@Test("Audio PCM guard prepareForPlayback normalizes likely int16-scaled stereo float buffers")
func audioPCMGuardPrepareForPlaybackNormalizesLikelyInt16ScaledStereoFloatBuffer() {
    let frames: [Float] = (0 ..< 512).map { index in
        index.isMultiple(of: 2) ? 12_000.0 : -9_000.0
    }
    let buffer = makeInterleavedPCMBuffer(samples: frames, channels: 2)

    ShadowClientRealtimeAudioPCMBufferGuard.prepareForPlayback(buffer)

    let audioBufferList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    let baseAddress = audioBufferList.first?.mData?.assumingMemoryBound(to: Float.self)
    #expect(baseAddress != nil)
    if let baseAddress {
        #expect(abs(baseAddress[0]) <= 1.0)
        #expect(abs(baseAddress[1]) <= 1.0)
    }
}

@Test("Audio PCM guard normalizes low-amplitude int16-scaled float buffers")
func audioPCMGuardNormalizesLowAmplitudeInt16ScaledFloatBuffer() {
    let frames: [Float] = (0 ..< 512).map { index in
        switch index % 4 {
        case 0:
            return 12
        case 1:
            return -9
        case 2:
            return 7
        default:
            return -8
        }
    }
    let buffer = makePCMBuffer(frames: frames)

    let accepted = ShadowClientRealtimeAudioPCMBufferGuard.isSafeForPlayback(buffer)

    #expect(accepted == true)
    if let channelData = buffer.floatChannelData {
        #expect(abs(channelData[0][0]) <= 1.0)
        #expect(abs(channelData[0][1]) <= 1.0)
    } else {
        #expect(Bool(false))
    }
}

@Test("Audio PCM guard tolerates sparse extreme samples by clamping")
func audioPCMGuardToleratesSparseExtremeSamples() {
    var frames = Array(repeating: Float(0.12), count: 512)
    frames[17] = 32.0
    let buffer = makePCMBuffer(frames: frames)

    let accepted = ShadowClientRealtimeAudioPCMBufferGuard.isSafeForPlayback(buffer)

    #expect(accepted == true)
    #expect(buffer.floatChannelData?[0][17] == 1.0)
}

@Test("Audio PCM guard accepts valid buffers")
func audioPCMGuardAcceptsValidBuffer() {
    let frames: [Float] = (0 ..< 256).map { index in
        sin(Float(index) * 0.05) * 0.4
    }
    let buffer = makePCMBuffer(frames: frames)

    let accepted = ShadowClientRealtimeAudioPCMBufferGuard.isSafeForPlayback(buffer)

    #expect(accepted == true)
}

@Test("Audio PCM guard accepts interleaved float buffers")
func audioPCMGuardAcceptsInterleavedFloatBuffer() {
    let samples: [Float] = (0 ..< 512).map { index in
        sin(Float(index) * 0.03) * 0.5
    }
    let buffer = makeInterleavedPCMBuffer(samples: samples, channels: 2)

    let accepted = ShadowClientRealtimeAudioPCMBufferGuard.isSafeForPlayback(buffer)

    #expect(accepted == true)
}

@Test("Audio PCM guard accepts non-interleaved int16 buffers")
func audioPCMGuardAcceptsInt16Buffer() {
    let samples: [Int16] = (0 ..< 512).map { index in
        Int16((sin(Float(index) * 0.05) * 8_000.0).rounded())
    }
    let buffer = makeInt16PCMBuffer(samples: samples, channels: 2, interleaved: false)

    let accepted = ShadowClientRealtimeAudioPCMBufferGuard.isSafeForPlayback(buffer)

    #expect(accepted == true)
}

@Test("Audio PCM guard can silence int16 buffers")
func audioPCMGuardSilencesInt16Buffer() {
    let samples: [Int16] = (0 ..< 256).map { index in
        index.isMultiple(of: 2) ? 12_000 : -12_000
    }
    let buffer = makeInt16PCMBuffer(samples: samples, channels: 2, interleaved: false)

    ShadowClientRealtimeAudioPCMBufferGuard.replaceWithSilence(buffer)

    if let channelData = buffer.int16ChannelData {
        for channelIndex in 0 ..< Int(buffer.format.channelCount) {
            for frameIndex in 0 ..< Int(buffer.frameLength) {
                #expect(channelData[channelIndex][frameIndex] == 0)
            }
        }
    } else {
        #expect(Bool(false))
    }
}

private func makePCMBuffer(frames: [Float]) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 1,
        interleaved: false
    )!
    let frameCapacity = AVAudioFrameCount(max(1, frames.count))
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity)!
    buffer.frameLength = AVAudioFrameCount(frames.count)
    if let channelData = buffer.floatChannelData {
        for (index, value) in frames.enumerated() {
            channelData[0][index] = value
        }
    }
    return buffer
}

private func makeInt16PCMBuffer(
    samples: [Int16],
    channels: Int,
    interleaved: Bool
) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatInt16,
        sampleRate: 48_000,
        channels: AVAudioChannelCount(max(1, channels)),
        interleaved: interleaved
    )!
    let frameCount = max(1, samples.count / max(1, channels))
    let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(frameCount)
    )!
    buffer.frameLength = AVAudioFrameCount(frameCount)

    if !interleaved, let channelData = buffer.int16ChannelData {
        for frameIndex in 0 ..< frameCount {
            for channelIndex in 0 ..< channels {
                let sourceIndex = frameIndex * channels + channelIndex
                guard sourceIndex < samples.count else {
                    continue
                }
                channelData[channelIndex][frameIndex] = samples[sourceIndex]
            }
        }
        return buffer
    }

    let audioBufferList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    if let rawData = audioBufferList.first?.mData {
        let sampleCount = Int(audioBufferList[0].mDataByteSize) / MemoryLayout<Int16>.size
        let destination = rawData.assumingMemoryBound(to: Int16.self)
        let copyCount = min(sampleCount, samples.count)
        for index in 0 ..< copyCount {
            destination[index] = samples[index]
        }
    }
    return buffer
}

private func makeInterleavedPCMBuffer(samples: [Float], channels: Int) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: AVAudioChannelCount(max(1, channels)),
        interleaved: true
    )!
    let frameCount = max(1, samples.count / max(1, channels))
    let buffer = AVAudioPCMBuffer(
        pcmFormat: format,
        frameCapacity: AVAudioFrameCount(frameCount)
    )!
    buffer.frameLength = AVAudioFrameCount(frameCount)

    let audioBufferList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
    if let rawData = audioBufferList.first?.mData {
        let sampleCount = Int(audioBufferList[0].mDataByteSize) / MemoryLayout<Float>.size
        let destination = rawData.assumingMemoryBound(to: Float.self)
        let copyCount = min(sampleCount, samples.count)
        for index in 0 ..< copyCount {
            destination[index] = samples[index]
        }
    }
    return buffer
}
