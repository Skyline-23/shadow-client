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
        showDiagnosticsHUD: true,
        audioConfiguration: .surround71
    )
    let lowLatencyPreferred = ShadowClientAppSettings(
        lowLatencyMode: true,
        preferHDR: true,
        showDiagnosticsHUD: true,
        audioConfiguration: .surround71
    )

    let surroundModel = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 2_000),
        settings: surroundPreferred
    )
    let lowLatencyModel = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 2_016),
        settings: lowLatencyPreferred
    )

    #expect(surroundModel.audioMode == StreamAudioMode.surround51)
    #expect(lowLatencyModel.audioMode == StreamAudioMode.stereo)
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

@Test("Settings telemetry runtime reports sample interval for sequential samples")
func settingsTelemetryRuntimeReportsSampleInterval() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let runtime = SettingsDiagnosticsTelemetryRuntime(
        baseDependencies: .live(bridge: bridge)
    )
    let settings = ShadowClientAppSettings()

    let first = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 5_000),
        settings: settings
    )
    let second = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 5_016),
        settings: settings
    )

    #expect(first.sampleIntervalMs == nil)
    #expect(second.sampleIntervalMs == 16)
}

@Test("Settings telemetry runtime clears sample interval when streaming identity changes")
func settingsTelemetryRuntimeClearsSampleIntervalOnStreamingSettingsChange() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let runtime = SettingsDiagnosticsTelemetryRuntime(
        baseDependencies: .live(bridge: bridge)
    )

    let defaultSettings = ShadowClientAppSettings()
    let lowLatencyDisabled = ShadowClientAppSettings(lowLatencyMode: false)

    _ = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 8_000),
        settings: defaultSettings
    )
    let second = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 8_016),
        settings: defaultSettings
    )
    let afterStreamingChange = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 8_032),
        settings: lowLatencyDisabled
    )

    #expect(second.sampleIntervalMs == 16)
    #expect(afterStreamingChange.sampleIntervalMs == nil)
}

@Test("Settings telemetry runtime flags out-of-order samples")
func settingsTelemetryRuntimeFlagsOutOfOrderSamples() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let runtime = SettingsDiagnosticsTelemetryRuntime(
        baseDependencies: .live(bridge: bridge)
    )
    let settings = ShadowClientAppSettings()

    _ = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 10_000),
        settings: settings
    )
    let second = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 10_016),
        settings: settings
    )
    let outOfOrder = await runtime.ingest(
        snapshot: stableSnapshot(timestampMs: 10_008),
        settings: settings
    )

    #expect(second.receivedOutOfOrderSample == false)
    #expect(outOfOrder.receivedOutOfOrderSample == true)
    #expect(outOfOrder.sampleIntervalMs == nil)
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
