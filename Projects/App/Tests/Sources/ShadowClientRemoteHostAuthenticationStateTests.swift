import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Remote host authentication state maps unreachable unpaired hosts to pairable unavailable state")
func remoteHostAuthenticationStateMapsUnreachableUnpairedHosts() {
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

    let authState = host.authenticationState

    #expect(authState.pairing == .unavailable("The operation couldn't be completed. Connection refused"))
    #expect(authState.canPair)
    #expect(!authState.canConnect)
    #expect(authState.statusLabel == "Unavailable")
    #expect(authState.detailLabel == "The operation couldn't be completed. Connection refused")
}

@Test("Remote host authentication state exposes selected admin readiness for paired hosts")
func remoteHostAuthenticationStateExposesAdminReadiness() {
    let host = ShadowClientRemoteHostDescriptor(
        host: "192.168.0.20",
        displayName: "LivingRoom-PC",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "ONLINE",
        httpsPort: 47984,
        appVersion: "7.0.0",
        gfeVersion: nil,
        uniqueID: "HOST-1",
        lastError: nil
    )
    let profile = ShadowClientLumenAdminClientProfile(
        name: "Current Device",
        uuid: "CURRENT-UUID",
        displayModeOverride: "2560x1440x120",
        permissions: 65535,
        allowClientCommands: true,
        alwaysUseVirtualDisplay: true,
        connected: true
    )

    let authState = host.authenticationState(
        adminState: .loaded,
        adminProfile: profile
    )

    #expect(authState.pairing == .paired)
    #expect(authState.admin == .ready(profileLoaded: true))
    #expect(authState.adminStatusLabel == "Loaded")
    #expect(authState.canRefreshApps)
    #expect(authState.canConnect)
}

@Test("Remote host authentication state keeps pending saved hosts out of pairing flow")
func remoteHostAuthenticationStateKeepsPendingSavedHostsOutOfPairingFlow() {
    let host = ShadowClientRemoteHostDescriptor(
        host: "saved.example.invalid",
        isSaved: true,
        displayName: "saved.example.invalid",
        pairStatus: .unknown,
        currentGameID: 0,
        serverState: "",
        httpsPort: 47984,
        appVersion: nil,
        gfeVersion: nil,
        uniqueID: nil,
        serverCodecModeSupport: 0,
        lastError: nil
    )

    let authState = host.authenticationState

    #expect(authState.pairing == .pendingResolution)
    #expect(!authState.canPair)
    #expect(!authState.canConnect)
    #expect(authState.statusLabel == "Saved")
}
