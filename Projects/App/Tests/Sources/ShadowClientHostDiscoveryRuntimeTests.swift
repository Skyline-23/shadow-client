import Testing
@testable import ShadowClientFeatureConnection

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
