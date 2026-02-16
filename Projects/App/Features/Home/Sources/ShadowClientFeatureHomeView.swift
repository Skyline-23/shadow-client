import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

public struct ShadowClientFeatureHomeView: View {
    private let platformName: String
    private let pipeline = LowLatencyTelemetryPipeline(initialBufferMs: 40.0)
    private let diagnosticsPresenter = StreamingDiagnosticsPresenter()
    private let sessionBridge: MoonlightSessionTelemetryBridge

    @State private var telemetryTask: Task<Void, Never>?
    @State private var diagnostics = StreamingDiagnosticsModel(
        bufferMs: 40,
        jitterMs: 0,
        packetLossPercent: 0.0,
        frameDropPercent: 0.0,
        avSyncOffsetMs: 0,
        tone: .healthy
    )

    public init(
        platformName: String,
        sessionBridge: MoonlightSessionTelemetryBridge = .shared
    ) {
        self.platformName = platformName
        self.sessionBridge = sessionBridge
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
            startTelemetryLoop()
        }
        .onDisappear {
            stopTelemetryLoop()
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

    private func startTelemetryLoop() {
        telemetryTask?.cancel()
        telemetryTask = Task {
            let stream = await sessionBridge.snapshotStream()
            for await snapshot in stream {
                if Task.isCancelled {
                    break
                }

                let decision = await pipeline.ingest(snapshot)
                let model = diagnosticsPresenter.makeModel(
                    decision: decision,
                    signal: snapshot.signal,
                    stats: snapshot.stats
                )

                await MainActor.run {
                    diagnostics = model
                }
            }
        }
    }

    private func stopTelemetryLoop() {
        telemetryTask?.cancel()
        telemetryTask = nil
    }
}
