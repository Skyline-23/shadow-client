public struct GateEvaluation: Equatable, Sendable {
    public let metric: String
    public let observed: Double
    public let threshold: Double
    public let passes: Bool

    public init(metric: String, observed: Double, threshold: Double, passes: Bool) {
        self.metric = metric
        self.observed = observed
        self.threshold = threshold
        self.passes = passes
    }
}

public struct InputRTTP95Gate: Sendable {
    public let thresholdMilliseconds: Double

    public init(thresholdMilliseconds: Double = 35.0) {
        self.thresholdMilliseconds = thresholdMilliseconds
    }

    public func evaluate(p95Milliseconds: Double) -> GateEvaluation {
        GateEvaluation(
            metric: "input_rtt_p95_ms",
            observed: p95Milliseconds,
            threshold: thresholdMilliseconds,
            passes: p95Milliseconds <= thresholdMilliseconds
        )
    }
}

public struct FrameDropRateGate: Sendable {
    public let thresholdPercent: Double

    public init(thresholdPercent: Double = 1.0) {
        self.thresholdPercent = thresholdPercent
    }

    public func evaluate(dropRatePercent: Double) -> GateEvaluation {
        GateEvaluation(
            metric: "frame_drop_percent",
            observed: dropRatePercent,
            threshold: thresholdPercent,
            passes: dropRatePercent <= thresholdPercent
        )
    }

    public func evaluate(droppedFrames: Int, totalFrames: Int) -> GateEvaluation {
        guard droppedFrames >= 0, totalFrames > 0 else {
            return GateEvaluation(
                metric: "frame_drop_percent",
                observed: .infinity,
                threshold: thresholdPercent,
                passes: false
            )
        }

        let dropRatePercent = (Double(droppedFrames) / Double(totalFrames)) * 100.0
        return evaluate(dropRatePercent: dropRatePercent)
    }
}

public struct AVSyncGate: Sendable {
    public let thresholdMilliseconds: Double

    public init(thresholdMilliseconds: Double = 40.0) {
        self.thresholdMilliseconds = thresholdMilliseconds
    }

    public func evaluate(offsetMilliseconds: Double) -> GateEvaluation {
        let absoluteOffset = Swift.abs(offsetMilliseconds)
        return GateEvaluation(
            metric: "av_sync_offset_ms",
            observed: absoluteOffset,
            threshold: thresholdMilliseconds,
            passes: absoluteOffset <= thresholdMilliseconds
        )
    }
}
