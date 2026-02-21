import Combine
import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

public struct ShadowClientFeatureHomeDependencies {
    public let telemetryPublisher: AnyPublisher<StreamingTelemetrySnapshot, Never>
    public let diagnosticsRuntime: HomeDiagnosticsRuntime
    public let connectionRuntime: ShadowClientConnectionRuntime
    public let hostDiscoveryRuntime: ShadowClientHostDiscoveryRuntime
    public let remoteDesktopRuntime: ShadowClientRemoteDesktopRuntime
    public let connectionBackendLabel: String
    public let settingsMapper: StreamingSessionSettingsMapper
    public let sessionPreferences: StreamingUserPreferences
    public let hostCapabilities: HostStreamingCapabilities

    public init(
        telemetryPublisher: AnyPublisher<StreamingTelemetrySnapshot, Never>,
        diagnosticsRuntime: HomeDiagnosticsRuntime,
        connectionRuntime: ShadowClientConnectionRuntime,
        hostDiscoveryRuntime: ShadowClientHostDiscoveryRuntime,
        remoteDesktopRuntime: ShadowClientRemoteDesktopRuntime,
        connectionBackendLabel: String,
        settingsMapper: StreamingSessionSettingsMapper,
        sessionPreferences: StreamingUserPreferences,
        hostCapabilities: HostStreamingCapabilities
    ) {
        self.telemetryPublisher = telemetryPublisher
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
            sessionConnectTimeout: ShadowClientGameStreamNetworkDefaults.defaultSessionConnectTimeout
        )
    }

    static func live(
        identityStore: ShadowClientPairingIdentityStore,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore,
        defaultHTTPPort: Int,
        defaultHTTPSPort: Int,
        sessionConnectTimeout: Duration
    ) -> Self {
        let sessionRuntime = ShadowClientRealtimeRTSPSessionRuntime()
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
    private let platformName: String
    private let dependencies: ShadowClientFeatureHomeDependencies
    private let connectionState: ShadowClientConnectionState
    private let showsDiagnosticsHUD: Bool
    private let onDiagnosticsTick: (@MainActor @Sendable (HomeDiagnosticsTick) -> Void)?

    private let streamOutputRuntime = StreamOutputMonitorRuntime()

    @State private var telemetryTask: Task<Void, Never>?
    @State private var streamOutputHeartbeatTask: Task<Void, Never>?
    @State private var sessionPlan: MoonlightSessionReconfigurationPlan?
    @State private var streamOutputModel: StreamOutputMonitorModel = .disconnected
    @State private var telemetryIngressActivity = MoonlightTelemetryIngressActivity(
        callbackCount: 0,
        lastCallbackTimestampMs: nil
    )
    @State private var diagnostics = StreamingDiagnosticsModel(
        bufferMs: 40,
        jitterMs: 0,
        packetLossPercent: 0.0,
        frameDropPercent: 0.0,
        avSyncOffsetMs: 0,
        networkDroppedFrames: 0,
        pacerDroppedFrames: 0,
        recoveryStableSamplesRemaining: 0,
        tone: .healthy
    )

    public init(
        platformName: String,
        dependencies: ShadowClientFeatureHomeDependencies,
        connectionState: ShadowClientConnectionState = .disconnected,
        showsDiagnosticsHUD: Bool = true,
        onDiagnosticsTick: (@MainActor @Sendable (HomeDiagnosticsTick) -> Void)? = nil
    ) {
        self.platformName = platformName
        self.dependencies = dependencies
        self.connectionState = connectionState
        self.showsDiagnosticsHUD = showsDiagnosticsHUD
        self.onDiagnosticsTick = onDiagnosticsTick
    }

    public var body: some View {
        VStack(spacing: 16) {
            sessionHeader
            streamOutputCard
            if streamOutputModel.state != .live {
                sessionStandbyCard
            }
            if showsDiagnosticsHUD {
                diagnosticsCard
            } else {
                hudHiddenCard
            }
        }
        .padding(24)
        .onAppear {
            startTelemetrySubscription()
            startStreamOutputHeartbeat()
            Task {
                await syncStreamOutputModel(for: connectionState)
            }
        }
        .onDisappear {
            stopTelemetrySubscription()
            stopStreamOutputHeartbeat()
        }
        .task(id: connectionState) {
            await syncStreamOutputModel(for: connectionState)
        }
    }

    private var sessionHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Remote Session")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                Text("Platform: \(platformName)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.8))
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 4) {
                Label(connectionStateBadgeText, systemImage: connectionStateBadgeSymbol)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(connectionStateBadgeColor)
                    .background(connectionStateBadgeColor.opacity(0.18), in: Capsule())
                Text("Native callbacks: \(telemetryIngressActivity.callbackCount)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
            }
        }
    }

    private var sessionStandbyCard: some View {
        cardSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("Session Launch Checklist")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("1) Discover/select host from Settings")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("2) Connect and verify pair status")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("3) Launch desktop/game on host")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))

                Label(streamOutputModel.detail, systemImage: streamStateSymbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(streamStateColor)
            }
        }
    }

    private var streamOutputCard: some View {
        cardSurface {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center) {
                    Text("Stream Output Monitor")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Label(streamOutputModel.stateLabel, systemImage: streamStateSymbol)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .foregroundStyle(streamStateColor)
                        .background(streamStateColor.opacity(0.18), in: Capsule())
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.black.opacity(0.62))

                    VStack(spacing: 8) {
                        Image(systemName: streamStateSymbol)
                            .font(.title)
                            .foregroundStyle(streamStateColor)
                        Text(streamOutputModel.detail)
                            .font(.callout.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white.opacity(0.9))
                    }
                    .padding(14)
                }
                .frame(height: 170)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 8)],
                    spacing: 8
                ) {
                    streamMetric(title: "Sample Age", value: streamSampleAgeText)
                    streamMetric(title: "Estimated FPS", value: streamEstimatedFPSText)
                    streamMetric(title: "Rendered Frames", value: streamRenderedFramesText)
                    streamMetric(title: "Dropped Frames", value: streamDroppedFramesText)
                    streamMetric(title: "Frame Drop", value: streamFrameDropText)
                    streamMetric(title: "Jitter", value: streamJitterText)
                    streamMetric(title: "Packet Loss", value: streamPacketLossText)
                    streamMetric(title: "Native Callbacks", value: streamNativeCallbackCountText)
                    streamMetric(title: "Last Callback TS", value: streamLastCallbackText)
                }

                Label(streamCallbackStatusText, systemImage: streamCallbackStatusSymbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(streamCallbackStatusColor)
            }
        }
    }

    private var diagnosticsCard: some View {
        cardSurface {
            VStack(alignment: .leading, spacing: 8) {
                Text("Low-Latency Debug HUD")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Tone: \(diagnostics.tone.rawValue.uppercased())")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(toneColor)
                Text("Target Buffer: \(diagnostics.bufferMs) ms")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("Jitter: \(diagnostics.jitterMs) ms | Packet Loss: \(String(format: "%.1f", diagnostics.packetLossPercent))%")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("Frame Drop: \(String(format: "%.1f", diagnostics.frameDropPercent))% | AV Sync: \(diagnostics.avSyncOffsetMs) ms")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("Drop Origin: NET \(diagnostics.networkDroppedFrames) | PACER \(diagnostics.pacerDroppedFrames)")
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.9))
                if diagnostics.recoveryStableSamplesRemaining > 0 {
                    Text("Recovery Hold: \(diagnostics.recoveryStableSamplesRemaining) stable sample(s) remaining")
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.orange)
                }
                if let sessionPlan {
                    Text("Session Video: \(sessionPlan.settings.hdrVideoMode.rawValue.uppercased()) | Audio: \(sessionPlan.settings.audioMode.rawValue.uppercased())")
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.86))
                    Text("Reconfig V:\(sessionPlan.shouldRenegotiateVideoPipeline ? "Y" : "N") A:\(sessionPlan.shouldRenegotiateAudioPipeline ? "Y" : "N") | QDrop: \(sessionPlan.shouldApplyQualityDropImmediately ? "Y" : "N")")
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                }
            }
        }
    }

    private var hudHiddenCard: some View {
        cardSurface {
            VStack(alignment: .leading, spacing: 8) {
                Text("Low-Latency HUD Disabled")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Enable diagnostics from Settings to inspect jitter, drop origin, and reconfiguration plans.")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.78))
                if let sessionPlan {
                    Text("Current Session: \(sessionPlan.settings.hdrVideoMode.rawValue.uppercased()) / \(sessionPlan.settings.audioMode.rawValue.uppercased())")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.86))
                }
            }
        }
    }

    private var toneColor: Color {
        switch diagnostics.tone {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private var connectionStateBadgeText: String {
        switch connectionState {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .disconnecting:
            return "Disconnecting"
        case .failed:
            return "Failed"
        }
    }

    private var connectionStateBadgeSymbol: String {
        switch connectionState {
        case .disconnected:
            return "bolt.slash.fill"
        case .connecting, .disconnecting:
            return "clock.fill"
        case .connected:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        }
    }

    private var connectionStateBadgeColor: Color {
        switch connectionState {
        case .disconnected:
            return Color.white.opacity(0.72)
        case .connecting, .disconnecting:
            return .orange
        case .connected:
            return .green
        case .failed:
            return .red
        }
    }

    private var streamStateColor: Color {
        switch streamOutputModel.state {
        case .live:
            return .green
        case .awaitingTelemetry, .connecting:
            return .orange
        case .stale, .failed:
            return .red
        case .disconnected:
            return Color.white.opacity(0.72)
        }
    }

    private var streamStateSymbol: String {
        switch streamOutputModel.state {
        case .live:
            return "waveform.and.magnifyingglass"
        case .awaitingTelemetry, .connecting:
            return "clock.fill"
        case .stale:
            return "wifi.slash"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .disconnected:
            return "bolt.slash.fill"
        }
    }

    private var streamSampleAgeText: String {
        if let sampleAgeMs = streamOutputModel.sampleAgeMs {
            return "\(sampleAgeMs) ms"
        }
        return "--"
    }

    private var streamEstimatedFPSText: String {
        if let estimatedFPS = streamOutputModel.estimatedFPS {
            return "\(estimatedFPS) fps"
        }
        return "--"
    }

    private var streamRenderedFramesText: String {
        if let renderedFrames = streamOutputModel.renderedFrames {
            return "\(renderedFrames)"
        }
        return "--"
    }

    private var streamDroppedFramesText: String {
        if let droppedFrames = streamOutputModel.droppedFrames {
            return "\(droppedFrames)"
        }
        return "--"
    }

    private var streamFrameDropText: String {
        if let frameDropPercent = streamOutputModel.frameDropPercent {
            return String(format: "%.1f%%", frameDropPercent)
        }
        return "--"
    }

    private var streamJitterText: String {
        if let jitterMs = streamOutputModel.jitterMs {
            return "\(jitterMs) ms"
        }
        return "--"
    }

    private var streamPacketLossText: String {
        if let packetLossPercent = streamOutputModel.packetLossPercent {
            return String(format: "%.1f%%", packetLossPercent)
        }
        return "--"
    }

    private var streamNativeCallbackCountText: String {
        "\(telemetryIngressActivity.callbackCount)"
    }

    private var streamLastCallbackText: String {
        if let timestampMs = telemetryIngressActivity.lastCallbackTimestampMs {
            return "\(timestampMs)"
        }
        return "--"
    }

    private var streamCallbackStatusText: String {
        if telemetryIngressActivity.callbackCount > 0 {
            return "Native callback active"
        }

        switch connectionState {
        case .connected:
            return "Connected, but no native callback samples yet"
        case .connecting, .disconnecting:
            return "Waiting for callback pipeline"
        case .failed:
            return "Callback pipeline unavailable (connection failed)"
        case .disconnected:
            return "Connect to a host to initialize callback pipeline"
        }
    }

    private var streamCallbackStatusSymbol: String {
        telemetryIngressActivity.callbackCount > 0 ? "waveform.path" : "waveform.slash"
    }

    private var streamCallbackStatusColor: Color {
        telemetryIngressActivity.callbackCount > 0 ? .green : Color.white.opacity(0.7)
    }

    private func streamMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.82))
            Text(value)
                .font(.title3.monospacedDigit().weight(.bold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.64))
        )
    }

    private func cardSurface<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.66))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.32), radius: 14, y: 6)
    }

    private func startTelemetrySubscription() {
        telemetryTask?.cancel()
        let telemetryValues = dependencies.telemetryPublisher.values
        telemetryTask = Task {
            for await snapshot in telemetryValues {
                if Task.isCancelled {
                    return
                }
                let tick = await dependencies.diagnosticsRuntime.ingest(snapshot: snapshot)
                let streamModel = await streamOutputRuntime.ingest(snapshot: snapshot)

                await MainActor.run {
                    sessionPlan = tick.sessionPlan
                    diagnostics = tick.model
                    streamOutputModel = streamModel
                    onDiagnosticsTick?(tick)
                }
            }
        }
    }

    private func stopTelemetrySubscription() {
        telemetryTask?.cancel()
        telemetryTask = nil
    }

    @MainActor
    private func startStreamOutputHeartbeat() {
        streamOutputHeartbeatTask?.cancel()
        streamOutputHeartbeatTask = Task {
            while !Task.isCancelled {
                let model = await streamOutputRuntime.heartbeat()
                let activity = await MoonlightSessionTelemetryIngress.callbackActivity()
                await MainActor.run {
                    streamOutputModel = model
                    telemetryIngressActivity = activity
                }

                try? await Task.sleep(for: ShadowClientUIRuntimeDefaults.streamOutputHeartbeatInterval)
            }
        }
    }

    @MainActor
    private func stopStreamOutputHeartbeat() {
        streamOutputHeartbeatTask?.cancel()
        streamOutputHeartbeatTask = nil
    }

    @MainActor
    private func syncStreamOutputModel(for state: ShadowClientConnectionState) async {
        streamOutputModel = await streamOutputRuntime.updateConnectionState(state)
    }
}
