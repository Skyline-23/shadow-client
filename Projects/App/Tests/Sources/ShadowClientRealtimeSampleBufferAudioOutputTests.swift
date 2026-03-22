import Testing
@preconcurrency import CoreMedia
@testable import ShadowClientFeatureHome

@Test("Sample buffer pressure shedding tracks the more backlogged output stage")
func sampleBufferPressureSheddingUsesMostBackloggedOutputStage() {
    let pendingDurationMs = ShadowClientRealtimeSampleBufferAudioOutput
        .pressureSheddingPendingDurationMs(
            moonlightQueuePendingDurationMs: 25,
            rendererPendingDurationMs: 174
        )

    #expect(pendingDurationMs == 174)
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

@Test("Sample buffer starvation reset ignores brief 40ms renderer clock jitter")
func sampleBufferStarvationResetIgnoresBriefClockJitter() {
    let shouldReset = ShadowClientRealtimeSampleBufferAudioOutput
        .shouldResetTimelineForStarvation(
            nextPresentationTime: CMTime(seconds: 0, preferredTimescale: 1_000),
            currentTime: CMTime(seconds: 0.04, preferredTimescale: 1_000),
            startupThreshold: CMTime(seconds: 0.01, preferredTimescale: 1_000)
        )

    #expect(!shouldReset)
}

@Test("Sample buffer starvation reset still trips once renderer stall exceeds steady-state floor")
func sampleBufferStarvationResetTripsAfterSustainedStall() {
    let shouldReset = ShadowClientRealtimeSampleBufferAudioOutput
        .shouldResetTimelineForStarvation(
            nextPresentationTime: CMTime(seconds: 0, preferredTimescale: 1_000),
            currentTime: CMTime(seconds: 0.13, preferredTimescale: 1_000),
            startupThreshold: CMTime(seconds: 0.01, preferredTimescale: 1_000)
        )

    #expect(shouldReset)
}

@Test("Sample buffer pressure shedding defers while renderer backlog is still below startup threshold")
func sampleBufferPressureSheddingDefersWhenRendererBacklogIsThin() {
    let decision = ShadowClientRealtimeSampleBufferAudioOutput.pressureSheddingDecision(
        hasStartedTimeline: true,
        nextPresentationTime: CMTime(seconds: 1.005, preferredTimescale: 1_000),
        currentTime: CMTime(seconds: 1.000, preferredTimescale: 1_000),
        startupThreshold: CMTime(seconds: 0.010, preferredTimescale: 1_000),
        pressureSheddingGraceUntilTime: CMTime(seconds: 0.900, preferredTimescale: 1_000)
    )

    #expect(decision.shouldDefer)
    #expect(!decision.shouldClearExpiredGrace)
}

@Test("Sample buffer pressure shedding clears expired grace once renderer backlog is healthy")
func sampleBufferPressureSheddingClearsExpiredGraceWhenBacklogRecovered() {
    let decision = ShadowClientRealtimeSampleBufferAudioOutput.pressureSheddingDecision(
        hasStartedTimeline: true,
        nextPresentationTime: CMTime(seconds: 1.050, preferredTimescale: 1_000),
        currentTime: CMTime(seconds: 1.000, preferredTimescale: 1_000),
        startupThreshold: CMTime(seconds: 0.010, preferredTimescale: 1_000),
        pressureSheddingGraceUntilTime: CMTime(seconds: 0.900, preferredTimescale: 1_000)
    )

    #expect(!decision.shouldDefer)
    #expect(decision.shouldClearExpiredGrace)
}
