import Testing
@testable import ShadowClientFeatureConnection
import Foundation

@Test("Host discovery runtime prefers resolved LAN addresses over Bonjour host names")
func hostDiscoveryRuntimePrefersResolvedLANAddressesOverBonjourHostNames() {
    let localAddress = ipv4SockAddrData("192.168.0.50")
    let publicAddress = ipv4SockAddrData("222.110.28.97")

    let resolved = ShadowClientHostDiscoveryRuntime.preferredResolvedAddressHost(
        from: [publicAddress, localAddress]
    )

    #expect(resolved == "192.168.0.50")
}

@Test("Host discovery runtime falls back to Bonjour host name when addresses are missing")
func hostDiscoveryRuntimeFallsBackToBonjourHostNameWhenAddressesAreMissing() {
    let resolved = ShadowClientHostDiscoveryRuntime.fallbackHostName(
        "wifi.skyline23.com.",
        serviceName: "Lumen Mac"
    )

    #expect(resolved == "wifi.skyline23.com")
}

@Test("Host discovery runtime synthesizes a local host name when resolve data is unavailable")
func hostDiscoveryRuntimeSynthesizesLocalHostNameWhenResolveDataIsUnavailable() {
    let resolved = ShadowClientHostDiscoveryRuntime.fallbackHostName(
        nil,
        serviceName: "Mac"
    )

    #expect(resolved == "Mac.local")
}

@Test("Host discovery catalog deduplicates same host discovered from multiple services")
func hostDiscoveryCatalogDeduplicatesHosts() {
    var catalog = ShadowClientDiscoveredHostCatalog()
    catalog.upsert(
        serviceKey: "a",
        host: .init(
            name: "LivingRoom-PC",
            host: "192.168.0.20",
            port: 47984,
            serviceType: "_shadow._tcp"
        )
    )
    catalog.upsert(
        serviceKey: "b",
        host: .init(
            name: "LivingRoom-PC (Host)",
            host: "192.168.0.20",
            port: 47984,
            serviceType: "_shadow._tcp"
        )
    )

    let hosts = catalog.hosts
    #expect(hosts.count == 1)
    #expect(hosts.first?.host == "192.168.0.20")
}

@Test("Host discovery catalog preserves same host discovered on different ports")
func hostDiscoveryCatalogPreservesDistinctPorts() {
    var catalog = ShadowClientDiscoveredHostCatalog()
    catalog.upsert(
        serviceKey: "a",
        host: .init(
            name: "Test-Route-Host",
            host: "test-route-host.local",
            port: 47989,
            serviceType: "_shadow._tcp"
        )
    )
    catalog.upsert(
        serviceKey: "b",
        host: .init(
            name: "Test-Route-Host",
            host: "test-route-host.local",
            port: 48989,
            serviceType: "_shadow._tcp"
        )
    )

    let hosts = catalog.hosts
    #expect(hosts.count == 2)
    #expect(hosts.map(\.probeCandidate).contains("test-route-host.local:47989"))
    #expect(hosts.map(\.probeCandidate).contains("test-route-host.local:48989"))
}

@Test("Host discovery catalog removes host when service disappears")
func hostDiscoveryCatalogRemovesHostWhenServiceRemoved() {
    var catalog = ShadowClientDiscoveredHostCatalog()
    catalog.upsert(
        serviceKey: "a",
        host: .init(
            name: "Office-PC",
            host: "192.168.0.30",
            port: 47984,
            serviceType: "_shadow._tcp"
        )
    )

    #expect(catalog.hosts.count == 1)
    catalog.remove(serviceKey: "a")
    #expect(catalog.hosts.isEmpty)
}

@Test("Host discovery catalog sorts hosts by display name")
func hostDiscoveryCatalogSortsHostsByName() {
    var catalog = ShadowClientDiscoveredHostCatalog()
    catalog.upsert(
        serviceKey: "b",
        host: .init(
            name: "Zulu-PC",
            host: "192.168.0.41",
            port: 47984,
            serviceType: "_shadow._tcp"
        )
    )
    catalog.upsert(
        serviceKey: "a",
        host: .init(
            name: "Alpha-PC",
            host: "192.168.0.40",
            port: 47984,
            serviceType: "_shadow._tcp"
        )
    )

    let hosts = catalog.hosts
    #expect(hosts.count == 2)
    #expect(hosts[0].name == "Alpha-PC")
    #expect(hosts[1].name == "Zulu-PC")
}

private func ipv4SockAddrData(_ host: String) -> Data {
    var address = in_addr()
    let conversionResult = host.withCString { inet_pton(AF_INET, $0, &address) }
    #expect(conversionResult == 1)

    var sockaddr = sockaddr_in()
    sockaddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    sockaddr.sin_family = sa_family_t(AF_INET)
    sockaddr.sin_port = in_port_t(0)
    sockaddr.sin_addr = address

    return withUnsafeBytes(of: &sockaddr) { Data($0) }
}
