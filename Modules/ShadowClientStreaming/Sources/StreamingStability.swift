import ShadowClientCore

public struct StreamingStats: Equatable, Sendable {
    public let renderedFrames: Int
    public let droppedFrames: Int
    public let avSyncOffsetMilliseconds: Double

    public init(renderedFrames: Int, droppedFrames: Int, avSyncOffsetMilliseconds: Double) {
        self.renderedFrames = renderedFrames
        self.droppedFrames = droppedFrames
        self.avSyncOffsetMilliseconds = avSyncOffsetMilliseconds
    }

    public var totalFrames: Int {
        max(0, renderedFrames) + max(0, droppedFrames)
    }
}

public struct StreamingStabilityReport: Equatable, Sendable {
    public let frameDrop: GateEvaluation
    public let avSync: GateEvaluation

    public init(frameDrop: GateEvaluation, avSync: GateEvaluation) {
        self.frameDrop = frameDrop
        self.avSync = avSync
    }

    public var passes: Bool {
        frameDrop.passes && avSync.passes
    }
}

public struct StreamingStabilityChecker: Sendable {
    public let frameDropGate: FrameDropRateGate
    public let avSyncGate: AVSyncGate

    public init(
        frameDropGate: FrameDropRateGate = .init(),
        avSyncGate: AVSyncGate = .init()
    ) {
        self.frameDropGate = frameDropGate
        self.avSyncGate = avSyncGate
    }

    public func evaluate(_ stats: StreamingStats) -> StreamingStabilityReport {
        let frameDrop = frameDropGate.evaluate(
            droppedFrames: stats.droppedFrames,
            totalFrames: stats.totalFrames
        )
        let avSync = avSyncGate.evaluate(offsetMilliseconds: stats.avSyncOffsetMilliseconds)
        return StreamingStabilityReport(frameDrop: frameDrop, avSync: avSync)
    }
}
