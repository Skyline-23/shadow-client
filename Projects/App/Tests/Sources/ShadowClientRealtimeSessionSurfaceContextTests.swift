import CoreVideo
@testable import ShadowClientFeatureHome
import ShadowClientFeatureSession
import Testing

@Test("Realtime session surface context tracks negotiated video codec")
func realtimeSessionSurfaceContextTracksNegotiatedVideoCodec() {
    let context = ShadowClientRealtimeSessionSurfaceContext()
    #expect(context.activeVideoCodec == nil)

    context.updateActiveVideoCodec(.av1)
    #expect(context.activeVideoCodec == .av1)

    context.updateActiveVideoCodec(.h265)
    #expect(context.activeVideoCodec == .h265)
}

@Test("Realtime session surface context reset clears negotiated video codec")
func realtimeSessionSurfaceContextResetClearsNegotiatedVideoCodec() {
    let context = ShadowClientRealtimeSessionSurfaceContext()
    context.updateActiveVideoCodec(.h264)
    context.updateRuntimeVideoStats(fps: 59.7, bitrateKbps: 23_500)

    context.reset()

    #expect(context.activeVideoCodec == nil)
    #expect(context.estimatedVideoFPS == nil)
    #expect(context.estimatedVideoBitrateKbps == nil)
}

@Test("Realtime session surface context tracks runtime video stats")
func realtimeSessionSurfaceContextTracksRuntimeVideoStats() {
    let context = ShadowClientRealtimeSessionSurfaceContext()

    context.updateRuntimeVideoStats(fps: 61.2, bitrateKbps: 41_000)

    #expect(context.estimatedVideoFPS == 61.2)
    #expect(context.estimatedVideoBitrateKbps == 41_000)
}

@Test("Realtime session surface context derives FPS from presented frames")
func realtimeSessionSurfaceContextDerivesFPSFromPresentedFrames() {
    let context = ShadowClientRealtimeSessionSurfaceContext()

    context.recordPresentedVideoFrame(nowUptime: 10.0)
    context.recordPresentedVideoFrame(nowUptime: 10.1)
    context.recordPresentedVideoFrame(nowUptime: 10.21)

    #expect(context.estimatedVideoFPS != nil)
    #expect((context.estimatedVideoFPS ?? 0) > 9.0)
    #expect((context.estimatedVideoFPS ?? 0) < 11.5)
}

@Test("Realtime session surface context syncs preferred render FPS with session FPS")
func realtimeSessionSurfaceContextSyncsPreferredRenderFPSWithSessionFPS() {
    let context = ShadowClientRealtimeSessionSurfaceContext()
    #expect(context.preferredRenderFPS == ShadowClientStreamingLaunchBounds.defaultFPS)

    context.updatePreferredRenderFPS(120)
    #expect(context.preferredRenderFPS == 120)

    context.updatePreferredRenderFPS(0)
    #expect(context.preferredRenderFPS == 1)
}

@Test("Realtime session surface context reset restores default preferred render FPS")
func realtimeSessionSurfaceContextResetRestoresDefaultPreferredRenderFPS() {
    let context = ShadowClientRealtimeSessionSurfaceContext()
    context.updatePreferredRenderFPS(120)
    #expect(context.preferredRenderFPS == 120)

    context.reset()

    #expect(context.preferredRenderFPS == ShadowClientStreamingLaunchBounds.defaultFPS)
}

@Test("Realtime session surface context streams controller feedback events")
func realtimeSessionSurfaceContextStreamsControllerFeedbackEvents() async {
    let context = ShadowClientRealtimeSessionSurfaceContext()
    let stream = context.controllerFeedbackAsyncStream()
    let expected = ShadowClientHostControllerFeedbackEvent.rumble(
        .init(
            controllerNumber: 0,
            lowFrequencyMotor: 0x1111,
            highFrequencyMotor: 0x2222
        )
    )

    context.publishControllerFeedbackEvent(expected)

    var iterator = stream.makeAsyncIterator()
    let received = await iterator.next()
    #expect(received == expected)
}

@Test("Realtime session surface context tracks active HDR metadata")
func realtimeSessionSurfaceContextTracksHDRMetadata() {
    let context = ShadowClientRealtimeSessionSurfaceContext()
    let metadata = ShadowClientHDRMetadata(
        displayPrimaries: [
            .init(x: 100, y: 200),
            .init(x: 300, y: 400),
            .init(x: 500, y: 600),
        ],
        whitePoint: .init(x: 700, y: 800),
        maxDisplayLuminance: 1000,
        minDisplayLuminance: 1,
        maxContentLightLevel: 1200,
        maxFrameAverageLightLevel: 600,
        maxFullFrameLuminance: 400
    )

    context.updateActiveHDRMetadata(metadata)
    #expect(context.activeHDRMetadata == metadata)

    context.reset()
    #expect(context.activeHDRMetadata == nil)
}

@Test("Realtime session surface context bumps color configuration revision for dynamic range transitions")
func realtimeSessionSurfaceContextBumpsColorConfigurationRevisionForDynamicRangeTransitions() {
    let context = ShadowClientRealtimeSessionSurfaceContext()
    #expect(context.colorConfigurationRevision == 0)

    context.updateActiveDynamicRangeMode(.hdr)
    #expect(context.colorConfigurationRevision == 1)

    context.updateActiveDynamicRangeMode(.hdr)
    #expect(context.colorConfigurationRevision == 1)

    context.updateActiveDynamicRangeMode(.sdr)
    #expect(context.colorConfigurationRevision == 2)
}

@Test("Realtime session surface context bumps color configuration revision for HDR metadata transitions")
func realtimeSessionSurfaceContextBumpsColorConfigurationRevisionForHDRMetadataTransitions() {
    let context = ShadowClientRealtimeSessionSurfaceContext()
    let metadata = ShadowClientHDRMetadata(
        displayPrimaries: [
            .init(x: 100, y: 200),
            .init(x: 300, y: 400),
            .init(x: 500, y: 600),
        ],
        whitePoint: .init(x: 700, y: 800),
        maxDisplayLuminance: 1000,
        minDisplayLuminance: 1,
        maxContentLightLevel: 1200,
        maxFrameAverageLightLevel: 600,
        maxFullFrameLuminance: 400
    )
    #expect(context.colorConfigurationRevision == 0)

    context.updateActiveHDRMetadata(metadata)
    #expect(context.colorConfigurationRevision == 1)

    context.updateActiveHDRMetadata(metadata)
    #expect(context.colorConfigurationRevision == 1)

    context.updateActiveHDRMetadata(nil)
    #expect(context.colorConfigurationRevision == 2)

    context.reset()
    #expect(context.colorConfigurationRevision == 0)
}

@Test("Realtime session surface context awaited reset clears frame store before returning")
func realtimeSessionSurfaceContextAwaitedResetClearsFrameStoreBeforeReturning() async throws {
    let context = ShadowClientRealtimeSessionSurfaceContext()
    let stream = await context.frameStore.snapshotStream()
    var iterator = stream.makeAsyncIterator()

    let initialSnapshot = await iterator.next()
    #expect(initialSnapshot?.pixelBuffer == nil)

    let pixelBuffer = try makeTestPixelBuffer()
    await context.frameStore.update(pixelBuffer: pixelBuffer)

    let populatedSnapshot = await iterator.next()
    #expect(populatedSnapshot?.pixelBuffer != nil)

    await context.resetAwaitingFrameClear()

    let clearedSnapshot = await iterator.next()
    #expect(clearedSnapshot?.pixelBuffer == nil)
    #expect(context.renderState == .idle)
}

private func makeTestPixelBuffer() throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        2,
        2,
        kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
        nil,
        &pixelBuffer
    )

    #expect(status == kCVReturnSuccess)

    guard let pixelBuffer else {
        struct PixelBufferCreationError: Error {}
        throw PixelBufferCreationError()
    }

    return pixelBuffer
}
