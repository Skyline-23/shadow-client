import ShadowClientFeatureHome
import ShadowClientStreaming
import Testing

@Test("App settings map directly to streaming preferences")
func appSettingsMapToStreamingPreferences() {
    let settings = ShadowClientAppSettings(
        lowLatencyMode: false,
        preferHDR: false,
        preferSurroundAudio: true,
        showDiagnosticsHUD: true
    )

    #expect(settings.streamingPreferences == .init(
        preferHDR: false,
        preferSurroundAudio: true,
        lowLatencyMode: false
    ))
}

@Test("Dependencies applying settings override session preferences while preserving host capabilities")
func dependenciesApplyingSettingsOverridesSessionPreferences() {
    let bridge = MoonlightSessionTelemetryBridge()
    let base = ShadowClientFeatureHomeDependencies.live(bridge: bridge)
    let settings = ShadowClientAppSettings(
        lowLatencyMode: false,
        preferHDR: false,
        preferSurroundAudio: false,
        showDiagnosticsHUD: false
    )

    let configured = base.applying(settings: settings)

    #expect(configured.sessionPreferences == settings.streamingPreferences)
    #expect(configured.hostCapabilities == base.hostCapabilities)
}

@Test("Settings identity key changes when any toggle value changes")
func settingsIdentityKeyChangesPerToggle() {
    let baseline = ShadowClientAppSettings()
    let lowLatencyDisabled = ShadowClientAppSettings(lowLatencyMode: false)
    let hdrDisabled = ShadowClientAppSettings(preferHDR: false)
    let surroundDisabled = ShadowClientAppSettings(preferSurroundAudio: false)
    let hudDisabled = ShadowClientAppSettings(showDiagnosticsHUD: false)

    #expect(baseline.identityKey != lowLatencyDisabled.identityKey)
    #expect(baseline.identityKey != hdrDisabled.identityKey)
    #expect(baseline.identityKey != surroundDisabled.identityKey)
    #expect(baseline.identityKey != hudDisabled.identityKey)
}
