import ShadowClientStreaming
import Testing
@testable import ShadowClientFeatureHome

@Test("Settings telemetry runtime preserves recovery hold across samples for same settings")
func settingsTelemetryRuntimePreservesRecoveryHold() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let runtime = SettingsDiagnosticsTelemetryRuntime(
        baseDependencies: .live(bridge: bridge)
    )
    let settings = ShadowClientAppSettings()

    let unstableModel = await runtime.ingest(
        snapshot: unstableSnapshot(),
        settings: settings
    )
    let firstStableModel = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 1_016),
        settings: settings
    )

    #expect(unstableModel.tone == .critical)
    #expect(firstStableModel.tone == .critical)
    #expect(firstStableModel.recoveryStableSamplesRemaining == 1)
    #expect(firstStableModel.targetBufferMs == 48)
}

@Test("Settings telemetry runtime resets mapping runtime when settings identity changes")
func settingsTelemetryRuntimeResetsWhenSettingsChange() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let runtime = SettingsDiagnosticsTelemetryRuntime(
        baseDependencies: .live(bridge: bridge)
    )

    let surroundPreferred = ShadowClientAppSettings(
        lowLatencyMode: false,
        preferHDR: true,
        preferSurroundAudio: true,
        showDiagnosticsHUD: true
    )
    let lowLatencyPreferred = ShadowClientAppSettings(
        lowLatencyMode: true,
        preferHDR: true,
        preferSurroundAudio: true,
        showDiagnosticsHUD: true
    )

    let surroundModel = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 2_000),
        settings: surroundPreferred
    )
    let lowLatencyModel = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 2_016),
        settings: lowLatencyPreferred
    )

    #expect(surroundModel.audioMode == .surround51)
    #expect(lowLatencyModel.audioMode == .stereo)
}

@Test("Settings telemetry runtime keeps recovery hold when only HUD visibility changes")
func settingsTelemetryRuntimeKeepsRecoveryOnHUDToggle() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let runtime = SettingsDiagnosticsTelemetryRuntime(
        baseDependencies: .live(bridge: bridge)
    )

    let hudShown = ShadowClientAppSettings(showDiagnosticsHUD: true)
    let hudHidden = ShadowClientAppSettings(showDiagnosticsHUD: false)

    _ = await runtime.ingest(
        snapshot: unstableSnapshot(),
        settings: hudShown
    )
    let stableAfterToggle = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 1_016),
        settings: hudHidden
    )

    #expect(stableAfterToggle.tone == .critical)
    #expect(stableAfterToggle.recoveryStableSamplesRemaining == 1)
    #expect(stableAfterToggle.targetBufferMs == 48)
}

private func unstableSnapshot() -> StreamingTelemetrySnapshot {
    StreamingTelemetrySnapshot(
        stats: .init(renderedFrames: 960, droppedFrames: 40, avSyncOffsetMilliseconds: 55.0),
        signal: .init(jitterMs: 80.0, packetLossPercent: 3.0),
        timestampMs: 1_000,
        dropBreakdown: .init(networkDroppedFrames: 20, pacerDroppedFrames: 20)
    )
}

private func stableSnapshot(timestampMs: Int) -> StreamingTelemetrySnapshot {
    StreamingTelemetrySnapshot(
        stats: .init(renderedFrames: 995, droppedFrames: 5, avSyncOffsetMilliseconds: 12.0),
        signal: .init(jitterMs: 3.0, packetLossPercent: 0.2),
        timestampMs: timestampMs,
        dropBreakdown: .init(networkDroppedFrames: 2, pacerDroppedFrames: 3)
    )
}
