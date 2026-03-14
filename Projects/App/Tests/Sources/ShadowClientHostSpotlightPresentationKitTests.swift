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
        issue: .init(title: "Apollo Permissions", message: "Grant Launch Apps."),
        apolloSummary: "ignored"
    )

    #expect(callouts == [.init(title: "Apollo Permissions", message: "Grant Launch Apps.", tone: .warning)])
}

@Test("Host spotlight presentation emits ready and Apollo override callouts for paired hosts")
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
        apolloSummary: "Display mode override: automatic"
    )

    #expect(callouts.count == 2)
    #expect(callouts[0] == .init(title: "Ready", message: "This device is paired and ready to launch a remote desktop session.", tone: .success))
    #expect(callouts[1] == .init(title: "Apollo Device Overrides", message: "Display mode override: automatic", tone: .info))
}
