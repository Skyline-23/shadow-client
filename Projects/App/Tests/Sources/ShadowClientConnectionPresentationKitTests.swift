import Testing
@testable import ShadowClientFeatureHome

@Test("Connection presentation kit derives connect and disconnect affordances from connection state")
func connectionPresentationKitAffordances() {
    #expect(!ShadowClientConnectionPresentationKit.canConnect(normalizedHost: "", state: .disconnected))
    #expect(ShadowClientConnectionPresentationKit.canConnect(normalizedHost: "desktop.local", state: .disconnected))
    #expect(!ShadowClientConnectionPresentationKit.canConnect(normalizedHost: "desktop.local", state: .connecting(host: "desktop.local")))
    #expect(ShadowClientConnectionPresentationKit.canDisconnect(state: .connected(host: "desktop.local")))
    #expect(!ShadowClientConnectionPresentationKit.canDisconnect(state: .disconnecting(host: "desktop.local")))
}

@Test("Connection presentation kit formats status text and symbol")
func connectionPresentationKitStatusPresentation() {
    #expect(ShadowClientConnectionPresentationKit.statusText(state: .disconnected) == "Status: Disconnected")
    #expect(ShadowClientConnectionPresentationKit.statusText(state: .connecting(host: "desktop.local")) == "Status: Connecting to desktop.local...")
    #expect(ShadowClientConnectionPresentationKit.statusText(state: .failed(host: "desktop.local", message: "Timed out")) == "Status: Connection Failed - Timed out")
    #expect(ShadowClientConnectionPresentationKit.statusSymbol(state: .connected(host: "desktop.local")) == "checkmark.circle.fill")
    #expect(ShadowClientConnectionPresentationKit.statusSymbol(state: .disconnecting(host: "desktop.local")) == "clock.fill")
}
