import Testing
@testable import ShadowClientFeatureHome

@Test("Remote host action kit still allows pairing when serverinfo is unavailable")
func remoteHostActionKitAllowsPairingWhenServerInfoIsUnavailable() {
    let host = ShadowClientRemoteHostDescriptor(
        host: "wifi-route.example.invalid",
        isSaved: true,
        displayName: "Example-PC",
        pairStatus: .notPaired,
        currentGameID: 0,
        serverState: "",
        httpsPort: 47984,
        appVersion: nil,
        gfeVersion: nil,
        uniqueID: nil,
        serverCodecModeSupport: 0,
        lastError: "The operation couldn't be completed. Connection refused"
    )

    #expect(ShadowClientRemoteHostActionKit.canPair(selectedHost: host))
    #expect(ShadowClientRemoteHostActionKit.shouldShowPairAction(host: host))
}

@Test("Remote host action kit hides pairing for paired hosts even if route is unreachable")
func remoteHostActionKitHidesPairingForPairedHosts() {
    let host = ShadowClientRemoteHostDescriptor(
        host: "wifi-route.example.invalid",
        isSaved: true,
        displayName: "Example-PC",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "",
        httpsPort: 47984,
        appVersion: nil,
        gfeVersion: nil,
        uniqueID: nil,
        serverCodecModeSupport: 0,
        lastError: "The operation couldn't be completed. Connection refused"
    )

    #expect(!ShadowClientRemoteHostActionKit.canPair(selectedHost: host))
    #expect(!ShadowClientRemoteHostActionKit.shouldShowPairAction(host: host))
}
