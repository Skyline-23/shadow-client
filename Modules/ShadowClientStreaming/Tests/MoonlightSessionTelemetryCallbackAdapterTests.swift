import Testing
@testable import ShadowClientStreaming

@Test("Session callback adapter forwards raw payload into live bridge stream")
func sessionCallbackAdapterForwardsRawPayloadToBridge() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let stream = await bridge.snapshotStream()

    let raw = MoonlightSessionRawTelemetry(
        renderedFrames: 1_200,
        networkDroppedFrames: 9,
        pacerDroppedFrames: 6,
        jitterMs: 16.0,
        packetLossPercent: 1.1,
        avSyncOffsetMs: 13.0,
        timestampMs: 4_096
    )

    async let first = stream.first(where: { _ in true })
    await MoonlightSessionTelemetryCallbackAdapter.ingest(raw, bridge: bridge)

    let snapshot = await first
    #expect(snapshot != nil)
    #expect(snapshot?.stats.renderedFrames == 1_200)
    #expect(snapshot?.stats.droppedFrames == 15)
    #expect(snapshot?.signal.jitterMs == 16.0)
    #expect(snapshot?.signal.packetLossPercent == 1.1)
    #expect(snapshot?.timestampMs == 4_096)
}

@Test("Session callback adapter preserves clamping behavior through snapshot mapping")
func sessionCallbackAdapterPreservesClampingBehavior() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let stream = await bridge.snapshotStream()

    let raw = MoonlightSessionRawTelemetry(
        renderedFrames: 100,
        networkDroppedFrames: -3,
        pacerDroppedFrames: -7,
        jitterMs: 4.0,
        packetLossPercent: 0.2,
        avSyncOffsetMs: 4.0,
        timestampMs: 5_000
    )

    async let first = stream.first(where: { _ in true })
    await MoonlightSessionTelemetryCallbackAdapter.ingest(raw, bridge: bridge)

    let snapshot = await first
    #expect(snapshot?.stats.droppedFrames == 0)
    #expect(snapshot?.stats.totalFrames == 100)
}
