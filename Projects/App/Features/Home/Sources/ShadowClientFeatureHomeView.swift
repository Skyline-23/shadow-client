import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

public struct ShadowClientFeatureHomeView: View {
    private let platformName: String
    private let controller = LowLatencyStreamingController()
    private let diagnosticsPresenter = StreamingDiagnosticsPresenter()
    private let ticker = Timer.publish(every: 0.8, on: .main, in: .common).autoconnect()

    @State private var telemetryIndex: Int = 0
    @State private var currentBufferMs: Double = 40.0
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
        let samples = Self.telemetrySamples
        let sample = samples[telemetryIndex % samples.count]
        telemetryIndex += 1

        let decision = controller.decide(
            currentBufferMs: currentBufferMs,
            stats: sample.stats,
            signal: sample.signal
        )
        currentBufferMs = decision.targetBufferMs
        diagnostics = diagnosticsPresenter.makeModel(
            decision: decision,
            signal: sample.signal,
            stats: sample.stats
        )
    }

    private static let telemetrySamples: [TelemetrySample] = [
        .init(
            stats: .init(renderedFrames: 995, droppedFrames: 5, avSyncOffsetMilliseconds: 14.0),
            signal: .init(jitterMs: 3.0, packetLossPercent: 0.2)
        ),
        .init(
            stats: .init(renderedFrames: 990, droppedFrames: 10, avSyncOffsetMilliseconds: 19.0),
            signal: .init(jitterMs: 12.0, packetLossPercent: 0.4)
        ),
        .init(
            stats: .init(renderedFrames: 965, droppedFrames: 35, avSyncOffsetMilliseconds: 53.0),
            signal: .init(jitterMs: 78.0, packetLossPercent: 3.2)
        ),
    ]
}

private struct TelemetrySample {
    let stats: StreamingStats
    let signal: StreamingNetworkSignal
}
