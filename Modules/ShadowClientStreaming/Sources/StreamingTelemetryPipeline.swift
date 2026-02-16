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
    private let qualityRecoveryStableSampleThreshold: Int
    private var currentBufferMs: Double
    private var stableSampleStreak: Int
    private var isRecoveryRequired: Bool

    public init(
        controller: LowLatencyStreamingController = .init(),
        initialBufferMs: Double = 40.0,
        qualityRecoveryStableSampleThreshold: Int = 2
    ) {
        self.controller = controller
        self.qualityRecoveryStableSampleThreshold = max(1, qualityRecoveryStableSampleThreshold)
        self.currentBufferMs = initialBufferMs
        self.stableSampleStreak = 0
        self.isRecoveryRequired = false
    }

    public func ingest(_ snapshot: StreamingTelemetrySnapshot) -> LowLatencyStreamingDecision {
        let previousBufferMs = currentBufferMs
        let decision = controller.decide(
            currentBufferMs: currentBufferMs,
            stats: snapshot.stats,
            signal: snapshot.signal
        )
        currentBufferMs = decision.targetBufferMs

        guard decision.stabilityPasses else {
            stableSampleStreak = 0
            isRecoveryRequired = true
            return LowLatencyStreamingDecision(
                targetBufferMs: decision.targetBufferMs,
                action: decision.action,
                stabilityPasses: false,
                recoveryStableSamplesRemaining: qualityRecoveryStableSampleThreshold
            )
        }

        stableSampleStreak += 1

        let shouldHoldReducedQuality =
            isRecoveryRequired &&
            stableSampleStreak < qualityRecoveryStableSampleThreshold

        if shouldHoldReducedQuality {
            currentBufferMs = max(currentBufferMs, previousBufferMs)
            let remaining = qualityRecoveryStableSampleThreshold - stableSampleStreak
            return LowLatencyStreamingDecision(
                targetBufferMs: currentBufferMs,
                action: .requestQualityReduction,
                stabilityPasses: true,
                recoveryStableSamplesRemaining: remaining
            )
        }

        isRecoveryRequired = false
        return LowLatencyStreamingDecision(
            targetBufferMs: decision.targetBufferMs,
            action: decision.action,
            stabilityPasses: true,
            recoveryStableSamplesRemaining: 0
        )
    }

    public func currentTargetBufferMs() -> Double {
        currentBufferMs
    }
}
