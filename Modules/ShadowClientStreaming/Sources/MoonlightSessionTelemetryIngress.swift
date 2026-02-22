import Foundation

private actor TelemetryBridgeRegistry {
    private var bridge: MoonlightSessionTelemetryBridge = .shared

    func setBridge(_ bridge: MoonlightSessionTelemetryBridge) {
        self.bridge = bridge
    }

    func getBridge() -> MoonlightSessionTelemetryBridge {
        bridge
    }
}

private final class TelemetryIngressActivityRegistry {
    private struct ActivityState {
        var callbackCount = 0
        var lastCallbackTimestampMs: Int?
    }

    private let lock = NSLock()
    private var globalActivity = ActivityState()
    private var perBridgeActivity: [ObjectIdentifier: ActivityState] = [:]

    func record(timestampMs: Int, bridge: MoonlightSessionTelemetryBridge) {
        lock.lock()
        globalActivity.callbackCount += 1
        globalActivity.lastCallbackTimestampMs = timestampMs

        let identifier = ObjectIdentifier(bridge)
        var bridgeActivity = perBridgeActivity[identifier] ?? ActivityState()
        bridgeActivity.callbackCount += 1
        bridgeActivity.lastCallbackTimestampMs = timestampMs
        perBridgeActivity[identifier] = bridgeActivity
        lock.unlock()
    }

    func recordGlobal(timestampMs: Int) {
        lock.lock()
        globalActivity.callbackCount += 1
        globalActivity.lastCallbackTimestampMs = timestampMs
        lock.unlock()
    }

    func recordPerBridge(timestampMs: Int, bridge: MoonlightSessionTelemetryBridge) {
        lock.lock()
        let identifier = ObjectIdentifier(bridge)
        var bridgeActivity = perBridgeActivity[identifier] ?? ActivityState()
        bridgeActivity.callbackCount += 1
        bridgeActivity.lastCallbackTimestampMs = timestampMs
        perBridgeActivity[identifier] = bridgeActivity
        lock.unlock()
    }

    func current() -> MoonlightTelemetryIngressActivity {
        lock.lock()
        defer { lock.unlock() }
        return MoonlightTelemetryIngressActivity(
            callbackCount: globalActivity.callbackCount,
            lastCallbackTimestampMs: globalActivity.lastCallbackTimestampMs
        )
    }

    func current(for bridge: MoonlightSessionTelemetryBridge) -> MoonlightTelemetryIngressActivity {
        lock.lock()
        defer { lock.unlock() }
        let identifier = ObjectIdentifier(bridge)
        let bridgeActivity = perBridgeActivity[identifier] ?? ActivityState()

        return MoonlightTelemetryIngressActivity(
            callbackCount: bridgeActivity.callbackCount,
            lastCallbackTimestampMs: bridgeActivity.lastCallbackTimestampMs
        )
    }

    func reset() {
        lock.lock()
        globalActivity = ActivityState()
        perBridgeActivity.removeAll()
        lock.unlock()
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
        activityRegistry.current()
    }

    public static func callbackActivity(
        for bridge: MoonlightSessionTelemetryBridge
    ) async -> MoonlightTelemetryIngressActivity {
        activityRegistry.current(for: bridge)
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
        await ingestFromCallback(
            renderedFrames: renderedFrames,
            networkDroppedFrames: networkDroppedFrames,
            pacerDroppedFrames: pacerDroppedFrames,
            jitterMs: jitterMs,
            packetLossPercent: packetLossPercent,
            avSyncOffsetMs: avSyncOffsetMs,
            timestampMs: timestampMs,
            bridge: bridge,
            recordGlobalActivity: true,
            recordPerBridgeActivity: true
        )
    }

    private static func ingestFromCallback(
        renderedFrames: Int32,
        networkDroppedFrames: Int32,
        pacerDroppedFrames: Int32,
        jitterMs: Double,
        packetLossPercent: Double,
        avSyncOffsetMs: Double,
        timestampMs: Int64,
        bridge: MoonlightSessionTelemetryBridge,
        recordGlobalActivity: Bool,
        recordPerBridgeActivity: Bool
    ) async {
        if recordGlobalActivity {
            activityRegistry.recordGlobal(timestampMs: Int(timestampMs))
        }

        if recordPerBridgeActivity {
            activityRegistry.recordPerBridge(timestampMs: Int(timestampMs), bridge: bridge)
        }

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
