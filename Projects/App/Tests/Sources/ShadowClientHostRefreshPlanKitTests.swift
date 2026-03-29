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
