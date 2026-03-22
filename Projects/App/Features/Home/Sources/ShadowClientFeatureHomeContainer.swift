import ShadowClientStreaming
import ShadowClientFeatureConnection

public final class ShadowClientFeatureHomeContainer {
    public let bridge: MoonlightSessionTelemetryBridge
    public let dependencies: ShadowClientFeatureHomeDependencies

    public init(
        bridge: MoonlightSessionTelemetryBridge,
        connectionClient: any ShadowClientConnectionClient,
        connectionBackendLabel: String = "Native Host Probe",
        hostDiscoveryRuntime: ShadowClientHostDiscoveryRuntime = .init(),
        remoteDesktopDependencies: ShadowClientRemoteDesktopDependencies = .live(),
        settingsMapper: StreamingSessionSettingsMapper = .init(),
        sessionPreferences: StreamingUserPreferences = .init(
            preferHDR: true,
            preferSurroundAudio: true,
            lowLatencyMode: true
        ),
        hostCapabilities: HostStreamingCapabilities = .init(
            supportsHDR10: true,
            supportsSurround51: true
        )
    ) {
        self.bridge = bridge

        let launchRuntime = AdaptiveSessionLaunchRuntime(
            telemetryPipeline: .init(initialBufferMs: 40.0),
            settingsMapper: settingsMapper,
            sessionPreferences: sessionPreferences,
            hostCapabilities: hostCapabilities
        )
        let diagnosticsRuntime = HomeDiagnosticsRuntime(launchRuntime: launchRuntime)
        let connectionRuntime = ShadowClientConnectionRuntime(client: connectionClient)
        let remoteDesktopRuntime = ShadowClientRemoteDesktopRuntime(
            metadataClient: remoteDesktopDependencies.metadataClient,
            controlClient: remoteDesktopDependencies.controlClient,
            wakeOnLANClient: remoteDesktopDependencies.wakeOnLANClient,
            sessionConnectionClient: remoteDesktopDependencies.sessionConnectionClient,
            sessionInputClient: remoteDesktopDependencies.sessionInputClient,
            pinProvider: remoteDesktopDependencies.pinProvider,
            pinnedCertificateStore: remoteDesktopDependencies.pinnedCertificateStore
        )

        self.dependencies = .init(
            makeTelemetryStream: { await bridge.snapshotStream() },
            diagnosticsRuntime: diagnosticsRuntime,
            connectionRuntime: connectionRuntime,
            hostDiscoveryRuntime: hostDiscoveryRuntime,
            remoteDesktopRuntime: remoteDesktopRuntime,
            connectionBackendLabel: connectionBackendLabel,
            settingsMapper: settingsMapper,
            sessionPreferences: sessionPreferences,
            hostCapabilities: hostCapabilities
        )
    }
}

public extension ShadowClientFeatureHomeContainer {
    static func live(
        bridge: MoonlightSessionTelemetryBridge,
        connectionClient: any ShadowClientConnectionClient = NativeHostProbeConnectionClient(),
        connectionBackendLabel: String = "Native Host Probe",
        hostDiscoveryRuntime: ShadowClientHostDiscoveryRuntime = .init(),
        remoteDesktopDependencies: ShadowClientRemoteDesktopDependencies = .live()
    ) -> ShadowClientFeatureHomeContainer {
        ShadowClientFeatureHomeContainer(
            bridge: bridge,
            connectionClient: connectionClient,
            connectionBackendLabel: connectionBackendLabel,
            hostDiscoveryRuntime: hostDiscoveryRuntime,
            remoteDesktopDependencies: remoteDesktopDependencies
        )
    }

    static func preview() -> ShadowClientFeatureHomeContainer {
        let bridge = MoonlightSessionTelemetryBridge()
        return .live(
            bridge: bridge,
            connectionClient: SimulatedShadowClientConnectionClient(bridge: bridge),
            connectionBackendLabel: "Simulated Connector"
        )
    }
}
