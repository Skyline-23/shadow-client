import Testing
@testable import ShadowClientFeatureHome

@Test("Remote host candidate filter removes self hosts and loopback entries")
func remoteHostCandidateFilterRemovesSelfHostsAndLoopbackEntries() {
    let candidates = ShadowClientRemoteHostCandidateFilter.filteredCandidates(
        discoveredHosts: [
            "buseongs-macbook-pro-14.local",
            "localhost",
            "127.0.0.1",
            "skyline23-pc.local",
        ],
        manualHost: "skyline23-pc.local",
        selfHostNames: [
            "buseongs-macbook-pro-14",
            "buseongs-macbook-pro-14.local",
        ]
    )

    #expect(candidates == ["skyline23-pc.local"])
}
