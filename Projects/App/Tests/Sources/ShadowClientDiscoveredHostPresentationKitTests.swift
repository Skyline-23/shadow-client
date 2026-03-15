import Testing
@testable import ShadowClientFeatureHome

@Test("Discovered host presentation formats detail line and button copy")
func discoveredHostPresentationFormatting() {
    let host = ShadowClientDiscoveredHost(
        name: "Desktop",
        host: "desktop.local",
        port: 47989,
        serviceType: "_sunshine._tcp"
    )

    #expect(ShadowClientDiscoveredHostPresentationKit.detailText(host) == "desktop.local:47989 · _sunshine._tcp")
    #expect(ShadowClientDiscoveredHostPresentationKit.useButtonTitle() == "Use")
    #expect(ShadowClientDiscoveredHostPresentationKit.connectButtonTitle() == "Connect")
}
