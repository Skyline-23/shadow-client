import ShadowClientStreaming
import ShadowClientUI
import Testing
@testable import ShadowClientFeatureHome

@Test("Home diagnostics runtime returns critical tone and 48ms buffer for first unstable sample")
func homeDiagnosticsRuntimeFirstUnstableSampleReturnsCriticalToneAndBuffer48() async {
    let runtime = HomeDiagnosticsRuntime()

    let tick = await runtime.ingest(qtSample: unstableSample())

    #expect(tick.model.tone == .critical)
    #expect(tick.model.bufferMs == 48)
    #expect(tick.timestampMs == 1_000)
}

@Test("Home diagnostics runtime keeps critical tone and 48ms buffer on first stable sample after instability")
func homeDiagnosticsRuntimeFirstStableSampleAfterInstabilityKeepsReducedQualityState() async {
    let runtime = HomeDiagnosticsRuntime()

    _ = await runtime.ingest(qtSample: unstableSample())
    let tick = await runtime.ingest(qtSample: stableLowJitterSample(timestampMs: 1_016))

    #expect(tick.model.tone == .critical)
    #expect(tick.model.bufferMs == 48)
    #expect(tick.timestampMs == 1_016)
}

@Test("Home diagnostics runtime clamps negative dropped frame telemetry to 0.0 frame drop percent")
func homeDiagnosticsRuntimeNegativeDropSampleClampsFrameDropPercentToZero() async {
    let runtime = HomeDiagnosticsRuntime()
    let sample = MoonlightQTTelemetrySample(
        renderedFrames: 240,
        networkDroppedFrames: -4,
        pacerDroppedFrames: -6,
        jitterMs: 4.0,
        packetLossPercent: 0.1,
        avSyncOffsetMs: 6.0,
        timestampMs: 2_000
    )

    let tick = await runtime.ingest(qtSample: sample)

    #expect(tick.model.frameDropPercent == 0.0)
    #expect(tick.timestampMs == 2_000)
}

@Test("Home diagnostics runtime returns healthy tone and 46ms buffer after two stable low-jitter samples post-instability")
func homeDiagnosticsRuntimeSecondStableSampleAfterInstabilityReturnsHealthyToneAndBuffer46() async {
    let runtime = HomeDiagnosticsRuntime()

    _ = await runtime.ingest(qtSample: unstableSample())
    _ = await runtime.ingest(qtSample: stableLowJitterSample(timestampMs: 1_016))
    let tick = await runtime.ingest(qtSample: stableLowJitterSample(timestampMs: 1_032))

    #expect(tick.model.tone == .healthy)
    #expect(tick.model.bufferMs == 46)
    #expect(tick.timestampMs == 1_032)
}

private func unstableSample() -> MoonlightQTTelemetrySample {
    MoonlightQTTelemetrySample(
        renderedFrames: 960,
        networkDroppedFrames: 20,
        pacerDroppedFrames: 20,
        jitterMs: 80.0,
        packetLossPercent: 3.0,
        avSyncOffsetMs: 55.0,
        timestampMs: 1_000
    )
}

private func stableLowJitterSample(timestampMs: Int) -> MoonlightQTTelemetrySample {
    MoonlightQTTelemetrySample(
        renderedFrames: 995,
        networkDroppedFrames: 2,
        pacerDroppedFrames: 3,
        jitterMs: 3.0,
        packetLossPercent: 0.2,
        avSyncOffsetMs: 12.0,
        timestampMs: timestampMs
    )
}
