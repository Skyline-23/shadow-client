import Combine
import Foundation

public struct ShadowClientDiscoveredHost: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let host: String
    public let port: Int
    public let serviceType: String

    public init(
        name: String,
        host: String,
        port: Int,
        serviceType: String
    ) {
        self.id = host.lowercased()
        self.name = name
        self.host = host
        self.port = port
        self.serviceType = serviceType
    }
}

public enum ShadowClientHostDiscoveryState: Equatable, Sendable {
    case idle
    case discovering
    case failed(String)
}

public extension ShadowClientHostDiscoveryState {
    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .discovering:
            return "Discovering"
        case let .failed(message):
            return "Failed - \(message)"
        }
    }
}

struct ShadowClientDiscoveredHostCatalog {
    private var hostsByServiceKey: [String: ShadowClientDiscoveredHost] = [:]

    mutating func upsert(
        serviceKey: String,
        host: ShadowClientDiscoveredHost
    ) {
        hostsByServiceKey[serviceKey] = host
    }

    mutating func remove(serviceKey: String) {
        hostsByServiceKey.removeValue(forKey: serviceKey)
    }

    mutating func removeAll() {
        hostsByServiceKey.removeAll()
    }

    var hosts: [ShadowClientDiscoveredHost] {
        var deduplicatedByHost: [String: ShadowClientDiscoveredHost] = [:]

        for key in hostsByServiceKey.keys.sorted() {
            guard let host = hostsByServiceKey[key] else {
                continue
            }
            let hostKey = host.host.lowercased()
            if deduplicatedByHost[hostKey] == nil {
                deduplicatedByHost[hostKey] = host
            }
        }

        return deduplicatedByHost.values.sorted { lhs, rhs in
            let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
            if nameOrder == .orderedSame {
                return lhs.host.localizedCaseInsensitiveCompare(rhs.host) == .orderedAscending
            }
            return nameOrder == .orderedAscending
        }
    }
}

public final class ShadowClientHostDiscoveryRuntime: NSObject, ObservableObject {
    public static let defaultBonjourServiceTypes = [
        "_nvstream._tcp",
        "_sunshine._tcp",
        "_moonlight._tcp",
    ]

    @Published public private(set) var hosts: [ShadowClientDiscoveredHost] = []
    @Published public private(set) var state: ShadowClientHostDiscoveryState = .idle

    private let bonjourServiceTypes: [String]
    private var browsers: [NetServiceBrowser] = []
    private var services: [String: NetService] = [:]
    private var catalog = ShadowClientDiscoveredHostCatalog()

    public init(
        bonjourServiceTypes: [String] = ShadowClientHostDiscoveryRuntime.defaultBonjourServiceTypes
    ) {
        self.bonjourServiceTypes = bonjourServiceTypes
        super.init()
    }

    public func start() {
        guard browsers.isEmpty else {
            return
        }

        state = .discovering
        catalog.removeAll()
        hosts = []

        for type in bonjourServiceTypes {
            let browser = NetServiceBrowser()
            browser.delegate = self
            browsers.append(browser)
            browser.searchForServices(ofType: normalizedServiceType(type), inDomain: "local.")
        }
    }

    public func stop() {
        for browser in browsers {
            browser.stop()
            browser.delegate = nil
        }
        browsers.removeAll()

        for service in services.values {
            service.stop()
            service.delegate = nil
        }
        services.removeAll()

        catalog.removeAll()
        hosts = []
        state = .idle
    }

    public func refresh() {
        stop()
        start()
    }

    private func normalizedServiceType(_ type: String) -> String {
        type.hasSuffix(".") ? type : "\(type)."
    }

    private func serviceKey(for service: NetService) -> String {
        "\(service.type)|\(service.domain)|\(service.name)"
    }

    private func renderHosts() {
        hosts = catalog.hosts
    }

    private func resolvedHostName(from service: NetService) -> String? {
        if let hostName = service.hostName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        {
            if !hostName.isEmpty {
                return hostName
            }
        }

        let sanitizedName = service.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
        if sanitizedName.isEmpty {
            return nil
        }

        return "\(sanitizedName).local"
    }
}

extension ShadowClientHostDiscoveryRuntime: NetServiceBrowserDelegate {
    public func netServiceBrowserWillSearch(_ browser: NetServiceBrowser) {
        state = .discovering
    }

    public func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        let code = errorDict[NetService.errorCode]?.intValue ?? -1
        state = .failed("Bonjour discovery error (\(code)).")
    }

    public func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        let key = serviceKey(for: service)
        services[key] = service
        service.delegate = self
        service.resolve(withTimeout: 2.0)
    }

    public func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        let key = serviceKey(for: service)
        services[key]?.delegate = nil
        services.removeValue(forKey: key)
        catalog.remove(serviceKey: key)
        if !moreComing {
            renderHosts()
        }
    }
}

extension ShadowClientHostDiscoveryRuntime: NetServiceDelegate {
    public func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = resolvedHostName(from: sender) else {
            return
        }

        let serviceType = sender.type
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let discoveredHost = ShadowClientDiscoveredHost(
            name: sender.name,
            host: hostName,
            port: sender.port,
            serviceType: serviceType
        )

        let key = serviceKey(for: sender)
        catalog.upsert(serviceKey: key, host: discoveredHost)
        renderHosts()
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let key = serviceKey(for: sender)
        services.removeValue(forKey: key)
        catalog.remove(serviceKey: key)
        renderHosts()
    }
}
