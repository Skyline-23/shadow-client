import Testing
@testable import ShadowClientStreaming

@Test("QT telemetry mapping sums dropped components and preserves signal fields")
func qtTelemetrySampleMappingPreservesSignalAndAggregatesDroppedFrames() {
    let sample = MoonlightQTTelemetrySample(
        renderedFrames: 2_400,
        networkDroppedFrames: 12,
        pacerDroppedFrames: 8,
        jitterMs: 23.5,
        packetLossPercent: 1.75,
        avSyncOffsetMs: 18.0,
        timestampMs: 123_456
    )

    let snapshot = StreamingTelemetrySnapshot(qtSample: sample)

    #expect(snapshot.stats.renderedFrames == 2_400)
    #expect(snapshot.stats.droppedFrames == 20)
    #expect(snapshot.stats.avSyncOffsetMilliseconds == 18.0)
    #expect(snapshot.signal.jitterMs == 23.5)
    #expect(snapshot.signal.packetLossPercent == 1.75)
    #expect(snapshot.timestampMs == 123_456)
}

@Test("QT telemetry mapping clamps negative dropped frames so pipeline can ingest stable snapshot")
func qtTelemetrySampleMappingClampsNegativeDropsForDecisionPipeline() async {
    let sample = MoonlightQTTelemetrySample(
        renderedFrames: 240,
        networkDroppedFrames: -4,
        pacerDroppedFrames: -6,
        jitterMs: 4.0,
        packetLossPercent: 0.1,
        avSyncOffsetMs: 6.0,
        timestampMs: 2_000
    )

    let snapshot = StreamingTelemetrySnapshot(qtSample: sample)
    let pipeline = LowLatencyTelemetryPipeline(initialBufferMs: 40.0)
    let decision = await pipeline.ingest(snapshot)

    #expect(snapshot.stats.droppedFrames == 0)
    #expect(snapshot.stats.totalFrames >= 0)
    #expect(decision.action == .holdQuality)
    #expect(decision.stabilityPasses)
    #expect(decision.targetBufferMs == 38.0)
}
