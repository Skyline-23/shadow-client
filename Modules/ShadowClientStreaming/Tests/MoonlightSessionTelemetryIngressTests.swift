import Testing
@testable import ShadowClientStreaming

@Test("Telemetry ingress async callback ingest maps payload and emits snapshot")
func telemetryIngressAsyncCallbackIngestMapsAndEmitsSnapshot() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let stream = await bridge.snapshotStream()

    let renderedFrames: Int32 = 2_048
    let networkDroppedFrames: Int32 = 12
    let pacerDroppedFrames: Int32 = 5
    let jitterMs = 13.5
    let packetLossPercent = 0.9
    let avSyncOffsetMs = 6.25
    let timestampMs: Int64 = 99_001

    async let firstSnapshot = stream.first(where: { $0.timestampMs == Int(timestampMs) })
    await MoonlightSessionTelemetryIngress.ingestFromCallback(
        renderedFrames: renderedFrames,
        networkDroppedFrames: networkDroppedFrames,
        pacerDroppedFrames: pacerDroppedFrames,
        jitterMs: jitterMs,
        packetLossPercent: packetLossPercent,
        avSyncOffsetMs: avSyncOffsetMs,
        timestampMs: timestampMs,
        bridge: bridge
    )

    let snapshot = await firstSnapshot
    #expect(snapshot != nil)
    #expect(snapshot?.stats.renderedFrames == Int(renderedFrames))
    #expect(snapshot?.stats.droppedFrames == Int(networkDroppedFrames) + Int(pacerDroppedFrames))
    #expect(snapshot?.stats.avSyncOffsetMilliseconds == avSyncOffsetMs)
    #expect(snapshot?.signal.jitterMs == jitterMs)
    #expect(snapshot?.signal.packetLossPercent == packetLossPercent)
    #expect(snapshot?.timestampMs == Int(timestampMs))
}

@Test("Telemetry ingress non-blocking callback ingest eventually emits snapshot to subscriber")
func telemetryIngressNonBlockingCallbackIngestEventuallyEmitsToSubscriber() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let stream = await bridge.snapshotStream()

    let renderedFrames: Int32 = 1_024
    let networkDroppedFrames: Int32 = 3
    let pacerDroppedFrames: Int32 = 2
    let jitterMs = 7.0
    let packetLossPercent = 0.4
    let avSyncOffsetMs = -2.0
    let timestampMs: Int64 = 99_777

    async let firstSnapshot = stream.first(where: { $0.timestampMs == Int(timestampMs) })
    MoonlightSessionTelemetryIngress.ingestFromCallbackNonBlocking(
        renderedFrames: renderedFrames,
        networkDroppedFrames: networkDroppedFrames,
        pacerDroppedFrames: pacerDroppedFrames,
        jitterMs: jitterMs,
        packetLossPercent: packetLossPercent,
        avSyncOffsetMs: avSyncOffsetMs,
        timestampMs: timestampMs,
        bridge: bridge
    )

    let snapshot = await firstSnapshot
    #expect(snapshot != nil)
    #expect(snapshot?.stats.renderedFrames == Int(renderedFrames))
    #expect(snapshot?.stats.droppedFrames == Int(networkDroppedFrames) + Int(pacerDroppedFrames))
    #expect(snapshot?.stats.avSyncOffsetMilliseconds == avSyncOffsetMs)
    #expect(snapshot?.signal.jitterMs == jitterMs)
    #expect(snapshot?.signal.packetLossPercent == packetLossPercent)
    #expect(snapshot?.timestampMs == Int(timestampMs))
}

@Test("Telemetry ingress exposes callback activity counters for stream observability")
func telemetryIngressExposesCallbackActivityCounters() async {
    let bridge = MoonlightSessionTelemetryBridge()
    await MoonlightSessionTelemetryIngress.resetActivityForTests()

    let initial = await MoonlightSessionTelemetryIngress.callbackActivity()
    #expect(initial.callbackCount == 0)
    #expect(initial.lastCallbackTimestampMs == nil)

    await MoonlightSessionTelemetryIngress.ingestFromCallback(
        renderedFrames: 100,
        networkDroppedFrames: 1,
        pacerDroppedFrames: 2,
        jitterMs: 6.0,
        packetLossPercent: 0.4,
        avSyncOffsetMs: 3.0,
        timestampMs: 1_111,
        bridge: bridge
    )

    let firstActivity = await MoonlightSessionTelemetryIngress.callbackActivity()
    #expect(firstActivity.callbackCount == 1)
    #expect(firstActivity.lastCallbackTimestampMs == 1_111)

    await MoonlightSessionTelemetryIngress.ingestFromCallback(
        renderedFrames: 110,
        networkDroppedFrames: 1,
        pacerDroppedFrames: 2,
        jitterMs: 7.0,
        packetLossPercent: 0.5,
        avSyncOffsetMs: 2.0,
        timestampMs: 2_222,
        bridge: bridge
    )

    let secondActivity = await MoonlightSessionTelemetryIngress.callbackActivity()
    #expect(secondActivity.callbackCount == 2)
    #expect(secondActivity.lastCallbackTimestampMs == 2_222)
}
