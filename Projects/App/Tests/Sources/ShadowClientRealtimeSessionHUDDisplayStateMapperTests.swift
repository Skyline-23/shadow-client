@testable import ShadowClientFeatureHome
import ShadowClientStreaming
import ShadowClientUI
import Testing

@Test("Realtime session HUD mapper hides HUD when toggle is disabled")
func realtimeSessionHUDMapperHidesWhenDisabled() {
    let model = ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
        showDiagnosticsHUD: false,
        diagnosticsModel: makeDiagnosticsModel(),
        controlRoundTripMs: 18,
        renderState: .rendering
    )

    #expect(model == nil)
}

@Test("Realtime session HUD mapper prioritizes telemetry model when available")
func realtimeSessionHUDMapperPrefersTelemetryModel() {
    let diagnosticsModel = makeDiagnosticsModel()
    let model = ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
        showDiagnosticsHUD: true,
        diagnosticsModel: diagnosticsModel,
        controlRoundTripMs: 18,
        renderState: .rendering
    )

    #expect(model == .telemetry(diagnosticsModel))
}

@Test("Realtime session HUD mapper emits bootstrap state while telemetry is pending")
func realtimeSessionHUDMapperEmitsBootstrapState() {
    let model = ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
        showDiagnosticsHUD: true,
        diagnosticsModel: nil,
        controlRoundTripMs: -7,
        renderState: .waitingForFirstFrame
    )

    #expect(model == .waitingForTelemetry(controlRoundTripMs: 0))
}

@Test("Realtime session HUD mapper prioritizes disconnected state")
func realtimeSessionHUDMapperPrioritizesDisconnectedState() {
    let model = ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
        showDiagnosticsHUD: true,
        diagnosticsModel: makeDiagnosticsModel(),
        controlRoundTripMs: 12,
        renderState: .disconnected("Connection reset by peer")
    )

    #expect(
        model == .connectionIssue(
            title: "Session Disconnected",
            message: "Connection reset by peer"
        )
    )
}

@Test("Realtime session HUD mapper prioritizes decoder failure state")
func realtimeSessionHUDMapperPrioritizesDecoderFailureState() {
    let model = ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
        showDiagnosticsHUD: true,
        diagnosticsModel: makeDiagnosticsModel(),
        controlRoundTripMs: 12,
        renderState: .failed("Could not create hardware decoder session")
    )

    #expect(
        model == .connectionIssue(
            title: "Session Error",
            message: "Could not create hardware decoder session"
        )
    )
}

@Test("Realtime session HUD mapper surfaces audio device issues")
func realtimeSessionHUDMapperSurfacesAudioDeviceIssue() {
    let model = ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
        showDiagnosticsHUD: true,
        diagnosticsModel: makeDiagnosticsModel(),
        controlRoundTripMs: 8,
        renderState: .rendering,
        audioOutputState: .deviceUnavailable("No default output device")
    )

    #expect(
        model == .connectionIssue(
            title: "Audio Device Unavailable",
            message: "No default output device"
        )
    )
}

@Test("Realtime session HUD mapper surfaces audio stream disconnect")
func realtimeSessionHUDMapperSurfacesAudioDisconnect() {
    let model = ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
        showDiagnosticsHUD: true,
        diagnosticsModel: makeDiagnosticsModel(),
        controlRoundTripMs: 8,
        renderState: .rendering,
        audioOutputState: .disconnected("Audio RTP receive failed")
    )

    #expect(
        model == .connectionIssue(
            title: "Audio Stream Disconnected",
            message: "Audio RTP receive failed"
        )
    )
}

@Test("Realtime session HUD mapper surfaces session permission issues ahead of telemetry")
func realtimeSessionHUDMapperSurfacesSessionPermissionIssue() {
    let model = ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
        showDiagnosticsHUD: true,
        diagnosticsModel: makeDiagnosticsModel(),
        controlRoundTripMs: 8,
        renderState: .rendering,
        sessionIssue: .init(
            title: "Clipboard Permission Required",
            message: "Grant Clipboard Read permission for this paired Lumen client."
        )
    )

    #expect(
        model == .connectionIssue(
            title: "Clipboard Permission Required",
            message: "Grant Clipboard Read permission for this paired Lumen client."
        )
    )
}

@Test("Realtime session HUD mapper surfaces host termination recovery issues ahead of telemetry")
func realtimeSessionHUDMapperSurfacesHostTerminationIssue() {
    let model = ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
        showDiagnosticsHUD: true,
        diagnosticsModel: makeDiagnosticsModel(),
        controlRoundTripMs: 8,
        renderState: .rendering,
        sessionIssue: .init(
            title: "Host Desktop Paused",
            message: "Lumen paused or closed the desktop session (0x80030023).\nReturn to the normal Windows desktop, dismiss the secure prompt or popup, then launch the session again."
        )
    )

    #expect(
        model == .connectionIssue(
            title: "Host Desktop Paused",
            message: "Lumen paused or closed the desktop session (0x80030023).\nReturn to the normal Windows desktop, dismiss the secure prompt or popup, then launch the session again."
        )
    )
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
