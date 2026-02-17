import ShadowClientStreaming
import Testing
@testable import ShadowClientFeatureHome

@Test("Stream monitor waits for first telemetry sample after connection")
func streamMonitorAwaitsTelemetryAfterConnect() async {
    let runtime = StreamOutputMonitorRuntime(staleAfterMs: 2_000)

    let model = await runtime.updateConnectionState(.connected(host: "192.168.0.20"), at: 1_000)

    #expect(model.state == .awaitingTelemetry)
    #expect(model.detail == "Connected. Waiting for first telemetry sample.")
}

@Test("Stream monitor becomes live when telemetry sample arrives")
func streamMonitorBecomesLiveOnSample() async {
    let runtime = StreamOutputMonitorRuntime(staleAfterMs: 2_000)
    _ = await runtime.updateConnectionState(.connected(host: "192.168.0.20"), at: 1_000)

    let model = await runtime.ingest(snapshot: makeSnapshot(timestampMs: 10_000), at: 1_050)

    #expect(model.state == .live)
    #expect(model.sampleAgeMs == 0)
    #expect(model.renderedFrames == 1_200)
    #expect(model.droppedFrames == 12)
}

@Test("Stream monitor marks stream as stale when telemetry stops")
func streamMonitorMarksStaleWhenTelemetryStops() async {
    let runtime = StreamOutputMonitorRuntime(staleAfterMs: 2_000)
    _ = await runtime.updateConnectionState(.connected(host: "192.168.0.20"), at: 1_000)
    _ = await runtime.ingest(snapshot: makeSnapshot(timestampMs: 10_000), at: 1_100)

    let model = await runtime.heartbeat(at: 3_400)

    #expect(model.state == .stale)
    #expect(model.sampleAgeMs == 2_300)
}

@Test("Stream monitor exposes connection failure detail")
func streamMonitorExposesConnectionFailureDetail() async {
    let runtime = StreamOutputMonitorRuntime(staleAfterMs: 2_000)

    let model = await runtime.updateConnectionState(
        .failed(host: "192.168.0.20", message: "Embedded runtime missing"),
        at: 1_000
    )

    #expect(model.state == .failed)
    #expect(model.detail == "Embedded runtime missing")
}

private func makeSnapshot(timestampMs: Int) -> StreamingTelemetrySnapshot {
    StreamingTelemetrySnapshot(
        stats: .init(
            renderedFrames: 1_200,
            droppedFrames: 12,
            avSyncOffsetMilliseconds: 5
        ),
        signal: .init(
            jitterMs: 7.0,
            packetLossPercent: 0.1
        ),
        timestampMs: timestampMs,
        dropBreakdown: .init(
            networkDroppedFrames: 7,
            pacerDroppedFrames: 5
        )
    )
}
