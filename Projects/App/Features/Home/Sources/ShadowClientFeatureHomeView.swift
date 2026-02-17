import Combine
import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

public struct ShadowClientFeatureHomeDependencies {
    public let telemetryPublisher: AnyPublisher<StreamingTelemetrySnapshot, Never>
    public let diagnosticsRuntime: HomeDiagnosticsRuntime
    public let connectionRuntime: ShadowClientConnectionRuntime
    public let settingsMapper: StreamingSessionSettingsMapper
    public let sessionPreferences: StreamingUserPreferences
    public let hostCapabilities: HostStreamingCapabilities

    public init(
        telemetryPublisher: AnyPublisher<StreamingTelemetrySnapshot, Never>,
        diagnosticsRuntime: HomeDiagnosticsRuntime,
        connectionRuntime: ShadowClientConnectionRuntime,
        settingsMapper: StreamingSessionSettingsMapper,
        sessionPreferences: StreamingUserPreferences,
        hostCapabilities: HostStreamingCapabilities
    ) {
        self.telemetryPublisher = telemetryPublisher
        self.diagnosticsRuntime = diagnosticsRuntime
        self.connectionRuntime = connectionRuntime
        self.settingsMapper = settingsMapper
        self.sessionPreferences = sessionPreferences
        self.hostCapabilities = hostCapabilities
    }
}

public extension ShadowClientFeatureHomeDependencies {
    static func live(bridge: MoonlightSessionTelemetryBridge) -> Self {
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
        #if os(macOS)
            let connectionClient: any ShadowClientConnectionClient = MoonlightCLIConnectionClient()
        #else
            let connectionClient: any ShadowClientConnectionClient = SimulatedShadowClientConnectionClient(bridge: bridge)
        #endif
        let connectionRuntime = ShadowClientConnectionRuntime(client: connectionClient)

        return .init(
            telemetryPublisher: bridge.snapshotPublisher,
            diagnosticsRuntime: diagnosticsRuntime,
            connectionRuntime: connectionRuntime,
            settingsMapper: settingsMapper,
            sessionPreferences: sessionPreferences,
            hostCapabilities: hostCapabilities
        )
    }

    static func preview() -> Self {
        live(bridge: MoonlightSessionTelemetryBridge())
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
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
            Text("Home running on \(platformName)")
                .font(.footnote)
                .foregroundStyle(Color.white.opacity(0.82))
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
                        .fill(Color.black.opacity(0.5))

                    VStack(spacing: 8) {
                        Image(systemName: streamStateSymbol)
                            .font(.title2)
                            .foregroundStyle(streamStateColor)
                        Text(streamOutputModel.detail)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(Color.white.opacity(0.84))
                    }
                    .padding(14)
                }
                .frame(height: 150)

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
                }
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(toneColor)
                Text("Target Buffer: \(diagnostics.bufferMs) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("Jitter: \(diagnostics.jitterMs) ms | Packet Loss: \(String(format: "%.1f", diagnostics.packetLossPercent))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("Frame Drop: \(String(format: "%.1f", diagnostics.frameDropPercent))% | AV Sync: \(diagnostics.avSyncOffsetMs) ms")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.9))
                Text("Drop Origin: NET \(diagnostics.networkDroppedFrames) | PACER \(diagnostics.pacerDroppedFrames)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.9))
                if diagnostics.recoveryStableSamplesRemaining > 0 {
                    Text("Recovery Hold: \(diagnostics.recoveryStableSamplesRemaining) stable sample(s) remaining")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.orange)
                }
                if let sessionPlan {
                    Text("Session Video: \(sessionPlan.settings.hdrVideoMode.rawValue.uppercased()) | Audio: \(sessionPlan.settings.audioMode.rawValue.uppercased())")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.86))
                    Text("Reconfig V:\(sessionPlan.shouldRenegotiateVideoPipeline ? "Y" : "N") A:\(sessionPlan.shouldRenegotiateAudioPipeline ? "Y" : "N") | QDrop: \(sessionPlan.shouldApplyQualityDropImmediately ? "Y" : "N")")
                        .font(.caption.monospacedDigit())
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

    private func streamMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(Color.white.opacity(0.72))
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func cardSurface<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.34))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
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
                await MainActor.run {
                    streamOutputModel = model
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
