import Testing
@testable import ShadowClientFeatureHome

@Test("Home feature snapshot is healthy when all first-pass gates pass")
func homeFeatureHealthySnapshot() {
    let builder = HomeFeatureBuilder()
    let snapshot = builder.makeSnapshot(
        streamingStats: .init(renderedFrames: 990, droppedFrames: 10, avSyncOffsetMilliseconds: 40.0),
        networkSignal: .init(jitterMs: 6.0, packetLossPercent: 0.2),
        inputSamples: (10...30).map { .init(milliseconds: Double($0)) },
        feedbackCapabilities: .init(
            supportsRumble: true,
            supportsAdaptiveTriggers: true,
            supportsLED: true
        ),
        transport: .usb
    )

    #expect(snapshot.streamHealthy)
    #expect(snapshot.inputHealthy)
    #expect(snapshot.feedbackReady)
    #expect(snapshot.sessionConfiguration.hdrVideoMode == .hdr10)
    #expect(snapshot.sessionConfiguration.audioMode == .stereo)
    #expect(snapshot.badge.tone == .healthy)
}

@Test("Home feature snapshot tracks DualSense first-pass feedback failure")
func homeFeatureFeedbackFailureSnapshot() {
    let builder = HomeFeatureBuilder()
    let snapshot = builder.makeSnapshot(
        streamingStats: .init(renderedFrames: 995, droppedFrames: 5, avSyncOffsetMilliseconds: 20.0),
        networkSignal: .init(jitterMs: 7.0, packetLossPercent: 0.1),
        inputSamples: (10...30).map { .init(milliseconds: Double($0)) },
        feedbackCapabilities: .init(
            supportsRumble: true,
            supportsAdaptiveTriggers: true,
            supportsLED: false
        ),
        transport: .usb
    )

    #expect(snapshot.streamHealthy)
    #expect(snapshot.inputHealthy)
    #expect(!snapshot.feedbackReady)
    #expect(snapshot.sessionConfiguration.hdrVideoMode == .hdr10)
    #expect(snapshot.sessionConfiguration.audioMode == .stereo)
    #expect(snapshot.badge.tone == .warning)
}

@Test("Home feature snapshot falls back to SDR stereo when session mapper gates fail")
func homeFeatureSessionSettingsFallbackSnapshot() {
    let builder = HomeFeatureBuilder(
        sessionPreferences: .init(
            preferHDR: true,
            preferSurroundAudio: true,
            lowLatencyMode: false
        )
    )
    let snapshot = builder.makeSnapshot(
        streamingStats: .init(renderedFrames: 995, droppedFrames: 5, avSyncOffsetMilliseconds: 20.0),
        networkSignal: .init(jitterMs: 45.0, packetLossPercent: 4.0),
        inputSamples: (10...30).map { .init(milliseconds: Double($0)) },
        feedbackCapabilities: .init(
            supportsRumble: true,
            supportsAdaptiveTriggers: true,
            supportsLED: true
        ),
        transport: .usb
    )

    #expect(snapshot.sessionConfiguration.hdrVideoMode == .off)
    #expect(snapshot.sessionConfiguration.audioMode == .stereo)
}
