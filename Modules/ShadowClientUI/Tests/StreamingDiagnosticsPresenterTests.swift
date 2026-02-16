import ShadowClientStreaming
import Testing
@testable import ShadowClientUI

@Test("Diagnostics presenter emits critical tone when decision requests quality reduction")
func diagnosticsPresenterCriticalToneWhenQualityReductionRequested() {
    let presenter = StreamingDiagnosticsPresenter()
    let decision = LowLatencyStreamingDecision(
        targetBufferMs: 48.0,
        action: .requestQualityReduction,
        stabilityPasses: false
    )
    let signal = StreamingNetworkSignal(jitterMs: 80.0, packetLossPercent: 3.0)
    let stats = StreamingStats(
        renderedFrames: 960,
        droppedFrames: 40,
        avSyncOffsetMilliseconds: 55.0
    )
    let expectedFrameDropPercent = (Double(stats.droppedFrames) / Double(stats.totalFrames)) * 100.0

    let model = presenter.makeModel(decision: decision, signal: signal, stats: stats)

    #expect(model.bufferMs == 48)
    #expect(model.jitterMs == 80)
    #expect(model.packetLossPercent == 3.0)
    #expect(model.frameDropPercent == expectedFrameDropPercent)
    #expect(model.avSyncOffsetMs == 55)
    #expect(model.recoveryStableSamplesRemaining == 0)
    #expect(model.tone == .critical)
}

@Test("Diagnostics presenter emits healthy tone when stability passes and decision holds quality")
func diagnosticsPresenterHealthyToneWhenStableAndHoldingQuality() {
    let presenter = StreamingDiagnosticsPresenter()
    let decision = LowLatencyStreamingDecision(
        targetBufferMs: 38.0,
        action: .holdQuality,
        stabilityPasses: true
    )
    let signal = StreamingNetworkSignal(jitterMs: 3.0, packetLossPercent: 0.2)
    let stats = StreamingStats(
        renderedFrames: 995,
        droppedFrames: 5,
        avSyncOffsetMilliseconds: 12.0
    )
    let expectedFrameDropPercent = (Double(stats.droppedFrames) / Double(stats.totalFrames)) * 100.0

    let model = presenter.makeModel(decision: decision, signal: signal, stats: stats)

    #expect(model.bufferMs == 38)
    #expect(model.jitterMs == 3)
    #expect(model.packetLossPercent == 0.2)
    #expect(model.frameDropPercent == expectedFrameDropPercent)
    #expect(model.avSyncOffsetMs == 12)
    #expect(model.recoveryStableSamplesRemaining == 0)
    #expect(model.tone == .healthy)
}

@Test("Diagnostics presenter preserves recovery stable sample remaining count from decision")
func diagnosticsPresenterPreservesRecoveryStableSampleRemainingCount() {
    let presenter = StreamingDiagnosticsPresenter()
    let decision = LowLatencyStreamingDecision(
        targetBufferMs: 48.0,
        action: .requestQualityReduction,
        stabilityPasses: true,
        recoveryStableSamplesRemaining: 1
    )
    let signal = StreamingNetworkSignal(jitterMs: 9.0, packetLossPercent: 0.4)
    let stats = StreamingStats(
        renderedFrames: 990,
        droppedFrames: 10,
        avSyncOffsetMilliseconds: 10.0
    )

    let model = presenter.makeModel(decision: decision, signal: signal, stats: stats)

    #expect(model.recoveryStableSamplesRemaining == 1)
    #expect(model.tone == .critical)
}
