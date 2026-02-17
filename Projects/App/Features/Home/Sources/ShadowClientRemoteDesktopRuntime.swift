import Combine
import Foundation

public enum ShadowClientRemoteHostPairStatus: String, Equatable, Sendable {
    case paired
    case notPaired
    case unknown
}

public struct ShadowClientRemoteHostDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let host: String
    public let displayName: String
    public let pairStatus: ShadowClientRemoteHostPairStatus
    public let currentGameID: Int
    public let serverState: String
    public let httpsPort: Int
    public let appVersion: String?
    public let gfeVersion: String?
    public let uniqueID: String?
    public let lastError: String?

    public init(
        host: String,
        displayName: String,
        pairStatus: ShadowClientRemoteHostPairStatus,
        currentGameID: Int,
        serverState: String,
        httpsPort: Int,
        appVersion: String?,
        gfeVersion: String?,
        uniqueID: String?,
        lastError: String?
    ) {
        self.id = host.lowercased()
        self.host = host
        self.displayName = displayName
        self.pairStatus = pairStatus
        self.currentGameID = currentGameID
        self.serverState = serverState
        self.httpsPort = httpsPort
        self.appVersion = appVersion
        self.gfeVersion = gfeVersion
        self.uniqueID = uniqueID
        self.lastError = lastError
    }

    public var isReachable: Bool {
        lastError == nil
    }

    public var statusLabel: String {
        if let lastError, !lastError.isEmpty {
            return "Unavailable"
        }

        if currentGameID > 0 {
            return "Streaming"
        }

        switch pairStatus {
        case .paired:
            return "Ready"
        case .notPaired:
            return "Needs Pairing"
        case .unknown:
            return "Reachable"
        }
    }

    public var detailLabel: String {
        if let lastError, !lastError.isEmpty {
            return lastError
        }

        if currentGameID > 0 {
            return "Active game ID: \(currentGameID)"
        }

        switch pairStatus {
        case .paired:
            return "Pair status verified"
        case .notPaired:
            return "Host reachable but not paired"
        case .unknown:
            return "Host reachable"
        }
    }
}

public struct ShadowClientRemoteAppDescriptor: Identifiable, Equatable, Sendable {
    public let id: Int
    public let title: String
    public let hdrSupported: Bool
    public let isAppCollectorGame: Bool

    public init(id: Int, title: String, hdrSupported: Bool, isAppCollectorGame: Bool) {
        self.id = id
        self.title = title
        self.hdrSupported = hdrSupported
        self.isAppCollectorGame = isAppCollectorGame
    }
}

public enum ShadowClientRemoteHostCatalogState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

public extension ShadowClientRemoteHostCatalogState {
    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .loading:
            return "Loading Hosts"
        case .loaded:
            return "Hosts Ready"
        case let .failed(message):
            return "Failed - \(message)"
        }
    }
}

public enum ShadowClientRemoteAppCatalogState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case failed(String)
}

public extension ShadowClientRemoteAppCatalogState {
    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .loading:
            return "Loading Apps"
        case .loaded:
            return "Apps Ready"
        case let .failed(message):
            return "Failed - \(message)"
        }
    }
}

public protocol ShadowClientPairingPINProviding {
    func nextPIN() -> String
}

public struct ShadowClientRandomPairingPINProvider: ShadowClientPairingPINProviding {
    public init() {}

    public func nextPIN() -> String {
        String(format: "%04d", Int.random(in: 0...9_999))
    }
}

public enum ShadowClientGameStreamError: Error, Equatable, Sendable {
    case invalidHost
    case invalidURL
    case invalidResponse
    case requestFailed(String)
    case malformedXML
    case responseRejected(code: Int, message: String)
}

extension ShadowClientGameStreamError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidHost:
            return "Host is invalid."
        case .invalidURL:
            return "Could not build request URL."
        case .invalidResponse:
            return "Host response is invalid."
        case let .requestFailed(message):
            return message.isEmpty ? "Host request failed." : message
        case .malformedXML:
            return "Host returned malformed XML."
        case let .responseRejected(code, message):
            return message.isEmpty ? "Host rejected request (\(code))." : "Host rejected request (\(code)): \(message)"
        }
    }
}

public struct ShadowClientGameStreamServerInfo: Equatable, Sendable {
    let host: String
    let displayName: String
    let pairStatus: ShadowClientRemoteHostPairStatus
    let currentGameID: Int
    let serverState: String
    let httpsPort: Int
    let appVersion: String?
    let gfeVersion: String?
    let uniqueID: String?
}

public protocol ShadowClientGameStreamMetadataClient: Sendable {
    func fetchServerInfo(host: String) async throws -> ShadowClientGameStreamServerInfo
    func fetchAppList(host: String, httpsPort: Int?) async throws -> [ShadowClientRemoteAppDescriptor]
}

public actor NativeGameStreamMetadataClient: ShadowClientGameStreamMetadataClient {
    private let identityStore: ShadowClientPairingIdentityStore
    private let pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    private let defaultHTTPPort: Int
    private let defaultHTTPSPort: Int

    public init(
        identityStore: ShadowClientPairingIdentityStore = .shared,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared,
        defaultHTTPPort: Int = 47989,
        defaultHTTPSPort: Int = 47984
    ) {
        self.identityStore = identityStore
        self.pinnedCertificateStore = pinnedCertificateStore
        self.defaultHTTPPort = defaultHTTPPort
        self.defaultHTTPSPort = defaultHTTPSPort
    }

    public func fetchServerInfo(host: String) async throws -> ShadowClientGameStreamServerInfo {
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPPort)
        var capturedError: Error?
        let attempts: [(scheme: String, port: Int)] = [
            (scheme: "https", port: defaultHTTPSPort),
            (scheme: "http", port: endpoint.port),
        ]

        var xml: String?
        for attempt in attempts {
            do {
                xml = try await requestXML(
                    host: endpoint.host,
                    port: attempt.port,
                    scheme: attempt.scheme,
                    command: "serverinfo"
                )
                break
            } catch {
                capturedError = error
            }
        }

        guard let xml else {
            if let capturedError = capturedError as? ShadowClientGameStreamError {
                throw capturedError
            }
            throw ShadowClientGameStreamError.requestFailed(
                capturedError?.localizedDescription ?? "Server info request failed."
            )
        }

        return try ShadowClientGameStreamXMLParsers.parseServerInfo(
            xml: xml,
            host: endpoint.host,
            fallbackHTTPSPort: defaultHTTPSPort
        )
    }

    public func fetchAppList(host: String, httpsPort: Int?) async throws -> [ShadowClientRemoteAppDescriptor] {
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPPort)
        let resolvedHTTPSPort = httpsPort ?? defaultHTTPSPort

        var capturedError: Error?
        let attempts: [(scheme: String, port: Int)] = [
            (scheme: "https", port: resolvedHTTPSPort),
            (scheme: "http", port: endpoint.port),
        ]

        for attempt in attempts {
            do {
                let xml = try await requestXML(
                    host: endpoint.host,
                    port: attempt.port,
                    scheme: attempt.scheme,
                    command: "applist"
                )

                return try ShadowClientGameStreamXMLParsers.parseAppList(xml: xml)
            } catch {
                capturedError = error
            }
        }

        if let capturedError = capturedError as? ShadowClientGameStreamError {
            throw capturedError
        }

        throw ShadowClientGameStreamError.requestFailed(
            capturedError?.localizedDescription ?? "App list request failed."
        )
    }

    private func requestXML(
        host: String,
        port: Int,
        scheme: String,
        command: String
    ) async throws -> String {
        let uniqueID = await identityStore.uniqueID()
        let pinnedCertificateDER = await pinnedCertificateStore.certificateDER(forHost: host)
        let clientCertificateCredential: URLCredential?
        if scheme == "https" {
            clientCertificateCredential = try? await identityStore.tlsClientCertificateCredential()
        } else {
            clientCertificateCredential = nil
        }
        return try await ShadowClientGameStreamHTTPTransport.requestXML(
            host: host,
            port: port,
            scheme: scheme,
            command: command,
            parameters: [:],
            uniqueID: uniqueID,
            pinnedServerCertificateDER: pinnedCertificateDER,
            clientCertificateCredential: clientCertificateCredential
        )
    }

    private static func parseHostEndpoint(host: String, fallbackPort: Int) throws -> (host: String, port: Int) {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ShadowClientGameStreamError.invalidHost
        }

        let candidate = normalized.contains("://") ? normalized : "http://\(normalized)"
        guard let url = URL(string: candidate), let parsedHost = url.host else {
            throw ShadowClientGameStreamError.invalidHost
        }

        return (parsedHost, url.port ?? fallbackPort)
    }
}

public final class ShadowClientRemoteDesktopRuntime: ObservableObject {
    @Published public private(set) var hosts: [ShadowClientRemoteHostDescriptor] = []
    @Published public private(set) var apps: [ShadowClientRemoteAppDescriptor] = []
    @Published public private(set) var hostState: ShadowClientRemoteHostCatalogState = .idle
    @Published public private(set) var appState: ShadowClientRemoteAppCatalogState = .idle
    @Published public private(set) var selectedHostID: String?
    @Published public private(set) var pairingState: ShadowClientRemotePairingState = .idle
    @Published public private(set) var launchState: ShadowClientRemoteLaunchState = .idle

    private let metadataClient: any ShadowClientGameStreamMetadataClient
    private let controlClient: any ShadowClientGameStreamControlClient
    private let pinProvider: any ShadowClientPairingPINProviding
    private var refreshHostsTask: Task<Void, Never>?
    private var refreshAppsTask: Task<Void, Never>?
    private var pairTask: Task<Void, Never>?
    private var launchTask: Task<Void, Never>?
    private var latestHostCandidates: [String] = []
    private var appRefreshGeneration: UInt64 = 0

    public init(
        metadataClient: any ShadowClientGameStreamMetadataClient = NativeGameStreamMetadataClient(),
        controlClient: any ShadowClientGameStreamControlClient = NativeGameStreamControlClient(),
        pinProvider: any ShadowClientPairingPINProviding = ShadowClientRandomPairingPINProvider()
    ) {
        self.metadataClient = metadataClient
        self.controlClient = controlClient
        self.pinProvider = pinProvider
    }

    deinit {
        refreshHostsTask?.cancel()
        refreshAppsTask?.cancel()
        pairTask?.cancel()
        launchTask?.cancel()
    }

    @MainActor
    public var selectedHost: ShadowClientRemoteHostDescriptor? {
        guard let selectedHostID else {
            return nil
        }

        return hosts.first { $0.id == selectedHostID }
    }

    @MainActor
    public var activePairingPIN: String? {
        pairingState.activePIN
    }

    @MainActor
    public func refreshHosts(
        candidates: [String],
        preferredHost: String? = nil
    ) {
        let normalizedCandidates = Self.normalizedHostCandidates(candidates)
        latestHostCandidates = normalizedCandidates
        guard !normalizedCandidates.isEmpty else {
            refreshHostsTask?.cancel()
            refreshAppsTask?.cancel()
            hosts = []
            apps = []
            selectedHostID = nil
            hostState = .idle
            appState = .idle
            pairingState = .idle
            launchState = .idle
            return
        }

        hostState = .loading
        refreshHostsTask?.cancel()
        let metadataClient = metadataClient
        refreshHostsTask = Task {
            let descriptors = await withTaskGroup(
                of: ShadowClientRemoteHostDescriptor.self,
                returning: [ShadowClientRemoteHostDescriptor].self
            ) { group in
                for host in normalizedCandidates {
                    group.addTask {
                        await Self.fetchHostDescriptor(host: host, metadataClient: metadataClient)
                    }
                }

                var resolved: [ShadowClientRemoteHostDescriptor] = []
                for await descriptor in group {
                    resolved.append(descriptor)
                }
                return resolved
            }

            let sorted = descriptors.sorted(by: Self.compareHosts)
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                hosts = sorted

                if sorted.isEmpty {
                    hostState = .failed("No hosts resolved.")
                    selectedHostID = nil
                    apps = []
                    appState = .idle
                    return
                }

                hostState = .loaded
                let preferredNormalized = Self.normalizeCandidate(preferredHost)

                if let selectedHostID,
                   sorted.contains(where: { $0.id == selectedHostID })
                {
                    self.selectedHostID = selectedHostID
                } else if let preferredNormalized,
                          let preferred = sorted.first(where: { $0.host.lowercased() == preferredNormalized })
                {
                    selectedHostID = preferred.id
                } else {
                    selectedHostID = sorted.first?.id
                }

                refreshSelectedHostApps()
            }
        }
    }

    @MainActor
    public func pairSelectedHost() {
        guard let selectedHost else {
            pairingState = .failed("Select host first.")
            return
        }

        let generatedPIN = pinProvider.nextPIN()

        pairingState = .pairing(
            host: selectedHost.displayName.isEmpty ? selectedHost.host : selectedHost.displayName,
            pin: generatedPIN
        )
        pairTask?.cancel()
        let controlClient = controlClient
        pairTask = Task {
            do {
                let pairingDeadline = Date().addingTimeInterval(120)
                while true {
                    do {
                        _ = try await controlClient.pair(
                            host: selectedHost.host,
                            pin: generatedPIN,
                            appVersion: selectedHost.appVersion,
                            httpsPort: selectedHost.httpsPort
                        )
                        break
                    } catch {
                        let shouldRetry = Self.shouldRetryPairing(
                            error: error,
                            deadline: pairingDeadline
                        )
                        guard shouldRetry else {
                            throw error
                        }
                        try? await Task.sleep(for: .milliseconds(900))
                    }
                }

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    pairingState = .paired("Paired")
                    let candidates = latestHostCandidates.isEmpty ? hosts.map(\.host) : latestHostCandidates
                    refreshHosts(candidates: candidates, preferredHost: selectedHost.host)
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    pairingState = .failed(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    public func launchSelectedApp(
        appID: Int,
        settings: ShadowClientGameStreamLaunchSettings
    ) {
        guard let selectedHost else {
            launchState = .failed("Select host first.")
            return
        }

        launchState = .launching
        launchTask?.cancel()
        let controlClient = controlClient
        launchTask = Task {
            do {
                let result = try await controlClient.launch(
                    host: selectedHost.host,
                    httpsPort: selectedHost.httpsPort,
                    appID: appID,
                    currentGameID: selectedHost.currentGameID,
                    settings: settings
                )

                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    if let sessionURL = result.sessionURL, !sessionURL.isEmpty {
                        launchState = .launched("Launch sent (\(result.verb)): \(sessionURL)")
                    } else {
                        launchState = .launched("Launch sent (\(result.verb))")
                    }
                }
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    launchState = .failed(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    public func selectHost(_ hostID: String) {
        guard hosts.contains(where: { $0.id == hostID }) else {
            return
        }

        selectedHostID = hostID
        refreshSelectedHostApps()
    }

    @MainActor
    public func refreshSelectedHostApps() {
        appRefreshGeneration &+= 1
        let refreshGeneration = appRefreshGeneration

        guard let selectedHost else {
            refreshAppsTask?.cancel()
            apps = []
            appState = .idle
            return
        }

        guard selectedHost.isReachable else {
            refreshAppsTask?.cancel()
            apps = []
            appState = .failed(selectedHost.lastError ?? "Host unavailable")
            return
        }

        guard selectedHost.pairStatus == .paired else {
            refreshAppsTask?.cancel()
            apps = []
            appState = .failed("Host requires pairing before app list queries.")
            return
        }

        appState = .loading
        refreshAppsTask?.cancel()
        let metadataClient = metadataClient
        let host = selectedHost.host
        let httpsPort = selectedHost.httpsPort
        refreshAppsTask = Task {
            do {
                let resolved = try await metadataClient.fetchAppList(
                    host: host,
                    httpsPort: httpsPort
                )
                let sorted = resolved.sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }

                guard !Task.isCancelled else {
                    await MainActor.run {
                        guard appRefreshGeneration == refreshGeneration, appState == .loading else {
                            return
                        }
                        appState = .idle
                    }
                    return
                }

                await MainActor.run {
                    apps = sorted
                    appState = .loaded
                }
            } catch {
                let message = error.localizedDescription
                guard !Task.isCancelled else {
                    await MainActor.run {
                        guard appRefreshGeneration == refreshGeneration, appState == .loading else {
                            return
                        }
                        appState = .idle
                    }
                    return
                }

                await MainActor.run {
                    apps = []
                    appState = .failed(message)
                }
            }
        }
    }

    private static func fetchHostDescriptor(
        host: String,
        metadataClient: any ShadowClientGameStreamMetadataClient
    ) async -> ShadowClientRemoteHostDescriptor {
        do {
            let info = try await metadataClient.fetchServerInfo(host: host)
            return ShadowClientRemoteHostDescriptor(
                host: info.host,
                displayName: info.displayName,
                pairStatus: info.pairStatus,
                currentGameID: max(0, info.currentGameID),
                serverState: info.serverState,
                httpsPort: info.httpsPort,
                appVersion: info.appVersion,
                gfeVersion: info.gfeVersion,
                uniqueID: info.uniqueID,
                lastError: nil
            )
        } catch {
            let message = error.localizedDescription.isEmpty
                ? "Could not query host serverinfo"
                : error.localizedDescription
            return ShadowClientRemoteHostDescriptor(
                host: host,
                displayName: host,
                pairStatus: .unknown,
                currentGameID: 0,
                serverState: "",
                httpsPort: 47984,
                appVersion: nil,
                gfeVersion: nil,
                uniqueID: nil,
                lastError: message
            )
        }
    }

    private static func shouldRetryPairing(error: Error, deadline: Date) -> Bool {
        guard Date() < deadline else {
            return false
        }

        if let controlError = error as? ShadowClientGameStreamControlError {
            switch controlError {
            case .pairingAlreadyInProgress:
                return true
            case .pinMismatch, .challengeRejected:
                return false
            case .invalidPIN, .invalidKeyMaterial, .mitmDetected, .launchRejected, .malformedResponse:
                return false
            }
        }

        if let streamError = error as? ShadowClientGameStreamError {
            switch streamError {
            case let .requestFailed(message):
                return shouldRetryTransientPairingFailure(message: message)
            case .invalidResponse:
                return true
            case .invalidHost, .invalidURL, .malformedXML, .responseRejected:
                return false
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }

        return false
    }

    private static func shouldRetryTransientPairingFailure(message: String) -> Bool {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return true
        }

        if normalized.contains("certificate required") ||
            normalized.contains("certificate verification failed") ||
            normalized.contains("not authorized")
        {
            return false
        }

        return normalized.contains("timed out") ||
            normalized.contains("timeout") ||
            normalized.contains("network connection was lost") ||
            normalized.contains("could not connect") ||
            normalized.contains("cannot connect")
    }

    private static func normalizedHostCandidates(_ candidates: [String]) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []

        for candidate in candidates {
            let normalized = normalizeCandidate(candidate)
            guard let normalized, !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            results.append(normalized)
        }

        return results.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private static func normalizeCandidate(_ candidate: String?) -> String? {
        guard let candidate else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let urlCandidate = trimmed.contains("://") ? trimmed : "http://\(trimmed)"
        guard let parsed = URL(string: urlCandidate), let host = parsed.host else {
            return trimmed.lowercased()
        }

        if let port = parsed.port {
            return "\(host.lowercased()):\(port)"
        }

        return host.lowercased()
    }

    private static func compareHosts(
        lhs: ShadowClientRemoteHostDescriptor,
        rhs: ShadowClientRemoteHostDescriptor
    ) -> Bool {
        if lhs.isReachable != rhs.isReachable {
            return lhs.isReachable
        }

        if lhs.currentGameID > 0, rhs.currentGameID == 0 {
            return true
        }

        if rhs.currentGameID > 0, lhs.currentGameID == 0 {
            return false
        }

        let displayOrder = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if displayOrder == .orderedSame {
            return lhs.host.localizedCaseInsensitiveCompare(rhs.host) == .orderedAscending
        }

        return displayOrder == .orderedAscending
    }
}

enum ShadowClientGameStreamXMLParsers {
    static func parseServerInfo(
        xml: String,
        host: String,
        fallbackHTTPSPort: Int
    ) throws -> ShadowClientGameStreamServerInfo {
        let document = try ShadowClientXMLFlatDocumentParser.parse(xml: xml)
        try validateRoot(document.rootStatus)

        let displayName = document.values["hostname"]?.first?.nonEmpty ?? host
        let pairStatus = parsePairStatus(document.values["PairStatus"]?.first)
        let currentGameID = Int(document.values["currentgame"]?.first ?? "") ?? 0
        let serverState = document.values["state"]?.first ?? ""
        let httpsPort = Int(document.values["HttpsPort"]?.first ?? "") ?? fallbackHTTPSPort

        return ShadowClientGameStreamServerInfo(
            host: host,
            displayName: displayName,
            pairStatus: pairStatus,
            currentGameID: currentGameID,
            serverState: serverState,
            httpsPort: httpsPort,
            appVersion: document.values["appversion"]?.first,
            gfeVersion: document.values["GfeVersion"]?.first,
            uniqueID: document.values["uniqueid"]?.first
        )
    }

    static func parseAppList(xml: String) throws -> [ShadowClientRemoteAppDescriptor] {
        let document = try ShadowClientXMLAppListParser.parse(xml: xml)
        try validateRoot(document.rootStatus)

        return document.apps.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private static func parsePairStatus(_ rawValue: String?) -> ShadowClientRemoteHostPairStatus {
        switch rawValue {
        case "1":
            return .paired
        case "0":
            return .notPaired
        default:
            return .unknown
        }
    }

    private static func validateRoot(_ root: ShadowClientXMLRootStatus?) throws {
        guard let root else {
            throw ShadowClientGameStreamError.malformedXML
        }

        if root.code == 200 {
            return
        }

        throw ShadowClientGameStreamError.responseRejected(
            code: root.code,
            message: root.message
        )
    }
}

struct ShadowClientXMLRootStatus: Equatable {
    let code: Int
    let message: String
}

struct ShadowClientXMLFlatDocument {
    let rootStatus: ShadowClientXMLRootStatus?
    let values: [String: [String]]
}

enum ShadowClientXMLFlatDocumentParser {
    static func parse(xml: String) throws -> ShadowClientXMLFlatDocument {
        guard let data = xml.data(using: .utf8) else {
            throw ShadowClientGameStreamError.malformedXML
        }

        let delegate = ShadowClientXMLFlatDocumentDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw ShadowClientGameStreamError.malformedXML
        }

        return ShadowClientXMLFlatDocument(
            rootStatus: delegate.rootStatus,
            values: delegate.values
        )
    }
}

final class ShadowClientXMLFlatDocumentDelegate: NSObject, XMLParserDelegate {
    private(set) var rootStatus: ShadowClientXMLRootStatus?
    private(set) var values: [String: [String]] = [:]

    private var currentElement: String?
    private var textBuffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        textBuffer = ""

        if elementName == "root" {
            let code = Int(attributeDict["status_code"] ?? "") ?? -1
            let message = attributeDict["status_message"] ?? ""
            rootStatus = ShadowClientXMLRootStatus(code: code, message: message)
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer {
            currentElement = nil
            textBuffer = ""
        }

        guard let currentElement, currentElement == elementName else {
            return
        }

        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            return
        }

        values[elementName, default: []].append(value)
    }
}

private struct ShadowClientXMLAppListDocument {
    let rootStatus: ShadowClientXMLRootStatus?
    let apps: [ShadowClientRemoteAppDescriptor]
}

private enum ShadowClientXMLAppListParser {
    static func parse(xml: String) throws -> ShadowClientXMLAppListDocument {
        guard let data = xml.data(using: .utf8) else {
            throw ShadowClientGameStreamError.malformedXML
        }

        let delegate = ShadowClientXMLAppListDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            throw ShadowClientGameStreamError.malformedXML
        }

        return ShadowClientXMLAppListDocument(
            rootStatus: delegate.rootStatus,
            apps: delegate.apps
        )
    }
}

private final class ShadowClientXMLAppListDelegate: NSObject, XMLParserDelegate {
    private(set) var rootStatus: ShadowClientXMLRootStatus?
    private(set) var apps: [ShadowClientRemoteAppDescriptor] = []

    private var currentElement: String?
    private var textBuffer = ""

    private var currentID: Int?
    private var currentTitle: String?
    private var currentHDRSupported = false
    private var currentIsCollector = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        textBuffer = ""

        if elementName == "root" {
            let code = Int(attributeDict["status_code"] ?? "") ?? -1
            let message = attributeDict["status_message"] ?? ""
            rootStatus = ShadowClientXMLRootStatus(code: code, message: message)
        } else if elementName == "App" {
            currentID = nil
            currentTitle = nil
            currentHDRSupported = false
            currentIsCollector = false
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        textBuffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer {
            currentElement = nil
            textBuffer = ""
        }

        guard let currentElement, currentElement == elementName else {
            return
        }

        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)

        switch elementName {
        case "AppTitle":
            currentTitle = value.nonEmpty
        case "ID":
            if let parsed = Int(value) {
                currentID = parsed
            }
        case "IsHdrSupported":
            currentHDRSupported = value == "1"
        case "IsAppCollectorGame":
            currentIsCollector = value == "1"
        case "App":
            if let id = currentID,
               let title = currentTitle,
               !title.isEmpty
            {
                apps.append(
                    ShadowClientRemoteAppDescriptor(
                        id: id,
                        title: title,
                        hdrSupported: currentHDRSupported,
                        isAppCollectorGame: currentIsCollector
                    )
                )
            }
        default:
            break
        }
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
