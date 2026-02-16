private actor TelemetryBridgeRegistry {
    private var bridge: MoonlightSessionTelemetryBridge = .shared

    func setBridge(_ bridge: MoonlightSessionTelemetryBridge) {
        self.bridge = bridge
    }

    func getBridge() -> MoonlightSessionTelemetryBridge {
        bridge
    }
}

public enum MoonlightSessionTelemetryIngress {
    private static let registry = TelemetryBridgeRegistry()

    public static func configure(bridge: MoonlightSessionTelemetryBridge) {
        Task {
            await registry.setBridge(bridge)
        }
    }

    public static func ingestFromCallback(
        renderedFrames: Int32,
        networkDroppedFrames: Int32,
        pacerDroppedFrames: Int32,
        jitterMs: Double,
        packetLossPercent: Double,
        avSyncOffsetMs: Double,
        timestampMs: Int64,
        bridge: MoonlightSessionTelemetryBridge
    ) async {
        let raw = MoonlightSessionRawTelemetry(
            renderedFrames: Int(renderedFrames),
            networkDroppedFrames: Int(networkDroppedFrames),
            pacerDroppedFrames: Int(pacerDroppedFrames),
            jitterMs: jitterMs,
            packetLossPercent: packetLossPercent,
            avSyncOffsetMs: avSyncOffsetMs,
            timestampMs: Int(timestampMs)
        )

        await MoonlightSessionTelemetryCallbackAdapter.ingest(raw, bridge: bridge)
    }

    public static func ingestFromCallbackNonBlocking(
        renderedFrames: Int32,
        networkDroppedFrames: Int32,
        pacerDroppedFrames: Int32,
        jitterMs: Double,
        packetLossPercent: Double,
        avSyncOffsetMs: Double,
        timestampMs: Int64,
        bridge: MoonlightSessionTelemetryBridge
    ) {
        Task.detached(priority: .high) {
            await ingestFromCallback(
                renderedFrames: renderedFrames,
                networkDroppedFrames: networkDroppedFrames,
                pacerDroppedFrames: pacerDroppedFrames,
                jitterMs: jitterMs,
                packetLossPercent: packetLossPercent,
                avSyncOffsetMs: avSyncOffsetMs,
                timestampMs: timestampMs,
                bridge: bridge
            )
        }
    }

    static func ingestFromConfiguredBridgeNonBlocking(
        renderedFrames: Int32,
        networkDroppedFrames: Int32,
        pacerDroppedFrames: Int32,
        jitterMs: Double,
        packetLossPercent: Double,
        avSyncOffsetMs: Double,
        timestampMs: Int64
    ) {
        Task.detached(priority: .high) {
            let bridge = await registry.getBridge()
            await ingestFromCallback(
                renderedFrames: renderedFrames,
                networkDroppedFrames: networkDroppedFrames,
                pacerDroppedFrames: pacerDroppedFrames,
                jitterMs: jitterMs,
                packetLossPercent: packetLossPercent,
                avSyncOffsetMs: avSyncOffsetMs,
                timestampMs: timestampMs,
                bridge: bridge
            )
        }
    }
}

@_cdecl("shadow_client_ingest_telemetry")
public func shadow_client_ingest_telemetry(
    _ renderedFrames: Int32,
    _ networkDroppedFrames: Int32,
    _ pacerDroppedFrames: Int32,
    _ jitterMs: Double,
    _ packetLossPercent: Double,
    _ avSyncOffsetMs: Double,
    _ timestampMs: Int64
) {
    MoonlightSessionTelemetryIngress.ingestFromConfiguredBridgeNonBlocking(
        renderedFrames: renderedFrames,
        networkDroppedFrames: networkDroppedFrames,
        pacerDroppedFrames: pacerDroppedFrames,
        jitterMs: jitterMs,
        packetLossPercent: packetLossPercent,
        avSyncOffsetMs: avSyncOffsetMs,
        timestampMs: timestampMs
    )
}
