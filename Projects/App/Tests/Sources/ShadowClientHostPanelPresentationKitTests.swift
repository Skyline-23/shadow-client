import Testing
@testable import ShadowClientFeatureHome

@Test("Host panel presentation maps auto-scan state to header badge and empty-state copy")
func hostPanelPresentationHeaderAndEmptyState() {
    #expect(ShadowClientHostPanelPresentationKit.headerTitle() == "Remote Desktop Hosts")
    #expect(ShadowClientHostPanelPresentationKit.headerBadge(autoFindHosts: true) == .init(title: "Auto Scan", symbol: "dot.radiowaves.left.and.right"))
    #expect(ShadowClientHostPanelPresentationKit.headerBadge(autoFindHosts: false) == .init(title: "Manual", symbol: "plus.circle"))
    #expect(ShadowClientHostPanelPresentationKit.emptyStateMessage(autoFindHosts: true).localizedCaseInsensitiveContains("Auto Scan is running"))
    #expect(ShadowClientHostPanelPresentationKit.emptyStateMessage(autoFindHosts: false).localizedCaseInsensitiveContains("Auto Scan is off"))
}

@Test("Host panel presentation formats host list accessibility summary")
func hostPanelPresentationAccessibilityValue() {
    let value = ShadowClientHostPanelPresentationKit.hostsAccessibilityValue(
        hostCount: 3,
        autoFindHosts: false,
        hostStateLabel: "Loaded",
        pairingStateLabel: "Idle"
    )

    #expect(value == "3 host(s). Auto Scan Disabled. Pairing Idle.")
}
