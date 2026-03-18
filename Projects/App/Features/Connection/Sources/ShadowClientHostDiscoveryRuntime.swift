import Combine
import Foundation
import OSLog

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
        self.id = Self.probeCandidate(host: host, port: port)
        self.name = Self.sanitizedDisplayName(name, fallbackHost: host)
        self.host = host
        self.port = port
        self.serviceType = serviceType
    }

    public var probeCandidate: String {
        Self.probeCandidate(host: host, port: port)
    }

    private static func probeCandidate(host: String, port: Int) -> String {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else {
            return ""
        }
        return "\(normalizedHost):\(port)"
    }

    private static func sanitizedDisplayName(_ rawName: String, fallbackHost: String) -> String {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.lowercased()

        if trimmed.isEmpty || normalized == "unknown" || normalized == "unknown name" {
            return fallbackHost
        }

        return trimmed
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
            let hostKey = host.probeCandidate
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

private enum ShadowClientHostDiscoveryEvent: Sendable {
    case startDiscovering(resetCatalog: Bool)
    case searchFailed(String)
    case serviceResolved(serviceKey: String, host: ShadowClientDiscoveredHost)
    case serviceRemoved(serviceKey: String, moreComing: Bool)
    case serviceDidNotResolve(serviceKey: String)
    case stopDiscovering
}

private struct ShadowClientHostDiscoverySnapshot: Sendable {
    let state: ShadowClientHostDiscoveryState
    let hosts: [ShadowClientDiscoveredHost]
}

private actor ShadowClientHostDiscoveryEventReducer {
    private var catalog = ShadowClientDiscoveredHostCatalog()
    private var state: ShadowClientHostDiscoveryState = .idle

    func reduce(_ event: ShadowClientHostDiscoveryEvent) -> ShadowClientHostDiscoverySnapshot? {
        switch event {
        case let .startDiscovering(resetCatalog):
            state = .discovering
            if resetCatalog {
                catalog.removeAll()
            }
            return snapshot()
        case let .searchFailed(message):
            state = .failed(message)
            return snapshot()
        case let .serviceResolved(serviceKey, host):
            catalog.upsert(serviceKey: serviceKey, host: host)
            return snapshot()
        case let .serviceRemoved(serviceKey, moreComing):
            catalog.remove(serviceKey: serviceKey)
            return moreComing ? nil : snapshot()
        case let .serviceDidNotResolve(serviceKey):
            catalog.remove(serviceKey: serviceKey)
            return snapshot()
        case .stopDiscovering:
            state = .idle
            catalog.removeAll()
            return snapshot()
        }
    }

    private func snapshot() -> ShadowClientHostDiscoverySnapshot {
        ShadowClientHostDiscoverySnapshot(
            state: state,
            hosts: catalog.hosts
        )
    }
}

public final class ShadowClientHostDiscoveryRuntime: NSObject, ObservableObject {
    private static let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "HostDiscovery"
    )

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

    private let reducer = ShadowClientHostDiscoveryEventReducer()
    private let eventContinuation: AsyncStream<ShadowClientHostDiscoveryEvent>.Continuation
    private var eventLoopTask: Task<Void, Never>?

    public init(
        bonjourServiceTypes: [String] = ShadowClientHostDiscoveryRuntime.defaultBonjourServiceTypes
    ) {
        self.bonjourServiceTypes = bonjourServiceTypes

        let (eventStream, eventContinuation) = AsyncStream.makeStream(of: ShadowClientHostDiscoveryEvent.self)
        self.eventContinuation = eventContinuation

        super.init()

        eventLoopTask = Task { [weak self] in
            guard let self else {
                return
            }

            for await event in eventStream {
                guard let snapshot = await self.reducer.reduce(event) else {
                    continue
                }

                await MainActor.run {
                    self.state = snapshot.state
                    self.hosts = snapshot.hosts
                }
            }
        }
    }

    deinit {
        eventContinuation.finish()
        eventLoopTask?.cancel()
    }

    public func start() {
        guard browsers.isEmpty else {
            return
        }

        emit(.startDiscovering(resetCatalog: true))
        let serviceTypes = bonjourServiceTypes.joined(separator: ",")
        Self.logger.notice(
            "Bonjour discovery start service-types=\(serviceTypes, privacy: .public)"
        )

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

        emit(.stopDiscovering)
        Self.logger.notice("Bonjour discovery stopped")
    }

    public func refresh() {
        stop()
        start()
    }

    private func emit(_ event: ShadowClientHostDiscoveryEvent) {
        eventContinuation.yield(event)
    }

    private func normalizedServiceType(_ type: String) -> String {
        type.hasSuffix(".") ? type : "\(type)."
    }

    private func serviceKey(for service: NetService) -> String {
        "\(service.type)|\(service.domain)|\(service.name)"
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
    public func netServiceBrowserWillSearch(_: NetServiceBrowser) {
        emit(.startDiscovering(resetCatalog: false))
    }

    public func netServiceBrowser(
        _: NetServiceBrowser,
        didNotSearch errorDict: [String: NSNumber]
    ) {
        let code = errorDict[NetService.errorCode]?.intValue ?? -1
        emit(.searchFailed("Bonjour discovery error (\(code))."))
    }

    public func netServiceBrowser(
        _: NetServiceBrowser,
        didFind service: NetService,
        moreComing _: Bool
    ) {
        Self.logger.notice(
            "Bonjour service found name=\(service.name, privacy: .public) type=\(service.type, privacy: .public) domain=\(service.domain, privacy: .public)"
        )
        let key = serviceKey(for: service)
        services[key] = service
        service.delegate = self
        service.resolve(withTimeout: 2.0)
    }

    public func netServiceBrowser(
        _: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        let key = serviceKey(for: service)
        services[key]?.delegate = nil
        services.removeValue(forKey: key)
        emit(.serviceRemoved(serviceKey: key, moreComing: moreComing))
    }
}

extension ShadowClientHostDiscoveryRuntime: NetServiceDelegate {
    public func netServiceDidResolveAddress(_ sender: NetService) {
        guard let hostName = resolvedHostName(from: sender) else {
            Self.logger.error(
                "Bonjour service resolved without hostname name=\(sender.name, privacy: .public) type=\(sender.type, privacy: .public)"
            )
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
        Self.logger.notice(
            "Bonjour service resolved host=\(discoveredHost.host, privacy: .public) port=\(discoveredHost.port, privacy: .public) name=\(discoveredHost.name, privacy: .public) type=\(discoveredHost.serviceType, privacy: .public)"
        )

        emit(
            .serviceResolved(
                serviceKey: serviceKey(for: sender),
                host: discoveredHost
            )
        )
    }

    public func netService(_ sender: NetService, didNotResolve _: [String: NSNumber]) {
        let key = serviceKey(for: sender)
        services.removeValue(forKey: key)
        Self.logger.error(
            "Bonjour service failed to resolve name=\(sender.name, privacy: .public) type=\(sender.type, privacy: .public)"
        )
        emit(.serviceDidNotResolve(serviceKey: key))
    }
}
