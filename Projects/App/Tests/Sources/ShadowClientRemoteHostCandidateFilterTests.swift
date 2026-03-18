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
            "second-stream-host.local",
            "192.168.0.50",
        ],
        manualHost: "second-stream-host.local",
        localInterfaceHosts: [
            "192.168.0.50",
        ]
    )

    #expect(candidates == ["second-stream-host.local"])
}

@Test("Remote host candidate filter classifies numeric loopback and link-local addresses without string prefix checks")
func remoteHostCandidateFilterClassifiesNumericLoopbackAndLinkLocalAddresses() {
    #expect(ShadowClientRemoteHostCandidateFilter.isLoopbackHost("127.0.0.1"))
    #expect(ShadowClientRemoteHostCandidateFilter.isLoopbackHost("::1"))
    #expect(ShadowClientRemoteHostCandidateFilter.isLinkLocalHost("169.254.15.176"))
    #expect(ShadowClientRemoteHostCandidateFilter.isLinkLocalHost("fe80::1%en12"))
    #expect(ShadowClientRemoteHostCandidateFilter.isLinkLocalHost("fdaf:7bd4:8418:463e:1c47:71fb:db43:1f94"))
    #expect(!ShadowClientRemoteHostCandidateFilter.isLoopbackHost("buseongs-macbook-pro-14.local"))
    #expect(!ShadowClientRemoteHostCandidateFilter.isLinkLocalHost("buseongs-macbook-pro-14.local"))
}
