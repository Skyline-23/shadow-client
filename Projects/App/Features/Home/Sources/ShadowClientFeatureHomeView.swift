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
    private let showsDiagnosticsHUD: Bool
    private let onDiagnosticsTick: (@MainActor @Sendable (HomeDiagnosticsTick) -> Void)?

    @State private var telemetryCancellable: AnyCancellable?
    @State private var sessionPlan: MoonlightSessionReconfigurationPlan?
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
        showsDiagnosticsHUD: Bool = true,
        onDiagnosticsTick: (@MainActor @Sendable (HomeDiagnosticsTick) -> Void)? = nil
    ) {
        self.platformName = platformName
        self.dependencies = dependencies
        self.showsDiagnosticsHUD = showsDiagnosticsHUD
        self.onDiagnosticsTick = onDiagnosticsTick
    }

    public var body: some View {
        VStack(spacing: 14) {
            Text("shadow-client")
                .font(.title2.weight(.semibold))
            Text("Home running on \(platformName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            if showsDiagnosticsHUD {
                diagnosticsCard
            } else {
                hudHiddenCard
            }
        }
        .padding(24)
        .onAppear {
            startTelemetrySubscription()
        }
        .onDisappear {
            stopTelemetrySubscription()
        }
    }

    private var diagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Low-Latency Debug HUD")
                .font(.headline)
            Text("Tone: \(diagnostics.tone.rawValue.uppercased())")
                .font(.caption.weight(.semibold))
                .foregroundStyle(toneColor)
            Text("Target Buffer: \(diagnostics.bufferMs) ms")
                .font(.caption.monospacedDigit())
            Text("Jitter: \(diagnostics.jitterMs) ms | Packet Loss: \(String(format: "%.1f", diagnostics.packetLossPercent))%")
                .font(.caption.monospacedDigit())
            Text("Frame Drop: \(String(format: "%.1f", diagnostics.frameDropPercent))% | AV Sync: \(diagnostics.avSyncOffsetMs) ms")
                .font(.caption.monospacedDigit())
            Text("Drop Origin: NET \(diagnostics.networkDroppedFrames) | PACER \(diagnostics.pacerDroppedFrames)")
                .font(.caption.monospacedDigit())
            if diagnostics.recoveryStableSamplesRemaining > 0 {
                Text("Recovery Hold: \(diagnostics.recoveryStableSamplesRemaining) stable sample(s) remaining")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.orange)
            }
            if let sessionPlan {
                Text("Session Video: \(sessionPlan.settings.hdrVideoMode.rawValue.uppercased()) | Audio: \(sessionPlan.settings.audioMode.rawValue.uppercased())")
                    .font(.caption.monospacedDigit())
                Text("Reconfig V:\(sessionPlan.shouldRenegotiateVideoPipeline ? "Y" : "N") A:\(sessionPlan.shouldRenegotiateAudioPipeline ? "Y" : "N") | QDrop: \(sessionPlan.shouldApplyQualityDropImmediately ? "Y" : "N")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var hudHiddenCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Low-Latency HUD Disabled")
                .font(.headline)
            Text("Enable diagnostics from Settings to inspect jitter, drop origin, and reconfiguration plans.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let sessionPlan {
                Text("Current Session: \(sessionPlan.settings.hdrVideoMode.rawValue.uppercased()) / \(sessionPlan.settings.audioMode.rawValue.uppercased())")
                    .font(.caption.monospacedDigit())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

    private func startTelemetrySubscription() {
        telemetryCancellable?.cancel()
        telemetryCancellable = dependencies.telemetryPublisher.sink { snapshot in
            Task {
                let tick = await dependencies.diagnosticsRuntime.ingest(snapshot: snapshot)

                await MainActor.run {
                    sessionPlan = tick.sessionPlan
                    diagnostics = tick.model
                    onDiagnosticsTick?(tick)
                }
            }
        }
    }

    private func stopTelemetrySubscription() {
        telemetryCancellable?.cancel()
        telemetryCancellable = nil
    }
}
