import Testing
@testable import ShadowClientFeatureHome
import ShadowClientStreaming
import ShadowClientUI

@Test("Settings diagnostics presentation builds telemetry rows including warnings and recovery hold")
func settingsDiagnosticsPresentationRows() {
    let model = SettingsDiagnosticsHUDModel(
        tick: HomeDiagnosticsTick(
            model: .init(
                bufferMs: 48,
                jitterMs: 24,
                packetLossPercent: 2.0,
                frameDropPercent: 1.4,
                avSyncOffsetMs: 6,
                networkDroppedFrames: 12,
                pacerDroppedFrames: 2,
                recoveryStableSamplesRemaining: 3,
                tone: .critical
            ),
            sessionPlan: .init(
                settings: .init(
                    hdrVideoMode: .hdr10,
                    audioMode: .surround51,
                    targetBufferMs: 48,
                    qualityReductionRequested: true,
                    recoveryStableSamplesRemaining: 3
                ),
                shouldRenegotiateVideoPipeline: true,
                shouldRenegotiateAudioPipeline: false,
                shouldApplyQualityDropImmediately: true
            ),
            timestampMs: 1024
        ),
        sampleIntervalMs: 33,
        receivedOutOfOrderSample: true
    )

    let rows = ShadowClientSettingsDiagnosticsPresentationKit.telemetryRows(model)
    #expect(rows.contains(where: { $0.label == "Tone" && $0.value == "CRITICAL" }))
    #expect(rows.contains(where: { $0.label == "Sample Order" && $0.usesWarningValueColor }))
    #expect(rows.contains(where: { $0.label == "Recovery Hold" && $0.value.contains("3 stable") }))
}

@Test("Settings diagnostics presentation exposes empty and controller copy")
func settingsDiagnosticsPresentationStaticCopy() {
    #expect(ShadowClientSettingsDiagnosticsPresentationKit.emptyTelemetryMessage() == "Awaiting telemetry samples from active session.")
    #expect(ShadowClientSettingsDiagnosticsPresentationKit.controllerContractMessage() == "DualSense feedback contract follows Apple Game Controller capabilities.")
}
