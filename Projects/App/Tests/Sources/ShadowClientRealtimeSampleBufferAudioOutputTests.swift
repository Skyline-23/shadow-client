import Testing
@preconcurrency import CoreMedia
@testable import ShadowClientFeatureHome

@Test("Sample buffer pressure shedding follows Moonlight queue duration instead of renderer backlog")
func sampleBufferPressureSheddingUsesMoonlightQueueDuration() {
    let pendingDurationMs = ShadowClientRealtimeSampleBufferAudioOutput
        .pressureSheddingPendingDurationMs(
            moonlightQueuePendingDurationMs: 25,
            rendererPendingDurationMs: 174
        )

    #expect(pendingDurationMs == 25)
}

@Test("Sample buffer pressure shedding clamps negative Moonlight queue duration")
func sampleBufferPressureSheddingClampsNegativeQueueDuration() {
    let pendingDurationMs = ShadowClientRealtimeSampleBufferAudioOutput
        .pressureSheddingPendingDurationMs(
            moonlightQueuePendingDurationMs: -5,
            rendererPendingDurationMs: 174
        )

    #expect(pendingDurationMs == 0)
}

@Test("Sample buffer starvation reset triggers after timeline falls well behind playback")
func sampleBufferStarvationResetTriggersForLateTimeline() {
    let shouldReset = ShadowClientRealtimeSampleBufferAudioOutput
        .shouldResetTimelineForStarvation(
            nextPresentationTime: CMTime(seconds: 0, preferredTimescale: 1_000),
            currentTime: CMTime(seconds: 0.20, preferredTimescale: 1_000),
            startupThreshold: CMTime(seconds: 0.01, preferredTimescale: 1_000)
        )

    #expect(shouldReset)
}

@Test("Sample buffer starvation reset ignores short renderer lateness")
func sampleBufferStarvationResetIgnoresShortLateness() {
    let shouldReset = ShadowClientRealtimeSampleBufferAudioOutput
        .shouldResetTimelineForStarvation(
            nextPresentationTime: CMTime(seconds: 0, preferredTimescale: 1_000),
            currentTime: CMTime(seconds: 0.02, preferredTimescale: 1_000),
            startupThreshold: CMTime(seconds: 0.01, preferredTimescale: 1_000)
        )

    #expect(!shouldReset)
}
