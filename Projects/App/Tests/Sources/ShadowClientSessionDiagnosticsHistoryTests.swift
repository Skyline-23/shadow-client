@testable import ShadowClientFeatureHome
import ShadowClientStreaming
import ShadowClientUI
import Testing

@Test("Session diagnostics history caps sample count and clamps negative values")
func sessionDiagnosticsHistoryCapsAndClampsValues() {
    var history = ShadowClientSessionDiagnosticsHistory(maxSamples: 3)

    history.append(makeDiagnosticsModel(jitterMs: 10, frameDropPercent: -1.0, packetLossPercent: 1.0))
    history.append(makeDiagnosticsModel(jitterMs: 20, frameDropPercent: 2.5, packetLossPercent: -3.0))
    history.append(makeDiagnosticsModel(jitterMs: 30, frameDropPercent: 3.5, packetLossPercent: 4.0))
    history.append(makeDiagnosticsModel(jitterMs: 40, frameDropPercent: 4.5, packetLossPercent: 5.0))

    #expect(history.jitterMsSamples == [20.0, 30.0, 40.0])
    #expect(history.frameDropPercentSamples == [2.5, 3.5, 4.5])
    #expect(history.packetLossPercentSamples == [0.0, 4.0, 5.0])
}

@Test("Session diagnostics history tracks ping samples and keeps latest window")
func sessionDiagnosticsHistoryTracksPingSamples() {
    var history = ShadowClientSessionDiagnosticsHistory(maxSamples: 3)

    history.appendControlRoundTripMs(12)
    history.appendControlRoundTripMs(-5)
    history.appendControlRoundTripMs(nil)
    history.appendControlRoundTripMs(24)
    history.appendControlRoundTripMs(31)

    #expect(history.controlRoundTripMsSamples == [0.0, 24.0, 31.0])
}

@Test("Session diagnostics history ignores non-finite metrics independently")
func sessionDiagnosticsHistorySkipsNonFiniteMetricsIndependently() {
    var history = ShadowClientSessionDiagnosticsHistory(maxSamples: 4)

    history.append(makeDiagnosticsModel(jitterMs: 18, frameDropPercent: .nan, packetLossPercent: 1.5))
    history.append(makeDiagnosticsModel(jitterMs: 21, frameDropPercent: 2.0, packetLossPercent: .infinity))

    #expect(history.jitterMsSamples == [18.0, 21.0])
    #expect(history.frameDropPercentSamples == [2.0])
    #expect(history.packetLossPercentSamples == [1.5])
}

@Test("Session diagnostics history enforces a minimum sample limit")
func sessionDiagnosticsHistoryEnforcesMinimumSampleLimit() {
    var history = ShadowClientSessionDiagnosticsHistory(maxSamples: 0)

    history.append(makeDiagnosticsModel(jitterMs: 8, frameDropPercent: 0.5, packetLossPercent: 0.4))
    history.append(makeDiagnosticsModel(jitterMs: 9, frameDropPercent: 0.6, packetLossPercent: 0.3))

    #expect(history.jitterMsSamples == [9.0])
    #expect(history.frameDropPercentSamples == [0.6])
    #expect(history.packetLossPercentSamples == [0.3])
}

private func makeDiagnosticsModel(
    jitterMs: Int,
    frameDropPercent: Double,
    packetLossPercent: Double
) -> SettingsDiagnosticsHUDModel {
    let tick = HomeDiagnosticsTick(
        model: .init(
            bufferMs: 48,
            jitterMs: jitterMs,
            packetLossPercent: packetLossPercent,
            frameDropPercent: frameDropPercent,
            avSyncOffsetMs: 4,
            networkDroppedFrames: 1,
            pacerDroppedFrames: 0,
            recoveryStableSamplesRemaining: 0,
            tone: .warning
        ),
        sessionPlan: .init(
            settings: .init(
                hdrVideoMode: .off,
                audioMode: .stereo,
                targetBufferMs: 48,
                qualityReductionRequested: false,
                recoveryStableSamplesRemaining: 0
            ),
            shouldRenegotiateVideoPipeline: false,
            shouldRenegotiateAudioPipeline: false,
            shouldApplyQualityDropImmediately: false
        ),
        timestampMs: 1_000
    )

    return SettingsDiagnosticsHUDModel(tick: tick)
}
