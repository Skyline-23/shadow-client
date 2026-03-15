import Testing
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
