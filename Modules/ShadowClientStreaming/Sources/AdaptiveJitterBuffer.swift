public struct AdaptiveJitterBufferPolicy: Equatable, Sendable {
    public let minimumBufferMs: Double
    public let maximumBufferMs: Double
    public let jitterSpikeThresholdMs: Double
    public let packetLossGuardPercent: Double
    public let lowJitterThresholdMs: Double
    public let lowPacketLossPercent: Double
    public let increaseStepMs: Double
    public let decreaseStepMs: Double

    public init(
        minimumBufferMs: Double = 16.0,
        maximumBufferMs: Double = 120.0,
        increaseStepMs: Double = 8.0,
        decreaseStepMs: Double = 2.0,
        packetLossGuardPercent: Double = 2.0,
        jitterSpikeThresholdMs: Double = 45.0,
        lowJitterThresholdMs: Double = 5.0,
        lowPacketLossPercent: Double = 0.5
    ) {
        let normalizedMin = Self.nonNegative(minimumBufferMs)
        let normalizedMax = max(normalizedMin, Self.nonNegative(maximumBufferMs))

        self.minimumBufferMs = normalizedMin
        self.maximumBufferMs = normalizedMax
        self.jitterSpikeThresholdMs = Self.nonNegative(jitterSpikeThresholdMs)
        self.packetLossGuardPercent = Self.nonNegative(packetLossGuardPercent)
        self.lowJitterThresholdMs = Self.nonNegative(lowJitterThresholdMs)
        self.lowPacketLossPercent = Self.nonNegative(lowPacketLossPercent)
        self.increaseStepMs = Self.nonNegative(increaseStepMs)
        self.decreaseStepMs = Self.nonNegative(decreaseStepMs)
    }

    public init(
        minBufferMs: Double,
        maxBufferMs: Double,
        jitterSpikeThresholdMs: Double,
        packetLossGuard: Double,
        lowJitterThresholdMs: Double,
        lowPacketLossThreshold: Double,
        increaseStepMs: Double,
        decreaseStepMs: Double
    ) {
        self.init(
            minimumBufferMs: minBufferMs,
            maximumBufferMs: maxBufferMs,
            increaseStepMs: increaseStepMs,
            decreaseStepMs: decreaseStepMs,
            packetLossGuardPercent: packetLossGuard * 100.0,
            jitterSpikeThresholdMs: jitterSpikeThresholdMs,
            lowJitterThresholdMs: lowJitterThresholdMs,
            lowPacketLossPercent: lowPacketLossThreshold * 100.0
        )
    }

    public var minBufferMs: Double {
        minimumBufferMs
    }

    public var maxBufferMs: Double {
        maximumBufferMs
    }

    func clampedBufferMs(_ bufferMs: Double) -> Double {
        guard bufferMs.isFinite else { return minimumBufferMs }
        return min(max(bufferMs, minimumBufferMs), maximumBufferMs)
    }

    private static func nonNegative(_ value: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        return max(0.0, value)
    }
}

public struct StreamingNetworkSignal: Equatable, Sendable {
    public let jitterMs: Double
    public let packetLossPercent: Double

    public init(jitterMs: Double, packetLossPercent: Double) {
        self.jitterMs = jitterMs
        self.packetLossPercent = packetLossPercent
    }

    public init(jitterMs: Double, packetLossRate: Double) {
        self.init(jitterMs: jitterMs, packetLossPercent: packetLossRate * 100.0)
    }

    public init(jitterMilliseconds: Double, packetLossRate: Double) {
        self.init(jitterMs: jitterMilliseconds, packetLossPercent: packetLossRate * 100.0)
    }

    public var jitterMilliseconds: Double {
        jitterMs
    }

    public var packetLossRate: Double {
        packetLossPercent / 100.0
    }
}

public struct AdaptiveJitterBufferController: Equatable, Sendable {
    public let policy: AdaptiveJitterBufferPolicy

    public init(policy: AdaptiveJitterBufferPolicy = .init()) {
        self.policy = policy
    }

    public func nextBufferMs(currentBufferMs: Int, signal: StreamingNetworkSignal) -> Int {
        let nextValue = nextBufferMs(currentBufferMs: Double(currentBufferMs), signal: signal)
        return Int(nextValue.rounded())
    }

    public func nextBufferMs(currentBufferMs: Double, signal: StreamingNetworkSignal) -> Double {
        let current = policy.clampedBufferMs(currentBufferMs)
        let jitterMs = normalizedJitter(signal.jitterMs)
        let packetLossPercent = normalizedPacketLossPercent(signal.packetLossPercent)

        if jitterMs >= policy.jitterSpikeThresholdMs || packetLossPercent > policy.packetLossGuardPercent {
            return policy.clampedBufferMs(current + policy.increaseStepMs)
        }

        if jitterMs <= policy.lowJitterThresholdMs && packetLossPercent <= policy.lowPacketLossPercent {
            return policy.clampedBufferMs(current - policy.decreaseStepMs)
        }

        return current
    }

    private func normalizedJitter(_ jitterMilliseconds: Double) -> Double {
        guard jitterMilliseconds.isFinite else { return .greatestFiniteMagnitude }
        return max(0.0, jitterMilliseconds)
    }

    private func normalizedPacketLossPercent(_ packetLossPercent: Double) -> Double {
        guard packetLossPercent.isFinite else { return 100.0 }
        return min(max(packetLossPercent, 0.0), 100.0)
    }
}
