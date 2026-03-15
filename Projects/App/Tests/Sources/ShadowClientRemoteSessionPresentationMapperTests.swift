import Testing
@testable import ShadowClientFeatureHome

@Test("Remote session presentation mapper emits waiting state when endpoint is missing")
func remoteSessionPresentationMapperMissingEndpoint() {
    let model = ShadowClientRemoteSessionPresentationKit.make(
        activeSessionEndpoint: "",
        launchState: .idle
    )

    #expect(model.launchTone == .idle)
    #expect(model.statusText.localizedCaseInsensitiveContains("launch desktop/game"))
    #expect(model.overlay?.symbol == "desktopcomputer")
}

@Test("Remote session presentation mapper emits connecting state while launching")
func remoteSessionPresentationMapperLaunching() {
    let model = ShadowClientRemoteSessionPresentationKit.make(
        activeSessionEndpoint: "rtsp://stream-host.example.invalid:48010",
        launchState: .launching
    )

    #expect(model.launchTone == .launching)
    #expect(model.statusText.localizedCaseInsensitiveContains("connecting"))
    #expect(model.overlay?.symbol == "antenna.radiowaves.left.and.right")
}

@Test("Remote session presentation mapper emits optimization state while relaunching an active session")
func remoteSessionPresentationMapperOptimizing() {
    let model = ShadowClientRemoteSessionPresentationKit.make(
        activeSessionEndpoint: "rtsp://stream-host.example.invalid:48010",
        launchState: .optimizing("Optimizing Display...")
    )

    #expect(model.launchTone == .launching)
    #expect(model.statusText.localizedCaseInsensitiveContains("optimizing"))
    #expect(model.overlay?.symbol == "arrow.trianglehead.2.clockwise.rotate.90")
}

@Test("Remote session presentation mapper emits decoder wait state after launch")
func remoteSessionPresentationMapperLaunched() {
    let model = ShadowClientRemoteSessionPresentationKit.make(
        activeSessionEndpoint: "rtsp://stream-host.example.invalid:48010",
        launchState: .launched("Remote session transport connected")
    )

    #expect(model.launchTone == .launched)
    #expect(model.statusText.localizedCaseInsensitiveContains("native frame decoder"))
    #expect(model.overlay?.symbol == "hourglass")
}

@Test("Remote session presentation mapper hides overlay once native rendering is live")
func remoteSessionPresentationMapperRenderingLive() {
    let model = ShadowClientRemoteSessionPresentationKit.make(
        activeSessionEndpoint: "rtsp://stream-host.example.invalid:48010",
        launchState: .launched("Remote session transport connected"),
        renderState: .rendering
    )

    #expect(model.launchTone == .launched)
    #expect(model.statusText.localizedCaseInsensitiveContains("live"))
    #expect(model.overlay == nil)
}

@Test("Remote session presentation mapper emits disconnected state when render transport drops")
func remoteSessionPresentationMapperDisconnected() {
    let model = ShadowClientRemoteSessionPresentationKit.make(
        activeSessionEndpoint: "rtsp://stream-host.example.invalid:48010",
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
    let model = ShadowClientRemoteSessionPresentationKit.make(
        activeSessionEndpoint: "rtsp://stream-host.example.invalid:48010",
        launchState: .failed("transport failed")
    )

    #expect(model.launchTone == .failed)
    #expect(model.statusText == "transport failed")
    #expect(model.overlay?.symbol == "exclamationmark.triangle")
}
