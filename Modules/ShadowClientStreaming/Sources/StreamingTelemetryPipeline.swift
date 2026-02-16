public struct StreamingTelemetrySnapshot: Equatable, Sendable {
    public let stats: StreamingStats
    public let signal: StreamingNetworkSignal
    public let timestampMs: Int

    public init(stats: StreamingStats, signal: StreamingNetworkSignal, timestampMs: Int) {
        self.stats = stats
        self.signal = signal
        self.timestampMs = timestampMs
    }
}

public actor LowLatencyTelemetryPipeline {
    private let controller: LowLatencyStreamingController
    private var currentBufferMs: Double

    public init(
        controller: LowLatencyStreamingController = .init(),
        initialBufferMs: Double = 40.0
    ) {
        self.controller = controller
        self.currentBufferMs = initialBufferMs
    }

    public func ingest(_ snapshot: StreamingTelemetrySnapshot) -> LowLatencyStreamingDecision {
        let decision = controller.decide(
            currentBufferMs: currentBufferMs,
            stats: snapshot.stats,
            signal: snapshot.signal
        )
        currentBufferMs = decision.targetBufferMs
        return decision
    }

    public func currentTargetBufferMs() -> Double {
        currentBufferMs
    }
}
