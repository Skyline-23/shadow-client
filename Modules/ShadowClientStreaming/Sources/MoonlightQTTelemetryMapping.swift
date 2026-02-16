public struct MoonlightQTTelemetrySample: Equatable, Sendable {
    public let renderedFrames: Int
    public let networkDroppedFrames: Int
    public let pacerDroppedFrames: Int
    public let jitterMs: Double
    public let packetLossPercent: Double
    public let avSyncOffsetMs: Double
    public let timestampMs: Int

    public init(
        renderedFrames: Int,
        networkDroppedFrames: Int,
        pacerDroppedFrames: Int,
        jitterMs: Double,
        packetLossPercent: Double,
        avSyncOffsetMs: Double,
        timestampMs: Int
    ) {
        self.renderedFrames = renderedFrames
        self.networkDroppedFrames = networkDroppedFrames
        self.pacerDroppedFrames = pacerDroppedFrames
        self.jitterMs = jitterMs
        self.packetLossPercent = packetLossPercent
        self.avSyncOffsetMs = avSyncOffsetMs
        self.timestampMs = timestampMs
    }
}

public extension StreamingTelemetrySnapshot {
    init(qtSample: MoonlightQTTelemetrySample) {
        let clampedRendered = max(0, qtSample.renderedFrames)
        let clampedNetworkDrop = max(0, qtSample.networkDroppedFrames)
        let clampedPacerDrop = max(0, qtSample.pacerDroppedFrames)
        let totalDropped = clampedNetworkDrop + clampedPacerDrop

        self.init(
            stats: StreamingStats(
                renderedFrames: clampedRendered,
                droppedFrames: totalDropped,
                avSyncOffsetMilliseconds: qtSample.avSyncOffsetMs
            ),
            signal: StreamingNetworkSignal(
                jitterMs: qtSample.jitterMs,
                packetLossPercent: qtSample.packetLossPercent
            ),
            timestampMs: qtSample.timestampMs,
            dropBreakdown: .init(
                networkDroppedFrames: clampedNetworkDrop,
                pacerDroppedFrames: clampedPacerDrop
            )
        )
    }
}
