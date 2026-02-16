import Combine
import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

public struct ShadowClientFeatureHomeDependencies {
    public let telemetryPublisher: AnyPublisher<StreamingTelemetrySnapshot, Never>
    public let pipeline: LowLatencyTelemetryPipeline
    public let diagnosticsPresenter: StreamingDiagnosticsPresenter
    public let settingsMapper: StreamingSessionSettingsMapper
    public let launchPlanBuilder: MoonlightSessionLaunchPlanBuilder
    public let sessionPreferences: StreamingUserPreferences
    public let hostCapabilities: HostStreamingCapabilities

    public init(
        telemetryPublisher: AnyPublisher<StreamingTelemetrySnapshot, Never>,
        pipeline: LowLatencyTelemetryPipeline,
        diagnosticsPresenter: StreamingDiagnosticsPresenter,
        settingsMapper: StreamingSessionSettingsMapper,
        launchPlanBuilder: MoonlightSessionLaunchPlanBuilder,
        sessionPreferences: StreamingUserPreferences,
        hostCapabilities: HostStreamingCapabilities
    ) {
        self.telemetryPublisher = telemetryPublisher
        self.pipeline = pipeline
        self.diagnosticsPresenter = diagnosticsPresenter
        self.settingsMapper = settingsMapper
        self.launchPlanBuilder = launchPlanBuilder
        self.sessionPreferences = sessionPreferences
        self.hostCapabilities = hostCapabilities
    }
}

public extension ShadowClientFeatureHomeDependencies {
    static func live(bridge: MoonlightSessionTelemetryBridge) -> Self {
        .init(
            telemetryPublisher: bridge.snapshotPublisher,
            pipeline: LowLatencyTelemetryPipeline(initialBufferMs: 40.0),
            diagnosticsPresenter: StreamingDiagnosticsPresenter(),
            settingsMapper: StreamingSessionSettingsMapper(),
            launchPlanBuilder: MoonlightSessionLaunchPlanBuilder(),
            sessionPreferences: StreamingUserPreferences(
                preferHDR: true,
                preferSurroundAudio: true,
                lowLatencyMode: true
            ),
            hostCapabilities: HostStreamingCapabilities(
                supportsHDR10: true,
                supportsSurround51: true
            )
        )
    }

    static func preview() -> Self {
        live(bridge: MoonlightSessionTelemetryBridge())
    }
}

public struct ShadowClientFeatureHomeView: View {
    private let platformName: String
    private let dependencies: ShadowClientFeatureHomeDependencies

    @State private var telemetryCancellable: AnyCancellable?
    @State private var previousLaunchSettings: MoonlightSessionLaunchSettings?
    @State private var sessionPlan: MoonlightSessionReconfigurationPlan?
    @State private var diagnostics = StreamingDiagnosticsModel(
        bufferMs: 40,
        jitterMs: 0,
        packetLossPercent: 0.0,
        frameDropPercent: 0.0,
        avSyncOffsetMs: 0,
        recoveryStableSamplesRemaining: 0,
        tone: .healthy
    )

    public init(platformName: String, dependencies: ShadowClientFeatureHomeDependencies) {
        self.platformName = platformName
        self.dependencies = dependencies
    }

    public var body: some View {
        VStack(spacing: 14) {
            Text("shadow-client")
                .font(.title2.weight(.semibold))
            Text("Home running on \(platformName)")
                .font(.footnote)
                .foregroundStyle(.secondary)
            diagnosticsCard
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
                let decision = await dependencies.pipeline.ingest(snapshot)
                let model = dependencies.diagnosticsPresenter.makeModel(
                    decision: decision,
                    signal: snapshot.signal,
                    stats: snapshot.stats
                )
                let sessionConfiguration = dependencies.settingsMapper.map(
                    preferences: dependencies.sessionPreferences,
                    capabilities: dependencies.hostCapabilities,
                    signal: snapshot.signal
                )

                await MainActor.run {
                    let plan = dependencies.launchPlanBuilder.makePlan(
                        previousSettings: previousLaunchSettings,
                        sessionConfiguration: sessionConfiguration,
                        decision: decision
                    )
                    previousLaunchSettings = plan.settings
                    sessionPlan = plan
                    diagnostics = model
                }
            }
        }
    }

    private func stopTelemetrySubscription() {
        telemetryCancellable?.cancel()
        telemetryCancellable = nil
    }
}
