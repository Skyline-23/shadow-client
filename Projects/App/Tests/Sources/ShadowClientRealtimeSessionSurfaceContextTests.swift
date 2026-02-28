@testable import ShadowClientFeatureHome
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
    let expected = ShadowClientSunshineControllerFeedbackEvent.rumble(
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
