import ShadowClientStreaming

public struct StreamingDiagnosticsModel: Equatable, Sendable {
    public let bufferMs: Int
    public let jitterMs: Int
    public let packetLossPercent: Double
    public let frameDropPercent: Double
    public let avSyncOffsetMs: Int
    public let tone: HealthTone

    public init(
        bufferMs: Int,
        jitterMs: Int,
        packetLossPercent: Double,
        frameDropPercent: Double,
        avSyncOffsetMs: Int,
        tone: HealthTone
    ) {
        self.bufferMs = bufferMs
        self.jitterMs = jitterMs
        self.packetLossPercent = packetLossPercent
        self.frameDropPercent = frameDropPercent
        self.avSyncOffsetMs = avSyncOffsetMs
        self.tone = tone
    }
}

public struct StreamingDiagnosticsPresenter: Sendable {
    public init() {}

    public func makeModel(
        decision: LowLatencyStreamingDecision,
        signal: StreamingNetworkSignal,
        stats: StreamingStats
    ) -> StreamingDiagnosticsModel {
        let frameDropPercent: Double
        if stats.totalFrames > 0 {
            frameDropPercent = (Double(stats.droppedFrames) / Double(stats.totalFrames)) * 100.0
        } else {
            frameDropPercent = .infinity
        }

        let tone: HealthTone
        if decision.action == .requestQualityReduction {
            tone = .critical
        } else if decision.stabilityPasses {
            tone = .healthy
        } else {
            tone = .warning
        }

        return StreamingDiagnosticsModel(
            bufferMs: Int(decision.targetBufferMs.rounded()),
            jitterMs: Int(signal.jitterMs.rounded()),
            packetLossPercent: signal.packetLossPercent,
            frameDropPercent: frameDropPercent,
            avSyncOffsetMs: Int(stats.avSyncOffsetMilliseconds.rounded()),
            tone: tone
        )
    }
}
