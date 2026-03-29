import Combine
import Darwin
import Foundation
import OSLog

public struct ShadowClientDiscoveredHost: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let host: String
    public let port: Int
    public let serviceType: String
    public let authorityHost: String?
    public let controlHTTPSPort: Int?

    public init(
        name: String,
        host: String,
        port: Int,
        serviceType: String,
        authorityHost: String? = nil,
        controlHTTPSPort: Int? = nil
    ) {
        self.id = Self.probeCandidate(host: host, port: port)
        self.name = Self.sanitizedDisplayName(name, fallbackHost: host)
        self.host = host
        self.port = port
        self.serviceType = serviceType
        let normalizedAuthorityHost = authorityHost?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if let normalizedAuthorityHost, !normalizedAuthorityHost.isEmpty {
            self.authorityHost = normalizedAuthorityHost.lowercased()
        } else {
            self.authorityHost = nil
        }
        self.controlHTTPSPort = controlHTTPSPort
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
    private static let resolveTimeout: TimeInterval = 5.0
    private static let linkLocalPrefixes = [
        "169.254.",
        "fe80:",
    ]

    public static let defaultBonjourServiceTypes = [
        "_shadow._tcp",
    ]

    @Published public private(set) var hosts: [ShadowClientDiscoveredHost] = []
    @Published public private(set) var state: ShadowClientHostDiscoveryState = .idle

    private let bonjourServiceTypes: [String]
    private var browsers: [NetServiceBrowser] = []
    private var services: [String: NetService] = [:]
    private var txtMetadataByServiceKey: [String: DiscoveryTXTMetadata] = [:]

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
            service.stopMonitoring()
            service.stop()
            service.delegate = nil
        }
        services.removeAll()
        txtMetadataByServiceKey.removeAll()

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

    private static func discoveredHost(
        from service: NetService,
        allowFallbackHostName: Bool,
        cachedTXTMetadata: DiscoveryTXTMetadata? = nil
    ) -> ShadowClientDiscoveredHost? {
        let hostName: String?
        if allowFallbackHostName {
            hostName = resolvedHost(from: service)
        } else {
            hostName = preferredResolvedAddressHost(from: service.addresses)
        }

        guard let hostName else {
            return nil
        }

        let txtMetadata = cachedTXTMetadata ??
            service.txtRecordData().map(Self.discoveryTXTMetadata(from:))
        let serviceType = service.type
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return ShadowClientDiscoveredHost(
            name: service.name,
            host: hostName,
            port: service.port,
            serviceType: serviceType,
            authorityHost: txtMetadata?.authorityHost,
            controlHTTPSPort: txtMetadata?.controlHTTPSPort
        )
    }

    struct DiscoveryTXTMetadata: Sendable {
        let authorityHost: String?
        let controlHTTPSPort: Int?
    }

    static func resolvedHost(from service: NetService) -> String? {
        let resolvedAddressHost = preferredResolvedAddressHost(from: service.addresses)
        if let resolvedAddressHost {
            return resolvedAddressHost
        }

        return fallbackHostName(
            service.hostName,
            serviceName: service.name
        )
    }

    static func preferredResolvedAddressHost(from addresses: [Data]?) -> String? {
        guard let addresses else {
            return nil
        }

        let candidates = addresses.compactMap(parsedNumericHost(fromSockAddrData:))
        let prioritized = candidates
            .filter { candidate in
                !isLoopbackHost(candidate)
            }
            .sorted { lhs, rhs in
                resolvedAddressPriority(for: lhs) < resolvedAddressPriority(for: rhs)
            }

        return prioritized.first
    }

    static func fallbackHostName(
        _ hostName: String?,
        serviceName: String
    ) -> String? {
        if let hostName = hostName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        {
            if !hostName.isEmpty {
                return hostName
            }
        }

        let sanitizedName = serviceName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "-")
        if sanitizedName.isEmpty {
            return nil
        }

        return "\(sanitizedName).local"
    }

    static func discoveryTXTMetadata(from txtRecordData: Data) -> DiscoveryTXTMetadata {
        let txtRecord = NetService.dictionary(fromTXTRecord: txtRecordData)

        func stringValue(for key: String) -> String? {
            guard let valueData = txtRecord[key] else {
                return nil
            }

            let decoded = String(data: valueData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard let decoded, !decoded.isEmpty else {
                return nil
            }

            return decoded
        }

        let authorityHost = stringValue(for: "authority-host")?.lowercased()
        let controlHTTPSPort = stringValue(for: "control-port").flatMap(Int.init)
        return DiscoveryTXTMetadata(
            authorityHost: authorityHost,
            controlHTTPSPort: controlHTTPSPort
        )
    }

    private static func parsedNumericHost(fromSockAddrData data: Data) -> String? {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return nil
            }

            let sockaddrPointer = baseAddress.assumingMemoryBound(to: sockaddr.self)
            let family = Int32(sockaddrPointer.pointee.sa_family)
            let maxHostLength = Int(NI_MAXHOST)
            var hostBuffer = [CChar](repeating: 0, count: maxHostLength)

            let result = getnameinfo(
                sockaddrPointer,
                socklen_t(data.count),
                &hostBuffer,
                socklen_t(maxHostLength),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else {
                return nil
            }

            let host = String(cString: hostBuffer)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !host.isEmpty else {
                return nil
            }

            switch family {
            case AF_INET, AF_INET6:
                return host
            default:
                return nil
            }
        }
    }

    private static func resolvedAddressPriority(for host: String) -> Int {
        if !isLinkLocalHost(host) {
            return host.contains(":") ? 1 : 0
        }
        return host.contains(":") ? 3 : 2
    }

    private static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "localhost" ||
            normalized == "::1" ||
            normalized.hasPrefix("127.")
    }

    private static func isLinkLocalHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return linkLocalPrefixes.contains(where: { normalized.hasPrefix($0) })
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
        txtMetadataByServiceKey.removeValue(forKey: key)
        services[key] = service
        service.delegate = self
        service.resolve(withTimeout: Self.resolveTimeout)
    }

    public func netServiceBrowser(
        _: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        let key = serviceKey(for: service)
        services[key]?.stopMonitoring()
        services[key]?.delegate = nil
        services.removeValue(forKey: key)
        txtMetadataByServiceKey.removeValue(forKey: key)
        emit(.serviceRemoved(serviceKey: key, moreComing: moreComing))
    }
}

extension ShadowClientHostDiscoveryRuntime: NetServiceDelegate {
    public func netServiceDidResolveAddress(_ sender: NetService) {
        let key = serviceKey(for: sender)
        guard let discoveredHost = Self.discoveredHost(
            from: sender,
            allowFallbackHostName: true,
            cachedTXTMetadata: txtMetadataByServiceKey[key]
        ) else {
            Self.logger.error(
                "Bonjour service resolved without hostname name=\(sender.name, privacy: .public) type=\(sender.type, privacy: .public)"
            )
            return
        }
        sender.startMonitoring()
        Self.logger.notice(
            "Bonjour service resolved host=\(discoveredHost.host, privacy: .public) port=\(discoveredHost.port, privacy: .public) name=\(discoveredHost.name, privacy: .public) type=\(discoveredHost.serviceType, privacy: .public)"
        )

        emit(
            .serviceResolved(
                serviceKey: key,
                host: discoveredHost
            )
        )
    }

    public func netService(_ sender: NetService, didUpdateTXTRecord data: Data) {
        let key = serviceKey(for: sender)
        let txtMetadata = Self.discoveryTXTMetadata(from: data)
        txtMetadataByServiceKey[key] = txtMetadata

        guard let discoveredHost = Self.discoveredHost(
            from: sender,
            allowFallbackHostName: true,
            cachedTXTMetadata: txtMetadata
        ) else {
            return
        }

        Self.logger.notice(
            "Bonjour service updated TXT host=\(discoveredHost.host, privacy: .public) authority=\((discoveredHost.authorityHost ?? "nil"), privacy: .public) control-port=\((discoveredHost.controlHTTPSPort.map(String.init) ?? "nil"), privacy: .public)"
        )
        emit(.serviceResolved(serviceKey: key, host: discoveredHost))
    }

    public func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        let key = serviceKey(for: sender)
        let errorCode = errorDict[NetService.errorCode]?.intValue ?? -1

        if let fallbackHost = Self.discoveredHost(
            from: sender,
            allowFallbackHostName: true,
            cachedTXTMetadata: txtMetadataByServiceKey[key]
        ) {
            Self.logger.notice(
                "Bonjour service using fallback host=\(fallbackHost.host, privacy: .public) port=\(fallbackHost.port, privacy: .public) name=\(fallbackHost.name, privacy: .public) type=\(fallbackHost.serviceType, privacy: .public) resolve-error=\(errorCode, privacy: .public)"
            )
            emit(.serviceResolved(serviceKey: key, host: fallbackHost))
            return
        }

        services.removeValue(forKey: key)
        Self.logger.error(
            "Bonjour service failed to resolve name=\(sender.name, privacy: .public) type=\(sender.type, privacy: .public) error=\(errorCode, privacy: .public)"
        )
        emit(.serviceDidNotResolve(serviceKey: key))
    }
}
