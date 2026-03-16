import Testing
@testable import ShadowClientFeatureHome

@Test("Remote desktop runtime removes hosts that share a self-host unique ID alias")
func remoteDesktopRuntimeRemovesSelfHostAliasesByUniqueID() {
    let localHost = ShadowClientRemoteHostDescriptor(
        host: "10.0.0.50",
        displayName: "Local Apollo",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        httpsPort: 47984,
        appVersion: "1.0",
        gfeVersion: nil,
        uniqueID: "local-host-uuid",
        lastError: nil,
        localHost: "10.0.0.50",
        remoteHost: "198.18.0.176"
    )
    let aliasHost = ShadowClientRemoteHostDescriptor(
        host: "apollo-host.local",
        displayName: "Local Apollo Alias",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        httpsPort: 47984,
        appVersion: "1.0",
        gfeVersion: nil,
        uniqueID: "local-host-uuid",
        lastError: nil
    )
    let remoteHost = ShadowClientRemoteHostDescriptor(
        host: "desktop-lan.local",
        displayName: "Remote Host",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        httpsPort: 47984,
        appVersion: "1.0",
        gfeVersion: nil,
        uniqueID: "remote-host-uuid",
        lastError: nil
    )

    let filtered = ShadowClientRemoteDesktopRuntime.filterOutSelfHosts(
        [localHost, aliasHost, remoteHost],
        localInterfaceHosts: ["10.0.0.50"]
    )

    #expect(filtered.map(\.host) == ["desktop-lan.local"])
}

@Test("Remote desktop runtime treats startup video datagram failures as transport recovery signals")
func remoteDesktopRuntimeClassifiesStartupVideoDatagramFailures() {
    #expect(
        ShadowClientRemoteDesktopRuntime.isStartupVideoDatagramFailure(
            normalizedError: "rtsp udp video startup traffic missing (silence=10.0s); terminating session"
        )
    )
    #expect(
        ShadowClientRemoteDesktopRuntime.isStartupVideoDatagramFailure(
            normalizedError: "rtsp udp video timeout: no startup datagrams received"
        )
    )
    #expect(
        !ShadowClientRemoteDesktopRuntime.isStartupVideoDatagramFailure(
            normalizedError: "could not create hardware decoder session"
        )
    )
}
