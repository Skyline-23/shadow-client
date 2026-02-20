@testable import ShadowClientFeatureHome
import ShadowClientStreaming
import ShadowClientUI
import Testing

@Test("Realtime session HUD mapper hides HUD when toggle is disabled")
func realtimeSessionHUDMapperHidesWhenDisabled() {
    let model = ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
        showDiagnosticsHUD: false,
        diagnosticsModel: makeDiagnosticsModel(),
        controlRoundTripMs: 18
    )

    #expect(model == nil)
}

@Test("Realtime session HUD mapper prioritizes telemetry model when available")
func realtimeSessionHUDMapperPrefersTelemetryModel() {
    let diagnosticsModel = makeDiagnosticsModel()
    let model = ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
        showDiagnosticsHUD: true,
        diagnosticsModel: diagnosticsModel,
        controlRoundTripMs: 18
    )

    #expect(model == .telemetry(diagnosticsModel))
}

@Test("Realtime session HUD mapper emits bootstrap state while telemetry is pending")
func realtimeSessionHUDMapperEmitsBootstrapState() {
    let model = ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
        showDiagnosticsHUD: true,
        diagnosticsModel: nil,
        controlRoundTripMs: -7
    )

    #expect(model == .waitingForTelemetry(controlRoundTripMs: 0))
}

private func makeDiagnosticsModel() -> SettingsDiagnosticsHUDModel {
    let tick = HomeDiagnosticsTick(
        model: .init(
            bufferMs: 50,
            jitterMs: 22,
            packetLossPercent: 1.1,
            frameDropPercent: 0.3,
            avSyncOffsetMs: 5,
            networkDroppedFrames: 2,
            pacerDroppedFrames: 1,
            recoveryStableSamplesRemaining: 0,
            tone: .healthy
        ),
        sessionPlan: .init(
            settings: .init(
                hdrVideoMode: .off,
                audioMode: .stereo,
                targetBufferMs: 50,
                qualityReductionRequested: false,
                recoveryStableSamplesRemaining: 0
            ),
            shouldRenegotiateVideoPipeline: false,
            shouldRenegotiateAudioPipeline: false,
            shouldApplyQualityDropImmediately: false
        ),
        timestampMs: 10
    )

    return SettingsDiagnosticsHUDModel(tick: tick)
}
