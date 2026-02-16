import Testing
@testable import ShadowClientStreaming

@Test("Telemetry pipeline requests quality reduction and increases buffer on first unstable snapshot")
func telemetryPipelineFirstUnstableSnapshotRequestsQualityReductionAndIncreasesBuffer() async {
    let pipeline = LowLatencyTelemetryPipeline(initialBufferMs: 40.0)
    let unstableSnapshot = StreamingTelemetrySnapshot(
        stats: StreamingStats(
            renderedFrames: 960,
            droppedFrames: 40,
            avSyncOffsetMilliseconds: 55.0
        ),
        signal: StreamingNetworkSignal(jitterMs: 80.0, packetLossPercent: 3.0),
        timestampMs: 1_000
    )

    let decision = await pipeline.ingest(unstableSnapshot)

    #expect(decision.targetBufferMs == 48.0)
    #expect(decision.action == .requestQualityReduction)
    #expect(decision.stabilityPasses == false)
}

@Test("Telemetry pipeline decreases buffer on stable low-jitter snapshot after prior unstable increase")
func telemetryPipelineSubsequentStableLowJitterSnapshotDecreasesBufferFromPreviousTarget() async {
    let pipeline = LowLatencyTelemetryPipeline(initialBufferMs: 40.0)
    let unstableSnapshot = StreamingTelemetrySnapshot(
        stats: StreamingStats(
            renderedFrames: 960,
            droppedFrames: 40,
            avSyncOffsetMilliseconds: 55.0
        ),
        signal: StreamingNetworkSignal(jitterMs: 80.0, packetLossPercent: 3.0),
        timestampMs: 1_000
    )
    let stableLowJitterSnapshot = StreamingTelemetrySnapshot(
        stats: StreamingStats(
            renderedFrames: 995,
            droppedFrames: 5,
            avSyncOffsetMilliseconds: 12.0
        ),
        signal: StreamingNetworkSignal(jitterMs: 3.0, packetLossPercent: 0.2),
        timestampMs: 1_016
    )

    let firstDecision = await pipeline.ingest(unstableSnapshot)
    let secondDecision = await pipeline.ingest(stableLowJitterSnapshot)

    #expect(firstDecision.targetBufferMs == 48.0)
    #expect(secondDecision.targetBufferMs == 46.0)
    #expect(secondDecision.targetBufferMs == firstDecision.targetBufferMs - 2.0)
    #expect(secondDecision.action == .holdQuality)
    #expect(secondDecision.stabilityPasses == true)
}

@Test("Telemetry pipeline keeps buffer unchanged for stable mid-jitter snapshot")
func telemetryPipelineStableMidJitterSnapshotKeepsBufferUnchanged() async {
    let pipeline = LowLatencyTelemetryPipeline(initialBufferMs: 40.0)
    let unstableSnapshot = StreamingTelemetrySnapshot(
        stats: StreamingStats(
            renderedFrames: 960,
            droppedFrames: 40,
            avSyncOffsetMilliseconds: 55.0
        ),
        signal: StreamingNetworkSignal(jitterMs: 80.0, packetLossPercent: 3.0),
        timestampMs: 1_000
    )
    let stableMidJitterSnapshot = StreamingTelemetrySnapshot(
        stats: StreamingStats(
            renderedFrames: 994,
            droppedFrames: 6,
            avSyncOffsetMilliseconds: 8.0
        ),
        signal: StreamingNetworkSignal(jitterMs: 18.0, packetLossPercent: 0.2),
        timestampMs: 1_016
    )

    let firstDecision = await pipeline.ingest(unstableSnapshot)
    let secondDecision = await pipeline.ingest(stableMidJitterSnapshot)

    #expect(firstDecision.targetBufferMs == 48.0)
    #expect(secondDecision.targetBufferMs == 48.0)
    #expect(secondDecision.targetBufferMs == firstDecision.targetBufferMs)
    #expect(secondDecision.action == .holdQuality)
    #expect(secondDecision.stabilityPasses == true)
}
