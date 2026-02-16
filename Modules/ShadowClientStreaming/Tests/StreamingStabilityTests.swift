import Testing
@testable import ShadowClientStreaming

@Test("Streaming checker passes when frame drop and AV sync are within gates")
func streamingStabilityPassesAtThresholds() {
    let checker = StreamingStabilityChecker()
    let report = checker.evaluate(
        .init(renderedFrames: 990, droppedFrames: 10, avSyncOffsetMilliseconds: 40.0)
    )

    #expect(report.frameDrop.passes)
    #expect(report.avSync.passes)
    #expect(report.passes)
}

@Test("Streaming checker fails when frame drop exceeds 1%")
func streamingStabilityFailsOnFrameDrop() {
    let checker = StreamingStabilityChecker()
    let report = checker.evaluate(
        .init(renderedFrames: 970, droppedFrames: 30, avSyncOffsetMilliseconds: 10.0)
    )

    #expect(!report.frameDrop.passes)
    #expect(!report.passes)
}

@Test("Streaming checker fails when AV sync exceeds 40ms")
func streamingStabilityFailsOnAVSync() {
    let checker = StreamingStabilityChecker()
    let report = checker.evaluate(
        .init(renderedFrames: 995, droppedFrames: 5, avSyncOffsetMilliseconds: 41.0)
    )

    #expect(report.frameDrop.passes)
    #expect(!report.avSync.passes)
    #expect(!report.passes)
}

@Test("Adaptive jitter buffer increases on jitter spike and caps at maximum")
func adaptiveJitterBufferCapsAtMaximumOnSpike() {
    let policy = AdaptiveJitterBufferPolicy(
        minimumBufferMs: 20,
        maximumBufferMs: 60,
        increaseStepMs: 15,
        decreaseStepMs: 5,
        packetLossGuardPercent: 3.0
    )
    let controller = AdaptiveJitterBufferController(policy: policy)
    let signal = StreamingNetworkSignal(jitterMs: 120.0, packetLossPercent: 0.2)

    let nextBufferMs = controller.nextBufferMs(currentBufferMs: 50, signal: signal)

    #expect(nextBufferMs == 60)
}

@Test("Adaptive jitter buffer decreases toward minimum under sustained low jitter")
func adaptiveJitterBufferDecreasesTowardMinimumOnSustainedLowJitter() {
    let policy = AdaptiveJitterBufferPolicy(
        minimumBufferMs: 20,
        maximumBufferMs: 80,
        increaseStepMs: 10,
        decreaseStepMs: 5,
        packetLossGuardPercent: 3.0
    )
    let controller = AdaptiveJitterBufferController(policy: policy)
    let lowJitterSignal = StreamingNetworkSignal(jitterMs: 2.0, packetLossPercent: 0.1)

    var bufferMs = 45
    for _ in 0..<10 {
        bufferMs = controller.nextBufferMs(currentBufferMs: bufferMs, signal: lowJitterSignal)
    }

    #expect(bufferMs == 20)
}

@Test("Adaptive jitter buffer does not decrease when packet loss exceeds guard")
func adaptiveJitterBufferPacketLossGuardPreventsDecrease() {
    let policy = AdaptiveJitterBufferPolicy(
        minimumBufferMs: 20,
        maximumBufferMs: 80,
        increaseStepMs: 10,
        decreaseStepMs: 5,
        packetLossGuardPercent: 2.0
    )
    let controller = AdaptiveJitterBufferController(policy: policy)
    let lossySignal = StreamingNetworkSignal(jitterMs: 2.0, packetLossPercent: 4.5)

    let currentBufferMs = 40
    let nextBufferMs = controller.nextBufferMs(currentBufferMs: currentBufferMs, signal: lossySignal)

    #expect(nextBufferMs >= currentBufferMs)
}

@Test("Adaptive jitter buffer stays unchanged for healthy stable signal")
func adaptiveJitterBufferRemainsStableForHealthySignal() {
    let policy = AdaptiveJitterBufferPolicy(
        minimumBufferMs: 20,
        maximumBufferMs: 80,
        increaseStepMs: 10,
        decreaseStepMs: 5,
        packetLossGuardPercent: 2.0
    )
    let controller = AdaptiveJitterBufferController(policy: policy)
    let stableSignal = StreamingNetworkSignal(jitterMs: 18.0, packetLossPercent: 0.2)

    let nextBufferMs = controller.nextBufferMs(currentBufferMs: 40, signal: stableSignal)

    #expect(nextBufferMs == 40)
}

@Test("Adaptive jitter buffer increases for packet-loss spike even when jitter is low")
func adaptiveJitterBufferIncreasesOnPacketLossSpikeWithLowJitter() {
    let policy = AdaptiveJitterBufferPolicy(
        minimumBufferMs: 20,
        maximumBufferMs: 80,
        increaseStepMs: 8,
        decreaseStepMs: 2,
        packetLossGuardPercent: 2.0
    )
    let controller = AdaptiveJitterBufferController(policy: policy)
    let lowJitterLossySignal = StreamingNetworkSignal(jitterMs: 4.0, packetLossPercent: 2.3)

    let nextBufferMs = controller.nextBufferMs(currentBufferMs: 40, signal: lowJitterLossySignal)

    #expect(nextBufferMs == 48)
}
