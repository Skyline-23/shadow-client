import Testing
@testable import ShadowClientStreaming

@Test("Low-latency controller requests quality reduction when stability fails under high jitter")
func lowLatencyControllerRequestsQualityReductionForUnstableHighJitter() {
    let controller = makeLowLatencyController()
    let currentBufferMs = 40.0
    let stats = StreamingStats(
        renderedFrames: 960,
        droppedFrames: 40,
        avSyncOffsetMilliseconds: 55.0
    )
    let signal = StreamingNetworkSignal(jitterMs: 80.0, packetLossPercent: 3.0)

    let decision = controller.decide(
        currentBufferMs: currentBufferMs,
        stats: stats,
        signal: signal
    )

    #expect(decision.targetBufferMs == 48.0)
    #expect(decision.action == .requestQualityReduction)
    #expect(decision.stabilityPasses == false)
}

@Test("Low-latency controller decreases buffer and holds quality for stable low jitter low loss")
func lowLatencyControllerDecreasesBufferForStableLowJitterAndLowLoss() {
    let controller = makeLowLatencyController()
    let currentBufferMs = 40.0
    let stats = StreamingStats(
        renderedFrames: 995,
        droppedFrames: 5,
        avSyncOffsetMilliseconds: 12.0
    )
    let signal = StreamingNetworkSignal(jitterMs: 3.0, packetLossPercent: 0.2)

    let decision = controller.decide(
        currentBufferMs: currentBufferMs,
        stats: stats,
        signal: signal
    )

    #expect(decision.targetBufferMs == 38.0)
    #expect(decision.action == .holdQuality)
    #expect(decision.stabilityPasses == true)
}

@Test("Low-latency controller keeps buffer unchanged and holds quality for stable mid-jitter conditions")
func lowLatencyControllerKeepsBufferUnchangedForStableMidJitter() {
    let controller = makeLowLatencyController()
    let currentBufferMs = 40.0
    let stats = StreamingStats(
        renderedFrames: 994,
        droppedFrames: 6,
        avSyncOffsetMilliseconds: 8.0
    )
    let signal = StreamingNetworkSignal(jitterMs: 18.0, packetLossPercent: 0.2)

    let decision = controller.decide(
        currentBufferMs: currentBufferMs,
        stats: stats,
        signal: signal
    )

    #expect(decision.targetBufferMs == 40.0)
    #expect(decision.action == .holdQuality)
    #expect(decision.stabilityPasses == true)
}

private func makeLowLatencyController() -> LowLatencyStreamingController {
    let stabilityChecker = StreamingStabilityChecker()
    let jitterBufferController = AdaptiveJitterBufferController(
        policy: AdaptiveJitterBufferPolicy(
            minimumBufferMs: 16.0,
            maximumBufferMs: 120.0,
            increaseStepMs: 8.0,
            decreaseStepMs: 2.0,
            packetLossGuardPercent: 2.0,
            jitterSpikeThresholdMs: 45.0,
            lowJitterThresholdMs: 5.0,
            lowPacketLossPercent: 0.5
        )
    )

    return LowLatencyStreamingController(
        stabilityChecker: stabilityChecker,
        jitterBufferController: jitterBufferController
    )
}
