import Testing
@testable import ShadowClientFeatureHome

@Test("Remote host candidate filter removes self hosts and loopback entries")
func remoteHostCandidateFilterRemovesSelfHostsAndLoopbackEntries() {
    let candidates = ShadowClientRemoteHostCandidateFilter.filteredCandidates(
        discoveredHosts: [
            "localhost",
            "127.0.0.1",
            "198.18.0.176",
            "fe80::1",
            "desktop-lan.local",
            "10.0.0.50",
        ],
        manualHost: "desktop-lan.local",
        localInterfaceHosts: [
            "10.0.0.50",
        ]
    )

    #expect(candidates == ["desktop-lan.local"])
}

@Test("Remote host candidate filter removes current machine hostnames")
func remoteHostCandidateFilterRemovesCurrentMachineHostNames() {
    let candidates = ShadowClientRemoteHostCandidateFilter.filteredCandidates(
        discoveredHosts: [
            "example-remote.local",
            "current-machine.local",
        ],
        manualHost: "CURRENT-MACHINE.LOCAL",
        localInterfaceHosts: [
            "current-machine.local",
            "current-machine",
        ]
    )

    #expect(candidates == ["example-remote.local"])
}
