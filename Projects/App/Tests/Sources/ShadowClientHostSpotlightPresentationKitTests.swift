import Testing
@testable import ShadowClientFeatureHome

@Test("Host spotlight presentation prefers issue over host status")
func hostSpotlightPresentationIssueCallout() {
    let host = ShadowClientRemoteHostDescriptor(
        host: "desktop.local",
        displayName: "Desktop",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "ONLINE",
        httpsPort: 47984,
        appVersion: nil,
        gfeVersion: nil,
        uniqueID: nil,
        lastError: nil
    )

    let callouts = ShadowClientHostSpotlightPresentationKit.statusCallouts(
        host: host,
        issue: .init(title: "Lumen Permissions", message: "Grant Launch Apps."),
        lumenSummary: "ignored"
    )

    #expect(callouts == [.init(title: "Lumen Permissions", message: "Grant Launch Apps.", tone: .warning)])
}

@Test("Host spotlight presentation emits ready and Lumen override callouts for paired hosts")
func hostSpotlightPresentationReadyCallouts() {
    let host = ShadowClientRemoteHostDescriptor(
        host: "desktop.local",
        displayName: "Desktop",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "ONLINE",
        httpsPort: 47984,
        appVersion: nil,
        gfeVersion: nil,
        uniqueID: nil,
        lastError: nil
    )

    let callouts = ShadowClientHostSpotlightPresentationKit.statusCallouts(
        host: host,
        issue: nil,
        lumenSummary: "Display mode override: automatic"
    )

    #expect(callouts.count == 2)
    #expect(callouts[0] == .init(title: "Ready", message: "This device is paired and ready to launch a remote desktop session.", tone: .success))
    #expect(callouts[1] == .init(title: "Lumen Device Overrides", message: "Display mode override: automatic", tone: .info))
}

@Test("Host spotlight presentation emits destructive connection callout for unavailable hosts")
func hostSpotlightPresentationUnavailableCallout() {
    let host = ShadowClientRemoteHostDescriptor(
        host: "wifi-route.example.invalid",
        displayName: "Desktop",
        pairStatus: .notPaired,
        currentGameID: 0,
        serverState: "",
        httpsPort: 47984,
        appVersion: nil,
        gfeVersion: nil,
        uniqueID: nil,
        lastError: "The operation couldn't be completed. Connection refused"
    )

    let callouts = ShadowClientHostSpotlightPresentationKit.statusCallouts(
        host: host,
        issue: nil,
        lumenSummary: nil
    )

    #expect(callouts == [.init(title: "Connection Issue", message: "The operation couldn't be completed. Connection refused", tone: .destructive)])
}
