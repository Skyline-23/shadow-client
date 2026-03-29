import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Host catalog maps cached Lumen HTTPS routes back to Moonlight connect candidates")
func hostCatalogMapsCachedLumenHTTPSRouteToConnectCandidate() {
    let descriptor = ShadowClientRemoteHostDescriptor(
        activeRoute: .init(host: "lumen-host.local", httpsPort: 48_984),
        displayName: "Lumen Mac",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        appVersion: "1.0",
        gfeVersion: nil,
        uniqueID: "HOST-APOLLO",
        lastError: nil,
        routes: .init(active: .init(host: "lumen-host.local", httpsPort: 48_984))
    )

    #expect(
        ShadowClientHostCatalogKit.cachedCandidateHosts(from: [descriptor]) == [
            "lumen-host.local:48989",
        ]
    )
}

@Test("Host catalog does not recache certificate mismatch routes as automatic candidates")
func hostCatalogSkipsRecachingCertificateMismatchRoutes() {
    let descriptor = ShadowClientRemoteHostDescriptor(
        activeRoute: .init(host: "lumen-host.local", httpsPort: 47_984),
        displayName: "Lumen Mac",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        appVersion: "1.0",
        gfeVersion: nil,
        uniqueID: "HOST-APOLLO",
        lastError: "Host rejected request (401): Server certificate mismatch",
        routes: .init(active: .init(host: "lumen-host.local", httpsPort: 47_984))
    )

    #expect(ShadowClientHostCatalogKit.cachedCandidateHosts(from: [descriptor]).isEmpty)
}

@Test("Host catalog collapses bare host aliases into explicit Lumen connect candidates")
func hostCatalogCollapsesBareHostIntoExplicitLumenConnectCandidate() {
    let candidates = ShadowClientHostCatalogKit.refreshCandidates(
        autoFindHosts: true,
        discoveredHosts: ["lumen-host.local:48989"],
        cachedHosts: ["lumen-host.local"],
        manualHost: nil
    )

    #expect(candidates == ["lumen-host.local:48984"])
}

@Test("Host catalog prefers Lumen connect base port over HTTPS endpoint aliases")
func hostCatalogPrefersLumenConnectPortOverHTTPSAlias() {
    let candidates = ShadowClientHostCatalogKit.refreshCandidates(
        autoFindHosts: true,
        discoveredHosts: ["lumen-host.local:48989"],
        cachedHosts: ["lumen-host.local:48984"],
        manualHost: nil
    )

    #expect(candidates == ["lumen-host.local:48984"])
}

@Test("Host catalog preserves distinct explicit Lumen service ports on the same host")
func hostCatalogPreservesDistinctExplicitLumenServicePortsOnSameHost() {
    let candidates = ShadowClientHostCatalogKit.refreshCandidates(
        autoFindHosts: true,
        discoveredHosts: ["lumen-host.local:47989", "lumen-host.local:48989"],
        cachedHosts: [],
        manualHost: nil
    )

    #expect(candidates == ["lumen-host.local:47984", "lumen-host.local:48984"])
}

@Test("Host catalog drops bare host aliases when explicit default and alternate service ports coexist")
func hostCatalogDropsBareHostAliasWhenSameHostHasExplicitServiceCandidates() {
    let candidates = ShadowClientHostCatalogKit.refreshCandidates(
        autoFindHosts: true,
        discoveredHosts: ["lumen-host.local", "lumen-host.local:47984", "lumen-host.local:48984"],
        cachedHosts: [],
        manualHost: nil
    )

    #expect(candidates == ["lumen-host.local:47984", "lumen-host.local:48984"])
}

@Test("Host catalog prefers the live discovered route over a stale preferred alias")
func hostCatalogPrefersLiveDiscoveredRouteOverStalePreferredAlias() {
    let preferred = resolvedPreferredCatalogCandidate(
        "mac.local:48984",
        discoveredCandidates: ["192.168.0.50:48984"],
        availableCandidates: ["192.168.0.50:48984", "mac.local:48984"]
    )

    #expect(preferred == "192.168.0.50:48984")
}
