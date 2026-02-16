public struct StreamingDropBreakdown: Equatable, Sendable {
    public let networkDroppedFrames: Int
    public let pacerDroppedFrames: Int

    public init(networkDroppedFrames: Int, pacerDroppedFrames: Int) {
        self.networkDroppedFrames = max(0, networkDroppedFrames)
        self.pacerDroppedFrames = max(0, pacerDroppedFrames)
    }

    public static var zero: StreamingDropBreakdown {
        .init(networkDroppedFrames: 0, pacerDroppedFrames: 0)
    }
}

public struct StreamingTelemetrySnapshot: Equatable, Sendable {
    public let stats: StreamingStats
    public let signal: StreamingNetworkSignal
    public let timestampMs: Int
    public let dropBreakdown: StreamingDropBreakdown

    public init(
        stats: StreamingStats,
        signal: StreamingNetworkSignal,
        timestampMs: Int,
        dropBreakdown: StreamingDropBreakdown = .zero
    ) {
        self.stats = stats
        self.signal = signal
        self.timestampMs = timestampMs
        self.dropBreakdown = dropBreakdown
    }
}

public actor LowLatencyTelemetryPipeline {
    private let controller: LowLatencyStreamingController
    private let qualityRecoveryStableSampleThreshold: Int
    private var currentBufferMs: Double
    private var stableSampleStreak: Int
    private var isRecoveryRequired: Bool
    private var latestTimestampMs: Int?
    private var latestDecision: LowLatencyStreamingDecision

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
        self.latestTimestampMs = nil
        self.latestDecision = LowLatencyStreamingDecision(
            targetBufferMs: initialBufferMs,
            action: .holdQuality,
            stabilityPasses: true
        )
    }

    public func ingest(_ snapshot: StreamingTelemetrySnapshot) -> LowLatencyStreamingDecision {
        if let latestTimestampMs, snapshot.timestampMs < latestTimestampMs {
            return latestDecision
        }

        let previousBufferMs = currentBufferMs
        let decision = controller.decide(
            currentBufferMs: currentBufferMs,
            stats: snapshot.stats,
            signal: snapshot.signal
        )
        currentBufferMs = decision.targetBufferMs

        let outputDecision: LowLatencyStreamingDecision
        guard decision.stabilityPasses else {
            stableSampleStreak = 0
            isRecoveryRequired = true
            outputDecision = LowLatencyStreamingDecision(
                targetBufferMs: decision.targetBufferMs,
                action: decision.action,
                stabilityPasses: false,
                recoveryStableSamplesRemaining: qualityRecoveryStableSampleThreshold
            )
            latestTimestampMs = snapshot.timestampMs
            latestDecision = outputDecision
            return outputDecision
        }

        stableSampleStreak += 1

        let shouldHoldReducedQuality =
            isRecoveryRequired &&
            stableSampleStreak < qualityRecoveryStableSampleThreshold

        if shouldHoldReducedQuality {
            currentBufferMs = max(currentBufferMs, previousBufferMs)
            let remaining = qualityRecoveryStableSampleThreshold - stableSampleStreak
            outputDecision = LowLatencyStreamingDecision(
                targetBufferMs: currentBufferMs,
                action: .requestQualityReduction,
                stabilityPasses: true,
                recoveryStableSamplesRemaining: remaining
            )
            latestTimestampMs = snapshot.timestampMs
            latestDecision = outputDecision
            return outputDecision
        }

        isRecoveryRequired = false
        outputDecision = LowLatencyStreamingDecision(
            targetBufferMs: decision.targetBufferMs,
            action: decision.action,
            stabilityPasses: true,
            recoveryStableSamplesRemaining: 0
        )
        latestTimestampMs = snapshot.timestampMs
        latestDecision = outputDecision
        return outputDecision
    }

    public func currentTargetBufferMs() -> Double {
        currentBufferMs
    }
}
