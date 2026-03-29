import Testing
@testable import ShadowClientFeatureConnection

@Test("Discovered host presentation formats detail line and button copy")
func discoveredHostPresentationFormatting() {
    let host = ShadowClientDiscoveredHost(
        name: "Desktop",
        host: "desktop.local",
        port: 47989,
        serviceType: "_shadow._tcp"
    )

    #expect(ShadowClientDiscoveredHostPresentationKit.detailText(host) == "desktop.local:47989 · _shadow._tcp")
    #expect(ShadowClientDiscoveredHostPresentationKit.useButtonTitle() == "Use")
    #expect(ShadowClientDiscoveredHostPresentationKit.connectButtonTitle() == "Connect")
}
