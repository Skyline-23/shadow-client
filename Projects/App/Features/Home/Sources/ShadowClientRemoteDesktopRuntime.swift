import Combine
import Foundation
import Network
import os

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

public struct ShadowClientActiveRemoteSession: Equatable, Sendable, Identifiable {
    public let id: String
    public let host: String
    public let appID: Int
    public let appTitle: String
    public let sessionURL: String?
    public let launchedAt: Date

    public init(
        host: String,
        appID: Int,
        appTitle: String,
        sessionURL: String?,
        launchedAt: Date = Date()
    ) {
        self.host = host
        self.appID = appID
        self.appTitle = appTitle
        self.sessionURL = sessionURL
        self.launchedAt = launchedAt
        let launchedAtMs = Int(launchedAt.timeIntervalSince1970 * 1_000)
        self.id = "\(host.lowercased())-\(appID)-\(launchedAtMs)"
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

public protocol ShadowClientRemoteSessionConnectionClient: Sendable {
    var presentationMode: ShadowClientRemoteSessionPresentationMode { get }
    var sessionSurfaceContext: ShadowClientRealtimeSessionSurfaceContext { get }
    func connect(
        to sessionURL: String,
        host: String,
        appTitle: String,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration
    ) async throws
    func disconnect() async
}

public struct ShadowClientRemoteSessionVideoConfiguration: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let fps: Int
    public let bitrateKbps: Int
    public let preferredCodec: ShadowClientVideoCodecPreference
    public let enableHDR: Bool
    public let enableSurroundAudio: Bool
    public let enableYUV444: Bool
    public let remoteInputKey: Data?
    public let remoteInputKeyID: UInt32?

    public init(
        width: Int,
        height: Int,
        fps: Int = ShadowClientStreamingLaunchBounds.defaultFPS,
        bitrateKbps: Int = ShadowClientRTSPAnnounceDefaults.configuredBitrateKbps,
        preferredCodec: ShadowClientVideoCodecPreference = .auto,
        enableHDR: Bool = false,
        enableSurroundAudio: Bool = false,
        enableYUV444: Bool = false,
        remoteInputKey: Data? = nil,
        remoteInputKeyID: UInt32? = nil
    ) {
        self.width = max(ShadowClientStreamingLaunchBounds.minimumWidth, width)
        self.height = max(ShadowClientStreamingLaunchBounds.minimumHeight, height)
        self.fps = max(ShadowClientStreamingLaunchBounds.minimumFPS, fps)
        self.bitrateKbps = min(
            max(ShadowClientStreamingLaunchBounds.minimumBitrateKbps, bitrateKbps),
            ShadowClientStreamingLaunchBounds.maximumBitrateKbps
        )
        self.preferredCodec = preferredCodec
        self.enableHDR = enableHDR
        self.enableSurroundAudio = enableSurroundAudio
        self.enableYUV444 = enableYUV444
        self.remoteInputKey = remoteInputKey
        self.remoteInputKeyID = remoteInputKeyID
    }
}

public enum ShadowClientRemoteSessionPresentationMode: Equatable, Sendable {
    case embeddedPlayer
    case externalRuntime
}

public enum ShadowClientRemoteMouseButton: Equatable, Sendable {
    case left
    case right
    case middle
    case other(Int)
}

public struct ShadowClientRemoteGamepadState: Equatable, Sendable {
    public let controllerNumber: UInt8
    public let activeGamepadMask: UInt16
    public let buttonFlags: UInt32
    public let leftTrigger: UInt8
    public let rightTrigger: UInt8
    public let leftStickX: Int16
    public let leftStickY: Int16
    public let rightStickX: Int16
    public let rightStickY: Int16

    public init(
        controllerNumber: UInt8,
        activeGamepadMask: UInt16,
        buttonFlags: UInt32,
        leftTrigger: UInt8,
        rightTrigger: UInt8,
        leftStickX: Int16,
        leftStickY: Int16,
        rightStickX: Int16,
        rightStickY: Int16
    ) {
        self.controllerNumber = controllerNumber
        self.activeGamepadMask = activeGamepadMask
        self.buttonFlags = buttonFlags
        self.leftTrigger = leftTrigger
        self.rightTrigger = rightTrigger
        self.leftStickX = leftStickX
        self.leftStickY = leftStickY
        self.rightStickX = rightStickX
        self.rightStickY = rightStickY
    }
}

public struct ShadowClientRemoteGamepadArrival: Equatable, Sendable {
    public let controllerNumber: UInt8
    public let activeGamepadMask: UInt16
    public let type: UInt8
    public let capabilities: UInt16
    public let supportedButtonFlags: UInt32

    public init(
        controllerNumber: UInt8,
        activeGamepadMask: UInt16,
        type: UInt8,
        capabilities: UInt16,
        supportedButtonFlags: UInt32
    ) {
        self.controllerNumber = controllerNumber
        self.activeGamepadMask = activeGamepadMask
        self.type = type
        self.capabilities = capabilities
        self.supportedButtonFlags = supportedButtonFlags
    }
}

public enum ShadowClientRemoteInputEvent: Equatable, Sendable {
    case keyDown(keyCode: UInt16, characters: String?)
    case keyUp(keyCode: UInt16, characters: String?)
    case pointerMoved(x: Double, y: Double)
    case pointerButton(button: ShadowClientRemoteMouseButton, isPressed: Bool)
    case scroll(deltaX: Double, deltaY: Double)
    case gamepadState(ShadowClientRemoteGamepadState)
    case gamepadArrival(ShadowClientRemoteGamepadArrival)
}

public protocol ShadowClientRemoteSessionInputClient: Sendable {
    func send(event: ShadowClientRemoteInputEvent, host: String, sessionURL: String) async throws
}

public struct NoopShadowClientRemoteSessionInputClient: ShadowClientRemoteSessionInputClient {
    public init() {}

    public func send(event: ShadowClientRemoteInputEvent, host: String, sessionURL: String) async throws {}
}

public struct NativeShadowClientRemoteSessionInputClient: ShadowClientRemoteSessionInputClient {
    private let sessionRuntime: ShadowClientRealtimeRTSPSessionRuntime

    public init(
        sessionRuntime: ShadowClientRealtimeRTSPSessionRuntime = .init()
    ) {
        self.sessionRuntime = sessionRuntime
    }

    public func send(
        event: ShadowClientRemoteInputEvent,
        host _: String,
        sessionURL _: String
    ) async throws {
        try await sessionRuntime.sendInput(event)
    }
}

public struct NoopShadowClientRemoteSessionConnectionClient: ShadowClientRemoteSessionConnectionClient {
    public let presentationMode: ShadowClientRemoteSessionPresentationMode = .embeddedPlayer
    public let sessionSurfaceContext: ShadowClientRealtimeSessionSurfaceContext = .init()

    public init() {}

    public func connect(
        to sessionURL: String,
        host: String,
        appTitle: String,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration
    ) async throws {}

    public func disconnect() async {}
}

public struct NativeShadowClientRemoteSessionConnectionClient: ShadowClientRemoteSessionConnectionClient {
    public let presentationMode: ShadowClientRemoteSessionPresentationMode = .embeddedPlayer
    public let sessionSurfaceContext: ShadowClientRealtimeSessionSurfaceContext

    private let sessionRuntime: ShadowClientRealtimeRTSPSessionRuntime

    public init(
        timeout: Duration = ShadowClientGameStreamNetworkDefaults.defaultSessionConnectTimeout,
        sessionRuntime: ShadowClientRealtimeRTSPSessionRuntime = .init()
    ) {
        _ = timeout
        self.sessionRuntime = sessionRuntime
        self.sessionSurfaceContext = sessionRuntime.surfaceContext
    }

    public func connect(
        to sessionURL: String,
        host: String,
        appTitle: String,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration
    ) async throws {
        try await sessionRuntime.connect(
            sessionURL: sessionURL,
            host: host,
            appTitle: appTitle,
            videoConfiguration: videoConfiguration
        )
    }

    public func disconnect() async {
        try? await sessionRuntime.disconnect()
    }
}

public protocol ShadowClientGameStreamRequestTransporting: Sendable {
    func requestXML(
        host: String,
        port: Int,
        scheme: String,
        command: String,
        parameters: [String: String],
        uniqueID: String,
        pinnedServerCertificateDER: Data?,
        clientCertificateCredential: URLCredential?
    ) async throws -> String
}

public struct NativeShadowClientGameStreamRequestTransport: ShadowClientGameStreamRequestTransporting {
    public init() {}

    public func requestXML(
        host: String,
        port: Int,
        scheme: String,
        command: String,
        parameters: [String: String],
        uniqueID: String,
        pinnedServerCertificateDER: Data?,
        clientCertificateCredential: URLCredential?
    ) async throws -> String {
        try await ShadowClientGameStreamHTTPTransport.requestXML(
            host: host,
            port: port,
            scheme: scheme,
            command: command,
            parameters: parameters,
            uniqueID: uniqueID,
            pinnedServerCertificateDER: pinnedServerCertificateDER,
            clientCertificateCredential: clientCertificateCredential
        )
    }
}

public actor NativeGameStreamMetadataClient: ShadowClientGameStreamMetadataClient {
    private let identityStore: ShadowClientPairingIdentityStore
    private let pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    private let transport: any ShadowClientGameStreamRequestTransporting
    private let defaultHTTPPort: Int
    private let defaultHTTPSPort: Int

    public init(
        identityStore: ShadowClientPairingIdentityStore = .shared,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared,
        transport: any ShadowClientGameStreamRequestTransporting = NativeShadowClientGameStreamRequestTransport(),
        defaultHTTPPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPPort,
        defaultHTTPSPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
    ) {
        self.identityStore = identityStore
        self.pinnedCertificateStore = pinnedCertificateStore
        self.transport = transport
        self.defaultHTTPPort = defaultHTTPPort
        self.defaultHTTPSPort = defaultHTTPSPort
    }

    public func fetchServerInfo(host: String) async throws -> ShadowClientGameStreamServerInfo {
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPPort)
        do {
            let httpsXML = try await requestXML(
                host: endpoint.host,
                port: defaultHTTPSPort,
                scheme: ShadowClientGameStreamNetworkDefaults.httpsScheme,
                command: "serverinfo"
            )

            return try ShadowClientGameStreamXMLParsers.parseServerInfo(
                xml: httpsXML,
                host: endpoint.host,
                fallbackHTTPSPort: defaultHTTPSPort
            )
        } catch let httpsError as ShadowClientGameStreamError {
            if Self.isUnauthorizedCertificateError(httpsError) {
                do {
                    let httpXML = try await requestXML(
                        host: endpoint.host,
                        port: endpoint.port,
                        scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
                        command: "serverinfo"
                    )

                    return try ShadowClientGameStreamXMLParsers.parseServerInfo(
                        xml: httpXML,
                        host: endpoint.host,
                        fallbackHTTPSPort: defaultHTTPSPort
                    )
                } catch let httpError as ShadowClientGameStreamError {
                    if Self.isAppTransportSecurityBlockedError(httpError) {
                        return Self.makeUnauthorizedServerInfo(
                            host: endpoint.host,
                            fallbackHTTPSPort: defaultHTTPSPort
                        )
                    }
                } catch {}

                // HTTPS 401 already proves host reachability; keep host selectable for pairing.
                return Self.makeUnauthorizedServerInfo(
                    host: endpoint.host,
                    fallbackHTTPSPort: defaultHTTPSPort
                )
            }
            do {
                let httpXML = try await requestXML(
                    host: endpoint.host,
                    port: endpoint.port,
                    scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
                    command: "serverinfo"
                )
                return try ShadowClientGameStreamXMLParsers.parseServerInfo(
                    xml: httpXML,
                    host: endpoint.host,
                    fallbackHTTPSPort: defaultHTTPSPort
                )
            } catch let httpError as ShadowClientGameStreamError {
                if Self.isAppTransportSecurityBlockedError(httpError) {
                    throw httpsError
                }
                throw httpError
            }
        }
    }

    public func fetchAppList(host: String, httpsPort: Int?) async throws -> [ShadowClientRemoteAppDescriptor] {
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPPort)
        let resolvedHTTPSPort = httpsPort ?? defaultHTTPSPort

        let httpsXML = try await requestXML(
            host: endpoint.host,
            port: resolvedHTTPSPort,
            scheme: ShadowClientGameStreamNetworkDefaults.httpsScheme,
            command: "applist"
        )

        return try ShadowClientGameStreamXMLParsers.parseAppList(xml: httpsXML)
    }

    private static func isUnauthorizedCertificateError(_ error: ShadowClientGameStreamError) -> Bool {
        guard case let .responseRejected(code, message) = error, code == 401 else {
            return false
        }

        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("not authorized") ||
            normalized.contains("certificate verification failed")
    }

    private static func isAppTransportSecurityBlockedError(_ error: ShadowClientGameStreamError) -> Bool {
        guard case let .requestFailed(message) = error else {
            return false
        }
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("app transport security") ||
            normalized.contains("insecure http is blocked")
    }

    private static func makeUnauthorizedServerInfo(
        host: String,
        fallbackHTTPSPort: Int
    ) -> ShadowClientGameStreamServerInfo {
        ShadowClientGameStreamServerInfo(
            host: host,
            displayName: host,
            pairStatus: .notPaired,
            currentGameID: 0,
            serverState: ShadowClientGameStreamServerState.free,
            httpsPort: fallbackHTTPSPort,
            appVersion: nil,
            gfeVersion: nil,
            uniqueID: nil
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
        if scheme == ShadowClientGameStreamNetworkDefaults.httpsScheme {
            clientCertificateCredential = try? await identityStore.tlsClientCertificateCredential()
        } else {
            clientCertificateCredential = nil
        }
        return try await transport.requestXML(
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

        let candidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(normalized)
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
    @Published public private(set) var activeSession: ShadowClientActiveRemoteSession?
    public let sessionPresentationMode: ShadowClientRemoteSessionPresentationMode
    public let sessionSurfaceContext: ShadowClientRealtimeSessionSurfaceContext

    private let metadataClient: any ShadowClientGameStreamMetadataClient
    private let controlClient: any ShadowClientGameStreamControlClient
    private let sessionConnectionClient: any ShadowClientRemoteSessionConnectionClient
    private let sessionInputClient: any ShadowClientRemoteSessionInputClient
    private let pinProvider: any ShadowClientPairingPINProviding
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "RemoteDesktopRuntime")
    private var refreshHostsTask: Task<Void, Never>?
    private var refreshAppsTask: Task<Void, Never>?
    private var pairTask: Task<Void, Never>?
    private var launchTask: Task<Void, Never>?
    private var latestHostCandidates: [String] = []
    private var cachedAppsByHostID: [String: [ShadowClientRemoteAppDescriptor]] = [:]
    private var appRefreshGeneration: UInt64 = 0
    private var pairGeneration: UInt64 = 0
    private var launchGeneration: UInt64 = 0
    private var pendingSelectedHostID: String?
    private var lastKnownSessionURL: String?

    public init(
        metadataClient: any ShadowClientGameStreamMetadataClient = NativeGameStreamMetadataClient(),
        controlClient: any ShadowClientGameStreamControlClient = NativeGameStreamControlClient(),
        sessionConnectionClient: any ShadowClientRemoteSessionConnectionClient = NoopShadowClientRemoteSessionConnectionClient(),
        sessionInputClient: any ShadowClientRemoteSessionInputClient = NoopShadowClientRemoteSessionInputClient(),
        pinProvider: any ShadowClientPairingPINProviding = ShadowClientRandomPairingPINProvider()
    ) {
        self.metadataClient = metadataClient
        self.controlClient = controlClient
        self.sessionConnectionClient = sessionConnectionClient
        self.sessionInputClient = sessionInputClient
        self.pinProvider = pinProvider
        self.sessionPresentationMode = sessionConnectionClient.presentationMode
        self.sessionSurfaceContext = sessionConnectionClient.sessionSurfaceContext
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
            cachedAppsByHostID = [:]
            selectedHostID = nil
            pendingSelectedHostID = nil
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

                if let pendingSelectedHostID,
                   sorted.contains(where: { $0.id == pendingSelectedHostID })
                {
                    self.selectedHostID = pendingSelectedHostID
                    self.pendingSelectedHostID = nil
                } else {
                    self.pendingSelectedHostID = nil
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
        pairGeneration &+= 1
        let currentPairGeneration = pairGeneration
        let controlClient = controlClient
        pairTask = Task {
            do {
                let pairingDeadline = Date().addingTimeInterval(
                    ShadowClientPairingDefaults.retryDeadlineSeconds
                )
                let maximumPairAttempts = ShadowClientPairingDefaults.maximumAttempts
                var pairAttemptCount = 0
                while true {
                    pairAttemptCount += 1
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
                        ) && pairAttemptCount < maximumPairAttempts
                        guard shouldRetry else {
                            throw error
                        }
                        try await Task.sleep(for: ShadowClientPairingDefaults.retryBackoff)
                    }
                }

                if Task.isCancelled {
                    await MainActor.run {
                        guard self.pairGeneration == currentPairGeneration,
                              case .pairing = pairingState
                        else {
                            return
                        }
                        pairingState = .idle
                    }
                    return
                }

                await MainActor.run {
                    guard self.pairGeneration == currentPairGeneration else {
                        return
                    }
                    pairingState = .paired("Paired")
                    let candidates = latestHostCandidates.isEmpty ? hosts.map(\.host) : latestHostCandidates
                    refreshHosts(candidates: candidates, preferredHost: selectedHost.host)
                }
            } catch {
                if Task.isCancelled {
                    await MainActor.run {
                        guard self.pairGeneration == currentPairGeneration,
                              case .pairing = pairingState
                        else {
                            return
                        }
                        pairingState = .idle
                    }
                    return
                }

                await MainActor.run {
                    guard self.pairGeneration == currentPairGeneration else {
                        return
                    }
                    pairingState = .failed(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    public func launchSelectedApp(
        appID: Int,
        appTitle: String? = nil,
        settings: ShadowClientGameStreamLaunchSettings
    ) {
        guard let selectedHost else {
            launchState = .failed("Select host first.")
            return
        }

        launchState = .launching
        activeSession = nil
        lastKnownSessionURL = nil
        launchTask?.cancel()
        launchGeneration &+= 1
        let currentLaunchGeneration = launchGeneration
        let controlClient = controlClient
        let sessionConnectionClient = sessionConnectionClient
        let launchedAppTitle = appTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        launchTask = Task {
            do {
                await sessionConnectionClient.disconnect()

                let initialLaunchResult = try await controlClient.launch(
                    host: selectedHost.host,
                    httpsPort: selectedHost.httpsPort,
                    appID: appID,
                    currentGameID: selectedHost.currentGameID,
                    forceLaunch: false,
                    settings: settings
                )

                let resolvedTitle: String
                if let launchedAppTitle, !launchedAppTitle.isEmpty {
                    resolvedTitle = launchedAppTitle
                } else {
                    resolvedTitle = "App \(appID)"
                }

                var connectedLaunchResult = initialLaunchResult
                var connectedSessionURL = try Self.validatedSessionURL(from: initialLaunchResult)

                do {
                    try await Self.connectWithCodecFallback(
                        sessionConnectionClient: sessionConnectionClient,
                        sessionURL: connectedSessionURL,
                        host: selectedHost.host,
                        appTitle: resolvedTitle,
                        settings: settings,
                        remoteInputKey: initialLaunchResult.remoteInputKey,
                        remoteInputKeyID: initialLaunchResult.remoteInputKeyID
                    )
                } catch {
                    guard Self.shouldRetryForcedLaunch(
                        launchVerb: initialLaunchResult.verb,
                        connectError: error
                    ) else {
                        throw error
                    }

                    await sessionConnectionClient.disconnect()

                    let forcedLaunchSettings = Self.forcedLaunchSettings(
                        from: settings,
                        connectError: error
                    )
                    let forcedLaunchResult = try await controlClient.launch(
                        host: selectedHost.host,
                        httpsPort: selectedHost.httpsPort,
                        appID: appID,
                        currentGameID: selectedHost.currentGameID,
                        forceLaunch: true,
                        settings: forcedLaunchSettings
                    )
                    let forcedSessionURL = try Self.validatedSessionURL(from: forcedLaunchResult)

                    try await Self.connectWithCodecFallback(
                        sessionConnectionClient: sessionConnectionClient,
                        sessionURL: forcedSessionURL,
                        host: selectedHost.host,
                        appTitle: resolvedTitle,
                        settings: forcedLaunchSettings,
                        remoteInputKey: forcedLaunchResult.remoteInputKey,
                        remoteInputKeyID: forcedLaunchResult.remoteInputKeyID
                    )

                    connectedLaunchResult = forcedLaunchResult
                    connectedSessionURL = forcedSessionURL
                }

                if Task.isCancelled {
                    await MainActor.run {
                        guard self.launchGeneration == currentLaunchGeneration,
                              launchState == .launching
                        else {
                            return
                        }
                        launchState = .idle
                        activeSession = nil
                        lastKnownSessionURL = nil
                    }
                    return
                }

                await MainActor.run {
                    guard self.launchGeneration == currentLaunchGeneration else {
                        return
                    }

                    activeSession = ShadowClientActiveRemoteSession(
                        host: selectedHost.host,
                        appID: appID,
                        appTitle: resolvedTitle,
                        sessionURL: connectedSessionURL
                    )
                    lastKnownSessionURL = Self.normalizedSessionURL(connectedSessionURL)
                    if sessionPresentationMode == .externalRuntime {
                        launchState = .launched(
                            "Remote desktop launched (\(connectedLaunchResult.verb)): \(resolvedTitle) on \(selectedHost.host)"
                        )
                    } else {
                        launchState = .launched("Remote session transport connected (\(connectedLaunchResult.verb)): \(connectedSessionURL)")
                    }
                }
            } catch {
                if Task.isCancelled {
                    await MainActor.run {
                        guard self.launchGeneration == currentLaunchGeneration,
                              launchState == .launching
                        else {
                            return
                        }
                        launchState = .idle
                        activeSession = nil
                        lastKnownSessionURL = nil
                    }
                    return
                }

                await MainActor.run {
                    guard self.launchGeneration == currentLaunchGeneration else {
                        return
                    }
                    launchState = .failed(
                        Self.userFacingLaunchFailureMessage(
                            error,
                            settings: settings
                        )
                    )
                    activeSession = nil
                    lastKnownSessionURL = nil
                }
            }
        }
    }

    @MainActor
    public func clearActiveSession() {
        launchTask?.cancel()
        launchTask = nil
        launchGeneration &+= 1

        activeSession = nil
        lastKnownSessionURL = nil
        launchState = .idle

        let sessionConnectionClient = sessionConnectionClient
        Task {
            await sessionConnectionClient.disconnect()
        }
    }

    @MainActor
    public func sendInput(_ event: ShadowClientRemoteInputEvent) {
        guard let activeSession else {
            return
        }

        let resolvedSessionURL = Self.normalizedSessionURL(activeSession.sessionURL)
            ?? lastKnownSessionURL
            ?? Self.normalizedSessionURL(
                ShadowClientRTSPProtocolProfile.withRTSPSchemeIfMissing(activeSession.host)
            )
        guard let sessionURL = resolvedSessionURL else {
            return
        }

        lastKnownSessionURL = sessionURL
        let host = activeSession.host
        let sessionInputClient = sessionInputClient
        Task {
            do {
                try await sessionInputClient.send(
                    event: event,
                    host: host,
                    sessionURL: sessionURL
                )
            } catch {
                if Self.shouldSuppressInputSendError(error) {
                    return
                }
                logger.debug("Remote input send failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func normalizedSessionURL(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private static func shouldSuppressInputSendError(_ error: Error) -> Bool {
        if let networkError = error as? NWError {
            if case let .posix(code) = networkError {
                switch code {
                case .ECANCELED, .ENOTCONN, .ECONNRESET, .EPIPE:
                    return true
                default:
                    break
                }
            }
        }

        if let controlError = error as? ShadowClientSunshineControlChannelError {
            switch controlError {
            case .connectionClosed, .connectionTimedOut:
                return true
            case .handshakeTimedOut,
                 .verifyConnectNotReceived,
                 .commandAcknowledgeTimedOut,
                 .invalidEncryptedControlKey,
                 .encryptedControlEncodingFailed:
                return false
            }
        }

        let normalized = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.contains("operation canceled") ||
            normalized.contains("connection closed")
        {
            return true
        }

        return false
    }

    private static func validatedSessionURL(
        from launchResult: ShadowClientGameStreamLaunchResult
    ) throws -> String {
        guard let sessionURL = launchResult.sessionURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionURL.isEmpty
        else {
            throw ShadowClientGameStreamError.requestFailed(
                "Host did not return a remote session URL."
            )
        }
        return sessionURL
    }

    private static func shouldRetryForcedLaunch(
        launchVerb: String,
        connectError: any Error
    ) -> Bool {
        if shouldRetryCodecFallback(connectError: connectError) {
            return true
        }

        guard launchVerb.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "resume" else {
            return false
        }

        let normalized = connectError.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return false
        }

        let retrySignatures = [
            "rtsp",
            "video timeout",
            "no video datagram",
            "no message available on stream",
            "transport connection timed out",
            "video session endpoint",
            "rtsp transport connection closed",
            "first frame",
            "could not create hardware decoder session",
            "cannot create decoder",
            "hardware decode failed",
            "decoder codec is not supported",
            "av1 codec configuration record",
            "av1c",
            "osstatus -8971",
        ]

        return retrySignatures.contains(where: normalized.contains)
    }

    private static func connectWithCodecFallback(
        sessionConnectionClient: any ShadowClientRemoteSessionConnectionClient,
        sessionURL: String,
        host: String,
        appTitle: String,
        settings: ShadowClientGameStreamLaunchSettings,
        remoteInputKey: Data?,
        remoteInputKeyID: UInt32?
    ) async throws {
        let codecCandidates = codecFallbackCandidates(for: settings.preferredCodec)
        var firstCodecFallbackError: (any Error)?

        for (index, codecCandidate) in codecCandidates.enumerated() {
            do {
                try await sessionConnectionClient.connect(
                    to: sessionURL,
                    host: host,
                    appTitle: appTitle,
                    videoConfiguration: sessionVideoConfiguration(
                        from: settings,
                        preferredCodec: codecCandidate,
                        remoteInputKey: remoteInputKey,
                        remoteInputKeyID: remoteInputKeyID
                    )
                )
                return
            } catch {
                let hasNextCandidate = index + 1 < codecCandidates.count
                let isCodecFallbackError = shouldRetryCodecFallback(connectError: error)

                if isCodecFallbackError, firstCodecFallbackError == nil {
                    firstCodecFallbackError = error
                }

                if hasNextCandidate, isCodecFallbackError {
                    await sessionConnectionClient.disconnect()
                    continue
                }

                if let firstCodecFallbackError, !isCodecFallbackError {
                    // Preserve the root decoder incompatibility signal instead of
                    // masking it with follow-up transport resets from the same session.
                    throw firstCodecFallbackError
                }

                guard hasNextCandidate, isCodecFallbackError else {
                    throw error
                }
                await sessionConnectionClient.disconnect()
            }
        }

        if let firstCodecFallbackError {
            throw firstCodecFallbackError
        }

        throw ShadowClientGameStreamError.requestFailed("Could not connect to remote session.")
    }

    private static func forcedLaunchSettings(
        from settings: ShadowClientGameStreamLaunchSettings,
        connectError: any Error
    ) -> ShadowClientGameStreamLaunchSettings {
        guard shouldDowngradeCodecForRecovery(
            settings: settings,
            connectError: connectError
        ),
              let downgradedCodec = codecFallbackCandidates(for: settings.preferredCodec).dropFirst().first
        else {
            return settings
        }

        return launchSettings(settings, preferredCodec: downgradedCodec)
    }

    private static func shouldDowngradeCodecForRecovery(
        settings: ShadowClientGameStreamLaunchSettings,
        connectError: any Error
    ) -> Bool {
        if shouldRetryCodecFallback(connectError: connectError) {
            return true
        }

        let isAV1Requested = settings.preferredCodec == .av1 || settings.preferredCodec == .auto
        guard isAV1Requested else {
            return false
        }

        let normalized = connectError.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return false
        }

        let av1StartupFailureSignatures = [
            "timed out waiting for first frame",
            "rtsp udp video timeout",
            "no video datagram",
            "connection reset by peer",
            "rtsp transport connection closed",
        ]

        return av1StartupFailureSignatures.contains(where: normalized.contains)
    }

    private static func shouldRetryCodecFallback(connectError: any Error) -> Bool {
        let normalized = connectError.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return false
        }

        let codecFallbackSignatures = [
            "could not create hardware decoder session",
            "cannot create decoder",
            "hardware decode failed",
            "decoder codec is not supported",
            "av1 codec configuration record",
            "av1c",
            "av1 decode failed",
            "runtime recovery exhausted",
            "hevc fallback",
            "osstatus -8971",
            "vtvideo decoderselection",
            "vt-ds",
        ]

        return codecFallbackSignatures.contains(where: normalized.contains)
    }

    private static func userFacingLaunchFailureMessage(
        _ error: any Error,
        settings: ShadowClientGameStreamLaunchSettings
    ) -> String {
        let base = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = base.lowercased()
        var hints: [String] = []

        if shouldRetryCodecFallback(connectError: error),
           settings.preferredCodec == .av1 || settings.preferredCodec == .auto || normalized.contains("av1")
        {
            hints.append(
                "AV1 decode setup failed (VideoToolbox/av1C configuration). Apple Silicon can support AV1, but some stream profiles are unsupported (for example missing codec config, HDR 10-bit, or 4:4:4). Try HEVC/H.264 or disable HDR/YUV444."
            )
        } else if (settings.preferredCodec == .av1 || settings.preferredCodec == .auto),
                  isLikelyAV1StartupFailure(normalizedError: normalized)
        {
            hints.append(
                "AV1 stream startup failed before first frame decode. This often means the negotiated AV1 profile is unsupported on this device/OS build. Try HEVC/H.264 or disable HDR/YUV444."
            )
        }

        if settings.enableYUV444,
           isLikelyYUV444CompatibilityFailure(normalizedError: normalized)
        {
            hints.append(
                "YUV 4:4:4 appears unsupported on the host encoder. Disable \"Enable YUV 4:4:4 (Experimental)\" and retry."
            )
        }

        guard !hints.isEmpty else {
            return base
        }

        let resolvedBase = base.isEmpty ? "Remote session launch failed." : base
        return ([resolvedBase] + hints).joined(separator: "\n")
    }

    private static func isLikelyYUV444CompatibilityFailure(normalizedError: String) -> Bool {
        let directSignatures = [
            "yuv444",
            "yuv 4:4:4",
            "chroma sampling type",
            "gpu doesn't support yuv444 encode",
        ]
        if directSignatures.contains(where: normalizedError.contains) {
            return true
        }

        let indirectTransportSignatures = [
            "rtsp udp video timeout",
            "no video datagram",
            "video session endpoint",
            "rtsp setup failed",
            "rtsp transport connection closed",
            "first frame",
            "transport connection timed out",
        ]
        return indirectTransportSignatures.contains(where: normalizedError.contains)
    }

    private static func isLikelyAV1StartupFailure(normalizedError: String) -> Bool {
        let signatures = [
            "timed out waiting for first frame",
            "rtsp udp video timeout",
            "no video datagram",
            "connection reset by peer",
            "rtsp transport connection closed",
        ]
        return signatures.contains(where: normalizedError.contains)
    }

    private static func codecFallbackCandidates(
        for preferredCodec: ShadowClientVideoCodecPreference
    ) -> [ShadowClientVideoCodecPreference] {
        switch preferredCodec {
        case .auto, .av1:
            return [preferredCodec, .h265, .h264]
        case .h265:
            return [.h265, .h264]
        case .h264:
            return [.h264]
        }
    }

    private static func launchSettings(
        _ settings: ShadowClientGameStreamLaunchSettings,
        preferredCodec: ShadowClientVideoCodecPreference
    ) -> ShadowClientGameStreamLaunchSettings {
        return .init(
            width: settings.width,
            height: settings.height,
            fps: settings.fps,
            bitrateKbps: settings.bitrateKbps,
            preferredCodec: preferredCodec,
            enableHDR: settings.enableHDR,
            enableSurroundAudio: settings.enableSurroundAudio,
            lowLatencyMode: settings.lowLatencyMode,
            enableVSync: settings.enableVSync,
            enableFramePacing: settings.enableFramePacing,
            enableYUV444: settings.enableYUV444,
            unlockBitrateLimit: settings.unlockBitrateLimit,
            forceHardwareDecoding: settings.forceHardwareDecoding,
            optimizeGameSettingsForStreaming: settings.optimizeGameSettingsForStreaming,
            quitAppOnHostAfterStreamEnds: settings.quitAppOnHostAfterStreamEnds
        )
    }

    private static func sessionVideoConfiguration(
        from settings: ShadowClientGameStreamLaunchSettings,
        preferredCodec: ShadowClientVideoCodecPreference,
        remoteInputKey: Data?,
        remoteInputKeyID: UInt32?
    ) -> ShadowClientRemoteSessionVideoConfiguration {
        return .init(
            width: settings.width,
            height: settings.height,
            fps: settings.fps,
            bitrateKbps: settings.bitrateKbps,
            preferredCodec: preferredCodec,
            enableHDR: settings.enableHDR,
            enableSurroundAudio: settings.enableSurroundAudio,
            enableYUV444: settings.enableYUV444,
            remoteInputKey: remoteInputKey,
            remoteInputKeyID: remoteInputKeyID
        )
    }

    @MainActor
    public func openSessionFlow(host: String, appTitle: String = "Remote Desktop") {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            return
        }

        let sessionURL = Self.normalizedSessionURL(
            ShadowClientRTSPProtocolProfile.withRTSPSchemeIfMissing(normalizedHost)
        )

        activeSession = ShadowClientActiveRemoteSession(
            host: normalizedHost,
            appID: 0,
            appTitle: appTitle,
            sessionURL: sessionURL
        )
        lastKnownSessionURL = sessionURL
    }

    @MainActor
    public func selectHost(_ hostID: String) {
        pendingSelectedHostID = hostID
        guard hosts.contains(where: { $0.id == hostID }) else {
            return
        }

        pendingSelectedHostID = nil
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
        let hostDescriptor = selectedHost
        let host = hostDescriptor.host
        let httpsPort = hostDescriptor.httpsPort
        let cachedAppsForHost = cachedAppsByHostID[hostDescriptor.id] ?? []
        refreshAppsTask = Task {
            do {
                let resolved = try await metadataClient.fetchAppList(
                    host: host,
                    httpsPort: httpsPort
                )
                let sorted = resolved.sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                let resolvedApps: [ShadowClientRemoteAppDescriptor]
                if sorted.isEmpty {
                    resolvedApps = Self.synthesizedFallbackApps(
                        for: hostDescriptor,
                        cachedApps: cachedAppsForHost
                    )
                } else {
                    resolvedApps = sorted
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
                    if !sorted.isEmpty {
                        cachedAppsByHostID[hostDescriptor.id] = sorted
                    }
                    apps = resolvedApps
                    appState = resolvedApps.isEmpty
                        ? .failed("No app metadata loaded yet. Pairing may be required before app list queries.")
                        : .loaded
                }
            } catch {
                let message = error.localizedDescription
                let fallbackApps = Self.synthesizedFallbackApps(
                    for: hostDescriptor,
                    cachedApps: cachedAppsForHost
                )
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
                    if fallbackApps.isEmpty {
                        apps = []
                        appState = .failed(message)
                    } else {
                        apps = fallbackApps
                        appState = .loaded
                    }
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
                httpsPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort,
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

        if normalized.contains("sunshine pin confirmation") {
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

        let urlCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmed)
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

    private static func synthesizedFallbackApps(
        for host: ShadowClientRemoteHostDescriptor,
        cachedApps: [ShadowClientRemoteAppDescriptor]
    ) -> [ShadowClientRemoteAppDescriptor] {
        var fallbackApps: [ShadowClientRemoteAppDescriptor] = []

        func appendFallbackApp(_ app: ShadowClientRemoteAppDescriptor) {
            guard app.id > 0 else {
                return
            }
            guard !fallbackApps.contains(where: { $0.id == app.id }) else {
                return
            }
            fallbackApps.append(app)
        }

        if host.currentGameID > 0 {
            if let cachedCurrent = cachedApps.first(where: { $0.id == host.currentGameID }) {
                appendFallbackApp(cachedCurrent)
            } else {
                appendFallbackApp(
                    ShadowClientRemoteAppDescriptor(
                        id: host.currentGameID,
                        title: ShadowClientRemoteAppLabels.currentSession(host.currentGameID),
                        hdrSupported: false,
                        isAppCollectorGame: false
                    )
                )
            }
        }

        for app in cachedApps {
            appendFallbackApp(app)
        }

        return fallbackApps
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
        let serverState = document.values["state"]?.first ?? ""
        let rawCurrentGameID = Int(document.values["currentgame"]?.first ?? "") ?? 0
        let currentGameID = normalizeCurrentGameID(
            rawCurrentGameID,
            serverState: serverState
        )
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

    private static func normalizeCurrentGameID(
        _ currentGameID: Int,
        serverState: String
    ) -> Int {
        guard currentGameID > 0 else {
            return 0
        }
        guard !isIdleServerState(serverState) else {
            return 0
        }
        return currentGameID
    }

    private static func isIdleServerState(_ serverState: String) -> Bool {
        let normalized = serverState
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return ShadowClientGameStreamServerState.idleStates.contains(normalized)
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

    private static let appElementNames: Set<String> = ["app", "game", "application"]

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
        textBuffer = ""

        let normalizedElement = Self.normalizedElementName(elementName)

        if normalizedElement == "root" {
            let code = Int(attributeDict["status_code"] ?? "") ?? -1
            let message = attributeDict["status_message"] ?? ""
            rootStatus = ShadowClientXMLRootStatus(code: code, message: message)
        } else if Self.appElementNames.contains(normalizedElement) {
            currentID = nil
            currentTitle = nil
            currentHDRSupported = false
            currentIsCollector = false

            currentID = parseIntAttribute(attributeDict, keys: [
                "id",
                "appid",
                "app_id",
                "app-id",
            ])
            currentTitle = parseStringAttribute(attributeDict, keys: [
                "apptitle",
                "title",
                "name",
            ])
            currentHDRSupported = parseBoolAttribute(attributeDict, keys: [
                "ishdrsupported",
                "hdr",
                "is_hdr_supported",
                "is-hdr-supported",
            ])
            currentIsCollector = parseBoolAttribute(attributeDict, keys: [
                "isappcollectorgame",
                "collector",
                "is_app_collector_game",
                "is-app-collector-game",
            ])
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
        let value = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedElement = Self.normalizedElementName(elementName)

        switch normalizedElement {
        case "apptitle", "title", "name":
            currentTitle = value.nonEmpty
        case "id", "appid", "app_id", "app-id":
            if let parsed = Self.parseIntString(value) {
                currentID = parsed
            }
        case "ishdrsupported", "hdr", "is_hdr_supported", "is-hdr-supported":
            currentHDRSupported = Self.parseBoolString(value)
        case "isappcollectorgame", "collector", "is_app_collector_game", "is-app-collector-game":
            currentIsCollector = Self.parseBoolString(value)
        case let element where Self.appElementNames.contains(element):
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

        textBuffer = ""
    }

    private func parseIntAttribute(
        _ attributes: [String: String],
        keys: [String]
    ) -> Int? {
        let normalizedAttributes = Self.normalizedAttributes(attributes)
        for key in keys {
            let normalizedKey = Self.normalizedAttributeName(key)
            if let value = normalizedAttributes[normalizedKey],
               let parsed = Self.parseIntString(value)
            {
                return parsed
            }
        }
        return nil
    }

    private func parseStringAttribute(
        _ attributes: [String: String],
        keys: [String]
    ) -> String? {
        let normalizedAttributes = Self.normalizedAttributes(attributes)
        for key in keys {
            let normalizedKey = Self.normalizedAttributeName(key)
            if let value = normalizedAttributes[normalizedKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty
            {
                return value
            }
        }
        return nil
    }

    private func parseBoolAttribute(
        _ attributes: [String: String],
        keys: [String]
    ) -> Bool {
        let normalizedAttributes = Self.normalizedAttributes(attributes)
        for key in keys {
            let normalizedKey = Self.normalizedAttributeName(key)
            if let value = normalizedAttributes[normalizedKey] {
                return Self.parseBoolString(value)
            }
        }
        return false
    }

    private static func normalizedAttributes(_ attributes: [String: String]) -> [String: String] {
        attributes.reduce(into: [String: String]()) { result, pair in
            result[normalizedAttributeName(pair.key)] = pair.value
        }
    }

    private static func normalizedAttributeName(_ key: String) -> String {
        normalizedElementName(key)
    }

    private static func parseIntString(_ value: String) -> Int? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = Int(trimmed) {
            return parsed
        }

        let normalized = trimmed
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        return Int(normalized)
    }

    private static func parseBoolString(_ value: String) -> Bool {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "y":
            return true
        default:
            return false
        }
    }

    private static func normalizedElementName(_ rawValue: String) -> String {
        let normalized = rawValue.split(separator: ":").last.map(String.init) ?? rawValue
        return normalized.lowercased()
    }
}

private extension String {
    var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
