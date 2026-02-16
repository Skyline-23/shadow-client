import ShadowClientStreaming
import ShadowClientUI

public struct HomeDiagnosticsTick: Equatable, Sendable {
    public let model: StreamingDiagnosticsModel
    public let timestampMs: Int

    public init(model: StreamingDiagnosticsModel, timestampMs: Int) {
        self.model = model
        self.timestampMs = timestampMs
    }
}

public actor HomeDiagnosticsRuntime {
    private let pipeline: LowLatencyTelemetryPipeline
    private let presenter: StreamingDiagnosticsPresenter

    public init(
        pipeline: LowLatencyTelemetryPipeline = .init(),
        presenter: StreamingDiagnosticsPresenter = .init()
    ) {
        self.pipeline = pipeline
        self.presenter = presenter
    }

    public func ingest(qtSample: MoonlightQTTelemetrySample) async -> HomeDiagnosticsTick {
        let snapshot = StreamingTelemetrySnapshot(qtSample: qtSample)
        let decision = await pipeline.ingest(snapshot)
        let model = presenter.makeModel(
            decision: decision,
            signal: snapshot.signal,
            stats: snapshot.stats,
            dropBreakdown: snapshot.dropBreakdown
        )

        return HomeDiagnosticsTick(model: model, timestampMs: snapshot.timestampMs)
    }
}
