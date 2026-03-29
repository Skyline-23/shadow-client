import Testing
@testable import ShadowClientFeatureHome

@Test("Remote host route selection keeps the configured display alias while connecting over the local route")
func remoteHostRouteSelectionSeparatesDisplayAliasFromConnectRoute() {
    let host = ShadowClientRemoteHostDescriptor(
        activeRoute: .init(host: "192.168.0.50", httpsPort: 48_984),
        displayName: "Buseong Mac",
        pairStatus: .notPaired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        appVersion: "1.0",
        gfeVersion: nil,
        uniqueID: "HOST-ROUTE-1",
        lastError: nil,
        routes: .init(
            active: .init(host: "192.168.0.50", httpsPort: 48_984),
            local: .init(host: "192.168.0.50", httpsPort: 48_984),
            remote: .init(host: "wifi.skyline23.com", httpsPort: 48_984),
            manual: .init(host: "wifi.skyline23.com", httpsPort: 48_984)
        )
    )

    #expect(
        ShadowClientRemoteHostRouteSelectionKit.displayCandidate(
            for: host,
            allHosts: [host]
        ) == "wifi.skyline23.com"
    )
    #expect(
        ShadowClientRemoteHostRouteSelectionKit.runtimeConnectCandidate(for: host) == "192.168.0.50"
    )
}

@Test("Remote host route selection preserves explicit non-default local ports for runtime connect")
func remoteHostRouteSelectionPreservesExplicitLocalPort() {
    let host = ShadowClientRemoteHostDescriptor(
        activeRoute: .init(host: "192.168.0.51", httpsPort: 47_984),
        displayName: "Studio Mac",
        pairStatus: .notPaired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        appVersion: "1.0",
        gfeVersion: nil,
        uniqueID: "HOST-ROUTE-2",
        lastError: nil,
        routes: .init(
            active: .init(host: "wifi.skyline23.com", httpsPort: 47_984),
            local: .init(host: "192.168.0.51", httpsPort: 47_984),
            remote: .init(host: "wifi.skyline23.com", httpsPort: 47_984),
            manual: .init(host: "wifi.skyline23.com", httpsPort: 47_984)
        )
    )

    #expect(
        ShadowClientRemoteHostRouteSelectionKit.runtimeConnectCandidate(for: host) == "192.168.0.51:47984"
    )
}
