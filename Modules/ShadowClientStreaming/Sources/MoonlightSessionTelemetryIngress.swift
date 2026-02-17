private actor TelemetryBridgeRegistry {
    private var bridge: MoonlightSessionTelemetryBridge = .shared

    func setBridge(_ bridge: MoonlightSessionTelemetryBridge) {
        self.bridge = bridge
    }

    func getBridge() -> MoonlightSessionTelemetryBridge {
        bridge
    }
}

private actor TelemetryIngressActivityRegistry {
    private var callbackCount = 0
    private var lastCallbackTimestampMs: Int?

    func record(timestampMs: Int) {
        callbackCount += 1
        lastCallbackTimestampMs = timestampMs
    }

    func current() -> MoonlightTelemetryIngressActivity {
        MoonlightTelemetryIngressActivity(
            callbackCount: callbackCount,
            lastCallbackTimestampMs: lastCallbackTimestampMs
        )
    }

    func reset() {
        callbackCount = 0
        lastCallbackTimestampMs = nil
    }
}

public struct MoonlightTelemetryIngressActivity: Equatable, Sendable {
    public let callbackCount: Int
    public let lastCallbackTimestampMs: Int?

    public init(
        callbackCount: Int,
        lastCallbackTimestampMs: Int?
    ) {
        self.callbackCount = callbackCount
        self.lastCallbackTimestampMs = lastCallbackTimestampMs
    }
}

public enum MoonlightSessionTelemetryIngress {
    private static let registry = TelemetryBridgeRegistry()
    private static let activityRegistry = TelemetryIngressActivityRegistry()

    public static func configure(bridge: MoonlightSessionTelemetryBridge) {
        Task {
            await registry.setBridge(bridge)
        }
    }

    public static func callbackActivity() async -> MoonlightTelemetryIngressActivity {
        await activityRegistry.current()
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
        await activityRegistry.record(timestampMs: Int(timestampMs))

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

    static func resetActivityForTests() async {
        await activityRegistry.reset()
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
