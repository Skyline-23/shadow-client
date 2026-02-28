import ShadowClientFeatureHome
import ShadowClientStreaming
import Testing

@Test("App settings map directly to streaming preferences")
func appSettingsMapToStreamingPreferences() {
    let settings = ShadowClientAppSettings(
        lowLatencyMode: false,
        preferHDR: false,
        showDiagnosticsHUD: true,
        audioConfiguration: .surround71
    )

    #expect(settings.streamingPreferences == StreamingUserPreferences(
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
        showDiagnosticsHUD: false,
        audioConfiguration: .stereo
    )

    let configured = base.applying(settings: settings)

    #expect(configured.sessionPreferences == settings.streamingPreferences)
    #expect(configured.hostCapabilities == base.hostCapabilities)
    #expect(configured.connectionBackendLabel == base.connectionBackendLabel)
    #expect(ObjectIdentifier(configured.hostDiscoveryRuntime) == ObjectIdentifier(base.hostDiscoveryRuntime))
    #expect(ObjectIdentifier(configured.remoteDesktopRuntime) == ObjectIdentifier(base.remoteDesktopRuntime))
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
    let surroundDisabled = ShadowClientAppSettings(audioConfiguration: .stereo)
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
    let surroundDisabled = ShadowClientAppSettings(audioConfiguration: .stereo)
    let hudDisabled = ShadowClientAppSettings(showDiagnosticsHUD: false)

    #expect(baseline.streamingIdentityKey != lowLatencyDisabled.streamingIdentityKey)
    #expect(baseline.streamingIdentityKey != hdrDisabled.streamingIdentityKey)
    #expect(baseline.streamingIdentityKey != surroundDisabled.streamingIdentityKey)
    #expect(baseline.streamingIdentityKey == hudDisabled.streamingIdentityKey)
}

@Test("App settings map to launch settings including codec, bitrate, and geometry")
func appSettingsMapToLaunchSettings() {
    let settings = ShadowClientAppSettings(
        lowLatencyMode: false,
        preferHDR: true,
        resolution: .p2160,
        frameRate: .fps120,
        bitrateKbps: 42_000,
        autoBitrate: false,
        audioConfiguration: .surround51,
        videoCodec: .av1,
        enableVSync: true,
        enableFramePacing: true,
        enableYUV444: true,
        unlockBitrateLimit: true,
        optimizeGameSettingsForStreaming: true,
        quitAppOnHostAfterStream: true
    )
    let hostApp = ShadowClientRemoteAppDescriptor(
        id: 99,
        title: "Desktop",
        hdrSupported: true,
        isAppCollectorGame: false
    )

    let launch = settings.launchSettings(hostApp: hostApp)

    #expect(launch.width == 3840)
    #expect(launch.height == 2160)
    #expect(launch.fps == 120)
    #expect(launch.bitrateKbps == 42_000)
    #expect(launch.preferredCodec == .av1)
    #expect(launch.enableHDR == true)
    #expect(launch.enableSurroundAudio == true)
    #expect(launch.enableVSync == true)
    #expect(launch.enableFramePacing == true)
    #expect(launch.enableYUV444 == true)
    #expect(launch.unlockBitrateLimit == true)
    #expect(launch.optimizeGameSettingsForStreaming == true)
    #expect(launch.quitAppOnHostAfterStreamEnds == true)
    #expect(launch.playAudioOnHost == false)
}

@Test("Launch settings disable HDR when selected app does not support HDR")
func launchSettingsDisableHDRForNonHDRApp() {
    let settings = ShadowClientAppSettings(preferHDR: true)
    let hostApp = ShadowClientRemoteAppDescriptor(
        id: 10,
        title: "Legacy App",
        hdrSupported: false,
        isAppCollectorGame: false
    )

    let launch = settings.launchSettings(hostApp: hostApp)
    #expect(launch.enableHDR == false)
}

@Test("Launch settings can route audio to host when host speaker mute is disabled")
func launchSettingsEnableAudioOnHostWhenConfigured() {
    let settings = ShadowClientAppSettings(muteHostSpeakersWhileStreaming: false)
    let launch = settings.launchSettings(hostApp: nil)

    #expect(launch.playAudioOnHost == true)
}

@Test("Auto bitrate computes launch bitrate from stream profile")
func autoBitrateComputesLaunchBitrate() {
    let settings = ShadowClientAppSettings(
        preferHDR: true,
        resolution: .p2160,
        frameRate: .fps120,
        bitrateKbps: 8_000,
        autoBitrate: true,
        videoCodec: .h264,
        enableYUV444: true
    )
    let launch = settings.launchSettings(hostApp: nil)

    #expect(launch.bitrateKbps > 8_000)
    #expect(launch.bitrateKbps <= ShadowClientAppSettingsDefaults.maximumBitrateWhenLocked)
}

@Test("Auto bitrate lowers recommendation when low-latency mode is enabled")
func autoBitratePrefersLowerBitrateForLowLatencyMode() {
    let conservative = ShadowClientAppSettings.recommendedBitrateKbps(
        resolution: .p1080,
        frameRate: .fps60,
        codec: .av1,
        enableHDR: true,
        enableYUV444: false,
        lowLatencyMode: true,
        unlockBitrateLimit: false
    )
    let qualityBiased = ShadowClientAppSettings.recommendedBitrateKbps(
        resolution: .p1080,
        frameRate: .fps60,
        codec: .av1,
        enableHDR: true,
        enableYUV444: false,
        lowLatencyMode: false,
        unlockBitrateLimit: false
    )

    #expect(conservative < qualityBiased)
}

@Test("Auto bitrate uses resolved codec efficiency for estimation")
func autoBitrateUsesResolvedCodecForEstimation() {
    let autoAsAV1 = ShadowClientAppSettings.recommendedBitrateKbps(
        resolution: .p2160,
        frameRate: .fps60,
        codec: .auto,
        enableHDR: true,
        enableYUV444: false,
        lowLatencyMode: true,
        unlockBitrateLimit: false,
        resolvedCodecForAuto: .av1
    )
    let autoAsH264 = ShadowClientAppSettings.recommendedBitrateKbps(
        resolution: .p2160,
        frameRate: .fps60,
        codec: .auto,
        enableHDR: true,
        enableYUV444: false,
        lowLatencyMode: true,
        unlockBitrateLimit: false,
        resolvedCodecForAuto: .h264
    )

    #expect(autoAsAV1 < autoAsH264)
}

@Test("Auto bitrate reduces under unstable network signal")
func autoBitrateDropsOnNetworkInstability() {
    let stable = ShadowClientAppSettings.recommendedBitrateKbps(
        resolution: .p2160,
        frameRate: .fps60,
        codec: .av1,
        enableHDR: true,
        enableYUV444: false,
        lowLatencyMode: true,
        unlockBitrateLimit: false,
        networkSignal: .init(jitterMs: 3.0, packetLossPercent: 0.1)
    )
    let unstable = ShadowClientAppSettings.recommendedBitrateKbps(
        resolution: .p2160,
        frameRate: .fps60,
        codec: .av1,
        enableHDR: true,
        enableYUV444: false,
        lowLatencyMode: true,
        unlockBitrateLimit: false,
        networkSignal: .init(jitterMs: 28.0, packetLossPercent: 2.2)
    )

    #expect(unstable < stable)
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
