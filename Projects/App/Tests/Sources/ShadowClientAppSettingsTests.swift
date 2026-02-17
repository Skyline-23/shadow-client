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
    #expect(configured.connectionBackendLabel == base.connectionBackendLabel)
    #expect(ObjectIdentifier(configured.diagnosticsRuntime) != ObjectIdentifier(base.diagnosticsRuntime))
}

@Test("Dependencies live factory uses injected connection client")
func dependenciesLiveFactoryUsesInjectedConnectionClient() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let connectionClient = RecordingConnectionClient()
    let dependencies = ShadowClientFeatureHomeDependencies.live(
        bridge: bridge,
        connectionClient: connectionClient
    )

    let state = await dependencies.connectionRuntime.connect(to: "192.168.0.25")

    #expect(state == .connected(host: "192.168.0.25"))
    #expect(await connectionClient.connectCalls() == ["192.168.0.25"])
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

@Test("Streaming identity key ignores HUD visibility and tracks streaming toggles only")
func settingsStreamingIdentityKeyTracksStreamingToggles() {
    let baseline = ShadowClientAppSettings()
    let lowLatencyDisabled = ShadowClientAppSettings(lowLatencyMode: false)
    let hdrDisabled = ShadowClientAppSettings(preferHDR: false)
    let surroundDisabled = ShadowClientAppSettings(preferSurroundAudio: false)
    let hudDisabled = ShadowClientAppSettings(showDiagnosticsHUD: false)

    #expect(baseline.streamingIdentityKey != lowLatencyDisabled.streamingIdentityKey)
    #expect(baseline.streamingIdentityKey != hdrDisabled.streamingIdentityKey)
    #expect(baseline.streamingIdentityKey != surroundDisabled.streamingIdentityKey)
    #expect(baseline.streamingIdentityKey == hudDisabled.streamingIdentityKey)
}

private actor RecordingConnectionClient: ShadowClientConnectionClient {
    private var connectInvocations: [String] = []

    func connect(to host: String) async throws {
        connectInvocations.append(host)
    }

    func disconnect() async {}

    func connectCalls() -> [String] {
        connectInvocations
    }
}
