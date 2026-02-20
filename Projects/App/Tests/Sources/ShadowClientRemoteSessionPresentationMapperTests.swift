import Testing
@testable import ShadowClientFeatureHome

@Test("Remote session presentation mapper emits waiting state when endpoint is missing")
func remoteSessionPresentationMapperMissingEndpoint() {
    let model = ShadowClientRemoteSessionPresentationMapper.make(
        activeSessionEndpoint: "",
        launchState: .idle
    )

    #expect(model.launchTone == .idle)
    #expect(model.statusText.localizedCaseInsensitiveContains("launch desktop/game"))
    #expect(model.overlay?.symbol == "desktopcomputer")
}

@Test("Remote session presentation mapper emits connecting state while launching")
func remoteSessionPresentationMapperLaunching() {
    let model = ShadowClientRemoteSessionPresentationMapper.make(
        activeSessionEndpoint: "rtsp://wifi.skyline23.com:48010",
        launchState: .launching
    )

    #expect(model.launchTone == .launching)
    #expect(model.statusText.localizedCaseInsensitiveContains("connecting"))
    #expect(model.overlay?.symbol == "antenna.radiowaves.left.and.right")
}

@Test("Remote session presentation mapper emits decoder wait state after launch")
func remoteSessionPresentationMapperLaunched() {
    let model = ShadowClientRemoteSessionPresentationMapper.make(
        activeSessionEndpoint: "rtsp://wifi.skyline23.com:48010",
        launchState: .launched("Remote session transport connected")
    )

    #expect(model.launchTone == .launched)
    #expect(model.statusText.localizedCaseInsensitiveContains("native frame decoder"))
    #expect(model.overlay?.symbol == "hourglass")
}

@Test("Remote session presentation mapper hides overlay once native rendering is live")
func remoteSessionPresentationMapperRenderingLive() {
    let model = ShadowClientRemoteSessionPresentationMapper.make(
        activeSessionEndpoint: "rtsp://wifi.skyline23.com:48010",
        launchState: .launched("Remote session transport connected"),
        renderState: .rendering
    )

    #expect(model.launchTone == .launched)
    #expect(model.statusText.localizedCaseInsensitiveContains("live"))
    #expect(model.overlay == nil)
}

@Test("Remote session presentation mapper emits disconnected state when render transport drops")
func remoteSessionPresentationMapperDisconnected() {
    let model = ShadowClientRemoteSessionPresentationMapper.make(
        activeSessionEndpoint: "rtsp://wifi.skyline23.com:48010",
        launchState: .launched("Remote session transport connected"),
        renderState: .disconnected("Connection reset by peer")
    )

    #expect(model.launchTone == .failed)
    #expect(model.statusText.localizedCaseInsensitiveContains("disconnected"))
    #expect(model.statusText.localizedCaseInsensitiveContains("connection reset by peer"))
    #expect(model.overlay?.symbol == "wifi.slash")
}

@Test("Remote session presentation mapper preserves launch failure reason")
func remoteSessionPresentationMapperFailure() {
    let model = ShadowClientRemoteSessionPresentationMapper.make(
        activeSessionEndpoint: "rtsp://wifi.skyline23.com:48010",
        launchState: .failed("transport failed")
    )

    #expect(model.launchTone == .failed)
    #expect(model.statusText == "transport failed")
    #expect(model.overlay?.symbol == "exclamationmark.triangle")
}
