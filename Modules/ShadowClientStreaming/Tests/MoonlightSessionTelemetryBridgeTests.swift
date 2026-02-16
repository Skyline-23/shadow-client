import Testing
@testable import ShadowClientStreaming

@Test("Session bridge emits mapped snapshot to subscriber")
func sessionBridgeEmitsMappedSnapshotToSubscriber() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let stream = await bridge.snapshotStream()
    let sample = MoonlightQTTelemetrySample(
        renderedFrames: 1_000,
        networkDroppedFrames: 7,
        pacerDroppedFrames: 3,
        jitterMs: 21.0,
        packetLossPercent: 1.3,
        avSyncOffsetMs: 11.0,
        timestampMs: 2_000
    )

    async let first = stream.first(where: { _ in true })
    await bridge.ingest(qtSample: sample)

    let snapshot = await first
    #expect(snapshot != nil)
    #expect(snapshot?.stats.renderedFrames == 1_000)
    #expect(snapshot?.stats.droppedFrames == 10)
    #expect(snapshot?.signal.jitterMs == 21.0)
    #expect(snapshot?.signal.packetLossPercent == 1.3)
    #expect(snapshot?.timestampMs == 2_000)
}

@Test("Session bridge broadcasts same snapshot to multiple subscribers")
func sessionBridgeBroadcastsToMultipleSubscribers() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let streamA = await bridge.snapshotStream()
    let streamB = await bridge.snapshotStream()
    let sample = MoonlightQTTelemetrySample(
        renderedFrames: 900,
        networkDroppedFrames: 5,
        pacerDroppedFrames: 4,
        jitterMs: 18.0,
        packetLossPercent: 0.8,
        avSyncOffsetMs: 9.0,
        timestampMs: 3_333
    )

    #expect(await bridge.activeSubscriberCount() == 2)

    async let firstA = streamA.first(where: { _ in true })
    async let firstB = streamB.first(where: { _ in true })
    await bridge.ingest(qtSample: sample)

    let snapshotA = await firstA
    let snapshotB = await firstB

    #expect(snapshotA == snapshotB)
    #expect(snapshotA?.stats.droppedFrames == 9)
    #expect(snapshotB?.timestampMs == 3_333)
}

@Test("Session bridge removes subscriber after stream consumer is cancelled")
func sessionBridgeRemovesSubscriberAfterCancellation() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let stream = await bridge.snapshotStream()
    #expect(await bridge.activeSubscriberCount() == 1)

    let consumer = Task {
        for await _ in stream {
            if Task.isCancelled { break }
        }
    }

    consumer.cancel()
    _ = await consumer.result

    for _ in 0..<20 {
        if await bridge.activeSubscriberCount() == 0 {
            break
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(await bridge.activeSubscriberCount() == 0)
}
