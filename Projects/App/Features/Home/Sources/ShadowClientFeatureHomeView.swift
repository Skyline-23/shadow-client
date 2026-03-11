import ShadowClientStreaming
import SwiftUI

public struct ShadowClientFeatureHomeDependencies {
    public typealias TelemetryStreamFactory = @Sendable () async -> AsyncStream<StreamingTelemetrySnapshot>

    public let makeTelemetryStream: TelemetryStreamFactory
    public let diagnosticsRuntime: HomeDiagnosticsRuntime
    public let connectionRuntime: ShadowClientConnectionRuntime
    public let hostDiscoveryRuntime: ShadowClientHostDiscoveryRuntime
    public let remoteDesktopRuntime: ShadowClientRemoteDesktopRuntime
    public let connectionBackendLabel: String
    public let settingsMapper: StreamingSessionSettingsMapper
    public let sessionPreferences: StreamingUserPreferences
    public let hostCapabilities: HostStreamingCapabilities

    public init(
        makeTelemetryStream: @escaping TelemetryStreamFactory,
        diagnosticsRuntime: HomeDiagnosticsRuntime,
        connectionRuntime: ShadowClientConnectionRuntime,
        hostDiscoveryRuntime: ShadowClientHostDiscoveryRuntime,
        remoteDesktopRuntime: ShadowClientRemoteDesktopRuntime,
        connectionBackendLabel: String,
        settingsMapper: StreamingSessionSettingsMapper,
        sessionPreferences: StreamingUserPreferences,
        hostCapabilities: HostStreamingCapabilities
    ) {
        self.makeTelemetryStream = makeTelemetryStream
        self.diagnosticsRuntime = diagnosticsRuntime
        self.connectionRuntime = connectionRuntime
        self.hostDiscoveryRuntime = hostDiscoveryRuntime
        self.remoteDesktopRuntime = remoteDesktopRuntime
        self.connectionBackendLabel = connectionBackendLabel
        self.settingsMapper = settingsMapper
        self.sessionPreferences = sessionPreferences
        self.hostCapabilities = hostCapabilities
    }
}

public struct ShadowClientRemoteDesktopDependencies {
    public let metadataClient: any ShadowClientGameStreamMetadataClient
    public let controlClient: any ShadowClientGameStreamControlClient
    public let sessionConnectionClient: any ShadowClientRemoteSessionConnectionClient
    public let sessionInputClient: any ShadowClientRemoteSessionInputClient
    public let pinProvider: any ShadowClientPairingPINProviding

    public init(
        metadataClient: any ShadowClientGameStreamMetadataClient,
        controlClient: any ShadowClientGameStreamControlClient,
        sessionConnectionClient: any ShadowClientRemoteSessionConnectionClient,
        sessionInputClient: any ShadowClientRemoteSessionInputClient,
        pinProvider: any ShadowClientPairingPINProviding
    ) {
        self.metadataClient = metadataClient
        self.controlClient = controlClient
        self.sessionConnectionClient = sessionConnectionClient
        self.sessionInputClient = sessionInputClient
        self.pinProvider = pinProvider
    }
}

public extension ShadowClientRemoteDesktopDependencies {
    static func live(
        identityStore: ShadowClientPairingIdentityStore = .shared,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared,
        defaultHTTPPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPPort,
        defaultHTTPSPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
    ) -> Self {
        live(
            identityStore: identityStore,
            pinnedCertificateStore: pinnedCertificateStore,
            defaultHTTPPort: defaultHTTPPort,
            defaultHTTPSPort: defaultHTTPSPort,
            prepareAudioDecoders: nil,
            audioSessionActivation: nil,
            audioSessionDeactivation: nil
        )
    }

    static func live(
        identityStore: ShadowClientPairingIdentityStore = .shared,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared,
        defaultHTTPPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPPort,
        defaultHTTPSPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort,
        prepareAudioDecoders: (@Sendable () async -> Void)? = nil,
        audioSessionActivation: (@Sendable () async -> Void)? = nil,
        audioSessionDeactivation: (@Sendable () async -> Void)? = nil
    ) -> Self {
        live(
            identityStore: identityStore,
            pinnedCertificateStore: pinnedCertificateStore,
            defaultHTTPPort: defaultHTTPPort,
            defaultHTTPSPort: defaultHTTPSPort,
            sessionConnectTimeout: ShadowClientGameStreamNetworkDefaults.defaultSessionConnectTimeout,
            prepareAudioDecoders: prepareAudioDecoders,
            audioSessionActivation: audioSessionActivation,
            audioSessionDeactivation: audioSessionDeactivation
        )
    }

    static func live(
        identityStore: ShadowClientPairingIdentityStore,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore,
        defaultHTTPPort: Int,
        defaultHTTPSPort: Int,
        sessionConnectTimeout: Duration
    ) -> Self {
        live(
            identityStore: identityStore,
            pinnedCertificateStore: pinnedCertificateStore,
            defaultHTTPPort: defaultHTTPPort,
            defaultHTTPSPort: defaultHTTPSPort,
            sessionConnectTimeout: sessionConnectTimeout,
            prepareAudioDecoders: nil,
            audioSessionActivation: nil,
            audioSessionDeactivation: nil
        )
    }

    static func live(
        identityStore: ShadowClientPairingIdentityStore,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore,
        defaultHTTPPort: Int,
        defaultHTTPSPort: Int,
        sessionConnectTimeout: Duration,
        prepareAudioDecoders: (@Sendable () async -> Void)? = nil,
        audioSessionActivation: (@Sendable () async -> Void)? = nil,
        audioSessionDeactivation: (@Sendable () async -> Void)? = nil
    ) -> Self {
        let sessionRuntime = ShadowClientRealtimeRTSPSessionRuntime(
            prepareAudioDecoders: prepareAudioDecoders,
            audioSessionActivation: audioSessionActivation,
            audioSessionDeactivation: audioSessionDeactivation
        )
        return .init(
            metadataClient: NativeGameStreamMetadataClient(
                identityStore: identityStore,
                pinnedCertificateStore: pinnedCertificateStore,
                defaultHTTPPort: defaultHTTPPort,
                defaultHTTPSPort: defaultHTTPSPort
            ),
            controlClient: NativeGameStreamControlClient(
                identityStore: identityStore,
                pinnedCertificateStore: pinnedCertificateStore,
                defaultHTTPPort: defaultHTTPPort,
                defaultHTTPSPort: defaultHTTPSPort
            ),
            sessionConnectionClient: NativeShadowClientRemoteSessionConnectionClient(
                timeout: sessionConnectTimeout,
                sessionRuntime: sessionRuntime
            ),
            sessionInputClient: NativeShadowClientRemoteSessionInputClient(
                sessionRuntime: sessionRuntime
            ),
            pinProvider: ShadowClientRandomPairingPINProvider()
        )
    }
}

public extension ShadowClientFeatureHomeDependencies {
    static func live(
        bridge: MoonlightSessionTelemetryBridge,
        connectionClient: any ShadowClientConnectionClient,
        connectionBackendLabel: String = "Native Host Probe",
        hostDiscoveryRuntime: ShadowClientHostDiscoveryRuntime = .init(),
        remoteDesktopDependencies: ShadowClientRemoteDesktopDependencies = .live()
    ) -> Self {
        ShadowClientFeatureHomeContainer(
            bridge: bridge,
            connectionClient: connectionClient,
            connectionBackendLabel: connectionBackendLabel,
            hostDiscoveryRuntime: hostDiscoveryRuntime,
            remoteDesktopDependencies: remoteDesktopDependencies
        ).dependencies
    }

    static func live(bridge: MoonlightSessionTelemetryBridge) -> Self {
        live(
            bridge: bridge,
            connectionClient: NativeHostProbeConnectionClient()
        )
    }

    static func preview() -> Self {
        let bridge = MoonlightSessionTelemetryBridge()
        return live(
            bridge: bridge,
            connectionClient: SimulatedShadowClientConnectionClient(bridge: bridge),
            connectionBackendLabel: "Simulated Connector"
        )
    }
}

public struct ShadowClientFeatureHomeView: View {
    private let dependencies: ShadowClientFeatureHomeDependencies
    private let onDiagnosticsTick: (@MainActor @Sendable (HomeDiagnosticsTick) -> Void)?

    @State private var telemetryTask: Task<Void, Never>?

    public init(
        platformName: String,
        dependencies: ShadowClientFeatureHomeDependencies,
        connectionState: ShadowClientConnectionState = .disconnected,
        showsDiagnosticsHUD: Bool = true,
        onDiagnosticsTick: (@MainActor @Sendable (HomeDiagnosticsTick) -> Void)? = nil
    ) {
        _ = platformName
        _ = connectionState
        _ = showsDiagnosticsHUD
        self.dependencies = dependencies
        self.onDiagnosticsTick = onDiagnosticsTick
    }

    public var body: some View {
        Color.clear
        .frame(height: 0)
        .onAppear {
            startTelemetrySubscription()
        }
        .onDisappear {
            stopTelemetrySubscription()
        }
    }

    private func startTelemetrySubscription() {
        telemetryTask?.cancel()
        telemetryTask = Task {
            let telemetryStream = await dependencies.makeTelemetryStream()
            for await snapshot in telemetryStream {
                if Task.isCancelled {
                    return
                }
                let tick = await dependencies.diagnosticsRuntime.ingest(snapshot: snapshot)

                await MainActor.run {
                    onDiagnosticsTick?(tick)
                }
            }
        }
    }

    private func stopTelemetrySubscription() {
        telemetryTask?.cancel()
        telemetryTask = nil
    }
}
