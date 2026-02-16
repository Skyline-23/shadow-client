public enum StreamingRecoveryAction: String, Equatable, Sendable {
    case holdQuality
    case requestQualityReduction
}

public struct LowLatencyStreamingDecision: Equatable, Sendable {
    public let targetBufferMs: Double
    public let action: StreamingRecoveryAction
    public let stabilityPasses: Bool
    public let recoveryStableSamplesRemaining: Int

    public init(
        targetBufferMs: Double,
        action: StreamingRecoveryAction,
        stabilityPasses: Bool,
        recoveryStableSamplesRemaining: Int = 0
    ) {
        self.targetBufferMs = targetBufferMs
        self.action = action
        self.stabilityPasses = stabilityPasses
        self.recoveryStableSamplesRemaining = max(0, recoveryStableSamplesRemaining)
    }
}

public struct LowLatencyStreamingController: Sendable {
    public let stabilityChecker: StreamingStabilityChecker
    public let jitterBufferController: AdaptiveJitterBufferController

    public init(
        stabilityChecker: StreamingStabilityChecker = .init(),
        jitterBufferController: AdaptiveJitterBufferController = .init()
    ) {
        self.stabilityChecker = stabilityChecker
        self.jitterBufferController = jitterBufferController
    }

    public func decide(
        currentBufferMs: Double,
        stats: StreamingStats,
        signal: StreamingNetworkSignal
    ) -> LowLatencyStreamingDecision {
        let stability = stabilityChecker.evaluate(stats)
        let targetBufferMs = jitterBufferController.nextBufferMs(
            currentBufferMs: currentBufferMs,
            signal: signal
        )

        let action: StreamingRecoveryAction = stability.passes ? .holdQuality : .requestQualityReduction

        return LowLatencyStreamingDecision(
            targetBufferMs: targetBufferMs,
            action: action,
            stabilityPasses: stability.passes
        )
    }
}
