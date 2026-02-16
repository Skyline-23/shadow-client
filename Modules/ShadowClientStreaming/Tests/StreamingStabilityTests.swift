import Testing
@testable import ShadowClientStreaming

@Test("Streaming checker passes when frame drop and AV sync are within gates")
func streamingStabilityPassesAtThresholds() {
    let checker = StreamingStabilityChecker()
    let report = checker.evaluate(
        .init(renderedFrames: 990, droppedFrames: 10, avSyncOffsetMilliseconds: 40.0)
    )

    #expect(report.frameDrop.passes)
    #expect(report.avSync.passes)
    #expect(report.passes)
}

@Test("Streaming checker fails when frame drop exceeds 1%")
func streamingStabilityFailsOnFrameDrop() {
    let checker = StreamingStabilityChecker()
    let report = checker.evaluate(
        .init(renderedFrames: 970, droppedFrames: 30, avSyncOffsetMilliseconds: 10.0)
    )

    #expect(!report.frameDrop.passes)
    #expect(!report.passes)
}

@Test("Streaming checker fails when AV sync exceeds 40ms")
func streamingStabilityFailsOnAVSync() {
    let checker = StreamingStabilityChecker()
    let report = checker.evaluate(
        .init(renderedFrames: 995, droppedFrames: 5, avSyncOffsetMilliseconds: 41.0)
    )

    #expect(report.frameDrop.passes)
    #expect(!report.avSync.passes)
    #expect(!report.passes)
}
