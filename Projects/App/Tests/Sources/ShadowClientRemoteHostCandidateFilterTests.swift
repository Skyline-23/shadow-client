import Testing
@testable import ShadowClientFeatureHome

@Test("Remote host candidate filter preserves same-machine service hosts while removing loopback entries")
func remoteHostCandidateFilterPreservesSameMachineServiceHostsWhileRemovingLoopbackEntries() {
    let candidates = ShadowClientRemoteHostCandidateFilter.filteredCandidates(
        discoveredHosts: [
            "localhost",
            "127.0.0.1",
            "169.254.15.176",
            "fe80::1",
            "second-stream-host.local",
            "192.168.10.50",
        ],
        manualHost: "second-stream-host.local",
        localInterfaceHosts: [
            "192.168.10.50",
        ]
    )

    #expect(candidates == ["second-stream-host.local", "192.168.10.50"])
}

@Test("Remote host candidate filter classifies numeric loopback and link-local addresses without string prefix checks")
func remoteHostCandidateFilterClassifiesNumericLoopbackAndLinkLocalAddresses() {
    #expect(ShadowClientRemoteHostCandidateFilter.isLoopbackHost("127.0.0.1"))
    #expect(ShadowClientRemoteHostCandidateFilter.isLoopbackHost("::1"))
    #expect(ShadowClientRemoteHostCandidateFilter.isLinkLocalHost("169.254.15.176"))
    #expect(ShadowClientRemoteHostCandidateFilter.isLinkLocalHost("fe80::1%en12"))
    #expect(ShadowClientRemoteHostCandidateFilter.isLinkLocalHost("fdaf:7bd4:8418:463e:1c47:71fb:db43:1f94"))
    #expect(!ShadowClientRemoteHostCandidateFilter.isLoopbackHost("test-route-host.local"))
    #expect(!ShadowClientRemoteHostCandidateFilter.isLinkLocalHost("test-route-host.local"))
}

@Test("Remote host candidate filter preserves explicit default Lumen service ports")
func remoteHostCandidateFilterPreservesExplicitDefaultLumenServicePorts() {
    let candidates = ShadowClientRemoteHostCandidateFilter.filteredCandidates(
        discoveredHosts: [
            "dual-lumen.example.invalid:47989",
            "dual-lumen.example.invalid:48989",
        ],
        manualHost: nil,
        localInterfaceHosts: []
    )

    #expect(candidates == ["dual-lumen.example.invalid:47984", "dual-lumen.example.invalid:48984"])
}

@Test("Remote host candidate filter keeps link-local routes when they are the only discovered option")
func remoteHostCandidateFilterKeepsLinkLocalRoutesWhenNoRoutableCandidatesExist() {
    let candidates = ShadowClientRemoteHostCandidateFilter.filteredCandidates(
        discoveredHosts: [
            "169.254.57.109:48984",
        ],
        manualHost: nil,
        localInterfaceHosts: []
    )

    #expect(candidates == ["169.254.57.109:48984"])
}
