import Testing
@testable import ShadowClientCore

@Test("Input RTT p95 gate is inclusive at 35ms")
func inputRTTP95GateThresholds() {
    let gate = InputRTTP95Gate(thresholdMilliseconds: 35.0)

    #expect(gate.evaluate(p95Milliseconds: 35.0).passes)
    #expect(!gate.evaluate(p95Milliseconds: 35.1).passes)
}

@Test("Frame drop gate enforces <= 1%")
func frameDropGateThresholds() {
    let gate = FrameDropRateGate(thresholdPercent: 1.0)

    #expect(gate.evaluate(droppedFrames: 10, totalFrames: 1_000).passes)
    #expect(!gate.evaluate(droppedFrames: 11, totalFrames: 1_000).passes)
}

@Test("AV sync gate enforces absolute <= 40ms")
func avSyncGateThresholds() {
    let gate = AVSyncGate(thresholdMilliseconds: 40.0)

    #expect(gate.evaluate(offsetMilliseconds: 40.0).passes)
    #expect(gate.evaluate(offsetMilliseconds: -40.0).passes)
    #expect(!gate.evaluate(offsetMilliseconds: 40.1).passes)
}
