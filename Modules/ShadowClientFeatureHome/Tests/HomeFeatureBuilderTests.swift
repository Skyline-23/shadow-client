import Testing
@testable import ShadowClientFeatureHome

@Test("Home feature snapshot is healthy when all first-pass gates pass")
func homeFeatureHealthySnapshot() {
    let builder = HomeFeatureBuilder()
    let snapshot = builder.makeSnapshot(
        streamingStats: .init(renderedFrames: 990, droppedFrames: 10, avSyncOffsetMilliseconds: 40.0),
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
    #expect(snapshot.badge.tone == .healthy)
}

@Test("Home feature snapshot tracks DualSense first-pass feedback failure")
func homeFeatureFeedbackFailureSnapshot() {
    let builder = HomeFeatureBuilder()
    let snapshot = builder.makeSnapshot(
        streamingStats: .init(renderedFrames: 995, droppedFrames: 5, avSyncOffsetMilliseconds: 20.0),
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
    #expect(snapshot.badge.tone == .warning)
}
