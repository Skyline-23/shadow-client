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

@Test("Audio PCM guard rejects heavily clipped buffers")
func audioPCMGuardRejectsHeavilyClippedBuffers() {
    let buffer = makePCMBuffer(frames: Array(repeating: 1.7, count: 256))

    let accepted = ShadowClientRealtimeAudioPCMBufferGuard.isSafeForPlayback(buffer)

    #expect(accepted == false)
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
