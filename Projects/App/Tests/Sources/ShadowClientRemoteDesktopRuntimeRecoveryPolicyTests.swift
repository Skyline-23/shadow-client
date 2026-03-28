import Testing
@testable import ShadowClientFeatureHome

@Test("Remote desktop runtime removes hosts that share a self-host unique ID alias")
func remoteDesktopRuntimeRemovesSelfHostAliasesByUniqueID() {
    let localHost = ShadowClientRemoteHostDescriptor(
        host: "192.168.10.50",
        displayName: "Local Lumen",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        httpsPort: 47984,
        appVersion: "1.0",
        gfeVersion: nil,
        uniqueID: "local-host-uuid",
        lastError: nil,
        localHost: "192.168.10.50",
        remoteHost: "169.254.15.176"
    )
    let aliasHost = ShadowClientRemoteHostDescriptor(
        host: "local-stream-host.local",
        displayName: "Local Lumen Alias",
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
        host: "second-stream-host.local",
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
        localInterfaceHosts: ["192.168.10.50"]
    )

    #expect(filtered.map(\.host) == ["second-stream-host.local"])
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
