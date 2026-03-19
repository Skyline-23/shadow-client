import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Host catalog maps cached Apollo HTTPS routes back to Moonlight connect candidates")
func hostCatalogMapsCachedApolloHTTPSRouteToConnectCandidate() {
    let descriptor = ShadowClientRemoteHostDescriptor(
        activeRoute: .init(host: "apollo-host.local", httpsPort: 48_984),
        displayName: "Apollo Mac",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        appVersion: "1.0",
        gfeVersion: nil,
        uniqueID: "HOST-APOLLO",
        lastError: nil,
        routes: .init(active: .init(host: "apollo-host.local", httpsPort: 48_984))
    )

    #expect(
        ShadowClientHostCatalogKit.cachedCandidateHosts(from: [descriptor]) == [
            "apollo-host.local:48989",
        ]
    )
}

@Test("Host catalog does not recache certificate mismatch routes as automatic candidates")
func hostCatalogSkipsRecachingCertificateMismatchRoutes() {
    let descriptor = ShadowClientRemoteHostDescriptor(
        activeRoute: .init(host: "apollo-host.local", httpsPort: 47_984),
        displayName: "Apollo Mac",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        appVersion: "1.0",
        gfeVersion: nil,
        uniqueID: "HOST-APOLLO",
        lastError: "Host rejected request (401): Server certificate mismatch",
        routes: .init(active: .init(host: "apollo-host.local", httpsPort: 47_984))
    )

    #expect(ShadowClientHostCatalogKit.cachedCandidateHosts(from: [descriptor]).isEmpty)
}

@Test("Host catalog collapses bare host aliases into explicit Apollo connect candidates")
func hostCatalogCollapsesBareHostIntoExplicitApolloConnectCandidate() {
    let candidates = ShadowClientHostCatalogKit.refreshCandidates(
        autoFindHosts: true,
        discoveredHosts: ["apollo-host.local:48989"],
        cachedHosts: ["apollo-host.local"],
        manualHost: nil
    )

    #expect(candidates == ["apollo-host.local:48984"])
}

@Test("Host catalog prefers Apollo connect base port over HTTPS endpoint aliases")
func hostCatalogPrefersApolloConnectPortOverHTTPSAlias() {
    let candidates = ShadowClientHostCatalogKit.refreshCandidates(
        autoFindHosts: true,
        discoveredHosts: ["apollo-host.local:48989"],
        cachedHosts: ["apollo-host.local:48984"],
        manualHost: nil
    )

    #expect(candidates == ["apollo-host.local:48984"])
}

@Test("Host catalog preserves distinct explicit Apollo service ports on the same host")
func hostCatalogPreservesDistinctExplicitApolloServicePortsOnSameHost() {
    let candidates = ShadowClientHostCatalogKit.refreshCandidates(
        autoFindHosts: true,
        discoveredHosts: ["apollo-host.local:47989", "apollo-host.local:48989"],
        cachedHosts: [],
        manualHost: nil
    )

    #expect(candidates == ["apollo-host.local:47984", "apollo-host.local:48984"])
}

@Test("Host catalog drops bare host aliases when explicit default and alternate service ports coexist")
func hostCatalogDropsBareHostAliasWhenSameHostHasExplicitServiceCandidates() {
    let candidates = ShadowClientHostCatalogKit.refreshCandidates(
        autoFindHosts: true,
        discoveredHosts: ["apollo-host.local", "apollo-host.local:47984", "apollo-host.local:48984"],
        cachedHosts: [],
        manualHost: nil
    )

    #expect(candidates == ["apollo-host.local:47984", "apollo-host.local:48984"])
}
