import Testing
@testable import ShadowClientFeatureHome

@Test("Session playback runtime starts and stops player for valid session URL")
@MainActor
func sessionPlaybackRuntimeStartsAndStopsPlayerForValidURL() {
    let runtime = ShadowClientSessionPlaybackRuntime()

    runtime.start(sessionURL: "rtsp://192.168.0.24:48010/session")

    #expect(runtime.player.currentItem != nil)
    if case let .playing(sessionURL) = runtime.state {
        #expect(sessionURL == "rtsp://192.168.0.24:48010/session")
    } else {
        Issue.record("Expected playing state, got \(runtime.state)")
    }

    runtime.stop()

    #expect(runtime.player.currentItem == nil)
    #expect(runtime.state == .idle)
}

@Test("Session playback runtime rejects malformed session URL")
@MainActor
func sessionPlaybackRuntimeRejectsMalformedSessionURL() {
    let runtime = ShadowClientSessionPlaybackRuntime()

    runtime.start(sessionURL: "%%%%")

    #expect(runtime.player.currentItem == nil)
    if case let .failed(message) = runtime.state {
        #expect(message.localizedCaseInsensitiveContains("invalid"))
    } else {
        Issue.record("Expected failed state, got \(runtime.state)")
    }
}

@Test("Session playback runtime reuses current item when session URL is unchanged")
@MainActor
func sessionPlaybackRuntimeReusesCurrentItemWhenSessionURLIsUnchanged() {
    let runtime = ShadowClientSessionPlaybackRuntime()

    runtime.start(sessionURL: "rtsp://192.168.0.24:48010/session")
    let firstItem = runtime.player.currentItem

    runtime.start(sessionURL: "rtsp://192.168.0.24:48010/session")
    let secondItem = runtime.player.currentItem

    #expect(firstItem != nil)
    #expect(firstItem === secondItem)
}

@Test("Session playback runtime normalizes host:port input into RTSP URL")
@MainActor
func sessionPlaybackRuntimeNormalizesHostPortInputIntoRTSPURL() {
    let resolved = ShadowClientSessionPlaybackRuntime.resolveSessionURL("192.168.0.24:48010/session")

    #expect(resolved?.absoluteString == "rtsp://192.168.0.24:48010/session")
}
