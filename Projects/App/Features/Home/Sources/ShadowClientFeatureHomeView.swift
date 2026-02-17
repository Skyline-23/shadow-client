import Combine
import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

public struct ShadowClientFeatureHomeDependencies {
    public let telemetryPublisher: AnyPublisher<StreamingTelemetrySnapshot, Never>
    public let diagnosticsRuntime: HomeDiagnosticsRuntime
    public let connectionRuntime: ShadowClientConnectionRuntime
    public let connectionBackendLabel: String
    public let settingsMapper: StreamingSessionSettingsMapper
    public let sessionPreferences: StreamingUserPreferences
    public let hostCapabilities: HostStreamingCapabilities

    public init(
        telemetryPublisher: AnyPublisher<StreamingTelemetrySnapshot, Never>,
        diagnosticsRuntime: HomeDiagnosticsRuntime,
        connectionRuntime: ShadowClientConnectionRuntime,
        connectionBackendLabel: String,
        settingsMapper: StreamingSessionSettingsMapper,
        sessionPreferences: StreamingUserPreferences,
        hostCapabilities: HostStreamingCapabilities
    ) {
        self.telemetryPublisher = telemetryPublisher
        self.diagnosticsRuntime = diagnosticsRuntime
        self.connectionRuntime = connectionRuntime
        self.connectionBackendLabel = connectionBackendLabel
        self.settingsMapper = settingsMapper
        self.sessionPreferences = sessionPreferences
        self.hostCapabilities = hostCapabilities
    }
}

public extension ShadowClientFeatureHomeDependencies {
    static func live(
        bridge: MoonlightSessionTelemetryBridge,
        connectionClient: any ShadowClientConnectionClient,
        connectionBackendLabel: String = "Native Host Probe"
    ) -> Self {
        let settingsMapper = StreamingSessionSettingsMapper()
        let sessionPreferences = StreamingUserPreferences(
            preferHDR: true,
            preferSurroundAudio: true,
            lowLatencyMode: true
        )
        let hostCapabilities = HostStreamingCapabilities(
            supportsHDR10: true,
            supportsSurround51: true
        )
        let launchRuntime = AdaptiveSessionLaunchRuntime(
            telemetryPipeline: .init(initialBufferMs: 40.0),
            settingsMapper: settingsMapper,
            sessionPreferences: sessionPreferences,
            hostCapabilities: hostCapabilities
        )
        let diagnosticsRuntime = HomeDiagnosticsRuntime(launchRuntime: launchRuntime)
        let connectionRuntime = ShadowClientConnectionRuntime(client: connectionClient)

        return .init(
            telemetryPublisher: bridge.snapshotPublisher,
            diagnosticsRuntime: diagnosticsRuntime,
            connectionRuntime: connectionRuntime,
            connectionBackendLabel: connectionBackendLabel,
            settingsMapper: settingsMapper,
            sessionPreferences: sessionPreferences,
            hostCapabilities: hostCapabilities
        )
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

    @State private var telemetryCancellable: AnyCancellable?
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
            Text("shadow-client")
                .font(.title.weight(.bold))
                .foregroundStyle(.white)
            Text("Home running on \(platformName)")
                .font(.callout.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.88))
            streamOutputCard
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
                .fill(Color.black.opacity(0.5))
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
                    .fill(Color.black.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.32), radius: 14, y: 6)
    }

    private func startTelemetrySubscription() {
        telemetryCancellable?.cancel()
        telemetryCancellable = dependencies.telemetryPublisher.sink { snapshot in
            Task {
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
        telemetryCancellable?.cancel()
        telemetryCancellable = nil
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

                try? await Task.sleep(for: .seconds(1))
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
