import Testing
@testable import ShadowClientFeatureHome

@Test("Host refresh plan prioritizes the preferred live route ahead of stale aliases")
func hostRefreshPlanPrioritizesPreferredLiveRouteAheadOfStaleAliases() {
    let candidates = ShadowClientHostRefreshPlanKit.orderedCandidates(
        discoveredHosts: ["192.168.0.50:48984"],
        cachedHosts: ["mac.local:48984"],
        preferredHost: "192.168.0.50:48984"
    )

    #expect(candidates == ["192.168.0.50:48984", "mac.local:48984"])
}

@Test("Host refresh plan rewrites control routes back to stream routes before scheduling fetches")
func hostRefreshPlanRewritesControlRoutesBackToStreamRoutesBeforeSchedulingFetches() {
    let candidates = ShadowClientHostRefreshPlanKit.orderedCandidates(
        discoveredHosts: [],
        cachedHosts: ["192.168.0.50:48990"],
        preferredHost: nil
    )

    #expect(candidates == ["192.168.0.50:48984"])
}

@Test("Host refresh plan keeps configured authority host separate from the preferred connect route")
func hostRefreshPlanKeepsConfiguredAuthorityHostSeparateFromConnectRoute() {
    let plan = ShadowClientHostRefreshPlanKit.makeCatalogRefreshPlan(
        autoFindHosts: true,
        discoveredHosts: [
            .init(name: "Mac", host: "192.168.0.50", port: 48984, serviceType: "_shadow._tcp"),
        ],
        cachedHosts: [],
        preferredHost: "wifi.skyline23.com:48984",
        hiddenCandidates: []
    )

    #expect(plan.refreshCandidates == ["192.168.0.50:48984"])
    #expect(plan.preferredRefreshCandidate == "192.168.0.50:48984")
    #expect(plan.preferredAuthorityHost == "wifi.skyline23.com")
}

@Test("Host refresh plan uses discovered authority host when no manual authority is saved")
func hostRefreshPlanUsesDiscoveredAuthorityHostWhenNoManualAuthorityIsSaved() {
    let plan = ShadowClientHostRefreshPlanKit.makeCatalogRefreshPlan(
        autoFindHosts: true,
        discoveredHosts: [
            .init(
                name: "Mac",
                host: "169.254.57.109",
                port: 48984,
                serviceType: "_shadow._tcp",
                authorityHost: "wifi.skyline23.com",
                controlHTTPSPort: 48990
            ),
        ],
        cachedHosts: [],
        preferredHost: nil,
        hiddenCandidates: []
    )

    #expect(plan.refreshCandidates == ["169.254.57.109:48984"])
    #expect(plan.preferredRefreshCandidate == "169.254.57.109:48984")
    #expect(plan.preferredAuthorityHost == "wifi.skyline23.com")
}
