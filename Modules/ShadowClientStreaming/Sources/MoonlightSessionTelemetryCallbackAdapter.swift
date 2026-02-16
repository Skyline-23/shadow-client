public struct MoonlightSessionRawTelemetry: Equatable, Sendable {
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

public enum MoonlightSessionTelemetryCallbackAdapter {
    public static func ingest(
        _ raw: MoonlightSessionRawTelemetry,
        bridge: MoonlightSessionTelemetryBridge
    ) async {
        let sample = MoonlightQTTelemetrySample(
            renderedFrames: raw.renderedFrames,
            networkDroppedFrames: raw.networkDroppedFrames,
            pacerDroppedFrames: raw.pacerDroppedFrames,
            jitterMs: raw.jitterMs,
            packetLossPercent: raw.packetLossPercent,
            avSyncOffsetMs: raw.avSyncOffsetMs,
            timestampMs: raw.timestampMs
        )

        await bridge.ingest(qtSample: sample)
    }
}
