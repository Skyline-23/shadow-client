import AVFoundation
import Testing
@testable import ShadowClientFeatureHome
import ShadowClientFeatureSession

@Test("Low-latency stereo output prefers audio engine backend")
func lowLatencyStereoOutputPrefersAudioEngineBackend() {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 2,
        interleaved: false
    )!

    #expect(
        ShadowClientAudioOutputBackendKit.preferredBackend(
            format: format,
            synchronizationPolicy: .lowLatency
        ) == .audioEngine
    )
}

@Test("Video-synchronized stereo output keeps sample buffer backend")
func videoSynchronizedStereoOutputKeepsSampleBufferBackend() {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 2,
        interleaved: false
    )!

    #expect(
        ShadowClientAudioOutputBackendKit.preferredBackend(
            format: format,
            synchronizationPolicy: .videoSynchronized
        ) == .sampleBufferRenderer
    )
}

@Test("Low-latency surround output keeps sample buffer backend")
func lowLatencySurroundOutputKeepsSampleBufferBackend() {
    let format = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 48_000,
        channels: 6,
        interleaved: false
    )!

    #expect(
        ShadowClientAudioOutputBackendKit.preferredBackend(
            format: format,
            synchronizationPolicy: .lowLatency
        ) == .sampleBufferRenderer
    )
}
