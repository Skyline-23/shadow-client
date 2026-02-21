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
