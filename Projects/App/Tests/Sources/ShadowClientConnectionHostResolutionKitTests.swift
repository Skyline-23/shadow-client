@testable import ShadowClientFeatureConnection
@testable import ShadowClientFeatureHome
import Testing

@Test("Connection host resolution upgrades a plain Lumen hostname to its connect candidate")
func connectionHostResolutionUpgradesPlainLumenHostname() {
    let resolved = ShadowClientConnectionHostResolutionKit.resolvedConnectHost(
        requestedHost: "test-route-host.local",
        discoveredHosts: [],
        knownHosts: [
            ShadowClientRemoteHostDescriptor(
                host: "test-route-host.local:48989",
                displayName: "Mac",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "",
                httpsPort: 48_984,
                appVersion: nil,
                gfeVersion: nil,
                uniqueID: "lumen",
                lastError: nil,
                localHost: "192.168.10.50:48989"
            )
        ]
    )

    #expect(resolved == "test-route-host.local:48989")
}

@Test("Connection host resolution upgrades a plain local route to the known Lumen connect candidate")
func connectionHostResolutionUpgradesPlainLocalRoute() {
    let resolved = ShadowClientConnectionHostResolutionKit.resolvedConnectHost(
        requestedHost: "192.168.10.50",
        discoveredHosts: [],
        knownHosts: [
            ShadowClientRemoteHostDescriptor(
                host: "test-route-host.local:48989",
                displayName: "Mac",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "",
                httpsPort: 48_984,
                appVersion: nil,
                gfeVersion: nil,
                uniqueID: "lumen",
                lastError: nil,
                localHost: "192.168.10.50:48989"
            )
        ]
    )

    #expect(resolved == "192.168.10.50:48989")
}

@Test("Connection host resolution preserves discovered explicit connect candidates")
func connectionHostResolutionPreservesDiscoveredExplicitCandidate() {
    let resolved = ShadowClientConnectionHostResolutionKit.resolvedConnectHost(
        requestedHost: "desktop.local",
        discoveredHosts: [
            ShadowClientDiscoveredHost(
                name: "Desktop",
                host: "desktop.local",
                port: 48_989,
                serviceType: "_shadow._tcp"
            )
        ],
        knownHosts: []
    )

    #expect(resolved == "desktop.local:48989")
}
