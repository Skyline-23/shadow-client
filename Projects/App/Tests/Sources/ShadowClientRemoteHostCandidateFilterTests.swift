import Testing
@testable import ShadowClientFeatureHome

@Test("Remote host candidate filter removes self hosts and loopback entries")
func remoteHostCandidateFilterRemovesSelfHostsAndLoopbackEntries() {
    let candidates = ShadowClientRemoteHostCandidateFilter.filteredCandidates(
        discoveredHosts: [
            "localhost",
            "127.0.0.1",
            "169.254.15.176",
            "fe80::1",
            "skyline23-pc.local",
            "192.168.0.50",
        ],
        manualHost: "skyline23-pc.local",
        localInterfaceHosts: [
            "192.168.0.50",
        ]
    )

    #expect(candidates == ["skyline23-pc.local"])
}
