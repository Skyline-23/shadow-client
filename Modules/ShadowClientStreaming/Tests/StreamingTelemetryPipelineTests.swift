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
    #expect(decision.recoveryStableSamplesRemaining == 2)
}

@Test("Telemetry pipeline keeps reduced quality for first stable sample after instability before lowering buffer")
func telemetryPipelineRecoveryGateKeepsReducedQualityBeforeBufferDecrease() async {
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
    let thirdDecision = await pipeline.ingest(stableLowJitterSnapshot)

    #expect(firstDecision.targetBufferMs == 48.0)
    #expect(secondDecision.targetBufferMs == 48.0)
    #expect(secondDecision.action == .requestQualityReduction)
    #expect(secondDecision.stabilityPasses == true)
    #expect(secondDecision.recoveryStableSamplesRemaining == 1)
    #expect(thirdDecision.targetBufferMs == 46.0)
    #expect(thirdDecision.targetBufferMs == secondDecision.targetBufferMs - 2.0)
    #expect(thirdDecision.action == .holdQuality)
    #expect(thirdDecision.stabilityPasses == true)
    #expect(thirdDecision.recoveryStableSamplesRemaining == 0)
}

@Test("Telemetry pipeline exits recovery gate after sustained stable mid-jitter samples")
func telemetryPipelineStableMidJitterExitsRecoveryGateAfterSecondSample() async {
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
    let thirdDecision = await pipeline.ingest(stableMidJitterSnapshot)

    #expect(firstDecision.targetBufferMs == 48.0)
    #expect(secondDecision.targetBufferMs == 48.0)
    #expect(secondDecision.targetBufferMs == firstDecision.targetBufferMs)
    #expect(secondDecision.action == .requestQualityReduction)
    #expect(secondDecision.stabilityPasses == true)
    #expect(secondDecision.recoveryStableSamplesRemaining == 1)
    #expect(thirdDecision.targetBufferMs == 48.0)
    #expect(thirdDecision.action == .holdQuality)
    #expect(thirdDecision.stabilityPasses == true)
    #expect(thirdDecision.recoveryStableSamplesRemaining == 0)
}

@Test("Telemetry pipeline honors configurable stable sample threshold before recovery release")
func telemetryPipelineHonorsCustomRecoveryStableSampleThreshold() async {
    let pipeline = LowLatencyTelemetryPipeline(
        initialBufferMs: 40.0,
        qualityRecoveryStableSampleThreshold: 3
    )
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

    _ = await pipeline.ingest(unstableSnapshot)
    let firstStableDecision = await pipeline.ingest(stableLowJitterSnapshot)
    let secondStableDecision = await pipeline.ingest(stableLowJitterSnapshot)
    let thirdStableDecision = await pipeline.ingest(stableLowJitterSnapshot)

    #expect(firstStableDecision.targetBufferMs == 48.0)
    #expect(firstStableDecision.action == .requestQualityReduction)
    #expect(firstStableDecision.recoveryStableSamplesRemaining == 2)
    #expect(secondStableDecision.targetBufferMs == 48.0)
    #expect(secondStableDecision.action == .requestQualityReduction)
    #expect(secondStableDecision.recoveryStableSamplesRemaining == 1)
    #expect(thirdStableDecision.targetBufferMs == 46.0)
    #expect(thirdStableDecision.action == .holdQuality)
    #expect(thirdStableDecision.recoveryStableSamplesRemaining == 0)
}
