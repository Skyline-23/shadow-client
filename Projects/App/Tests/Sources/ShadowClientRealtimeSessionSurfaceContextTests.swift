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

    context.reset()

    #expect(context.activeVideoCodec == nil)
}
