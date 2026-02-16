import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

public struct ShadowClientFeatureHomeView: View {
    private let platformName: String
    private let pipeline = LowLatencyTelemetryPipeline(initialBufferMs: 40.0)
    private let diagnosticsPresenter = StreamingDiagnosticsPresenter()
    private let ticker = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    @State private var telemetryIndex: Int = 0
    @State private var diagnostics = StreamingDiagnosticsModel(
        bufferMs: 40,
        jitterMs: 0,
        packetLossPercent: 0.0,
        frameDropPercent: 0.0,
        avSyncOffsetMs: 0,
        tone: .healthy
    )

    public init(platformName: String) {
        self.platformName = platformName
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
            applyNextTelemetrySample()
        }
        .onReceive(ticker) { _ in
            applyNextTelemetrySample()
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

    private func applyNextTelemetrySample() {
        let samples = Self.qtTelemetrySamples
        let sample = samples[telemetryIndex % samples.count]
        telemetryIndex += 1

        Task {
            let snapshot = StreamingTelemetrySnapshot(qtSample: sample)
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

    private static let qtTelemetrySamples: [MoonlightQTTelemetrySample] = [
        .init(
            renderedFrames: 995,
            networkDroppedFrames: 2,
            pacerDroppedFrames: 3,
            jitterMs: 3.0,
            packetLossPercent: 0.2,
            avSyncOffsetMs: 14.0,
            timestampMs: 1_000
        ),
        .init(
            renderedFrames: 990,
            networkDroppedFrames: 4,
            pacerDroppedFrames: 6,
            jitterMs: 12.0,
            packetLossPercent: 0.4,
            avSyncOffsetMs: 19.0,
            timestampMs: 1_016
        ),
        .init(
            renderedFrames: 965,
            networkDroppedFrames: 18,
            pacerDroppedFrames: 17,
            jitterMs: 78.0,
            packetLossPercent: 3.2,
            avSyncOffsetMs: 53.0,
            timestampMs: 1_032
        ),
    ]
}
