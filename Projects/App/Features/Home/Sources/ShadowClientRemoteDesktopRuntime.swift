import Combine
import Foundation
import ShadowClientFeatureSession
import Network
import os
import ShadowClientFeatureConnection
import ShadowClientFeatureSession

public enum ShadowClientRemoteHostPairStatus: String, Equatable, Sendable {
    case paired
    case notPaired
    case unknown
}

public struct ShadowClientRemoteHostEndpoint: Equatable, Sendable {
    public let host: String
    public let httpsPort: Int

    public init(host: String, httpsPort: Int) {
        self.host = host
        self.httpsPort = httpsPort
    }
}

enum ShadowClientHostEndpointKit {
    static func parseCandidate(
        _ candidate: String?,
        fallbackHTTPSPort: Int
    ) -> ShadowClientRemoteHostEndpoint? {
        guard let candidate else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let urlCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmed)
        guard let parsed = URL(string: urlCandidate), let host = parsed.host else {
            return ShadowClientRemoteHostEndpoint(
                host: trimmed.lowercased(),
                httpsPort: fallbackHTTPSPort
            )
        }

        return ShadowClientRemoteHostEndpoint(
            host: host.lowercased(),
            httpsPort: parsed.port ?? fallbackHTTPSPort
        )
    }

    static func parseApolloConnectCandidate(
        _ candidate: String?,
        fallbackHTTPSPort: Int
    ) -> ShadowClientRemoteHostEndpoint? {
        guard let endpoint = parseCandidate(candidate, fallbackHTTPSPort: fallbackHTTPSPort) else {
            return nil
        }

        let trimmedCandidate = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let urlCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmedCandidate)
        guard let parsed = URL(string: urlCandidate),
              let explicitPort = parsed.port
        else {
            return endpoint
        }

        guard let mappedHTTPSPort = ShadowClientGameStreamNetworkDefaults.mappedHTTPSPort(
            forHTTPPort: explicitPort
        ),
        mappedHTTPSPort == fallbackHTTPSPort
        else {
            return endpoint
        }

        return ShadowClientRemoteHostEndpoint(
            host: endpoint.host,
            httpsPort: fallbackHTTPSPort
        )
    }

    static func candidateString(
        for endpoint: ShadowClientRemoteHostEndpoint,
        defaultHTTPSPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
    ) -> String {
        let normalizedHost = endpoint.host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedHost.isEmpty else {
            return ""
        }

        if endpoint.httpsPort == defaultHTTPSPort {
            return normalizedHost
        }

        return "\(normalizedHost):\(endpoint.httpsPort)"
    }
}

public struct ShadowClientRemoteHostRoutes: Equatable, Sendable {
    public let active: ShadowClientRemoteHostEndpoint
    public let local: ShadowClientRemoteHostEndpoint?
    public let remote: ShadowClientRemoteHostEndpoint?
    public let manual: ShadowClientRemoteHostEndpoint?

    public init(
        active: ShadowClientRemoteHostEndpoint,
        local: ShadowClientRemoteHostEndpoint? = nil,
        remote: ShadowClientRemoteHostEndpoint? = nil,
        manual: ShadowClientRemoteHostEndpoint? = nil
    ) {
        self.active = active
        self.local = local
        self.remote = remote
        self.manual = manual
    }

    public var allEndpoints: [ShadowClientRemoteHostEndpoint] {
        var seen: Set<String> = []
        return [active, local, remote, manual]
            .compactMap { $0 }
            .filter { endpoint in
                let key = "\(endpoint.host.lowercased()):\(endpoint.httpsPort)"
                if seen.contains(key) {
                    return false
                }
                seen.insert(key)
                return true
            }
    }
}

public struct ShadowClientRemoteHostDescriptor: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let pairStatus: ShadowClientRemoteHostPairStatus
    public let currentGameID: Int
    public let serverState: String
    public let appVersion: String?
    public let gfeVersion: String?
    public let uniqueID: String?
    public let serverCodecModeSupport: Int
    public let lastError: String?
    public let routes: ShadowClientRemoteHostRoutes

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
        serverCodecModeSupport: Int = 0,
        lastError: String?,
        localHost: String? = nil,
        remoteHost: String? = nil,
        manualHost: String? = nil
    ) {
        let activeRoute = ShadowClientHostEndpointKit.parseApolloConnectCandidate(
            host,
            fallbackHTTPSPort: httpsPort
        ) ?? .init(host: host, httpsPort: httpsPort)
        self.id = ShadowClientHostEndpointKit.candidateString(for: activeRoute)
        self.displayName = displayName
        self.pairStatus = pairStatus
        self.currentGameID = currentGameID
        self.serverState = serverState
        self.appVersion = appVersion
        self.gfeVersion = gfeVersion
        self.uniqueID = uniqueID
        self.serverCodecModeSupport = serverCodecModeSupport
        self.lastError = lastError
        self.routes = ShadowClientRemoteHostRoutes(
            active: activeRoute,
            local: ShadowClientHostEndpointKit.parseApolloConnectCandidate(
                localHost,
                fallbackHTTPSPort: httpsPort
            ),
            remote: ShadowClientHostEndpointKit.parseApolloConnectCandidate(
                remoteHost,
                fallbackHTTPSPort: httpsPort
            ),
            manual: ShadowClientHostEndpointKit.parseApolloConnectCandidate(
                manualHost,
                fallbackHTTPSPort: httpsPort
            )
        )
    }

    public init(
        activeRoute: ShadowClientRemoteHostEndpoint,
        displayName: String,
        pairStatus: ShadowClientRemoteHostPairStatus,
        currentGameID: Int,
        serverState: String,
        appVersion: String?,
        gfeVersion: String?,
        uniqueID: String?,
        serverCodecModeSupport: Int = 0,
        lastError: String?,
        routes: ShadowClientRemoteHostRoutes
    ) {
        self.id = ShadowClientHostEndpointKit.candidateString(for: activeRoute)
        self.displayName = displayName
        self.pairStatus = pairStatus
        self.currentGameID = currentGameID
        self.serverState = serverState
        self.appVersion = appVersion
        self.gfeVersion = gfeVersion
        self.uniqueID = uniqueID
        self.serverCodecModeSupport = serverCodecModeSupport
        self.lastError = lastError
        self.routes = routes
    }

    public var host: String { routes.active.host }
    public var httpsPort: Int { routes.active.httpsPort }
    public var hostCandidate: String { ShadowClientPairRouteKit.candidateString(for: routes.active) }

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
            return "Pairing Required"
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
            return "Host reachable. Pair this client in Apollo to continue."
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

public struct ShadowClientRemoteSessionIssue: Equatable, Sendable {
    public let title: String
    public let message: String

    public init(title: String, message: String) {
        self.title = title
        self.message = message
    }
}

public enum ShadowClientApolloAdminClientState: Equatable, Sendable {
    case idle
    case loading
    case saving
    case loaded
    case failed(String)
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
    let localHost: String?
    let remoteHost: String?
    let manualHost: String?
    let displayName: String
    let pairStatus: ShadowClientRemoteHostPairStatus
    let currentGameID: Int
    let serverState: String
    let httpsPort: Int
    let appVersion: String?
    let gfeVersion: String?
    let uniqueID: String?
    let serverCodecModeSupport: Int

    init(
        host: String,
        localHost: String? = nil,
        remoteHost: String? = nil,
        manualHost: String? = nil,
        displayName: String,
        pairStatus: ShadowClientRemoteHostPairStatus,
        currentGameID: Int,
        serverState: String,
        httpsPort: Int,
        appVersion: String?,
        gfeVersion: String?,
        uniqueID: String?,
        serverCodecModeSupport: Int = 0
    ) {
        self.host = host
        self.localHost = localHost
        self.remoteHost = remoteHost
        self.manualHost = manualHost
        self.displayName = displayName
        self.pairStatus = pairStatus
        self.currentGameID = currentGameID
        self.serverState = serverState
        self.httpsPort = httpsPort
        self.appVersion = appVersion
        self.gfeVersion = gfeVersion
        self.uniqueID = uniqueID
        self.serverCodecModeSupport = serverCodecModeSupport
    }
}

public struct ShadowClientGameStreamPortHint: Equatable, Sendable {
    public let httpPort: Int?
    public let httpsPort: Int?

    public init(httpPort: Int?, httpsPort: Int?) {
        self.httpPort = httpPort
        self.httpsPort = httpsPort
    }
}

enum ShadowClientServerCodecModeSupport {
    static let h264 = 0x00000001
    static let hevc = 0x00000100
    static let hevcMain10 = 0x00000200
    static let av1Main8 = 0x00010000
    static let av1Main10 = 0x00020000
    static let h264High8444 = 0x00040000
    static let hevcRext8444 = 0x00080000
    static let hevcRext10444 = 0x00100000
    static let av1High8444 = 0x00200000
    static let av1High10444 = 0x00400000

    static let maskH264 = h264 | h264High8444
    static let maskHEVC = hevc | hevcMain10 | hevcRext8444 | hevcRext10444
    static let maskAV1 = av1Main8 | av1Main10 | av1High8444 | av1High10444
}

public protocol ShadowClientGameStreamMetadataClient: Sendable {
    func fetchServerInfo(
        host: String,
        portHint: ShadowClientGameStreamPortHint?
    ) async throws -> ShadowClientGameStreamServerInfo
    func fetchAppList(host: String, httpsPort: Int?) async throws -> [ShadowClientRemoteAppDescriptor]
}

public extension ShadowClientGameStreamMetadataClient {
    func fetchServerInfo(host: String) async throws -> ShadowClientGameStreamServerInfo {
        try await fetchServerInfo(host: host, portHint: nil)
    }
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
    public let preferredSurroundChannelCount: Int
    public let enableYUV444: Bool
    public let remoteInputKey: Data?
    public let remoteInputKeyID: UInt32?
    public let serverAppVersion: String?

    public init(
        width: Int,
        height: Int,
        fps: Int = ShadowClientStreamingLaunchBounds.defaultFPS,
        bitrateKbps: Int = ShadowClientRTSPAnnounceDefaults.configuredBitrateKbps,
        preferredCodec: ShadowClientVideoCodecPreference = .auto,
        enableHDR: Bool = false,
        enableSurroundAudio: Bool = false,
        preferredSurroundChannelCount: Int = 6,
        enableYUV444: Bool = false,
        remoteInputKey: Data? = nil,
        remoteInputKeyID: UInt32? = nil,
        serverAppVersion: String? = nil
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
        self.preferredSurroundChannelCount = max(2, min(8, preferredSurroundChannelCount))
        self.enableYUV444 = enableYUV444
        self.remoteInputKey = remoteInputKey
        self.remoteInputKeyID = remoteInputKeyID
        self.serverAppVersion = serverAppVersion
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
    case text(String)
    case pointerMoved(x: Double, y: Double)
    case pointerPosition(x: Double, y: Double, referenceWidth: Double, referenceHeight: Double)
    case pointerButton(button: ShadowClientRemoteMouseButton, isPressed: Bool)
    case scroll(deltaX: Double, deltaY: Double)
    case gamepadState(ShadowClientRemoteGamepadState)
    case gamepadArrival(ShadowClientRemoteGamepadArrival)
}

public extension ShadowClientRemoteInputEvent {
    /// Sentinel key code used by software keyboards when no hardware scan code exists.
    static let softwareKeyboardSyntheticKeyCode: UInt16 = .max

    private static let pretranslatedWindowsVirtualKeyMask: UInt16 = 0x8000

    static func pretranslatedWindowsVirtualKey(_ virtualKey: UInt16) -> UInt16 {
        pretranslatedWindowsVirtualKeyMask | (virtualKey & ~pretranslatedWindowsVirtualKeyMask)
    }

    static func pretranslatedWindowsVirtualKeyCode(from keyCode: UInt16) -> UInt16? {
        guard keyCode != softwareKeyboardSyntheticKeyCode,
              keyCode & pretranslatedWindowsVirtualKeyMask != 0
        else {
            return nil
        }

        return keyCode & ~pretranslatedWindowsVirtualKeyMask
    }
}

public protocol ShadowClientRemoteSessionInputClient: Sendable {
    func send(event: ShadowClientRemoteInputEvent, host: String, sessionURL: String) async throws
    func sendKeepAlive(host: String, sessionURL: String) async throws
}

public extension ShadowClientRemoteSessionInputClient {
    func sendKeepAlive(host: String, sessionURL: String) async throws {
        _ = host
        _ = sessionURL
    }
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

    public func sendKeepAlive(
        host _: String,
        sessionURL _: String
    ) async throws {
        try await sessionRuntime.sendInputKeepAlive()
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
    func requestXMLResponse(
        host: String,
        port: Int,
        scheme: String,
        command: String,
        parameters: [String: String],
        uniqueID: String,
        pinnedServerCertificateDER: Data?,
        clientCertificateCredential: URLCredential?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?
    ) async throws -> ShadowClientGameStreamXMLResponse

    func requestXML(
        host: String,
        port: Int,
        scheme: String,
        command: String,
        parameters: [String: String],
        uniqueID: String,
        pinnedServerCertificateDER: Data?,
        clientCertificateCredential: URLCredential?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?
    ) async throws -> String
}

public extension ShadowClientGameStreamRequestTransporting {
    func requestXML(
        host: String,
        port: Int,
        scheme: String,
        command: String,
        parameters: [String: String],
        uniqueID: String,
        pinnedServerCertificateDER: Data?,
        clientCertificateCredential: URLCredential?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?
    ) async throws -> String {
        try await requestXMLResponse(
            host: host,
            port: port,
            scheme: scheme,
            command: command,
            parameters: parameters,
            uniqueID: uniqueID,
            pinnedServerCertificateDER: pinnedServerCertificateDER,
            clientCertificateCredential: clientCertificateCredential,
            clientCertificates: clientCertificates,
            clientCertificateIdentity: clientCertificateIdentity
        ).xml
    }
}

public struct ShadowClientGameStreamXMLResponse: Equatable, Sendable {
    public let xml: String
    public let usedConnectHost: String?

    public init(xml: String, usedConnectHost: String? = nil) {
        self.xml = xml
        self.usedConnectHost = usedConnectHost
    }
}

public struct NativeShadowClientGameStreamRequestTransport: ShadowClientGameStreamRequestTransporting {
    public init() {}

    public func requestXMLResponse(
        host: String,
        port: Int,
        scheme: String,
        command: String,
        parameters: [String: String],
        uniqueID: String,
        pinnedServerCertificateDER: Data?,
        clientCertificateCredential: URLCredential?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?
    ) async throws -> ShadowClientGameStreamXMLResponse {
        try await ShadowClientGameStreamHTTPTransport.requestXMLResponse(
            host: host,
            port: port,
            scheme: scheme,
            command: command,
            parameters: parameters,
            uniqueID: uniqueID,
            pinnedServerCertificateDER: pinnedServerCertificateDER,
            clientCertificateCredential: clientCertificateCredential,
            clientCertificates: clientCertificates,
            clientCertificateIdentity: clientCertificateIdentity
        )
    }
}

public actor NativeGameStreamMetadataClient: ShadowClientGameStreamMetadataClient {
    private let identityStore: ShadowClientPairingIdentityStore
    private let pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    private let transport: any ShadowClientGameStreamRequestTransporting
    private let defaultHTTPPort: Int
    private let defaultHTTPSPort: Int
    private let connectionTargetsResolver: @Sendable (String) -> [String]

    public static func defaultConnectionTargetsResolver(_ host: String) -> [String] {
        ShadowClientGameStreamHTTPTransport.connectionTargets(for: host)
    }

    public init(
        identityStore: ShadowClientPairingIdentityStore = .shared,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared,
        transport: any ShadowClientGameStreamRequestTransporting = NativeShadowClientGameStreamRequestTransport(),
        defaultHTTPPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPPort,
        defaultHTTPSPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort,
        connectionTargetsResolver: @escaping @Sendable (String) -> [String] = NativeGameStreamMetadataClient.defaultConnectionTargetsResolver
    ) {
        self.identityStore = identityStore
        self.pinnedCertificateStore = pinnedCertificateStore
        self.transport = transport
        self.defaultHTTPPort = defaultHTTPPort
        self.defaultHTTPSPort = defaultHTTPSPort
        self.connectionTargetsResolver = connectionTargetsResolver
    }

    public func fetchServerInfo(
        host: String,
        portHint: ShadowClientGameStreamPortHint?
    ) async throws -> ShadowClientGameStreamServerInfo {
        let requestEndpoints = try Self.resolveServerInfoRequestEndpoints(
            host: host,
            portHint: portHint,
            defaultHTTPPort: defaultHTTPPort,
            defaultHTTPSPort: defaultHTTPSPort
        )
        let requestedHost = requestEndpoints.host
        let connectionTargets = connectionTargetsResolver(requestEndpoints.host)
        let pinnedCertificateDER = await pinnedCertificateStore.certificateDER(forHost: requestEndpoints.host)

        if pinnedCertificateDER == nil {
            let httpResponse = try await requestXML(
                host: requestEndpoints.host,
                port: requestEndpoints.httpPort,
                scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
                command: "serverinfo"
            )

            let serverInfo = try ShadowClientGameStreamXMLParsers.parseServerInfo(
                xml: httpResponse.xml,
                host: requestedHost,
                fallbackHTTPSPort: requestEndpoints.httpsPort
            )
            return Self.reconciledServerInfo(
                serverInfo,
                requestedHost: requestedHost,
                connectionTargets: connectionTargets,
                usedConnectHost: httpResponse.usedConnectHost
            )
        }

        do {
            let httpsResponse = try await requestXML(
                host: requestEndpoints.host,
                port: requestEndpoints.httpsPort,
                scheme: ShadowClientGameStreamNetworkDefaults.httpsScheme,
                command: "serverinfo"
            )

            let serverInfo = try ShadowClientGameStreamXMLParsers.parseServerInfo(
                xml: httpsResponse.xml,
                host: requestedHost,
                fallbackHTTPSPort: requestEndpoints.httpsPort
            )
            return Self.reconciledServerInfo(
                serverInfo,
                requestedHost: requestedHost,
                connectionTargets: connectionTargets,
                usedConnectHost: httpsResponse.usedConnectHost
            )
        } catch let httpsError as ShadowClientGameStreamError {
            if Self.isUnauthorizedCertificateError(httpsError) {
                if Self.shouldSkipPlainHTTPFallback(host: requestEndpoints.host, httpsError: httpsError) {
                    return Self.makeUnauthorizedServerInfo(
                        host: requestedHost,
                        fallbackHTTPSPort: requestEndpoints.httpsPort
                    )
                }
                do {
                    let httpResponse = try await requestXML(
                        host: requestEndpoints.host,
                        port: requestEndpoints.httpPort,
                        scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
                        command: "serverinfo"
                    )

                    let serverInfo = try ShadowClientGameStreamXMLParsers.parseServerInfo(
                        xml: httpResponse.xml,
                        host: requestedHost,
                        fallbackHTTPSPort: requestEndpoints.httpsPort
                    )
                    return Self.reconciledServerInfo(
                        serverInfo,
                        requestedHost: requestedHost,
                        connectionTargets: connectionTargets,
                        usedConnectHost: httpResponse.usedConnectHost
                    )
                } catch let httpError as ShadowClientGameStreamError {
                    if Self.isAppTransportSecurityBlockedError(httpError) {
                        return Self.makeUnauthorizedServerInfo(
                            host: requestedHost,
                            fallbackHTTPSPort: requestEndpoints.httpsPort
                        )
                    }
                } catch {}

                return Self.makeUnauthorizedServerInfo(
                    host: requestedHost,
                    fallbackHTTPSPort: requestEndpoints.httpsPort
                )
            }

            if Self.shouldSkipPlainHTTPFallback(host: requestEndpoints.host, httpsError: httpsError) {
                throw httpsError
            }
            do {
                let httpResponse = try await requestXML(
                    host: requestEndpoints.host,
                    port: requestEndpoints.httpPort,
                    scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
                    command: "serverinfo"
                )

                let serverInfo = try ShadowClientGameStreamXMLParsers.parseServerInfo(
                    xml: httpResponse.xml,
                    host: requestedHost,
                    fallbackHTTPSPort: requestEndpoints.httpsPort
                )
                return Self.reconciledServerInfo(
                    serverInfo,
                    requestedHost: requestedHost,
                    connectionTargets: connectionTargets,
                    usedConnectHost: httpResponse.usedConnectHost
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
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPSPort)
        let resolvedHTTPSPort = httpsPort ?? endpoint.port
        let pinnedCertificateDER = await pinnedCertificateStore.certificateDER(forHost: endpoint.host)

        guard pinnedCertificateDER != nil else {
            throw ShadowClientGameStreamError.requestFailed(
                "Host requires a paired HTTPS certificate before app list queries."
            )
        }

        let httpsResponse = try await requestXML(
            host: endpoint.host,
            port: resolvedHTTPSPort,
            scheme: ShadowClientGameStreamNetworkDefaults.httpsScheme,
            command: "applist"
        )

        return try ShadowClientGameStreamXMLParsers.parseAppList(xml: httpsResponse.xml)
    }

    private static func resolveServerInfoRequestEndpoints(
        host: String,
        portHint: ShadowClientGameStreamPortHint?,
        defaultHTTPPort: Int,
        defaultHTTPSPort: Int
    ) throws -> (host: String, httpPort: Int, httpsPort: Int) {
        let resolvedHost = try parseHostEndpoint(host: host, fallbackPort: defaultHTTPSPort).host
        let explicitPort = parseExplicitPort(from: host)

        let httpPort = portHint?.httpPort ?? explicitPort ?? defaultHTTPPort
        let httpsPort = portHint?.httpsPort ??
            explicitPort.flatMap { ShadowClientGameStreamNetworkDefaults.mappedHTTPSPort(forHTTPPort: $0) } ??
            explicitPort ??
            defaultHTTPSPort

        return (
            host: resolvedHost,
            httpPort: httpPort,
            httpsPort: httpsPort
        )
    }

    private static func reconciledServerInfo(
        _ serverInfo: ShadowClientGameStreamServerInfo,
        requestedHost: String,
        connectionTargets: [String],
        usedConnectHost: String?
    ) -> ShadowClientGameStreamServerInfo {
        let reconciledLocalHost = preferredResolvedLocalRouteHost(
            requestedHost: requestedHost,
            connectionTargets: connectionTargets
        ) ?? serverInfo.localHost

        return ShadowClientGameStreamServerInfo(
            host: serverInfo.host,
            localHost: reconciledLocalHost,
            remoteHost: serverInfo.remoteHost,
            manualHost: serverInfo.manualHost,
            displayName: serverInfo.displayName,
            pairStatus: serverInfo.pairStatus,
            currentGameID: serverInfo.currentGameID,
            serverState: serverInfo.serverState,
            httpsPort: serverInfo.httpsPort,
            appVersion: serverInfo.appVersion,
            gfeVersion: serverInfo.gfeVersion,
            uniqueID: serverInfo.uniqueID,
            serverCodecModeSupport: serverInfo.serverCodecModeSupport
        )
    }

    private static func preferredResolvedLocalRouteHost(
        requestedHost: String,
        connectionTargets: [String]
    ) -> String? {
        let normalizedRequestedHost = requestedHost
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalizedRequestedHost.isEmpty, !isIPAddressLiteral(normalizedRequestedHost) else {
            return nil
        }

        let candidates = connectionTargets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && $0 != normalizedRequestedHost }
            .reduce(into: [String]()) { partialResult, candidate in
                guard !partialResult.contains(candidate) else {
                    return
                }
                partialResult.append(candidate)
            }

        return candidates.sorted { lhs, rhs in
            let lhsRank = resolvedLocalRouteRank(lhs)
            let rhsRank = resolvedLocalRouteRank(rhs)
            if lhsRank == rhsRank {
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            return lhsRank < rhsRank
        }.first
    }

    private static func resolvedLocalRouteRank(_ host: String) -> Int {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return 100
        }

        if isPrivateIPv4Literal(normalized) {
            return 0
        }
        if normalized.hasPrefix("fd") || normalized.hasPrefix("fc") {
            return 10
        }
        if isIPAddressLiteral(normalized) && !ShadowClientRemoteHostCandidateFilter.isLinkLocalHost(normalized) {
            return 20
        }
        if ShadowClientRemoteHostCandidateFilter.isLinkLocalHost(normalized) {
            return 30
        }
        if normalized.hasSuffix(".local") || !normalized.contains(".") {
            return 40
        }
        return 50
    }

    private static func isIPAddressLiteral(_ host: String) -> Bool {
        if host.contains(":") {
            return true
        }
        return host.allSatisfy { $0.isNumber || $0 == "." }
    }

    private static func isPrivateIPv4Literal(_ host: String) -> Bool {
        if host.hasPrefix("10.") || host.hasPrefix("192.168.") {
            return true
        }
        if host.hasPrefix("172."),
           let secondOctet = host.split(separator: ".").dropFirst().first,
           let secondOctetValue = Int(secondOctet),
           (16...31).contains(secondOctetValue)
        {
            return true
        }
        return false
    }

    private static func parseExplicitPort(from host: String) -> Int? {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        let candidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(normalized)
        guard let url = URL(string: candidate) else {
            return nil
        }
        return url.port
    }

    private static func isUnauthorizedCertificateError(_ error: ShadowClientGameStreamError) -> Bool {
        switch error {
        case let .responseRejected(code, message):
            guard code == 401 else {
                return false
            }
            let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("not authorized") ||
                normalized.contains("certificate verification failed") ||
                normalized.contains("server certificate mismatch") ||
                normalized.contains("trust failed")
        case let .requestFailed(message):
            let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("tls error caused the secure connection to fail") ||
                normalized.contains("certificate verification failed") ||
                normalized.contains("server certificate mismatch") ||
                normalized.contains("trust failed") ||
                normalized.contains("self-signed")
        default:
            return false
        }
    }

    private static func isAppTransportSecurityBlockedError(_ error: ShadowClientGameStreamError) -> Bool {
        guard case let .requestFailed(message) = error else {
            return false
        }
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("app transport security") ||
            normalized.contains("insecure http is blocked")
    }

    private static func shouldSkipPlainHTTPFallback(
        host: String,
        httpsError: ShadowClientGameStreamError
    ) -> Bool {
        guard isLikelyLocalNetworkHost(host) else {
            return false
        }

        if isUnauthorizedCertificateError(httpsError) {
            return true
        }

        if case let .requestFailed(message) = httpsError {
            let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("connection refused") ||
                normalized.contains("could not connect") ||
                normalized.contains("timed out")
        }

        return false
    }

    private static func isLikelyLocalNetworkHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasSuffix(".local") {
            return true
        }
        if normalized.hasPrefix("10.") || normalized.hasPrefix("192.168.") || normalized.hasPrefix("169.254.") {
            return true
        }
        if normalized.hasPrefix("fe80:") || normalized.hasPrefix("fd") || normalized.hasPrefix("fc") {
            return true
        }
        if normalized.hasPrefix("172."),
           let secondOctet = normalized.split(separator: ".").dropFirst().first,
           let secondOctetValue = Int(secondOctet),
           (16...31).contains(secondOctetValue)
        {
            return true
        }
        return false
    }

    private static func makeUnauthorizedServerInfo(
        host: String,
        fallbackHTTPSPort: Int
    ) -> ShadowClientGameStreamServerInfo {
        ShadowClientGameStreamServerInfo(
            host: host,
            localHost: nil,
            remoteHost: nil,
            manualHost: nil,
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
    ) async throws -> ShadowClientGameStreamXMLResponse {
        let uniqueID = await identityStore.uniqueID()
        let pinnedCertificateDER = await pinnedCertificateStore.certificateDER(forHost: host)
        let clientCertificateCredential: URLCredential?
        let clientCertificates: [SecCertificate]?
        let clientCertificateIdentity: SecIdentity?
        if scheme == ShadowClientGameStreamNetworkDefaults.httpsScheme {
            clientCertificateCredential = try? await identityStore.tlsClientCertificateCredential()
            clientCertificates = try? await identityStore.tlsClientCertificates()
            clientCertificateIdentity = try? await identityStore.tlsClientIdentity()
        } else {
            clientCertificateCredential = nil
            clientCertificates = nil
            clientCertificateIdentity = nil
        }
        return try await transport.requestXMLResponse(
            host: host,
            port: port,
            scheme: scheme,
            command: command,
            parameters: [:],
            uniqueID: uniqueID,
            pinnedServerCertificateDER: pinnedCertificateDER,
            clientCertificateCredential: clientCertificateCredential,
            clientCertificates: clientCertificates,
            clientCertificateIdentity: clientCertificateIdentity
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

private actor ShadowClientRemoteInputSendQueue {
    private static let baseCooldownNanoseconds: UInt64 = 50_000_000
    private static let maximumCooldownNanoseconds: UInt64 = 800_000_000
    private static let maximumCooldownExponent = 5
    private static let maximumPendingInputs = 512

    private struct PendingInput: Sendable {
        var event: ShadowClientRemoteInputEvent
        let host: String
        let sessionURL: String

        var isMotionLike: Bool {
            switch event {
            case .pointerMoved, .pointerPosition, .scroll:
                return true
            default:
                return false
            }
        }
    }

    private let send: @Sendable (
        ShadowClientRemoteInputEvent,
        String,
        String
    ) async throws -> Void
    private let onSendError: @Sendable (Error) -> Void
    private let shouldCooldownAfterError: @Sendable (Error) -> Bool
    private var pendingInputs: [PendingInput] = []
    private var pendingHeadIndex = 0
    private var isDraining = false
    private var cooldownDeadlineUptimeNanoseconds: UInt64?
    private var cooldownExponent = 0

    init(
        send: @escaping @Sendable (
            ShadowClientRemoteInputEvent,
            String,
            String
        ) async throws -> Void,
        onSendError: @escaping @Sendable (Error) -> Void,
        shouldCooldownAfterError: @escaping @Sendable (Error) -> Bool = { _ in false }
    ) {
        self.send = send
        self.onSendError = onSendError
        self.shouldCooldownAfterError = shouldCooldownAfterError
    }

    func enqueue(
        event: ShadowClientRemoteInputEvent,
        host: String,
        sessionURL: String
    ) {
        compactPendingInputsIfNeeded()
        let pending = PendingInput(event: event, host: host, sessionURL: sessionURL)
        if shouldDropForBackpressure(pending) {
            return
        }
        if !coalesceIntoTail(pending) {
            pendingInputs.append(pending)
        }

        guard !isDraining else {
            return
        }
        isDraining = true
        Task { await drainLoop() }
    }

    func clear() {
        pendingInputs.removeAll(keepingCapacity: false)
        pendingHeadIndex = 0
        cooldownDeadlineUptimeNanoseconds = nil
        cooldownExponent = 0
    }

    private func drainLoop() async {
        while pendingHeadIndex < pendingInputs.count {
            await sleepForCooldownIfNeeded()
            let next = pendingInputs[pendingHeadIndex]
            pendingHeadIndex += 1
            do {
                try await send(next.event, next.host, next.sessionURL)
                cooldownDeadlineUptimeNanoseconds = nil
                cooldownExponent = 0
            } catch {
                onSendError(error)
                if shouldCooldownAfterError(error) {
                    cooldownExponent = min(
                        cooldownExponent + 1,
                        Self.maximumCooldownExponent
                    )
                    let shift = max(0, cooldownExponent - 1)
                    let uncappedCooldown = Self.baseCooldownNanoseconds &<< UInt64(shift)
                    let cooldownNanoseconds = min(
                        uncappedCooldown,
                        Self.maximumCooldownNanoseconds
                    )
                    cooldownDeadlineUptimeNanoseconds = DispatchTime.now().uptimeNanoseconds &+ cooldownNanoseconds
                } else {
                    cooldownDeadlineUptimeNanoseconds = nil
                    cooldownExponent = 0
                }
            }
        }
        pendingInputs.removeAll(keepingCapacity: false)
        pendingHeadIndex = 0
        isDraining = false
    }

    private func sleepForCooldownIfNeeded() async {
        guard let cooldownDeadlineUptimeNanoseconds else {
            return
        }
        let now = DispatchTime.now().uptimeNanoseconds
        guard cooldownDeadlineUptimeNanoseconds > now else {
            self.cooldownDeadlineUptimeNanoseconds = nil
            return
        }

        let delay = cooldownDeadlineUptimeNanoseconds - now
        do {
            try await Task.sleep(nanoseconds: delay)
        } catch {
            // Preserve cancellation semantics for caller loop.
        }
        self.cooldownDeadlineUptimeNanoseconds = nil
    }

    private func compactPendingInputsIfNeeded() {
        guard pendingHeadIndex >= 64,
              pendingHeadIndex * 2 >= pendingInputs.count
        else {
            return
        }
        pendingInputs.removeFirst(pendingHeadIndex)
        pendingHeadIndex = 0
    }

    private func shouldDropForBackpressure(_ pending: PendingInput) -> Bool {
        let pendingCount = pendingInputs.count - pendingHeadIndex
        guard pendingCount >= Self.maximumPendingInputs else {
            return false
        }

        if pending.isMotionLike {
            return true
        }
        if dropOldestMotionEventIfAny() {
            return false
        }
        if pendingHeadIndex < pendingInputs.count {
            pendingHeadIndex += 1
        }
        return false
    }

    private func dropOldestMotionEventIfAny() -> Bool {
        guard pendingHeadIndex < pendingInputs.count else {
            return false
        }
        for index in pendingHeadIndex ..< pendingInputs.count where pendingInputs[index].isMotionLike {
            pendingInputs.remove(at: index)
            return true
        }
        return false
    }

    private func coalesceIntoTail(_ pending: PendingInput) -> Bool {
        guard pendingHeadIndex < pendingInputs.count else {
            return false
        }
        let lastIndex = pendingInputs.count - 1

        let last = pendingInputs[lastIndex]
        guard last.host == pending.host,
              last.sessionURL == pending.sessionURL
        else {
            return false
        }

        switch (last.event, pending.event) {
        case (.pointerMoved, .pointerMoved):
            pendingInputs[lastIndex] = pending
            return true
        case (.pointerPosition, .pointerPosition):
            pendingInputs[lastIndex] = pending
            return true
        case let (.scroll(previousX, previousY), .scroll(nextX, nextY)):
            pendingInputs[lastIndex] = PendingInput(
                event: .scroll(
                    deltaX: previousX + nextX,
                    deltaY: previousY + nextY
                ),
                host: last.host,
                sessionURL: last.sessionURL
            )
            return true
        default:
            return false
        }
    }
}

private enum ShadowClientRemoteDesktopCommand: Sendable {
    case refreshHosts(
        candidates: [String],
        preferredHost: String?,
        portHintsByCandidate: [String: ShadowClientGameStreamPortHint]
    )
    case pairSelectedHost
    case deleteHost(String)
    case syncClipboardIfNeeded
    case pullClipboard
    case syncClipboard(String)
    case launchSelectedApp(
        appID: Int,
        appTitle: String?,
        forceLaunch: Bool,
        settings: ShadowClientGameStreamLaunchSettings
    )
    case clearActiveSession
    case sendInput(ShadowClientRemoteInputEvent)
    case sendInputKeepAlive
    case openSessionFlow(host: String, appTitle: String)
    case selectHost(String)
    case refreshSelectedHostApps
    case refreshSelectedHostApolloAdmin(username: String, password: String)
    case updateSelectedHostApolloAdmin(
        username: String,
        password: String,
        displayModeOverride: String,
        alwaysUseVirtualDisplay: Bool,
        permissions: UInt32
    )
    case disconnectSelectedHostApolloAdmin(username: String, password: String)
    case unpairSelectedHostApolloAdmin(username: String, password: String)
}

private struct ShadowClientLaunchRequestContext: Sendable {
    let hostKey: String
    let appID: Int
    let appTitle: String?
    let settings: ShadowClientGameStreamLaunchSettings
}

private struct ShadowClientPairHostCandidate: Equatable, Sendable {
    let host: String
    let httpsPort: Int

    init(host: String, httpsPort: Int) {
        self.host = Self.normalizedCandidate(host)
        self.httpsPort = httpsPort
    }

    private static func normalizedCandidate(_ host: String) -> String {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let candidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmed)
        guard let url = URL(string: candidate), let parsedHost = url.host?.lowercased() else {
            return trimmed.lowercased()
        }

        if let port = url.port {
            return "\(parsedHost):\(port)"
        }

        return parsedHost
    }
}

private enum ShadowClientPairRouteKit {
    static func candidateString(
        for descriptor: ShadowClientRemoteHostDescriptor
    ) -> String {
        candidateString(for: descriptor.routes.active)
    }

    static func candidateString(
        for endpoint: ShadowClientRemoteHostEndpoint
    ) -> String {
        let normalizedHost = endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else {
            return ""
        }

        guard let httpPort = ShadowClientGameStreamNetworkDefaults.mappedHTTPPort(
            forHTTPSPort: endpoint.httpsPort
        ) else {
            return normalizedHost
        }

        if httpPort == ShadowClientGameStreamNetworkDefaults.defaultHTTPPort {
            return normalizedHost
        }

        return "\(normalizedHost):\(httpPort)"
    }
}

private struct ShadowClientPersistedRemoteHostCatalog: Codable {
    let hosts: [ShadowClientPersistedRemoteHostRecord]
}

private struct ShadowClientPersistedRemoteHostRecord: Codable {
    let activeHost: String
    let httpsPort: Int
    let displayName: String
    let pairStatusRawValue: String
    let currentGameID: Int
    let serverState: String
    let appVersion: String?
    let gfeVersion: String?
    let uniqueID: String?
    let lastError: String?
    let localHost: String?
    let remoteHost: String?
    let manualHost: String?
    let activeRoute: String?
    let localRoute: String?
    let remoteRoute: String?
    let manualRoute: String?

    init(descriptor: ShadowClientRemoteHostDescriptor) {
        activeHost = descriptor.host
        httpsPort = descriptor.httpsPort
        displayName = descriptor.displayName
        pairStatusRawValue = descriptor.pairStatus.rawValue
        currentGameID = descriptor.currentGameID
        serverState = descriptor.serverState
        appVersion = descriptor.appVersion
        gfeVersion = descriptor.gfeVersion
        uniqueID = descriptor.uniqueID
        lastError = descriptor.lastError
        activeRoute = ShadowClientHostEndpointKit.candidateString(for: descriptor.routes.active)
        localHost = nil
        remoteHost = nil
        manualHost = nil
        localRoute = nil
        remoteRoute = nil
        manualRoute = nil
    }

    var descriptor: ShadowClientRemoteHostDescriptor {
        ShadowClientRemoteHostDescriptor(
            host: activeRoute ?? activeHost,
            displayName: displayName,
            pairStatus: ShadowClientRemoteHostPairStatus(rawValue: pairStatusRawValue) ?? .unknown,
            currentGameID: currentGameID,
            serverState: serverState,
            httpsPort: httpsPort,
            appVersion: appVersion,
            gfeVersion: gfeVersion,
            uniqueID: uniqueID,
            lastError: lastError,
            localHost: nil,
            remoteHost: nil,
            manualHost: nil
        )
    }
}

private struct ShadowClientPersistedRemoteSessionFingerprint: Codable, Equatable {
    let hostKey: String
    let appID: Int
    let settingsKey: String
    let negotiatedVideoCodec: ShadowClientVideoCodec?
}

private struct ShadowClientRemoteDesktopPersistence {
    let defaults: UserDefaults
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    func loadCachedHosts() -> [ShadowClientRemoteHostDescriptor] {
        guard let data = defaults.data(forKey: ShadowClientAppSettings.StorageKeys.cachedRemoteHosts),
              let catalog = try? decoder.decode(ShadowClientPersistedRemoteHostCatalog.self, from: data)
        else {
            return []
        }

        return catalog.hosts.map(\.descriptor)
    }

    func saveCachedHosts(_ hosts: [ShadowClientRemoteHostDescriptor]) {
        let persistableHosts = hosts.filter { $0.pairStatus == .paired }
        let catalog = ShadowClientPersistedRemoteHostCatalog(
            hosts: persistableHosts.map(ShadowClientPersistedRemoteHostRecord.init(descriptor:))
        )
        guard let data = try? encoder.encode(catalog) else {
            return
        }

        defaults.set(data, forKey: ShadowClientAppSettings.StorageKeys.cachedRemoteHosts)
    }

    func loadSessionFingerprint() -> ShadowClientPersistedRemoteSessionFingerprint? {
        guard let data = defaults.data(forKey: ShadowClientAppSettings.StorageKeys.lastRemoteSessionFingerprint) else {
            return nil
        }

        return try? decoder.decode(ShadowClientPersistedRemoteSessionFingerprint.self, from: data)
    }

    func saveSessionFingerprint(_ fingerprint: ShadowClientPersistedRemoteSessionFingerprint?) {
        let key = ShadowClientAppSettings.StorageKeys.lastRemoteSessionFingerprint
        guard let fingerprint else {
            defaults.removeObject(forKey: key)
            return
        }

        guard let data = try? encoder.encode(fingerprint) else {
            return
        }
        defaults.set(data, forKey: key)
    }
}

public final class ShadowClientRemoteDesktopRuntime: ObservableObject {
    private static let runtimeStreamReconnectCooldownSeconds: TimeInterval = 4.0

    @Published public private(set) var hosts: [ShadowClientRemoteHostDescriptor] = []
    @Published public private(set) var apps: [ShadowClientRemoteAppDescriptor] = []
    @Published public private(set) var hostState: ShadowClientRemoteHostCatalogState = .idle
    @Published public private(set) var appState: ShadowClientRemoteAppCatalogState = .idle
    @Published public private(set) var selectedHostID: String?
    @Published public private(set) var pairingState: ShadowClientRemotePairingState = .idle
    @Published public private(set) var launchState: ShadowClientRemoteLaunchState = .idle
    @Published public private(set) var activeSession: ShadowClientActiveRemoteSession?
    @Published public private(set) var isClearingActiveSession = false
    @Published public private(set) var sessionIssue: ShadowClientRemoteSessionIssue?
    @Published public private(set) var selectedHostApolloAdminProfile: ShadowClientApolloAdminClientProfile?
    @Published public private(set) var selectedHostApolloAdminState: ShadowClientApolloAdminClientState = .idle
    public let sessionPresentationMode: ShadowClientRemoteSessionPresentationMode
    public let sessionSurfaceContext: ShadowClientRealtimeSessionSurfaceContext

    private let metadataClient: any ShadowClientGameStreamMetadataClient
    private let controlClient: any ShadowClientGameStreamControlClient
    private let apolloAdminClient: any ShadowClientApolloAdminClient
    private let clipboardClient: any ShadowClientClipboardClient
    private let sessionConnectionClient: any ShadowClientRemoteSessionConnectionClient
    private let sessionInputClient: any ShadowClientRemoteSessionInputClient
    private let inputSendQueue: ShadowClientRemoteInputSendQueue
    private let pinProvider: any ShadowClientPairingPINProviding
    private let pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    private let pairingRouteStore: ShadowClientPairingRouteStore
    private let persistence: ShadowClientRemoteDesktopPersistence
    private let inputKeepAliveInterval: Duration
    private let clipboardSyncInterval: Duration
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "RemoteDesktopRuntime")
    private let commandContinuation: AsyncStream<ShadowClientRemoteDesktopCommand>.Continuation
    private var commandLoopTask: Task<Void, Never>?
    private var refreshHostsTask: Task<Void, Never>?
    private var refreshAppsTask: Task<Void, Never>?
    private var pairTask: Task<Void, Never>?
    private var launchTask: Task<Void, Never>?
    private var activeSessionCancelTask: Task<Void, Never>?
    private var inputKeepAliveTask: Task<Void, Never>?
    private var clipboardSyncTask: Task<Void, Never>?
    private var latestHostCandidates: [String] = []
    private var latestResolvedHostDescriptors: [ShadowClientRemoteHostDescriptor] = []
    private var cachedAppsByHostID: [String: [ShadowClientRemoteAppDescriptor]] = [:]
    private var appRefreshGeneration: UInt64 = 0
    private var pairGeneration: UInt64 = 0
    private var launchGeneration: UInt64 = 0
    private var pendingSelectedHostID: String?
    private var lastKnownSessionURL: String?
    private var persistentCodecFallback: ShadowClientVideoCodecPreference?
    private var lastLaunchRequestContext: ShadowClientLaunchRequestContext?
    private var lastConnectedLaunchSettings: ShadowClientGameStreamLaunchSettings?
    private var lastLocalSessionFingerprint: ShadowClientPersistedRemoteSessionFingerprint?
    private var runtimeCodecRecoveryInProgress = false
    private var runtimeStreamReconnectInProgress = false
    private var lastRuntimeStreamReconnectUptime: TimeInterval = 0
    private var renderStateFailureObservation: AnyCancellable?
    private var lastSynchronizedClipboardText: String?
    private var clipboardReadPermissionDenied = false
    private var clipboardWritePermissionDenied = false
    private var clipboardActionRequiresActiveStream = false
    private var hostTerminationIssue: ShadowClientRemoteSessionIssue?

    public init(
        metadataClient: any ShadowClientGameStreamMetadataClient = NativeGameStreamMetadataClient(),
        controlClient: any ShadowClientGameStreamControlClient = NativeGameStreamControlClient(),
        apolloAdminClient: any ShadowClientApolloAdminClient = NativeShadowClientApolloAdminClient(),
        clipboardClient: any ShadowClientClipboardClient = NativeShadowClientClipboardClient(),
        sessionConnectionClient: any ShadowClientRemoteSessionConnectionClient = NoopShadowClientRemoteSessionConnectionClient(),
        sessionInputClient: any ShadowClientRemoteSessionInputClient = NoopShadowClientRemoteSessionInputClient(),
        pinProvider: any ShadowClientPairingPINProviding = ShadowClientRandomPairingPINProvider(),
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared,
        pairingRouteStore: ShadowClientPairingRouteStore = .shared,
        inputKeepAliveInterval: Duration = .seconds(3),
        clipboardSyncInterval: Duration = .milliseconds(750),
        defaults: UserDefaults = .standard
    ) {
        let (commandStream, commandContinuation) = AsyncStream.makeStream(of: ShadowClientRemoteDesktopCommand.self)
        let persistence = ShadowClientRemoteDesktopPersistence(defaults: defaults)
        let persistedHosts = persistence.loadCachedHosts()
        let persistedFingerprint = persistence.loadSessionFingerprint()

        self.metadataClient = metadataClient
        self.controlClient = controlClient
        self.apolloAdminClient = apolloAdminClient
        self.clipboardClient = clipboardClient
        self.sessionConnectionClient = sessionConnectionClient
        self.sessionInputClient = sessionInputClient
        self.commandContinuation = commandContinuation
        self.persistence = persistence
        self.inputSendQueue = ShadowClientRemoteInputSendQueue(
            send: { [sessionInputClient] event, host, sessionURL in
                try await sessionInputClient.send(
                    event: event,
                    host: host,
                    sessionURL: sessionURL
                )
            },
            onSendError: { [logger] error in
                if Self.shouldSuppressInputSendError(error) {
                    return
                }
                logger.debug("Remote input send failed: \(error.localizedDescription, privacy: .public)")
            },
            shouldCooldownAfterError: { error in
                Self.shouldThrottleInputSendAfterError(error)
            }
        )
        self.pinProvider = pinProvider
        self.pinnedCertificateStore = pinnedCertificateStore
        self.pairingRouteStore = pairingRouteStore
        self.inputKeepAliveInterval = inputKeepAliveInterval
        self.clipboardSyncInterval = clipboardSyncInterval
        self.sessionPresentationMode = sessionConnectionClient.presentationMode
        self.sessionSurfaceContext = sessionConnectionClient.sessionSurfaceContext
        self.hosts = persistedHosts
        self.latestResolvedHostDescriptors = persistedHosts
        self.hostState = persistedHosts.isEmpty ? .idle : .loaded
        self.selectedHostID = persistedHosts.first?.id
        self.lastLocalSessionFingerprint = persistedFingerprint
        self.renderStateFailureObservation = self.sessionSurfaceContext.$renderState
            .removeDuplicates()
            .sink { [weak self] state in
                guard case let .failed(message) = state else {
                    return
                }
                Task { @MainActor [weak self] in
                    self?.handleSessionRenderStateTransition(.failed(message))
                }
            }

        commandLoopTask = Task { [weak self] in
            guard let self else {
                return
            }

            for await command in commandStream {
                await self.process(command: command)
            }
        }
    }

    deinit {
        commandContinuation.finish()
        commandLoopTask?.cancel()
        refreshHostsTask?.cancel()
        refreshAppsTask?.cancel()
        pairTask?.cancel()
        launchTask?.cancel()
        activeSessionCancelTask?.cancel()
        inputKeepAliveTask?.cancel()
        renderStateFailureObservation?.cancel()
    }

    @MainActor
    private func process(command: ShadowClientRemoteDesktopCommand) async {
        switch command {
        case let .refreshHosts(candidates, preferredHost, portHintsByCandidate):
            performRefreshHosts(
                candidates: candidates,
                preferredHost: preferredHost,
                portHintsByCandidate: portHintsByCandidate
            )
        case .pairSelectedHost:
            performPairSelectedHost()
        case let .deleteHost(hostID):
            performDeleteHost(hostID)
        case .syncClipboardIfNeeded:
            await performSyncClipboardIfNeeded()
        case .pullClipboard:
            await performPullClipboard()
        case let .syncClipboard(text):
            await performSyncClipboard(text)
        case let .launchSelectedApp(appID, appTitle, forceLaunch, settings):
            performLaunchSelectedApp(
                appID: appID,
                appTitle: appTitle,
                forceLaunch: forceLaunch,
                settings: settings
            )
        case .clearActiveSession:
            performClearActiveSession()
        case let .sendInput(event):
            await performSendInput(event)
        case .sendInputKeepAlive:
            await performSendInputKeepAlive()
        case let .openSessionFlow(host, appTitle):
            performOpenSessionFlow(host: host, appTitle: appTitle)
        case let .selectHost(hostID):
            performSelectHost(hostID)
        case .refreshSelectedHostApps:
            performRefreshSelectedHostApps()
        case let .refreshSelectedHostApolloAdmin(username, password):
            performRefreshSelectedHostApolloAdmin(username: username, password: password)
        case let .updateSelectedHostApolloAdmin(username, password, displayModeOverride, alwaysUseVirtualDisplay, permissions):
            performUpdateSelectedHostApolloAdmin(
                username: username,
                password: password,
                displayModeOverride: displayModeOverride,
                alwaysUseVirtualDisplay: alwaysUseVirtualDisplay,
                permissions: permissions
            )
        case let .disconnectSelectedHostApolloAdmin(username, password):
            performDisconnectSelectedHostApolloAdmin(
                username: username,
                password: password
            )
        case let .unpairSelectedHostApolloAdmin(username, password):
            performUnpairSelectedHostApolloAdmin(
                username: username,
                password: password
            )
        }
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
        preferredHost: String? = nil,
        portHintsByCandidate: [String: ShadowClientGameStreamPortHint] = [:]
    ) {
        commandContinuation.yield(
            .refreshHosts(
                candidates: candidates,
                preferredHost: preferredHost,
                portHintsByCandidate: portHintsByCandidate
            )
        )
    }

    @MainActor
    private func performRefreshHosts(
        candidates: [String],
        preferredHost: String? = nil,
        portHintsByCandidate: [String: ShadowClientGameStreamPortHint] = [:]
    ) {
        let normalizedCandidates = Self.normalizedHostCandidates(candidates)
        let normalizedPortHintsByCandidate = Self.normalizedPortHintsByCandidate(
            portHintsByCandidate
        )
        latestHostCandidates = normalizedCandidates
        guard !normalizedCandidates.isEmpty else {
            refreshHostsTask?.cancel()
            refreshAppsTask?.cancel()
            hosts = []
            latestResolvedHostDescriptors = []
            apps = []
            cachedAppsByHostID = [:]
            selectedHostID = nil
            clearSelectedHostApolloAdminState()
            pendingSelectedHostID = nil
            hostState = .idle
            appState = .idle
            pairingState = .idle
            launchState = .idle
            return
        }

        if isClearingActiveSession || launchState.isTransitioning || activeSession != nil {
            logger.notice(
                "Skipping host metadata refresh while session transition is active"
            )
            return
        }

        hostState = .loading
        refreshHostsTask?.cancel()
        let metadataClient = metadataClient
        let pairingRouteStore = pairingRouteStore
        let pinnedCertificateStore = self.pinnedCertificateStore
        let logger = self.logger
        let localInterfaceHosts = ShadowClientHostCatalogKit.currentMachineInterfaceHosts()
        let probeCandidates = Self.refreshProbeCandidates(
            normalizedCandidates,
            localInterfaceHosts: localInterfaceHosts
        )
        guard !probeCandidates.isEmpty else {
            refreshHostsTask?.cancel()
            refreshAppsTask?.cancel()
            hosts = []
            latestResolvedHostDescriptors = []
            apps = []
            cachedAppsByHostID = [:]
            selectedHostID = nil
            clearSelectedHostApolloAdminState()
            pendingSelectedHostID = nil
            hostState = .loaded
            appState = .idle
            pairingState = .idle
            launchState = .idle
            return
        }
        let knownHosts = hosts.isEmpty ? latestResolvedHostDescriptors : hosts
        refreshHostsTask = Task { [weak self] in
            let persistentPreferredRoutes = await Self.persistentPreferredRouteOverrides(
                for: knownHosts,
                pairingRouteStore: pairingRouteStore
            )
            let sessionPreferredRoutes = await Self.sessionPreferredRouteOverrides(
                for: knownHosts,
                pairingRouteStore: pairingRouteStore
            )
            let preferredRoutes = Self.mergedPreferredRouteOverrides(
                persistentPreferredRoutesByKey: persistentPreferredRoutes,
                sessionPreferredRoutesByKey: sessionPreferredRoutes
            )
            let coalescedCandidates = Self.coalescedCandidatesUsingKnownHosts(
                probeCandidates,
                knownHosts: knownHosts,
                preferredHost: preferredHost,
                preferredRoutesByKey: preferredRoutes
            )
            if !knownHosts.isEmpty {
                let summary = knownHosts
                    .map { host in
                        let key = Self.mergeKey(for: host)
                        let endpoints = Self.knownHostSet(for: host)
                            .sorted()
                            .joined(separator: ",")
                        return "\(key)=\(endpoints)"
                    }
                    .sorted()
                    .joined(separator: ";")
                logger.notice("Host refresh known groups \(summary, privacy: .public)")
            }
            if coalescedCandidates != probeCandidates {
                let originalCandidatesSummary = probeCandidates.joined(separator: ",")
                let coalescedCandidatesSummary = coalescedCandidates.joined(separator: ",")
                logger.notice(
                    "Host refresh coalesced candidates from \(originalCandidatesSummary, privacy: .public) to \(coalescedCandidatesSummary, privacy: .public)"
                )
            }

            let descriptors = await withTaskGroup(
                of: ShadowClientRemoteHostDescriptor.self,
                returning: [ShadowClientRemoteHostDescriptor].self
            ) { group in
                for host in coalescedCandidates {
                    let portHint = normalizedPortHintsByCandidate[host]
                    group.addTask {
                        await Self.fetchHostDescriptor(
                            host: host,
                            portHint: portHint,
                            metadataClient: metadataClient
                        )
                    }
                }

                var resolved: [ShadowClientRemoteHostDescriptor] = []
                for await descriptor in group {
                    resolved.append(descriptor)
                }
                return resolved
            }

            let hydratedDescriptors = Self.hydrateDescriptorsUsingKnownHosts(
                descriptors,
                knownHosts: knownHosts,
                preferredRoutesByKey: preferredRoutes
            )
            let filteredDescriptors = Self.filterOutSelfHosts(
                hydratedDescriptors,
                localInterfaceHosts: localInterfaceHosts
            )
            let reconciledPersistentPreferredRoutes = Self.reconciledPreferredRoutesByKey(
                preferredRoutesByKey: persistentPreferredRoutes,
                resolvedHosts: filteredDescriptors
            )
            let reconciledSessionPreferredRoutes = Self.reconciledPreferredRoutesByKey(
                preferredRoutesByKey: sessionPreferredRoutes,
                resolvedHosts: filteredDescriptors
            )
            if reconciledPersistentPreferredRoutes != persistentPreferredRoutes {
                let allKeys = Set(persistentPreferredRoutes.keys).union(reconciledPersistentPreferredRoutes.keys)
                for key in allKeys {
                    let previousValue = persistentPreferredRoutes[key]
                    let nextValue = reconciledPersistentPreferredRoutes[key]
                    guard previousValue != nextValue else {
                        continue
                    }
                    await pairingRouteStore.setPersistentPreferredHost(nextValue, for: key)
                }
            }
            if reconciledSessionPreferredRoutes != sessionPreferredRoutes {
                let allKeys = Set(sessionPreferredRoutes.keys).union(reconciledSessionPreferredRoutes.keys)
                for key in allKeys {
                    let previousValue = sessionPreferredRoutes[key]
                    let nextValue = reconciledSessionPreferredRoutes[key]
                    guard previousValue != nextValue else {
                        continue
                    }
                    await pairingRouteStore.setSessionPreferredHost(nextValue, for: key)
                }
            }
            let reconciledPreferredRoutes = Self.mergedPreferredRouteOverrides(
                persistentPreferredRoutesByKey: reconciledPersistentPreferredRoutes,
                sessionPreferredRoutesByKey: reconciledSessionPreferredRoutes
            )
            let sorted = filteredDescriptors.sorted(by: Self.compareHosts)
            let pairedHostKeys = await Self.pairedHostKeys(
                for: sorted,
                existingHosts: knownHosts,
                pinnedCertificateStore: pinnedCertificateStore
            )
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                self.latestResolvedHostDescriptors = sorted
                let preferredNormalized = Self.normalizeCandidate(preferredHost)
                let mergedHosts = Self.mergeResolvedHosts(
                    sorted,
                    selectedHostID: self.selectedHostID,
                    preferredHost: preferredNormalized,
                    preferredRoutesByKey: reconciledPreferredRoutes,
                    pairedHostKeys: pairedHostKeys
                )
                let mergedSummary = mergedHosts
                    .map { host in
                        let endpoints = host.routes.allEndpoints
                            .map(\.host)
                            .joined(separator: ",")
                        return "\(host.displayName)=\(endpoints)"
                    }
                    .joined(separator: ";")
                logger.notice("Host refresh merged hosts \(mergedSummary, privacy: .public)")
                self.hosts = mergedHosts
                self.persistence.saveCachedHosts(mergedHosts)

                if mergedHosts.isEmpty {
                    self.hostState = .failed("No hosts resolved.")
                    self.selectedHostID = nil
                    self.apps = []
                    self.appState = .idle
                    return
                }

                self.hostState = .loaded

                if let pendingSelectedHostID = self.pendingSelectedHostID,
                   mergedHosts.contains(where: { $0.id == pendingSelectedHostID })
                {
                    self.selectedHostID = pendingSelectedHostID
                    self.pendingSelectedHostID = nil
                } else {
                    self.pendingSelectedHostID = nil
                    if let selectedHostID = self.selectedHostID,
                       mergedHosts.contains(where: { $0.id == selectedHostID })
                    {
                        self.selectedHostID = selectedHostID
                    } else if let preferredNormalized,
                              let preferred = mergedHosts.first(where: { $0.host.lowercased() == preferredNormalized })
                    {
                        self.selectedHostID = preferred.id
                    } else {
                        self.selectedHostID = mergedHosts.first?.id
                    }
                }

                self.performRefreshSelectedHostApps()
            }
        }
    }

    @MainActor
    public func pairSelectedHost() {
        commandContinuation.yield(.pairSelectedHost)
    }

    @MainActor
    public func deleteHost(_ hostID: String) {
        commandContinuation.yield(.deleteHost(hostID))
    }

    @MainActor
    private func performPairSelectedHost() {
        guard let selectedHost else {
            pairingState = .failed("Select host first.")
            return
        }
        pairTask?.cancel()
        pairGeneration &+= 1
        let currentPairGeneration = pairGeneration
        let controlClient = controlClient
        let pairingRouteStore = pairingRouteStore
        let currentHosts = latestResolvedHostDescriptors.isEmpty ? hosts : latestResolvedHostDescriptors
        let currentLatestHostCandidates = latestHostCandidates
        pairTask = Task { [weak self] in
            do {
                let storedPreferredPairHost = await Self.effectivePreferredRoute(
                    for: selectedHost,
                    pairingRouteStore: pairingRouteStore
                )
                let pairCandidates = Self.pairHostCandidates(
                    for: selectedHost,
                    hosts: currentHosts,
                    latestHostCandidates: currentLatestHostCandidates,
                    preferredPairHost: storedPreferredPairHost
                )

                let generatedPIN = await MainActor.run { [weak self] in
                    let pin = self?.pinProvider.nextPIN() ?? "0000"
                    self?.pairingState = .pairing(
                        host: selectedHost.displayName.isEmpty ? selectedHost.host : selectedHost.displayName,
                        pin: pin
                    )
                    return pin
                }

                let pairingDeadline = Date().addingTimeInterval(
                    ShadowClientPairingDefaults.retryDeadlineSeconds
                )
                let maximumPairAttempts = ShadowClientPairingDefaults.maximumAttempts
                var lastError: Error?
                var pairedHost: String?

                candidateLoop: for candidate in pairCandidates {
                    var pairAttemptCount = 0
                    while true {
                        pairAttemptCount += 1
                        do {
                            _ = try await controlClient.pair(
                                host: candidate.host,
                                pin: generatedPIN,
                                appVersion: selectedHost.appVersion,
                                httpsPort: candidate.httpsPort
                            )
                            pairedHost = candidate.host
                            await pairingRouteStore.setSessionPreferredHost(
                                candidate.host,
                                for: Self.sessionRouteStoreKey(for: selectedHost)
                            )
                            if let persistentRouteKey = Self.persistentRouteStoreKey(for: selectedHost) {
                                await pairingRouteStore.setPersistentPreferredHost(
                                    candidate.host,
                                    for: persistentRouteKey
                                )
                            }
                            break candidateLoop
                        } catch {
                            lastError = error

                            if Self.shouldAdvanceToNextPairHost(error: error) {
                                break
                            }

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
                }

                if let lastError, pairedHost == nil {
                    throw lastError
                }

                if Task.isCancelled {
                    await MainActor.run { [weak self] in
                        guard let self,
                              self.pairGeneration == currentPairGeneration,
                              self.pairingState.isInProgress
                        else {
                            return
                        }
                        self.pairingState = .idle
                    }
                    return
                }

                await MainActor.run { [weak self] in
                    guard let self,
                          self.pairGeneration == currentPairGeneration
                    else {
                        return
                    }
                    self.pairingState = .paired("Paired")
                    self.hosts = self.hosts.map {
                        Self.markHostAsPaired(
                            $0,
                            matching: selectedHost,
                            preferredHost: pairedHost
                        )
                    }
                    self.latestResolvedHostDescriptors = self.latestResolvedHostDescriptors.map {
                        Self.markHostAsPaired(
                            $0,
                            matching: selectedHost,
                            preferredHost: pairedHost
                        )
                    }
                    self.performRefreshSelectedHostApps()
                    let candidates = self.latestHostCandidates.isEmpty
                        ? ShadowClientHostCatalogKit.cachedCandidateHosts(from: self.hosts)
                        : self.latestHostCandidates
                    self.refreshHosts(
                        candidates: candidates,
                        preferredHost: pairedHost ?? selectedHost.host
                    )
                }
            } catch {
                if Task.isCancelled {
                    await MainActor.run { [weak self] in
                        guard let self,
                              self.pairGeneration == currentPairGeneration,
                              self.pairingState.isInProgress
                        else {
                            return
                        }
                        self.pairingState = .idle
                    }
                    return
                }

                await MainActor.run { [weak self] in
                    guard let self,
                          self.pairGeneration == currentPairGeneration
                    else {
                        return
                    }
                    self.pairingState = .failed(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func performDeleteHost(_ hostID: String) {
        guard let host = hosts.first(where: { $0.id == hostID }) else {
            return
        }

        let sessionRouteKey = Self.sessionRouteStoreKey(for: host)
        let persistentRouteKey = Self.persistentRouteStoreKey(for: host)
        let remainingHosts = hosts.filter { $0.id != hostID }

        hosts = remainingHosts
        latestResolvedHostDescriptors = latestResolvedHostDescriptors.filter { $0.id != hostID }
        cachedAppsByHostID.removeValue(forKey: hostID)
        persistence.saveCachedHosts(remainingHosts)

        if selectedHostID == hostID {
            selectedHostID = remainingHosts.first?.id
            apps = []
            appState = remainingHosts.isEmpty ? .idle : appState
            clearSelectedHostApolloAdminState()
        }

        Task {
            await self.pairingRouteStore.setSessionPreferredHost(nil, for: sessionRouteKey)
            if let persistentRouteKey {
                await self.pairingRouteStore.setPersistentPreferredHost(nil, for: persistentRouteKey)
            }
            for endpoint in host.routes.allEndpoints {
                await self.pinnedCertificateStore.removeCertificate(forHost: endpoint.host)
            }
        }
    }

    @MainActor
    public func pullClipboard() {
        commandContinuation.yield(.pullClipboard)
    }

    @MainActor
    public func syncClipboard(_ text: String) {
        commandContinuation.yield(.syncClipboard(text))
    }

    @MainActor
    public func launchSelectedApp(
        appID: Int,
        appTitle: String? = nil,
        forceLaunch: Bool = false,
        settings: ShadowClientGameStreamLaunchSettings
    ) {
        commandContinuation.yield(
            .launchSelectedApp(
                appID: appID,
                appTitle: appTitle,
                forceLaunch: forceLaunch,
                settings: settings
            )
        )
    }

    @MainActor
    private func performLaunchSelectedApp(
        appID: Int,
        appTitle: String? = nil,
        forceLaunch: Bool,
        settings: ShadowClientGameStreamLaunchSettings
    ) {
        guard let selectedHost else {
            launchState = .failed("Select host first.")
            return
        }

        let selectedHostKey = Self.mergeKey(for: selectedHost)
        let launchedAppTitle = appTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let launchSettingsToUse = Self.normalizeAudioLaunchSettings(
            Self.normalizeCodecLaunchSettings(
                launchSettingsApplyingPersistentFallback(settings),
                serverCodecModeSupport: selectedHost.serverCodecModeSupport
            ),
            maximumOutputChannels: ShadowClientAudioOutputCapabilityKit.currentMaximumOutputChannels()
        )
        let currentFingerprint = Self.sessionFingerprint(
            hostKey: selectedHostKey,
            appID: appID,
            settings: launchSettingsToUse
        )
        let previouslyAppliedSettings = lastConnectedLaunchSettings ?? lastLaunchRequestContext?.settings
        let launchContextMatchesCurrentGame = lastLaunchRequestContext?.hostKey == selectedHostKey &&
            lastLaunchRequestContext?.appID == appID
        let settingsChangedForCurrentGame = selectedHost.currentGameID == appID &&
            launchContextMatchesCurrentGame &&
            previouslyAppliedSettings != nil &&
            previouslyAppliedSettings != launchSettingsToUse
        let localFingerprintMatchesActiveGame = selectedHost.currentGameID == appID &&
            Self.sessionFingerprintMatches(
                lastLocalSessionFingerprint,
                currentFingerprint,
                requestedCodec: launchSettingsToUse.preferredCodec
            )
        let negotiatedCodecMismatchForCurrentGame = selectedHost.currentGameID == appID &&
            Self.sessionSettingsMatch(lastLocalSessionFingerprint, currentFingerprint) &&
            !localFingerprintMatchesActiveGame
        let activeGameSettingsUnknown = selectedHost.currentGameID == appID &&
            !localFingerprintMatchesActiveGame &&
            !settingsChangedForCurrentGame &&
            !negotiatedCodecMismatchForCurrentGame
        let effectiveForceLaunch = forceLaunch ||
            settingsChangedForCurrentGame ||
            negotiatedCodecMismatchForCurrentGame ||
            activeGameSettingsUnknown
        let isReconfiguringActiveSession =
            activeSession?.appID == appID &&
            activeSession?.host.lowercased() == selectedHost.host.lowercased()
        let isResumingActiveHostSession =
            selectedHost.currentGameID == appID &&
            !effectiveForceLaunch
        let preserveLocalSessionState =
            isReconfiguringActiveSession &&
            !isResumingActiveHostSession
        launchState = preserveLocalSessionState
            ? .optimizing("Optimizing Display...")
            : .launching
        clearSessionIssueState()
        stopInputKeepAliveLoop()
        if !preserveLocalSessionState {
            activeSession = nil
            lastKnownSessionURL = nil
        }
        let previousLaunchTask = launchTask
        previousLaunchTask?.cancel()
        launchGeneration &+= 1
        let currentLaunchGeneration = launchGeneration
        let controlClient = controlClient
        let sessionConnectionClient = sessionConnectionClient
        let latestResolvedHostDescriptors = latestResolvedHostDescriptors
        let pairingRouteStore = pairingRouteStore
        let runtimeLogger = logger
        if settingsChangedForCurrentGame {
            logger.notice(
                "Launch settings changed for active game appID=\(appID, privacy: .public); forcing relaunch instead of resume"
            )
        }
        if negotiatedCodecMismatchForCurrentGame,
           let negotiatedVideoCodec = lastLocalSessionFingerprint?.negotiatedVideoCodec?.rawValue {
            logger.notice(
                "Last negotiated codec \(negotiatedVideoCodec, privacy: .public) is incompatible with requested codec mode \(launchSettingsToUse.preferredCodec.rawValue, privacy: .public) for active game appID=\(appID, privacy: .public); forcing relaunch instead of resume"
            )
        }
        if activeGameSettingsUnknown {
            logger.notice(
                "Active game appID=\(appID, privacy: .public) on host key \(selectedHostKey, privacy: .public) has no matching local session fingerprint; forcing relaunch instead of resume"
            )
        }
        lastLaunchRequestContext = .init(
            hostKey: selectedHostKey,
            appID: appID,
            appTitle: launchedAppTitle,
            settings: launchSettingsToUse
        )
        launchTask = Task { [weak self] in
            if let previousLaunchTask {
                await previousLaunchTask.value
            }

            if Task.isCancelled {
                await sessionConnectionClient.disconnect()
                await MainActor.run { [weak self] in
                    guard let self,
                          self.launchGeneration == currentLaunchGeneration,
                          self.launchState.isTransitioning
                    else {
                        return
                    }
                    self.launchState = .idle
                    self.activeSession = nil
                    self.lastKnownSessionURL = nil
                }
                return
            }

            do {
                await sessionConnectionClient.disconnect()
                var resolvedHostDescriptor = await Self.preferredRuntimeHostDescriptor(
                    for: selectedHost,
                    latestResolvedHostDescriptors: latestResolvedHostDescriptors,
                    pairingRouteStore: pairingRouteStore
                )

                let initialLaunchResult: ShadowClientGameStreamLaunchResult
                do {
                    initialLaunchResult = try await controlClient.launch(
                        host: resolvedHostDescriptor.host,
                        httpsPort: resolvedHostDescriptor.httpsPort,
                        appID: appID,
                        currentGameID: resolvedHostDescriptor.currentGameID,
                        forceLaunch: effectiveForceLaunch,
                        settings: launchSettingsToUse
                    )
                } catch {
                    guard Self.shouldRetryLaunchOnAlternateRoute(error),
                          let alternateHostDescriptor = Self.alternateRuntimeHostDescriptor(
                              afterFailureOn: resolvedHostDescriptor,
                              selectedHost: selectedHost,
                              latestResolvedHostDescriptors: latestResolvedHostDescriptors
                          )
                    else {
                        throw error
                    }

                    runtimeLogger.notice(
                        "Launch failed on runtime host \(resolvedHostDescriptor.host, privacy: .public); retrying alternate route \(alternateHostDescriptor.host, privacy: .public)"
                    )
                    resolvedHostDescriptor = alternateHostDescriptor
                    initialLaunchResult = try await controlClient.launch(
                        host: resolvedHostDescriptor.host,
                        httpsPort: resolvedHostDescriptor.httpsPort,
                        appID: appID,
                        currentGameID: resolvedHostDescriptor.currentGameID,
                        forceLaunch: effectiveForceLaunch,
                        settings: launchSettingsToUse
                    )
                }

                let resolvedTitle: String
                if let launchedAppTitle, !launchedAppTitle.isEmpty {
                    resolvedTitle = launchedAppTitle
                } else {
                    resolvedTitle = "App \(appID)"
                }

                var connectedLaunchResult = initialLaunchResult
                var connectedSessionURL = try Self.validatedSessionURL(
                    from: initialLaunchResult,
                    runtimeHost: resolvedHostDescriptor.host
                )
                var connectedSettings = launchSettingsToUse

                do {
                    try await Self.connectWithCodecFallback(
                        sessionConnectionClient: sessionConnectionClient,
                        sessionURL: connectedSessionURL,
                        host: resolvedHostDescriptor.host,
                        appTitle: resolvedTitle,
                        settings: launchSettingsToUse,
                        remoteInputKey: initialLaunchResult.remoteInputKey,
                        remoteInputKeyID: initialLaunchResult.remoteInputKeyID,
                        serverAppVersion: resolvedHostDescriptor.appVersion
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
                        from: launchSettingsToUse,
                        connectError: error
                    )
                    let forcedLaunchResult = try await controlClient.launch(
                        host: resolvedHostDescriptor.host,
                        httpsPort: resolvedHostDescriptor.httpsPort,
                        appID: appID,
                        currentGameID: resolvedHostDescriptor.currentGameID,
                        forceLaunch: true,
                        settings: forcedLaunchSettings
                    )
                    let forcedSessionURL = try Self.validatedSessionURL(
                        from: forcedLaunchResult,
                        runtimeHost: resolvedHostDescriptor.host
                    )

                    await MainActor.run { [weak self] in
                        self?.persistCodecFallbackIfNeeded(
                            attemptedPreferredCodec: launchSettingsToUse.preferredCodec,
                            fallbackSettings: forcedLaunchSettings
                        )
                    }

                    try await Self.connectWithCodecFallback(
                        sessionConnectionClient: sessionConnectionClient,
                        sessionURL: forcedSessionURL,
                        host: resolvedHostDescriptor.host,
                        appTitle: resolvedTitle,
                        settings: forcedLaunchSettings,
                        remoteInputKey: forcedLaunchResult.remoteInputKey,
                        remoteInputKeyID: forcedLaunchResult.remoteInputKeyID,
                        serverAppVersion: resolvedHostDescriptor.appVersion
                    )

                    connectedLaunchResult = forcedLaunchResult
                    connectedSessionURL = forcedSessionURL
                    connectedSettings = forcedLaunchSettings
                }

                if Task.isCancelled {
                    await sessionConnectionClient.disconnect()
                    await MainActor.run { [weak self] in
                        guard let self,
                              self.launchGeneration == currentLaunchGeneration,
                              self.launchState.isTransitioning
                        else {
                            return
                        }
                        self.launchState = .idle
                        self.activeSession = nil
                        self.lastKnownSessionURL = nil
                    }
                    return
                }

                await MainActor.run { [weak self] in
                    guard let self,
                          self.launchGeneration == currentLaunchGeneration
                    else {
                        return
                    }
                    self.runtimeStreamReconnectInProgress = false
                    self.runtimeCodecRecoveryInProgress = false

                    self.activeSession = ShadowClientActiveRemoteSession(
                        host: resolvedHostDescriptor.host,
                        appID: appID,
                        appTitle: resolvedTitle,
                        sessionURL: connectedSessionURL
                    )
                    self.lastConnectedLaunchSettings = connectedSettings
                    let negotiatedVideoCodec = self.sessionSurfaceContext.activeVideoCodec
                    let connectedFingerprint = Self.sessionFingerprint(
                        hostKey: selectedHostKey,
                        appID: appID,
                        settings: connectedSettings,
                        negotiatedVideoCodec: negotiatedVideoCodec
                    )
                    self.lastLocalSessionFingerprint = connectedFingerprint
                    self.persistence.saveSessionFingerprint(connectedFingerprint)
                    if let negotiatedVideoCodec,
                       connectedSettings.preferredCodec != .auto,
                       negotiatedVideoCodec.rawValue != connectedSettings.preferredCodec.rawValue {
                        self.logger.notice(
                            "Connected session negotiated codec \(negotiatedVideoCodec.rawValue, privacy: .public) while requested codec was \(connectedSettings.preferredCodec.rawValue, privacy: .public)"
                        )
                    }
                    self.lastKnownSessionURL = Self.normalizedSessionURL(connectedSessionURL)
                    self.clearSessionIssueState()
                    Task {
                        await self.pairingRouteStore.setSessionPreferredHost(
                            resolvedHostDescriptor.host,
                            for: Self.sessionRouteStoreKey(for: selectedHost)
                        )
                        if let persistentRouteKey = Self.persistentRouteStoreKey(for: selectedHost) {
                            await self.pairingRouteStore.setPersistentPreferredHost(
                                resolvedHostDescriptor.host,
                                for: persistentRouteKey
                            )
                        }
                    }
                    if self.sessionPresentationMode == .externalRuntime {
                        self.launchState = .launched(
                            "Remote desktop launched (\(connectedLaunchResult.verb)): \(resolvedTitle) on \(resolvedHostDescriptor.host)"
                        )
                    } else {
                        self.launchState = .launched("Remote session transport connected (\(connectedLaunchResult.verb)): \(connectedSessionURL)")
                    }
                    self.startInputKeepAliveLoop()
                }
            } catch {
                if Task.isCancelled {
                    await sessionConnectionClient.disconnect()
                    await MainActor.run { [weak self] in
                        guard let self,
                              self.launchGeneration == currentLaunchGeneration,
                              self.launchState.isTransitioning
                        else {
                            return
                        }
                        self.launchState = .idle
                        self.activeSession = nil
                        self.lastKnownSessionURL = nil
                    }
                    return
                }

                await MainActor.run { [weak self] in
                    guard let self,
                          self.launchGeneration == currentLaunchGeneration
                    else {
                        return
                    }
                    self.runtimeStreamReconnectInProgress = false
                    self.runtimeCodecRecoveryInProgress = false
                    self.launchState = .failed(
                        Self.userFacingLaunchFailureMessage(
                            error,
                            settings: settings
                        )
                    )
                    self.stopInputKeepAliveLoop()
                    self.activeSession = nil
                    self.lastKnownSessionURL = nil
                }
            }
        }
    }

    @MainActor
    public func clearActiveSession() {
        commandContinuation.yield(.clearActiveSession)
    }

    @MainActor
    public func suspendActiveSessionForAppLifecycle() async {
        let previousLaunchTask = prepareActiveSessionClear()
        await completeActiveSessionClear(previousLaunchTask: previousLaunchTask)
    }

    @MainActor
    private func performClearActiveSession() {
        let selectedHost = selectedHost
        let latestResolvedHostDescriptors = latestResolvedHostDescriptors
        let latestHostCandidates = latestHostCandidates
        let controlClient = controlClient
        let pairingRouteStore = pairingRouteStore
        let previousLaunchTask = prepareActiveSessionClear()
        Task {
            await completeActiveSessionClear(
                previousLaunchTask: previousLaunchTask,
                selectedHost: selectedHost,
                latestResolvedHostDescriptors: latestResolvedHostDescriptors,
                latestHostCandidates: latestHostCandidates,
                controlClient: controlClient,
                pairingRouteStore: pairingRouteStore
            )
        }
    }

    @MainActor
    private func prepareActiveSessionClear() -> Task<Void, Never>? {
        let previousLaunchTask = launchTask
        previousLaunchTask?.cancel()
        launchTask = nil
        refreshHostsTask?.cancel()
        refreshHostsTask = nil
        refreshAppsTask?.cancel()
        refreshAppsTask = nil
        activeSessionCancelTask?.cancel()
        activeSessionCancelTask = nil
        launchGeneration &+= 1
        isClearingActiveSession = true

        activeSession = nil
        lastKnownSessionURL = nil
        lastLaunchRequestContext = nil
        clearSessionIssueState()
        runtimeStreamReconnectInProgress = false
        runtimeCodecRecoveryInProgress = false
        stopInputKeepAliveLoop()
        launchState = .idle
        return previousLaunchTask
    }

    private func completeActiveSessionClear(
        previousLaunchTask: Task<Void, Never>?,
        selectedHost: ShadowClientRemoteHostDescriptor? = nil,
        latestResolvedHostDescriptors: [ShadowClientRemoteHostDescriptor] = [],
        latestHostCandidates: [String] = [],
        controlClient: (any ShadowClientGameStreamControlClient)? = nil,
        pairingRouteStore: ShadowClientPairingRouteStore? = nil
    ) async {
        let sessionConnectionClient = sessionConnectionClient
        let inputSendQueue = inputSendQueue
        if let previousLaunchTask {
            await previousLaunchTask.value
        }
        await inputSendQueue.clear()
        await sessionConnectionClient.disconnect()
        var cancelRequest: (host: String, httpsPort: Int, refreshCandidates: [String])?
        if let selectedHost,
           selectedHost.currentGameID > 0,
           let pairingRouteStore
        {
            let runtimeHost = await Self.preferredRuntimeHostDescriptor(
                for: selectedHost,
                latestResolvedHostDescriptors: latestResolvedHostDescriptors,
                pairingRouteStore: pairingRouteStore
            )
            let candidates = latestHostCandidates.isEmpty
                ? ShadowClientHostCatalogKit.cachedCandidateHosts(from: [selectedHost])
                : latestHostCandidates
            cancelRequest = (runtimeHost.host, runtimeHost.httpsPort, candidates)
        }

        await MainActor.run { [weak self] in
            guard let self else {
                return
            }
            self.isClearingActiveSession = false

            guard let cancelRequest, let controlClient else {
                return
            }

            self.activeSessionCancelTask?.cancel()
            self.activeSessionCancelTask = Task { [weak self] in
                try? await controlClient.cancelActiveSession(
                    host: cancelRequest.host,
                    httpsPort: cancelRequest.httpsPort
                )
                guard !Task.isCancelled else {
                    return
                }
                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    self.refreshHosts(
                        candidates: cancelRequest.refreshCandidates,
                        preferredHost: cancelRequest.host
                    )
                    self.activeSessionCancelTask = nil
                }
            }
        }
    }

    @MainActor
    public func sendInput(_ event: ShadowClientRemoteInputEvent) {
        commandContinuation.yield(.sendInput(event))
    }

    @MainActor
    public func handleSessionRenderStateTransition(
        _ state: ShadowClientRealtimeSessionSurfaceContext.RenderState
    ) {
        switch state {
        case let .disconnected(message):
        if let hostTerminationIssue = ShadowClientRemoteSessionIssueKit.hostTerminationSessionIssue(message: message) {
            sessionIssue = hostTerminationIssue
        }
            return
        case let .failed(message):
            if attemptRuntimeStreamReconnect(afterFailureMessage: message) {
                return
            }
            attemptRuntimeCodecRecovery(afterFailureMessage: message)
        case .idle, .connecting, .waitingForFirstFrame, .rendering:
            return
        }
    }

    @MainActor
    private func performSendInput(_ event: ShadowClientRemoteInputEvent) async {
        guard let destination = activeSessionInputDestination() else {
            return
        }

        await inputSendQueue.enqueue(
            event: event,
            host: destination.host,
            sessionURL: destination.sessionURL
        )
    }

    @MainActor
    private func performSendInputKeepAlive() async {
        guard case .launched = launchState,
              let destination = activeSessionInputDestination()
        else {
            return
        }

        do {
            try await sessionInputClient.sendKeepAlive(
                host: destination.host,
                sessionURL: destination.sessionURL
            )
        } catch {
            if Self.shouldSuppressInputSendError(error) {
                return
            }
            logger.debug("Remote input keepalive failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func performSyncClipboard(_ text: String) async {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return
        }

        guard case .launched = launchState,
              let endpoint = activeSessionClipboardEndpoint()
        else {
            return
        }

        do {
            try await controlClient.setClipboard(
                host: endpoint.host,
                httpsPort: endpoint.httpsPort,
                text: normalized
            )
            lastSynchronizedClipboardText = normalized
            clearClipboardWriteIssue()
        } catch {
            setClipboardIssue(for: .write, error: error)
            logger.error(
                "Apollo clipboard sync failed for host=\(endpoint.host, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    @MainActor
    private func performSyncClipboardIfNeeded() async {
        guard case .launched = launchState,
              let localClipboard = await clipboardClient.currentString()
        else {
            return
        }

        let normalized = localClipboard.replacingOccurrences(of: "\r\n", with: "\n")
        guard !normalized.isEmpty,
              normalized != lastSynchronizedClipboardText
        else {
            return
        }

        await performSyncClipboard(normalized)
    }

    @MainActor
    private func performPullClipboard() async {
        guard case .launched = launchState,
              let destination = activeSessionInputDestination(),
              let endpoint = activeSessionClipboardEndpoint()
        else {
            return
        }

        do {
            // Trigger copy on the remote app first, then read the host clipboard.
            await inputSendQueue.enqueue(
                event: .keyDown(keyCode: 0x37, characters: nil),
                host: destination.host,
                sessionURL: destination.sessionURL
            )
            await inputSendQueue.enqueue(
                event: .keyDown(keyCode: 0x08, characters: "c"),
                host: destination.host,
                sessionURL: destination.sessionURL
            )
            await inputSendQueue.enqueue(
                event: .keyUp(keyCode: 0x08, characters: "c"),
                host: destination.host,
                sessionURL: destination.sessionURL
            )
            await inputSendQueue.enqueue(
                event: .keyUp(keyCode: 0x37, characters: nil),
                host: destination.host,
                sessionURL: destination.sessionURL
            )
            try? await Task.sleep(for: .milliseconds(120))
            let remoteClipboard = try await controlClient.getClipboard(
                host: endpoint.host,
                httpsPort: endpoint.httpsPort
            )
            let normalized = remoteClipboard.replacingOccurrences(of: "\r\n", with: "\n")
            guard !normalized.isEmpty else {
                clearClipboardReadIssue()
                return
            }
            await clipboardClient.setString(normalized)
            lastSynchronizedClipboardText = normalized
            clearClipboardReadIssue()
        } catch {
            setClipboardIssue(for: .read, error: error)
            logger.error(
                "Apollo clipboard pull failed for host=\(endpoint.host, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    @MainActor
    private func activeSessionInputDestination() -> (host: String, sessionURL: String)? {
        guard let activeSession else {
            return nil
        }

        let resolvedSessionURL = Self.normalizedSessionURL(activeSession.sessionURL)
            ?? lastKnownSessionURL
            ?? Self.normalizedSessionURL(
                ShadowClientRTSPProtocolProfile.withRTSPSchemeIfMissing(activeSession.host)
            )
        guard let sessionURL = resolvedSessionURL else {
            return nil
        }

        lastKnownSessionURL = sessionURL
        return (host: activeSession.host, sessionURL: sessionURL)
    }

    @MainActor
    private func activeSessionClipboardEndpoint() -> (host: String, httpsPort: Int)? {
        guard let activeSession else {
            return nil
        }

        if let selectedHost {
            if let matchingEndpoint = selectedHost.routes.allEndpoints.first(where: {
                $0.host.lowercased() == activeSession.host.lowercased()
            }) {
                return (host: matchingEndpoint.host, httpsPort: matchingEndpoint.httpsPort)
            }
            return (host: activeSession.host, httpsPort: selectedHost.httpsPort)
        }

        return (host: activeSession.host, httpsPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort)
    }

    @MainActor
    private func startInputKeepAliveLoop() {
        stopInputKeepAliveLoop()
        guard inputKeepAliveInterval > .zero else {
            return
        }

        inputKeepAliveTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self.inputKeepAliveInterval)
                } catch {
                    break
                }

                guard !Task.isCancelled else {
                    break
                }
                await MainActor.run { [weak self] in
                    _ = self?.commandContinuation.yield(.sendInputKeepAlive)
                }
            }
        }
    }

    @MainActor
    private func stopInputKeepAliveLoop() {
        inputKeepAliveTask?.cancel()
        inputKeepAliveTask = nil
    }

    @MainActor
    private func startClipboardSyncLoop() {
        stopClipboardSyncLoop()
        guard clipboardSyncInterval > .zero else {
            return
        }

        clipboardSyncTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self.clipboardSyncInterval)
                } catch {
                    break
                }

                guard !Task.isCancelled else {
                    break
                }

                await MainActor.run { [weak self] in
                    _ = self?.commandContinuation.yield(.syncClipboardIfNeeded)
                    _ = self?.commandContinuation.yield(.pullClipboard)
                }
            }
        }
    }

    @MainActor
    private func stopClipboardSyncLoop() {
        clipboardSyncTask?.cancel()
        clipboardSyncTask = nil
    }

    @MainActor
    private func clearSessionIssueState() {
        clipboardReadPermissionDenied = false
        clipboardWritePermissionDenied = false
        clipboardActionRequiresActiveStream = false
        hostTerminationIssue = nil
        sessionIssue = nil
    }

    @MainActor
    private func clearClipboardWriteIssue() {
        clipboardWritePermissionDenied = false
        clipboardActionRequiresActiveStream = false
        refreshSessionIssue()
    }

    @MainActor
    private func clearClipboardReadIssue() {
        clipboardReadPermissionDenied = false
        clipboardActionRequiresActiveStream = false
        refreshSessionIssue()
    }

    @MainActor
    private func setClipboardIssue(
        for operation: ShadowClientRemoteSessionIssueKit.ClipboardOperation,
        error: Error
    ) {
        guard let issue = Self.classifyClipboardIssue(error, operation: operation) else {
            return
        }

        switch issue {
        case .readPermissionDenied:
            clipboardReadPermissionDenied = true
        case .writePermissionDenied:
            clipboardWritePermissionDenied = true
        case .requiresActiveStream:
            clipboardActionRequiresActiveStream = true
        }
        refreshSessionIssue()
    }

    @MainActor
    private func refreshSessionIssue() {
        sessionIssue = hostTerminationIssue ?? Self.sessionIssue(
            clipboardReadPermissionDenied: clipboardReadPermissionDenied,
            clipboardWritePermissionDenied: clipboardWritePermissionDenied,
            clipboardActionRequiresActiveStream: clipboardActionRequiresActiveStream
        )
    }

    @MainActor
    func reportHostTerminationIssue(message: String) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        hostTerminationIssue = .init(
            title: "Host Desktop Paused",
            message: "\(trimmed)\nReturn to the normal Windows desktop, dismiss the popup or secure prompt, then launch the session again."
        )
        refreshSessionIssue()
    }

    private static func classifyClipboardIssue(
        _ error: Error,
        operation: ShadowClientRemoteSessionIssueKit.ClipboardOperation
    ) -> ShadowClientRemoteSessionIssueKit.ClipboardIssueKind? {
        ShadowClientRemoteSessionIssueKit.classifyClipboardIssue(
            error,
            operation: operation
        )
    }

    private static func sessionIssue(
        clipboardReadPermissionDenied: Bool,
        clipboardWritePermissionDenied: Bool,
        clipboardActionRequiresActiveStream: Bool
    ) -> ShadowClientRemoteSessionIssue? {
        ShadowClientRemoteSessionIssueKit.sessionIssue(
            clipboardReadPermissionDenied: clipboardReadPermissionDenied,
            clipboardWritePermissionDenied: clipboardWritePermissionDenied,
            clipboardActionRequiresActiveStream: clipboardActionRequiresActiveStream
        )
    }

    private static func normalizedSessionURL(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private enum ApolloPermissionCapability {
        case listApps
        case launchApps
    }

    private static func apolloPermissionDeniedMessage(
        _ error: any Error,
        capability: ApolloPermissionCapability
    ) -> String? {
        guard case let ShadowClientGameStreamError.responseRejected(code, message) = error,
              code == 403,
              message.trimmingCharacters(in: .whitespacesAndNewlines)
                  .localizedCaseInsensitiveContains("permission denied")
        else {
            return nil
        }

        switch capability {
        case .listApps:
            return "Apollo denied List Apps permission for this paired client."
        case .launchApps:
            return "Apollo denied Launch Apps permission for this paired client."
        }
    }

    private static func shouldSuppressInputSendError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if (nsError.domain == "Network.NWError" && nsError.code == 89) ||
            (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
        {
            return true
        }

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

        if let controlError = error as? ShadowClientHostControlChannelError {
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
            normalized.contains("operation cancelled") ||
            normalized.contains("nwerror error 89") ||
            normalized.contains("connection closed")
        {
            return true
        }

        return false
    }

    private static func shouldThrottleInputSendAfterError(_ error: Error) -> Bool {
        if shouldSuppressInputSendError(error) {
            return true
        }
        if let runtimeError = error as? ShadowClientRealtimeSessionRuntimeError {
            switch runtimeError {
            case .connectionClosed:
                return true
            default:
                break
            }
        }
        return false
    }

    private static func shouldRetryRuntimeStreamReconnect(failureMessage: String) -> Bool {
        let normalized = failureMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return false
        }

        if isStartupVideoDatagramFailure(normalizedError: normalized) {
            return true
        }

        // Inactivity/stall class errors should stay in-session recovery only.
        // Runtime relaunch is reserved for explicit transport-termination class errors.
        let reconnectSignatures = [
            "no message available on stream",
            "rtsp transport connection closed",
            "transport connection timed out",
            "connection reset by peer",
            "network.nwerror error 96",
        ]
        return reconnectSignatures.contains(where: normalized.contains)
    }

    @MainActor
    @discardableResult
    private func attemptRuntimeStreamReconnect(afterFailureMessage message: String) -> Bool {
        guard !runtimeStreamReconnectInProgress,
              !runtimeCodecRecoveryInProgress
        else {
            return false
        }
        guard let launchRequest = lastLaunchRequestContext else {
            return false
        }
        guard Self.shouldRetryRuntimeStreamReconnect(failureMessage: message) else {
            return false
        }

        let shouldAttemptRecoveryFromLaunchState: Bool
        switch launchState {
        case .launched, .launching, .optimizing:
            shouldAttemptRecoveryFromLaunchState = true
        case .idle, .failed:
            shouldAttemptRecoveryFromLaunchState = false
        }
        let activeSessionMatchesLaunchRequest = activeSession?.appID == launchRequest.appID
        guard shouldAttemptRecoveryFromLaunchState || activeSessionMatchesLaunchRequest else {
            return false
        }

        let now = ProcessInfo.processInfo.systemUptime
        if lastRuntimeStreamReconnectUptime > 0,
           now - lastRuntimeStreamReconnectUptime < Self.runtimeStreamReconnectCooldownSeconds
        {
            return false
        }
        lastRuntimeStreamReconnectUptime = now
        runtimeStreamReconnectInProgress = true
        logger.notice(
            "Session runtime transport failed; attempting in-place stream reconnect for appID=\(launchRequest.appID, privacy: .public)"
        )

        launchSelectedApp(
            appID: launchRequest.appID,
            appTitle: launchRequest.appTitle,
            forceLaunch: false,
            settings: launchRequest.settings
        )
        return true
    }

    @MainActor
    private func attemptRuntimeCodecRecovery(afterFailureMessage message: String) {
        guard !runtimeCodecRecoveryInProgress,
              !runtimeStreamReconnectInProgress
        else {
            return
        }
        guard let launchRequest = lastLaunchRequestContext
        else {
            return
        }
        let shouldAttemptRecoveryFromLaunchState: Bool
        switch launchState {
        case .launched, .launching, .optimizing:
            shouldAttemptRecoveryFromLaunchState = true
        case .idle, .failed:
            shouldAttemptRecoveryFromLaunchState = false
        }
        let activeSessionMatchesLaunchRequest = activeSession?.appID == launchRequest.appID
        guard shouldAttemptRecoveryFromLaunchState || activeSessionMatchesLaunchRequest else {
            return
        }

        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMessage.isEmpty else {
            return
        }

        let decoderFailure = ShadowClientGameStreamError.requestFailed(normalizedMessage)
        guard Self.shouldRetryCodecFallback(connectError: decoderFailure) else {
            return
        }

        let fallbackSettings = Self.forcedLaunchSettings(
            from: launchRequest.settings,
            connectError: decoderFailure
        )
        guard fallbackSettings.preferredCodec != launchRequest.settings.preferredCodec else {
            return
        }

        runtimeCodecRecoveryInProgress = true
        lastLaunchRequestContext = .init(
            hostKey: launchRequest.hostKey,
            appID: launchRequest.appID,
            appTitle: launchRequest.appTitle,
            settings: fallbackSettings
        )
        logger.notice(
            "Session runtime failed after launch; attempting codec recovery relaunch \(launchRequest.settings.preferredCodec.rawValue, privacy: .public)->\(fallbackSettings.preferredCodec.rawValue, privacy: .public)"
        )
        launchSelectedApp(
            appID: launchRequest.appID,
            appTitle: launchRequest.appTitle,
            forceLaunch: true,
            settings: fallbackSettings
        )
        persistCodecFallbackIfNeeded(
            attemptedPreferredCodec: launchRequest.settings.preferredCodec,
            fallbackSettings: fallbackSettings
        )
    }

    private static func validatedSessionURL(
        from launchResult: ShadowClientGameStreamLaunchResult,
        runtimeHost: String
    ) throws -> String {
        guard let sessionURL = launchResult.sessionURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionURL.isEmpty
        else {
            throw ShadowClientGameStreamError.requestFailed(
                "Host did not return a remote session URL."
            )
        }
        return rewrittenSessionURL(sessionURL, runtimeHost: runtimeHost)
    }

    static func rewrittenSessionURL(_ sessionURL: String, runtimeHost: String) -> String {
        let trimmedSessionURL = sessionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRuntimeHost = runtimeHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !trimmedSessionURL.isEmpty,
            !trimmedRuntimeHost.isEmpty,
            var components = URLComponents(string: trimmedSessionURL)
        else {
            return trimmedSessionURL
        }

        components.host = trimmedRuntimeHost
        return components.string ?? trimmedSessionURL
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
        remoteInputKeyID: UInt32?,
        serverAppVersion: String?
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
                        remoteInputKeyID: remoteInputKeyID,
                        serverAppVersion: serverAppVersion
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
        if shouldPreferH264AfterDecoderRuntimeFailure(
            settings: settings,
            connectError: connectError
        ) {
            return launchSettings(settings, preferredCodec: .h264)
        }
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

    private static func shouldPreferH264AfterDecoderRuntimeFailure(
        settings: ShadowClientGameStreamLaunchSettings,
        connectError: any Error
    ) -> Bool {
        let isHEVCRequested = settings.preferredCodec == .h265
        let isAV1Requested = settings.preferredCodec == .av1 || settings.preferredCodec == .auto
        guard isAV1Requested || isHEVCRequested else {
            return false
        }

        let normalized = connectError.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return false
        }

        let directH264FallbackSignatures = [
            "runtime recovery exhausted",
            "decoder recovery exhausted",
            "decoder-output-stall-exhausted",
            "decoder-recovery-exhausted-monitor",
            "waiting for codec parameter sets",
            "vtvideo decoderselection",
            "vt-ds",
            "osstatus -12903",
            "osstatus -12909",
            "osstatus -17694",
        ]
        return directH264FallbackSignatures.contains(where: normalized.contains)
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

        if isStartupVideoDatagramFailure(normalizedError: normalized) {
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
            "decoder recovery exhausted",
            "decoder-output-stall-exhausted",
            "decoder-recovery-exhausted-monitor",
            "waiting for codec parameter sets",
            "hevc fallback",
            "osstatus -8971",
            "osstatus -17694",
            "vtvideo decoderselection",
            "vt-ds",
        ]

        return codecFallbackSignatures.contains(where: normalized.contains)
    }

    static func isStartupVideoDatagramFailure(
        normalizedError: String
    ) -> Bool {
        let signatures = [
            "udp video startup traffic missing",
            "no startup datagrams received",
        ]
        return signatures.contains(where: normalizedError.contains)
    }

    private static func userFacingLaunchFailureMessage(
        _ error: any Error,
        settings: ShadowClientGameStreamLaunchSettings
    ) -> String {
        if let permissionMessage = apolloPermissionDeniedMessage(
            error,
            capability: .launchApps
        ) {
            return permissionMessage
        }

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
            preferredSurroundChannelCount: settings.preferredSurroundChannelCount,
            lowLatencyMode: settings.lowLatencyMode,
            enableVSync: settings.enableVSync,
            enableFramePacing: settings.enableFramePacing,
            enableYUV444: settings.enableYUV444,
            unlockBitrateLimit: settings.unlockBitrateLimit,
            forceHardwareDecoding: settings.forceHardwareDecoding,
            resolutionScalePercent: settings.resolutionScalePercent,
            preferVirtualDisplay: settings.preferVirtualDisplay,
            optimizeGameSettingsForStreaming: settings.optimizeGameSettingsForStreaming,
            quitAppOnHostAfterStreamEnds: settings.quitAppOnHostAfterStreamEnds,
            playAudioOnHost: settings.playAudioOnHost
        )
    }

    static func normalizeCodecLaunchSettings(
        _ settings: ShadowClientGameStreamLaunchSettings,
        serverCodecModeSupport: Int
    ) -> ShadowClientGameStreamLaunchSettings {
        let normalizedCodec = normalizePreferredCodec(
            settings.preferredCodec,
            serverCodecModeSupport: serverCodecModeSupport
        )
        guard normalizedCodec != settings.preferredCodec else {
            return settings
        }
        return launchSettings(settings, preferredCodec: normalizedCodec)
    }

    private static func normalizePreferredCodec(
        _ preferredCodec: ShadowClientVideoCodecPreference,
        serverCodecModeSupport: Int
    ) -> ShadowClientVideoCodecPreference {
        if serverCodecModeSupport == 0 {
            // Sunshine always advertises ServerCodecModeSupport, but Apollo can omit it.
            // Keep the client-decoder-derived preference in that case instead of forcing H.264.
            return ShadowClientVideoCodecSupport().resolvePreferredCodec(
                preferredCodec,
                enableHDR: false,
                enableYUV444: false
            )
        }
        let supportsAV1 = (serverCodecModeSupport & ShadowClientServerCodecModeSupport.maskAV1) != 0
        let supportsHEVC = (serverCodecModeSupport & ShadowClientServerCodecModeSupport.maskHEVC) != 0

        switch preferredCodec {
        case .auto, .av1:
            if supportsAV1 {
                return preferredCodec
            }
            if supportsHEVC {
                return .h265
            }
            return .h264
        case .h265:
            return supportsHEVC ? .h265 : .h264
        case .h264:
            return .h264
        }
    }

    private static func normalizeAudioLaunchSettings(
        _ settings: ShadowClientGameStreamLaunchSettings
    ) async -> ShadowClientGameStreamLaunchSettings {
        guard settings.enableSurroundAudio else {
            return settings
        }

        let preferredChannelCount =
            await ShadowClientRealtimeAudioSessionRuntime.preferredOpusChannelCountForNegotiation(
                surroundRequested: settings.enableSurroundAudio,
                preferredSurroundChannelCount: settings.preferredSurroundChannelCount
            )

        return normalizeAudioLaunchSettings(
            settings,
            preferredOpusChannelCount: preferredChannelCount
        )
    }

    static func normalizeAudioLaunchSettings(
        _ settings: ShadowClientGameStreamLaunchSettings,
        maximumOutputChannels: Int
    ) -> ShadowClientGameStreamLaunchSettings {
        guard settings.enableSurroundAudio else {
            return settings
        }
        let preferredOpusChannelCount = max(
            2,
            min(settings.preferredSurroundChannelCount, max(1, maximumOutputChannels))
        )
        return normalizeAudioLaunchSettings(
            settings,
            preferredOpusChannelCount: preferredOpusChannelCount
        )
    }

    private static func normalizeAudioLaunchSettings(
        _ settings: ShadowClientGameStreamLaunchSettings,
        preferredOpusChannelCount: Int
    ) -> ShadowClientGameStreamLaunchSettings {
        guard settings.enableSurroundAudio else {
            return settings
        }

        guard preferredOpusChannelCount <= 2 else {
            if preferredOpusChannelCount == settings.preferredSurroundChannelCount {
                return settings
            }

            return .init(
                width: settings.width,
                height: settings.height,
                fps: settings.fps,
                bitrateKbps: settings.bitrateKbps,
                preferredCodec: settings.preferredCodec,
                enableHDR: settings.enableHDR,
                enableSurroundAudio: true,
                preferredSurroundChannelCount: preferredOpusChannelCount,
                lowLatencyMode: settings.lowLatencyMode,
                enableVSync: settings.enableVSync,
                enableFramePacing: settings.enableFramePacing,
                enableYUV444: settings.enableYUV444,
                unlockBitrateLimit: settings.unlockBitrateLimit,
                forceHardwareDecoding: settings.forceHardwareDecoding,
                resolutionScalePercent: settings.resolutionScalePercent,
                preferVirtualDisplay: settings.preferVirtualDisplay,
                optimizeGameSettingsForStreaming: settings.optimizeGameSettingsForStreaming,
                quitAppOnHostAfterStreamEnds: settings.quitAppOnHostAfterStreamEnds,
                playAudioOnHost: settings.playAudioOnHost
            )
        }

        return .init(
            width: settings.width,
            height: settings.height,
            fps: settings.fps,
            bitrateKbps: settings.bitrateKbps,
            preferredCodec: settings.preferredCodec,
            enableHDR: settings.enableHDR,
            enableSurroundAudio: false,
            preferredSurroundChannelCount: 2,
            lowLatencyMode: settings.lowLatencyMode,
            enableVSync: settings.enableVSync,
            enableFramePacing: settings.enableFramePacing,
            enableYUV444: settings.enableYUV444,
            unlockBitrateLimit: settings.unlockBitrateLimit,
            forceHardwareDecoding: settings.forceHardwareDecoding,
            resolutionScalePercent: settings.resolutionScalePercent,
            preferVirtualDisplay: settings.preferVirtualDisplay,
            optimizeGameSettingsForStreaming: settings.optimizeGameSettingsForStreaming,
            quitAppOnHostAfterStreamEnds: settings.quitAppOnHostAfterStreamEnds,
            playAudioOnHost: settings.playAudioOnHost
        )
    }

    private static func sessionVideoConfiguration(
        from settings: ShadowClientGameStreamLaunchSettings,
        preferredCodec: ShadowClientVideoCodecPreference,
        remoteInputKey: Data?,
        remoteInputKeyID: UInt32?,
        serverAppVersion: String?
    ) -> ShadowClientRemoteSessionVideoConfiguration {
        return .init(
            width: settings.width,
            height: settings.height,
            fps: settings.fps,
            bitrateKbps: settings.bitrateKbps,
            preferredCodec: preferredCodec,
            enableHDR: settings.enableHDR,
            enableSurroundAudio: settings.enableSurroundAudio,
            preferredSurroundChannelCount: settings.preferredSurroundChannelCount,
            enableYUV444: settings.enableYUV444,
            remoteInputKey: remoteInputKey,
            remoteInputKeyID: remoteInputKeyID,
            serverAppVersion: serverAppVersion
        )
    }

    private func launchSettingsApplyingPersistentFallback(
        _ settings: ShadowClientGameStreamLaunchSettings
    ) -> ShadowClientGameStreamLaunchSettings {
        let result = Self.resolvedSettingsApplyingPersistentFallback(
            settings,
            persistentFallback: persistentCodecFallback
        )
        persistentCodecFallback = result.remainingFallback
        return result.settings
    }

    static func resolvedSettingsApplyingPersistentFallback(
        _ settings: ShadowClientGameStreamLaunchSettings,
        persistentFallback: ShadowClientVideoCodecPreference?
    ) -> (settings: ShadowClientGameStreamLaunchSettings, remainingFallback: ShadowClientVideoCodecPreference?) {
        switch settings.preferredCodec {
        case .h264, .h265:
            return (settings, nil)
        case .auto, .av1:
            if let fallback = persistentFallback {
                return (Self.launchSettings(settings, preferredCodec: fallback), nil)
            }
            return (settings, nil)
        }
    }

    private static func sessionFingerprint(
        hostKey: String,
        appID: Int,
        settings: ShadowClientGameStreamLaunchSettings,
        negotiatedVideoCodec: ShadowClientVideoCodec? = nil
    ) -> ShadowClientPersistedRemoteSessionFingerprint {
        ShadowClientPersistedRemoteSessionFingerprint(
            hostKey: hostKey,
            appID: appID,
            settingsKey: [
                "\(settings.width)x\(settings.height)",
                "fps=\(settings.fps)",
                "bitrate=\(settings.bitrateKbps)",
                "codec=\(settings.preferredCodec.rawValue)",
                "hdr=\(settings.enableHDR ? 1 : 0)",
                "surround=\(settings.enableSurroundAudio ? 1 : 0)",
                "channels=\(settings.preferredSurroundChannelCount)",
                "lowlat=\(settings.lowLatencyMode ? 1 : 0)",
                "vsync=\(settings.enableVSync ? 1 : 0)",
                "framepacing=\(settings.enableFramePacing ? 1 : 0)",
                "yuv444=\(settings.enableYUV444 ? 1 : 0)",
                "unlock=\(settings.unlockBitrateLimit ? 1 : 0)",
                "hwdecode=\(settings.forceHardwareDecoding ? 1 : 0)",
                "optgame=\(settings.optimizeGameSettingsForStreaming ? 1 : 0)",
                "quit=\(settings.quitAppOnHostAfterStreamEnds ? 1 : 0)",
                "hostaudio=\(settings.playAudioOnHost ? 1 : 0)",
            ].joined(separator: "|"),
            negotiatedVideoCodec: negotiatedVideoCodec
        )
    }

    private static func sessionSettingsMatch(
        _ persisted: ShadowClientPersistedRemoteSessionFingerprint?,
        _ current: ShadowClientPersistedRemoteSessionFingerprint
    ) -> Bool {
        guard let persisted else {
            return false
        }

        return persisted.hostKey == current.hostKey &&
            persisted.appID == current.appID &&
            persisted.settingsKey == current.settingsKey
    }

    private static func sessionFingerprintMatches(
        _ persisted: ShadowClientPersistedRemoteSessionFingerprint?,
        _ current: ShadowClientPersistedRemoteSessionFingerprint,
        requestedCodec: ShadowClientVideoCodecPreference
    ) -> Bool {
        guard sessionSettingsMatch(persisted, current),
              let persisted
        else {
            return false
        }

        return negotiatedCodecIsCompatible(
            persisted.negotiatedVideoCodec,
            with: requestedCodec
        )
    }

    private static func negotiatedCodecIsCompatible(
        _ negotiatedCodec: ShadowClientVideoCodec?,
        with requestedCodec: ShadowClientVideoCodecPreference
    ) -> Bool {
        switch requestedCodec {
        case .auto:
            return true
        case .av1:
            return negotiatedCodec == .av1
        case .h265:
            return negotiatedCodec == .h265
        case .h264:
            return negotiatedCodec == .h264
        }
    }

    private func persistCodecFallbackIfNeeded(
        attemptedPreferredCodec: ShadowClientVideoCodecPreference,
        fallbackSettings: ShadowClientGameStreamLaunchSettings
    ) {
        guard fallbackSettings.preferredCodec != attemptedPreferredCodec else {
            return
        }
        persistentCodecFallback = fallbackSettings.preferredCodec
    }

    @MainActor
    public func openSessionFlow(host: String, appTitle: String = "Remote Desktop") {
        commandContinuation.yield(
            .openSessionFlow(
                host: host,
                appTitle: appTitle
            )
        )
    }

    @MainActor
    private func performOpenSessionFlow(host: String, appTitle: String = "Remote Desktop") {
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
        commandContinuation.yield(.selectHost(hostID))
    }

    @MainActor
    public func rememberPreferredRoute(_ routeHost: String?, forHostID hostID: String) async {
        guard let normalizedRouteHost = Self.normalizeCandidate(routeHost),
              !normalizedRouteHost.isEmpty
        else {
            return
        }

        guard let matchedHost = hosts.first(where: { $0.id == hostID })
            ?? latestResolvedHostDescriptors.first(where: { $0.id == hostID })
        else {
            return
        }

        guard normalizedRouteHost != matchedHost.host.lowercased() else {
            return
        }

        let mergeKey = Self.mergeKey(for: matchedHost)
        let knownHosts = hosts.isEmpty ? latestResolvedHostDescriptors : hosts
        let conflictingDescriptor = Self.bestKnownHost(
            matching: normalizedRouteHost,
            in: knownHosts
        ).flatMap { descriptor in
            Self.mergeKey(for: descriptor) == mergeKey ? nil : descriptor
        }
        if let conflictingDescriptor {
            logger.notice(
                "Host route alias skipped mergeKey=\(mergeKey, privacy: .public) alias=\(normalizedRouteHost, privacy: .public) conflictingMergeKey=\(Self.mergeKey(for: conflictingDescriptor), privacy: .public)"
            )
            return
        }

        let sessionRouteKey = Self.sessionRouteStoreKey(for: matchedHost)
        logger.notice(
            "Host route alias remembered mergeKey=\(mergeKey, privacy: .public) alias=\(normalizedRouteHost, privacy: .public)"
        )
        await pairingRouteStore.setSessionPreferredHost(normalizedRouteHost, for: sessionRouteKey)
    }

    @MainActor
    private func performSelectHost(_ hostID: String) {
        pendingSelectedHostID = hostID
        guard hosts.contains(where: { $0.id == hostID }) else {
            return
        }

        pendingSelectedHostID = nil
        selectedHostID = hostID
        clearSelectedHostApolloAdminState()
        performRefreshSelectedHostApps()
    }

    @MainActor
    public func refreshSelectedHostApps() {
        commandContinuation.yield(.refreshSelectedHostApps)
    }

    @MainActor
    public func refreshSelectedHostApolloAdmin(username: String, password: String) {
        commandContinuation.yield(
            .refreshSelectedHostApolloAdmin(
                username: username,
                password: password
            )
        )
    }

    @MainActor
    public func updateSelectedHostApolloAdmin(
        username: String,
        password: String,
        displayModeOverride: String,
        alwaysUseVirtualDisplay: Bool,
        permissions: UInt32
    ) {
        commandContinuation.yield(
            .updateSelectedHostApolloAdmin(
                username: username,
                password: password,
                displayModeOverride: displayModeOverride,
                alwaysUseVirtualDisplay: alwaysUseVirtualDisplay,
                permissions: permissions
            )
        )
    }

    @MainActor
    public func disconnectSelectedHostApolloAdmin(username: String, password: String) {
        commandContinuation.yield(
            .disconnectSelectedHostApolloAdmin(
                username: username,
                password: password
            )
        )
    }

    @MainActor
    public func unpairSelectedHostApolloAdmin(username: String, password: String) {
        commandContinuation.yield(
            .unpairSelectedHostApolloAdmin(
                username: username,
                password: password
            )
        )
    }

    @MainActor
    private func performRefreshSelectedHostApps() {
        appRefreshGeneration &+= 1
        let refreshGeneration = appRefreshGeneration

        if isClearingActiveSession || launchState.isTransitioning || activeSession != nil {
            logger.notice(
                "Skipping app list refresh while session transition is active"
            )
            return
        }

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
        let latestResolvedHostDescriptors = latestResolvedHostDescriptors
        let pairingRouteStore = pairingRouteStore
        let cachedAppsForHost = cachedAppsByHostID[hostDescriptor.id] ?? []
        refreshAppsTask = Task { [weak self] in
            do {
                let resolvedHostDescriptor = await Self.preferredRuntimeHostDescriptor(
                    for: hostDescriptor,
                    latestResolvedHostDescriptors: latestResolvedHostDescriptors,
                    pairingRouteStore: pairingRouteStore
                )
                let resolved = try await metadataClient.fetchAppList(
                    host: resolvedHostDescriptor.host,
                    httpsPort: resolvedHostDescriptor.httpsPort
                )
                let sorted = resolved.sorted {
                    $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                let resolvedApps: [ShadowClientRemoteAppDescriptor]
                if sorted.isEmpty {
                    resolvedApps = Self.synthesizedFallbackApps(
                        for: resolvedHostDescriptor,
                        cachedApps: cachedAppsForHost
                    )
                } else {
                    resolvedApps = sorted
                }

                guard !Task.isCancelled else {
                    await MainActor.run { [weak self] in
                        guard let self,
                              self.appRefreshGeneration == refreshGeneration,
                              self.appState == .loading
                        else {
                            return
                        }
                        self.appState = .idle
                    }
                    return
                }

                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    Task {
                        await pairingRouteStore.setSessionPreferredHost(
                            resolvedHostDescriptor.host,
                            for: Self.sessionRouteStoreKey(for: hostDescriptor)
                        )
                        if let persistentRouteKey = Self.persistentRouteStoreKey(for: hostDescriptor) {
                            await pairingRouteStore.setPersistentPreferredHost(
                                resolvedHostDescriptor.host,
                                for: persistentRouteKey
                            )
                        }
                    }
                    if !sorted.isEmpty {
                        self.cachedAppsByHostID[hostDescriptor.id] = sorted
                    }
                    self.apps = resolvedApps
                    self.appState = resolvedApps.isEmpty
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
                    await MainActor.run { [weak self] in
                        guard let self,
                              self.appRefreshGeneration == refreshGeneration,
                              self.appState == .loading
                        else {
                            return
                        }
                        self.appState = .idle
                    }
                    return
                }

                await MainActor.run { [weak self] in
                    guard let self else {
                        return
                    }
                    if fallbackApps.isEmpty {
                        self.apps = []
                        self.appState = .failed(
                            Self.apolloPermissionDeniedMessage(
                                error,
                                capability: .listApps
                            ) ?? message
                        )
                    } else {
                        self.apps = fallbackApps
                        self.appState = .loaded
                    }
                }
            }
        }
    }

    @MainActor
    private func performRefreshSelectedHostApolloAdmin(
        username: String,
        password: String
    ) {
        guard let selectedHost else {
            clearSelectedHostApolloAdminState()
            return
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            selectedHostApolloAdminProfile = nil
            selectedHostApolloAdminState = .failed("Apollo admin credentials are required.")
            return
        }

        selectedHostApolloAdminState = .loading
        selectedHostApolloAdminProfile = nil

        let apolloAdminClient = apolloAdminClient
        let host = selectedHost.host
        let httpsPort = selectedHost.httpsPort
        let selectedHostID = selectedHost.id
        Task { [weak self] in
            do {
                let profile = try await apolloAdminClient.fetchCurrentClientProfile(
                    host: host,
                    httpsPort: httpsPort,
                    username: trimmedUsername,
                    password: trimmedPassword
                )
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostApolloAdminProfile = profile
                    self.selectedHostApolloAdminState = .loaded
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostApolloAdminProfile = nil
                    self.selectedHostApolloAdminState = .failed(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func performUpdateSelectedHostApolloAdmin(
        username: String,
        password: String,
        displayModeOverride: String,
        alwaysUseVirtualDisplay: Bool,
        permissions: UInt32
    ) {
        guard let selectedHost,
              let currentProfile = selectedHostApolloAdminProfile
        else {
            selectedHostApolloAdminState = .failed("Sync Apollo client metadata first.")
            return
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            selectedHostApolloAdminState = .failed("Apollo admin credentials are required.")
            return
        }

        selectedHostApolloAdminState = .saving

        let apolloAdminClient = apolloAdminClient
        let host = selectedHost.host
        let httpsPort = selectedHost.httpsPort
        let selectedHostID = selectedHost.id
        let updatedProfile = ShadowClientApolloAdminClientProfile(
            name: currentProfile.name,
            uuid: currentProfile.uuid,
            displayModeOverride: displayModeOverride.trimmingCharacters(in: .whitespacesAndNewlines),
            permissions: permissions,
            enableLegacyOrdering: currentProfile.enableLegacyOrdering,
            allowClientCommands: currentProfile.allowClientCommands,
            alwaysUseVirtualDisplay: alwaysUseVirtualDisplay,
            connected: currentProfile.connected,
            doCommands: currentProfile.doCommands,
            undoCommands: currentProfile.undoCommands
        )

        Task { [weak self] in
            do {
                let savedProfile = try await apolloAdminClient.updateCurrentClientProfile(
                    host: host,
                    httpsPort: httpsPort,
                    username: trimmedUsername,
                    password: trimmedPassword,
                    profile: updatedProfile
                )
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostApolloAdminProfile = savedProfile
                    self.selectedHostApolloAdminState = .loaded
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostApolloAdminState = .failed(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func clearSelectedHostApolloAdminState() {
        selectedHostApolloAdminProfile = nil
        selectedHostApolloAdminState = .idle
    }

    @MainActor
    private func performDisconnectSelectedHostApolloAdmin(
        username: String,
        password: String
    ) {
        guard let selectedHost,
              let currentProfile = selectedHostApolloAdminProfile
        else {
            selectedHostApolloAdminState = .failed("Sync Apollo client metadata first.")
            return
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            selectedHostApolloAdminState = .failed("Apollo admin credentials are required.")
            return
        }

        selectedHostApolloAdminState = .saving
        let apolloAdminClient = apolloAdminClient
        let host = selectedHost.host
        let httpsPort = selectedHost.httpsPort
        let selectedHostID = selectedHost.id
        let uuid = currentProfile.uuid

        Task { [weak self] in
            do {
                try await apolloAdminClient.disconnectCurrentClient(
                    host: host,
                    httpsPort: httpsPort,
                    username: trimmedUsername,
                    password: trimmedPassword,
                    uuid: uuid
                )
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    if let profile = self.selectedHostApolloAdminProfile {
                        self.selectedHostApolloAdminProfile = .init(
                            name: profile.name,
                            uuid: profile.uuid,
                            displayModeOverride: profile.displayModeOverride,
                            permissions: profile.permissions,
                            enableLegacyOrdering: profile.enableLegacyOrdering,
                            allowClientCommands: profile.allowClientCommands,
                            alwaysUseVirtualDisplay: profile.alwaysUseVirtualDisplay,
                            connected: false,
                            doCommands: profile.doCommands,
                            undoCommands: profile.undoCommands
                        )
                    }
                    self.selectedHostApolloAdminState = .loaded
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostApolloAdminState = .failed(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func performUnpairSelectedHostApolloAdmin(
        username: String,
        password: String
    ) {
        guard let selectedHost,
              let currentProfile = selectedHostApolloAdminProfile
        else {
            selectedHostApolloAdminState = .failed("Sync Apollo client metadata first.")
            return
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            selectedHostApolloAdminState = .failed("Apollo admin credentials are required.")
            return
        }

        selectedHostApolloAdminState = .saving
        let apolloAdminClient = apolloAdminClient
        let host = selectedHost.host
        let httpsPort = selectedHost.httpsPort
        let selectedHostID = selectedHost.id
        let uuid = currentProfile.uuid

        Task { [weak self] in
            do {
                try await apolloAdminClient.unpairCurrentClient(
                    host: host,
                    httpsPort: httpsPort,
                    username: trimmedUsername,
                    password: trimmedPassword,
                    uuid: uuid
                )
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.clearSelectedHostApolloAdminState()
                    self.performRefreshHosts(
                        candidates: self.latestHostCandidates,
                        preferredHost: selectedHost.host
                    )
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostApolloAdminState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private static func fetchHostDescriptor(
        host: String,
        portHint: ShadowClientGameStreamPortHint?,
        metadataClient: any ShadowClientGameStreamMetadataClient
    ) async -> ShadowClientRemoteHostDescriptor {
        do {
            let info = try await metadataClient.fetchServerInfo(
                host: host,
                portHint: portHint
            )
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
                serverCodecModeSupport: info.serverCodecModeSupport,
                lastError: nil,
                localHost: info.localHost,
                remoteHost: info.remoteHost,
                manualHost: info.manualHost
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
                httpsPort: portHint?.httpsPort ?? ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort,
                appVersion: nil,
                gfeVersion: nil,
                uniqueID: nil,
                serverCodecModeSupport: 0,
                lastError: message
            )
        }
    }

    private static func fetchDirectHostDescriptor(
        hostAddress: String,
        metadataClient: any ShadowClientGameStreamMetadataClient
    ) async throws -> ShadowClientRemoteHostDescriptor {
        let info = try await metadataClient.fetchServerInfo(host: hostAddress)
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
            serverCodecModeSupport: info.serverCodecModeSupport,
            lastError: nil,
            localHost: info.localHost,
            remoteHost: info.remoteHost,
            manualHost: info.manualHost
        )
    }

    static func filterOutSelfHosts(
        _ hosts: [ShadowClientRemoteHostDescriptor],
        localInterfaceHosts: Set<String>
    ) -> [ShadowClientRemoteHostDescriptor] {
        var removedUniqueIDs: Set<String> = []
        let routeFilteredHosts = hosts.filter { host in
            let overlapsLocalRoute = !routeHostSet(for: host).isDisjoint(with: localInterfaceHosts)
            if overlapsLocalRoute, let uniqueID = normalizedUniqueID(host.uniqueID) {
                removedUniqueIDs.insert(uniqueID)
            }
            return !overlapsLocalRoute
        }

        guard !removedUniqueIDs.isEmpty else {
            return routeFilteredHosts
        }

        return routeFilteredHosts.filter { host in
            guard let uniqueID = normalizedUniqueID(host.uniqueID) else {
                return true
            }
            return !removedUniqueIDs.contains(uniqueID)
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

    private static func shouldAdvanceToNextPairHost(error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed, .cannotConnectToHost, .appTransportSecurityRequiresSecureConnection:
                return true
            default:
                break
            }
        }

        if let streamError = error as? ShadowClientGameStreamError {
            switch streamError {
            case let .requestFailed(message):
                let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return normalized.contains("app transport security") ||
                    normalized.contains("insecure http is blocked") ||
                    normalized.contains("server with the specified hostname could not be found") ||
                    normalized.contains("could not find host") ||
                    normalized.contains("dns")
            default:
                return false
            }
        }

        return false
    }

    private static func pairHostCandidates(
        for selectedHost: ShadowClientRemoteHostDescriptor,
        hosts: [ShadowClientRemoteHostDescriptor],
        latestHostCandidates: [String],
        preferredPairHost: String?
    ) -> [ShadowClientPairHostCandidate] {
        var candidates: [ShadowClientPairHostCandidate] = []
        let selectedPairCandidate = ShadowClientPairRouteKit.candidateString(for: selectedHost)
        let normalizedSelectedPairCandidate = normalizeCandidate(selectedPairCandidate)
        let normalizedSelectedPairHost = normalizedCandidateHost(normalizedSelectedPairCandidate)

        if let preferredPairHost {
            let normalizedPreferredPairHost = normalizeCandidate(preferredPairHost)
            let normalizedPreferredPairHostOnly = normalizedCandidateHost(normalizedPreferredPairHost)
            let canonicalPreferredPairHost = normalizedPreferredPairHostOnly == normalizedSelectedPairHost
                ? selectedPairCandidate
                : preferredPairHost
            candidates.append(.init(host: canonicalPreferredPairHost, httpsPort: selectedHost.httpsPort))
        }

        if let uniqueID = selectedHost.uniqueID, !uniqueID.isEmpty {
            let matchingHosts = hosts.filter { $0.uniqueID == uniqueID }
            candidates.append(contentsOf: matchingHosts.map {
                .init(host: ShadowClientPairRouteKit.candidateString(for: $0), httpsPort: $0.httpsPort)
            })
        }

        candidates.append(
            contentsOf: latestHostCandidates.map {
                .init(host: $0, httpsPort: selectedHost.httpsPort)
            }
        )
        candidates.append(
            .init(
                host: ShadowClientPairRouteKit.candidateString(for: selectedHost),
                httpsPort: selectedHost.httpsPort
            )
        )

        var seen: Set<String> = []
        let deduplicated = candidates.filter { candidate in
            let key = candidate.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }

        return deduplicated.sorted {
            let lhsRank = pairHostCandidateRank(
                host: $0.host,
                selectedHost: selectedHost,
                preferredPairHost: preferredPairHost
            )
            let rhsRank = pairHostCandidateRank(
                host: $1.host,
                selectedHost: selectedHost,
                preferredPairHost: preferredPairHost
            )
            if lhsRank == rhsRank {
                return $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending
            }
            return lhsRank < rhsRank
        }
    }

    private static func pairHostCandidateRank(
        host: String,
        selectedHost: ShadowClientRemoteHostDescriptor,
        preferredPairHost: String?
    ) -> Int {
        let normalized = normalizeCandidate(host)
            ?? host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedHostOnly = normalizedCandidateHost(normalized) ?? normalized
        let normalizedPreferred = normalizeCandidate(preferredPairHost)
            ?? preferredPairHost?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPreferredHostOnly = normalizedCandidateHost(normalizedPreferred) ?? normalizedPreferred
        let normalizedSelectedPairCandidate = normalizeCandidate(
            ShadowClientPairRouteKit.candidateString(for: selectedHost)
        )
        let normalizedSelected = normalizeCandidate(selectedHost.hostCandidate)
            ?? selectedHost.hostCandidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedSelectedHostOnly = normalizedCandidateHost(normalizedSelected) ?? normalizedSelected

        if normalized == normalizedPreferred || normalizedHostOnly == normalizedPreferredHostOnly {
            return runtimeRouteRank(normalizedHostOnly)
        }
        if normalized == normalizedSelectedPairCandidate {
            return 10 + runtimeRouteRank(normalizedHostOnly)
        }
        if normalized == normalizedSelected || normalizedHostOnly == normalizedSelectedHostOnly {
            return 20 + runtimeRouteRank(normalizedHostOnly)
        }
        if !isLinkLocalRouteHost(normalized) {
            return 30 + runtimeRouteRank(normalizedHostOnly)
        }
        if isLocalPairHost(normalized) {
            return 40 + runtimeRouteRank(normalizedHostOnly)
        }
        return 50 + runtimeRouteRank(normalizedHostOnly)
    }

    private static func persistentRouteStoreKey(for selectedHost: ShadowClientRemoteHostDescriptor) -> String? {
        guard let uniqueID = normalizedUniqueID(selectedHost.uniqueID) else {
            return nil
        }

        return "uniqueid:\(uniqueID)"
    }

    private static func sessionRouteStoreKey(for selectedHost: ShadowClientRemoteHostDescriptor) -> String {
        mergeKey(for: selectedHost)
    }

    private static func isLocalPairHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return isIPAddressCandidate(normalized) || normalized.hasSuffix(".local") || !normalized.contains(".")
    }

    private static func isIPAddressCandidate(_ host: String) -> Bool {
        if host.contains(":") {
            return true
        }
        return host.allSatisfy { $0.isNumber || $0 == "." }
    }

    private static func isLinkLocalRouteHost(_ host: String) -> Bool {
        ShadowClientRemoteHostCandidateFilter.isLinkLocalHost(
            host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    private static func runtimeRouteRank(_ host: String) -> Int {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return 100
        }
        if isLinkLocalRouteHost(normalized) {
            return 30
        }
        if isIPAddressCandidate(normalized) {
            return 20
        }
        if normalized.hasSuffix(".local") || !normalized.contains(".") {
            return 0
        }
        return 10
    }

    private static func compareRuntimeEndpointCandidates(_ lhs: String, _ rhs: String) -> Bool {
        let lhsHost = normalizedCandidateHost(lhs) ?? lhs
        let rhsHost = normalizedCandidateHost(rhs) ?? rhs
        let lhsRank = runtimeRouteRank(lhsHost)
        let rhsRank = runtimeRouteRank(rhsHost)
        if lhsRank == rhsRank {
            return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
        return lhsRank < rhsRank
    }

    private static func runtimePreferredCandidate(
        from candidates: [String],
        preferredCandidate: String?
    ) -> String? {
        let normalizedCandidates = candidates.compactMap { normalizeProbeCandidate($0) }
        guard !normalizedCandidates.isEmpty else {
            return nil
        }

        let sortedCandidates = normalizedCandidates.sorted(by: compareRuntimeEndpointCandidates)
        guard let preferredCandidate = normalizeProbeCandidate(preferredCandidate) else {
            return nil
        }

        guard sortedCandidates.contains(preferredCandidate) else {
            return nil
        }

        guard let bestCandidate = sortedCandidates.first else {
            return preferredCandidate
        }

        let preferredHost = normalizedCandidateHost(preferredCandidate) ?? preferredCandidate
        let bestHost = normalizedCandidateHost(bestCandidate) ?? bestCandidate
        let preferredRank = runtimeRouteRank(preferredHost)
        let bestRank = runtimeRouteRank(bestHost)
        if bestRank < preferredRank {
            return bestCandidate
        }

        return preferredCandidate
    }

    private static func normalizedHostCandidates(_ candidates: [String]) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []

        for candidate in candidates {
            let normalized = normalizeProbeCandidate(candidate)
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

    public static func refreshProbeCandidates(
        _ candidates: [String],
        localInterfaceHosts: Set<String>
    ) -> [String] {
        ShadowClientRemoteHostCandidateFilter.filteredCandidates(
            discoveredHosts: candidates,
            manualHost: nil,
            localInterfaceHosts: localInterfaceHosts
        )
    }

    private static func normalizedPortHintsByCandidate(
        _ portHintsByCandidate: [String: ShadowClientGameStreamPortHint]
    ) -> [String: ShadowClientGameStreamPortHint] {
        var normalized: [String: ShadowClientGameStreamPortHint] = [:]
        for (candidate, portHint) in portHintsByCandidate {
            guard let normalizedCandidate = normalizeProbeCandidate(candidate) else {
                continue
            }
            normalized[normalizedCandidate] = portHint
        }
        return normalized
    }

    private static func normalizeProbeCandidate(_ candidate: String?) -> String? {
        guard let candidate else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let urlCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmed)
        guard let parsed = URL(string: urlCandidate),
              let host = parsed.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty
        else {
            return trimmed.lowercased()
        }

        guard let port = parsed.port else {
            return host
        }

        if port == ShadowClientGameStreamNetworkDefaults.defaultHTTPPort {
            return host
        }

        return "\(host):\(port)"
    }

    private static func normalizedProbeCandidateHost(_ candidate: String?) -> String? {
        guard let normalized = normalizeProbeCandidate(candidate) else {
            return nil
        }

        if let separatorIndex = normalized.lastIndex(of: ":"),
           !normalized[..<separatorIndex].contains(":"),
           Int(normalized[normalized.index(after: separatorIndex)...]) != nil {
            return String(normalized[..<separatorIndex])
        }

        return normalized
    }

    private static func normalizeCandidate(_ candidate: String?) -> String? {
        guard let endpoint = ShadowClientHostEndpointKit.parseCandidate(
            candidate,
            fallbackHTTPSPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
        ) else {
            return nil
        }

        return ShadowClientHostEndpointKit.candidateString(for: endpoint)
    }

    private static func normalizedCandidateHost(_ candidate: String?) -> String? {
        guard let endpoint = ShadowClientHostEndpointKit.parseCandidate(
            candidate,
            fallbackHTTPSPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
        ) else {
            return nil
        }

        let normalizedHost = endpoint.host
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalizedHost.isEmpty ? nil : normalizedHost
    }

    private static func knownHostSetContainsCandidate(
        _ candidate: String,
        knownHostSet: Set<String>
    ) -> Bool {
        let normalizedCandidate = normalizeProbeCandidate(candidate)
            ?? candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedCandidate.isEmpty else {
            return false
        }

        if knownHostSet.contains(normalizedCandidate) {
            return true
        }

        guard let normalizedHost = normalizedProbeCandidateHost(normalizedCandidate) else {
            return false
        }

        return knownHostSet.contains(normalizedHost)
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

    private static func coalescedCandidatesUsingKnownHosts(
        _ candidates: [String],
        knownHosts: [ShadowClientRemoteHostDescriptor],
        preferredHost: String?,
        preferredRoutesByKey: [String: String]
    ) -> [String] {
        let normalizedPreferredHost = normalizeProbeCandidate(preferredHost)
        var results: [String] = []
        var seenCandidates: Set<String> = []
        var seenKnownHostKeys: Set<String> = []

        for candidate in candidates {
            if let matchedKnownHost = matchedKnownHostForProbeCandidate(
                candidate,
                knownHosts: knownHosts,
                preferredRoutesByKey: preferredRoutesByKey
            ) {
                let hostKey = mergeKey(for: matchedKnownHost)
                guard !seenKnownHostKeys.contains(hostKey) else {
                    continue
                }
                seenKnownHostKeys.insert(hostKey)

                let matchedKnownHostSet = knownHostSet(for: matchedKnownHost)
                let groupedCandidates = candidates.filter { groupedCandidate in
                    knownHostSetContainsCandidate(groupedCandidate, knownHostSet: matchedKnownHostSet)
                }
                let probeCandidate = preferredProbeCandidate(
                    from: groupedCandidates,
                    knownHost: matchedKnownHost,
                    preferredHost: normalizedPreferredHost,
                    preferredRoute: normalizeProbeCandidate(preferredRoutesByKey[hostKey])
                )
                guard seenCandidates.insert(probeCandidate).inserted else {
                    continue
                }
                results.append(probeCandidate)
                continue
            }

            guard seenCandidates.insert(candidate).inserted else {
                continue
            }
            results.append(candidate)
        }

        return results
    }

    private static func matchedKnownHostForProbeCandidate(
        _ candidate: String,
        knownHosts: [ShadowClientRemoteHostDescriptor],
        preferredRoutesByKey: [String: String]
    ) -> ShadowClientRemoteHostDescriptor? {
        if let matchedKnownHost = bestKnownHost(
            matching: candidate,
            in: knownHosts
        ) {
            return matchedKnownHost
        }

        guard let normalizedCandidate = normalizeProbeCandidate(candidate),
              let normalizedCandidateHostname = normalizedProbeCandidateHost(normalizedCandidate)
        else {
            return nil
        }

        return knownHosts
            .filter { host in
                guard let preferredRoute = normalizeProbeCandidate(preferredRoutesByKey[mergeKey(for: host)]),
                      let preferredRouteHost = normalizedProbeCandidateHost(preferredRoute)
                else {
                    return false
                }
                return preferredRoute == normalizedCandidate || preferredRouteHost == normalizedCandidateHostname
            }
            .sorted(by: compareKnownHostHydrationPriority)
            .first
    }

    private static func hydrateDescriptorsUsingKnownHosts(
        _ descriptors: [ShadowClientRemoteHostDescriptor],
        knownHosts: [ShadowClientRemoteHostDescriptor],
        preferredRoutesByKey: [String: String]
    ) -> [ShadowClientRemoteHostDescriptor] {
        descriptors.map { descriptor in
            hydrateDescriptorUsingKnownHosts(
                descriptor,
                knownHosts: knownHosts,
                preferredRoutesByKey: preferredRoutesByKey
            )
        }
    }

    private static func hydrateDescriptorUsingKnownHosts(
        _ descriptor: ShadowClientRemoteHostDescriptor,
        knownHosts: [ShadowClientRemoteHostDescriptor],
        preferredRoutesByKey: [String: String]
    ) -> ShadowClientRemoteHostDescriptor {
        guard descriptor.lastError != nil, normalizedUniqueID(descriptor.uniqueID) == nil else {
            return descriptor
        }

        let normalizedHost = descriptor.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else {
            return descriptor
        }

        guard let matchedHost = bestKnownHost(
            matching: normalizedHost,
            in: knownHosts
        ) else {
            return descriptor
        }

        let matchedHostKey = mergeKey(for: matchedHost)
        let preferredRoute = normalizeProbeCandidate(preferredRoutesByKey[matchedHostKey])
        let hydratedRoutes = matchedHost.routes
        let activeRoute = hydratedRoutes.allEndpoints.first(where: {
            $0.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedHost
        }) ?? hydratedRoutes.allEndpoints.first(where: {
            ShadowClientHostEndpointKit.candidateString(for: $0) == preferredRoute
        }) ?? descriptor.routes.active
        let routes = ShadowClientRemoteHostRoutes(
            active: activeRoute,
            local: hydratedRoutes.local,
            remote: hydratedRoutes.remote,
            manual: hydratedRoutes.manual
        )
        let displayName = descriptor.displayName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedHost
            ? matchedHost.displayName
            : descriptor.displayName

        return ShadowClientRemoteHostDescriptor(
            activeRoute: routes.active,
            displayName: displayName,
            pairStatus: matchedHost.pairStatus,
            currentGameID: max(descriptor.currentGameID, matchedHost.currentGameID),
            serverState: descriptor.serverState.isEmpty ? matchedHost.serverState : descriptor.serverState,
            appVersion: descriptor.appVersion ?? matchedHost.appVersion,
            gfeVersion: descriptor.gfeVersion ?? matchedHost.gfeVersion,
            uniqueID: descriptor.uniqueID ?? matchedHost.uniqueID,
            serverCodecModeSupport: max(
                descriptor.serverCodecModeSupport,
                matchedHost.serverCodecModeSupport
            ),
            lastError: descriptor.lastError,
            routes: routes
        )
    }

    private static func bestKnownHost(
        matching host: String,
        in knownHosts: [ShadowClientRemoteHostDescriptor]
    ) -> ShadowClientRemoteHostDescriptor? {
        let normalizedHost = normalizeCandidate(host)
            ?? host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else {
            return nil
        }

        return knownHosts
            .filter { knownHost in
                knownHostSetContainsCandidate(
                    normalizedHost,
                    knownHostSet: knownHostSet(for: knownHost)
                )
            }
            .sorted(by: compareKnownHostHydrationPriority)
            .first
    }

    private static func reconciledPreferredRoutesByKey(
        preferredRoutesByKey: [String: String],
        resolvedHosts: [ShadowClientRemoteHostDescriptor]
    ) -> [String: String] {
        guard !preferredRoutesByKey.isEmpty, !resolvedHosts.isEmpty else {
            return preferredRoutesByKey
        }

        let groupedHosts = clusterResolvedHosts(resolvedHosts)
        let reachableGroups = groupedHosts.compactMap { group -> (key: String, group: [ShadowClientRemoteHostDescriptor])? in
            guard let primary = group.first(where: \.isReachable) ?? group.first else {
                return nil
            }
            return (mergeKey(for: primary), group)
        }
        let reachableRouteGroupsByKey = Dictionary(uniqueKeysWithValues: reachableGroups.map { ($0.key, $0.group) })

        var reconciledRoutes = preferredRoutesByKey
        for (key, preferredRoute) in preferredRoutesByKey {
            guard let normalizedPreferredRoute = normalizeCandidate(preferredRoute),
                  let normalizedPreferredHost = normalizedCandidateHost(normalizedPreferredRoute)
            else {
                reconciledRoutes.removeValue(forKey: key)
                continue
            }

            if let owningGroup = reachableRouteGroupsByKey[key] {
                let reachableCandidates = owningGroup
                    .filter(\.isReachable)
                    .filter { $0.host.lowercased() == normalizedPreferredHost }
                    .map { ShadowClientHostEndpointKit.candidateString(for: $0.routes.active) }
                if reachableCandidates.contains(normalizedPreferredRoute) {
                    reconciledRoutes[key] = normalizedPreferredRoute
                    continue
                }
                if let fallbackCandidate = reachableCandidates.sorted(by: {
                    compareRuntimeEndpointCandidates($0, $1)
                }).first {
                    reconciledRoutes[key] = fallbackCandidate
                    continue
                }
            }

            let competingOwners = reachableRouteGroupsByKey.compactMap { ownerKey, group -> String? in
                guard ownerKey != key else {
                    return nil
                }
                let ownsHost = group.contains {
                    $0.isReachable && $0.host.lowercased() == normalizedPreferredHost
                }
                return ownsHost ? ownerKey : nil
            }

            if !competingOwners.isEmpty {
                reconciledRoutes.removeValue(forKey: key)
            }
        }

        return reconciledRoutes
    }

    private static func compareKnownHostHydrationPriority(
        lhs: ShadowClientRemoteHostDescriptor,
        rhs: ShadowClientRemoteHostDescriptor
    ) -> Bool {
        let lhsHasIdentity = normalizedUniqueID(lhs.uniqueID) != nil
        let rhsHasIdentity = normalizedUniqueID(rhs.uniqueID) != nil
        if lhsHasIdentity != rhsHasIdentity {
            return lhsHasIdentity
        }

        if lhs.pairStatus != rhs.pairStatus {
            return lhs.pairStatus == .paired
        }

        let lhsRoutes = lhs.routes.allEndpoints.count
        let rhsRoutes = rhs.routes.allEndpoints.count
        if lhsRoutes != rhsRoutes {
            return lhsRoutes > rhsRoutes
        }

        if lhs.isReachable != rhs.isReachable {
            return lhs.isReachable
        }

        return lhs.host.localizedCaseInsensitiveCompare(rhs.host) == .orderedAscending
    }

    private static func preferredProbeCandidate(
        from groupedCandidates: [String],
        knownHost: ShadowClientRemoteHostDescriptor,
        preferredHost: String?,
        preferredRoute: String?
    ) -> String {
        let normalizedPreferredHost = normalizeProbeCandidate(preferredHost)
        if let preferredHostCandidate = runtimePreferredCandidate(
            from: groupedCandidates,
            preferredCandidate: preferredHost
        ),
        preferredHostCandidate == normalizedPreferredHost {
            return preferredHostCandidate
        }

        let normalizedPreferredRoute = normalizeProbeCandidate(preferredRoute)
        if let preferredRouteCandidate = runtimePreferredCandidate(
            from: groupedCandidates,
            preferredCandidate: preferredRoute
        ),
        preferredRouteCandidate == normalizedPreferredRoute {
            return preferredRouteCandidate
        }

        let normalizedGroupedCandidates = groupedCandidates.map {
            normalizeProbeCandidate($0) ?? $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
        if let bestGroupedCandidate = normalizedGroupedCandidates.sorted(by: compareRuntimeEndpointCandidates).first {
            return bestGroupedCandidate
        }

        return groupedCandidates.sorted { lhs, rhs in
            let lhsRank = runtimeRouteRank(lhs)
            let rhsRank = runtimeRouteRank(rhs)
            if lhsRank == rhsRank {
                return lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
            }
            return lhsRank < rhsRank
        }.first ?? knownHost.host.lowercased()
    }

    private static func mergeResolvedHosts(
        _ hosts: [ShadowClientRemoteHostDescriptor],
        selectedHostID: String?,
        preferredHost: String?,
        preferredRoutesByKey: [String: String],
        pairedHostKeys: Set<String>
    ) -> [ShadowClientRemoteHostDescriptor] {
        let groupedHosts = clusterResolvedHosts(hosts)
        return groupedHosts.compactMap {
            mergeResolvedHostGroup(
                $0,
                selectedHostID: selectedHostID,
                preferredHost: preferredHost,
                preferredRoutesByKey: preferredRoutesByKey,
                pairedHostKeys: pairedHostKeys
            )
        }
        .sorted(by: compareHosts)
    }

    private static func clusterResolvedHosts(
        _ hosts: [ShadowClientRemoteHostDescriptor]
    ) -> [[ShadowClientRemoteHostDescriptor]] {
        var clusters: [[ShadowClientRemoteHostDescriptor]] = []

        for host in hosts {
            if let matchingClusterIndex = clusters.firstIndex(where: { cluster in
                cluster.contains(where: { clusteredHost in
                    descriptorsBelongToSamePhysicalHost(clusteredHost, host)
                })
            }) {
                clusters[matchingClusterIndex].append(host)
                continue
            }
            clusters.append([host])
        }

        var merged = true
        while merged {
            merged = false
            outer: for lhsIndex in clusters.indices {
                for rhsIndex in clusters.indices where lhsIndex < rhsIndex {
                    let lhsCluster = clusters[lhsIndex]
                    let rhsCluster = clusters[rhsIndex]
                    let overlaps = lhsCluster.contains { lhsHost in
                        rhsCluster.contains { rhsHost in
                            descriptorsBelongToSamePhysicalHost(lhsHost, rhsHost)
                        }
                    }
                    if overlaps {
                        clusters[lhsIndex].append(contentsOf: rhsCluster)
                        clusters.remove(at: rhsIndex)
                        merged = true
                        break outer
                    }
                }
            }
        }

        return clusters
    }

    private static func mergeResolvedHostGroup(
        _ group: [ShadowClientRemoteHostDescriptor],
        selectedHostID: String?,
        preferredHost: String?,
        preferredRoutesByKey: [String: String],
        pairedHostKeys: Set<String>
    ) -> ShadowClientRemoteHostDescriptor? {
        guard let primary = group.sorted(by: {
            compareMergePriority(
                lhs: $0,
                rhs: $1,
                selectedHostID: selectedHostID,
                preferredHost: preferredHost,
                preferredRoute: preferredRoutesByKey[mergeKey(for: $0)]
            )
        }).first else {
            return nil
        }

        let displayName = group.first(where: {
            let trimmed = $0.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && trimmed.lowercased() != $0.host.lowercased()
        })?.displayName ?? primary.displayName

        let pairStatus: ShadowClientRemoteHostPairStatus
        if pairedHostKeys.contains(mergeKey(for: primary)) || group.contains(where: { $0.pairStatus == .paired }) {
            pairStatus = .paired
        } else if group.contains(where: { $0.pairStatus == .notPaired }) {
            pairStatus = .notPaired
        } else {
            pairStatus = .unknown
        }

        let currentGameID = group.map(\.currentGameID).max() ?? primary.currentGameID
        let lastError = group.contains(where: \.isReachable)
            ? nil
            : group.compactMap(\.lastError).first
        let preferredRoute = preferredRoutesByKey[mergeKey(for: primary)]
        let mergedRoutes = mergedHostRoutes(
            from: group,
            fallbackPrimary: primary,
            selectedHostID: selectedHostID,
            preferredHost: preferredHost,
            preferredRoute: preferredRoute
        )

        return ShadowClientRemoteHostDescriptor(
            activeRoute: mergedRoutes.active,
            displayName: displayName,
            pairStatus: pairStatus,
            currentGameID: currentGameID,
            serverState: primary.serverState,
            appVersion: primary.appVersion,
            gfeVersion: primary.gfeVersion,
            uniqueID: primary.uniqueID,
            lastError: lastError,
            routes: mergedRoutes
        )
    }

    private static func pairedHostKeys(
        for hosts: [ShadowClientRemoteHostDescriptor],
        existingHosts: [ShadowClientRemoteHostDescriptor],
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    ) async -> Set<String> {
        var pairedKeys = Set(
            existingHosts
                .filter { $0.pairStatus == .paired }
                .map(mergeKey(for:))
        )

        for host in hosts {
            if host.pairStatus == .paired {
                pairedKeys.insert(mergeKey(for: host))
                continue
            }

            for endpoint in host.routes.allEndpoints {
                if await pinnedCertificateStore.certificateDER(forHost: endpoint.host) != nil {
                    pairedKeys.insert(mergeKey(for: host))
                    break
                }
            }
        }

        return pairedKeys
    }

    private static func compareMergePriority(
        lhs: ShadowClientRemoteHostDescriptor,
        rhs: ShadowClientRemoteHostDescriptor,
        selectedHostID: String?,
        preferredHost: String?,
        preferredRoute: String?
    ) -> Bool {
        let normalizedPreferredHost = normalizeCandidate(preferredHost)
        let normalizedPreferredRoute = normalizeCandidate(preferredRoute)
        let lhsPreferred = normalizedPreferredHost.map { routeCandidateSet(for: lhs).contains($0) } ?? false
        let rhsPreferred = normalizedPreferredHost.map { routeCandidateSet(for: rhs).contains($0) } ?? false
        if lhsPreferred != rhsPreferred {
            return lhsPreferred
        }

        let lhsStoredPreferred = normalizedPreferredRoute.map { routeCandidateSet(for: lhs).contains($0) } ?? false
        let rhsStoredPreferred = normalizedPreferredRoute.map { routeCandidateSet(for: rhs).contains($0) } ?? false
        if lhsStoredPreferred != rhsStoredPreferred {
            return lhsStoredPreferred
        }

        let lhsSelected = lhs.id == selectedHostID
        let rhsSelected = rhs.id == selectedHostID
        if lhsSelected != rhsSelected {
            return lhsSelected
        }

        if lhs.isReachable != rhs.isReachable {
            return lhs.isReachable
        }

        if lhs.pairStatus != rhs.pairStatus {
            return lhs.pairStatus == .paired
        }

        if lhs.currentGameID != rhs.currentGameID {
            return lhs.currentGameID > rhs.currentGameID
        }

        let lhsLocal = isLocalPairHost(lhs.host)
        let rhsLocal = isLocalPairHost(rhs.host)
        if lhsLocal != rhsLocal {
            return lhsLocal
        }

        return lhs.host.localizedCaseInsensitiveCompare(rhs.host) == .orderedAscending
    }

    private static func descriptorsBelongToSamePhysicalHost(
        _ lhs: ShadowClientRemoteHostDescriptor,
        _ rhs: ShadowClientRemoteHostDescriptor
    ) -> Bool {
        if let lhsUniqueID = lhs.uniqueID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let rhsUniqueID = rhs.uniqueID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !lhsUniqueID.isEmpty,
           !rhsUniqueID.isEmpty
        {
            return lhsUniqueID == rhsUniqueID
        }

        let lhsRouteHosts = routeHostSet(for: lhs)
        let rhsRouteHosts = routeHostSet(for: rhs)
        if !lhsRouteHosts.isDisjoint(with: rhsRouteHosts) {
            return true
        }

        return false
    }

    private static func mergeKey(for host: ShadowClientRemoteHostDescriptor) -> String {
        if let uniqueID = normalizedUniqueID(host.uniqueID) {
            return "uniqueid:\(uniqueID)"
        }

        let routeHosts = routeHostSet(for: host).sorted()
        if !routeHosts.isEmpty {
            return "routes:\(routeHosts.joined(separator: "|"))"
        }

        return "host:\(host.id)"
    }

    private static func routeHostSet(for host: ShadowClientRemoteHostDescriptor) -> Set<String> {
        Set(
            host.routes.allEndpoints.map {
                $0.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            .filter { !$0.isEmpty }
        )
    }

    private static func routeCandidateSet(for host: ShadowClientRemoteHostDescriptor) -> Set<String> {
        Set(host.routes.allEndpoints.map { ShadowClientHostEndpointKit.candidateString(for: $0) })
    }

    private static func probeCandidateSet(for host: ShadowClientRemoteHostDescriptor) -> Set<String> {
        Set(host.routes.allEndpoints.map { ShadowClientPairRouteKit.candidateString(for: $0) })
    }

    private static func knownHostSet(
        for host: ShadowClientRemoteHostDescriptor
    ) -> Set<String> {
        routeHostSet(for: host)
            .union(probeCandidateSet(for: host))
    }

    private static func normalizedUniqueID(_ uniqueID: String?) -> String? {
        guard let uniqueID else {
            return nil
        }

        let normalized = uniqueID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }

    private static func mergedHostRoutes(
        from group: [ShadowClientRemoteHostDescriptor],
        fallbackPrimary: ShadowClientRemoteHostDescriptor,
        selectedHostID: String?,
        preferredHost: String?,
        preferredRoute: String?
    ) -> ShadowClientRemoteHostRoutes {
        let candidateRoutes = group
            .flatMap { $0.routes.allEndpoints }
            .reduce(into: [ShadowClientRemoteHostEndpoint]()) { partialResult, endpoint in
                guard !partialResult.contains(where: { $0 == endpoint }) else {
                    return
                }
                partialResult.append(endpoint)
            }

        let reachableHostNames = Set(
            group
                .filter(\.isReachable)
                .map { $0.host.lowercased() }
        )
        let reachableLocalHost = group.first(where: {
            $0.isReachable && isLocalPairHost($0.host)
        })?.host.lowercased()
        let activeRouteCandidates = candidateRoutes.filter {
            reachableHostNames.isEmpty || reachableHostNames.contains($0.host.lowercased())
        }
        let rankedActiveRouteCandidates = activeRouteCandidates.sorted {
            let lhsRank = runtimeRouteRank($0.host)
            let rhsRank = runtimeRouteRank($1.host)
            if lhsRank == rhsRank {
                return $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending
            }
            return lhsRank < rhsRank
        }
        let normalizedPreferredHost = normalizeCandidate(preferredHost)
        let normalizedPreferredRoute = normalizeCandidate(preferredRoute)
        let selectedReachableCandidate = group.first(where: {
            $0.id == selectedHostID && $0.isReachable
        }).map { ShadowClientHostEndpointKit.candidateString(for: $0.routes.active) }
        let preferredActiveCandidate = runtimePreferredCandidate(
            from: rankedActiveRouteCandidates.map { ShadowClientHostEndpointKit.candidateString(for: $0) },
            preferredCandidate: normalizedPreferredHost
        )
        let preferredStoredCandidate = runtimePreferredCandidate(
            from: rankedActiveRouteCandidates.map { ShadowClientHostEndpointKit.candidateString(for: $0) },
            preferredCandidate: normalizedPreferredRoute
        )
        let preferredSelectedCandidate = runtimePreferredCandidate(
            from: rankedActiveRouteCandidates.map { ShadowClientHostEndpointKit.candidateString(for: $0) },
            preferredCandidate: selectedReachableCandidate
        )

        let active = rankedActiveRouteCandidates.first(where: {
            ShadowClientHostEndpointKit.candidateString(for: $0) == preferredActiveCandidate
        }) ?? rankedActiveRouteCandidates.first(where: {
            ShadowClientHostEndpointKit.candidateString(for: $0) == preferredStoredCandidate
        }) ?? rankedActiveRouteCandidates.first(where: {
            ShadowClientHostEndpointKit.candidateString(for: $0) == preferredSelectedCandidate
        }) ?? rankedActiveRouteCandidates.first(where: {
            $0.host.lowercased() == reachableLocalHost && !isLinkLocalRouteHost($0.host)
        }) ?? rankedActiveRouteCandidates.first(where: {
            isLocalPairHost($0.host)
        }) ?? rankedActiveRouteCandidates.first ?? fallbackPrimary.routes.active

        let local = preferredLocalSupplementalRoute(
            active: active,
            candidateRoutes: candidateRoutes,
            explicitLocalRoutes: group.compactMap(\.routes.local)
        )
        let remote = preferredSupplementalRoute(group.compactMap(\.routes.remote))
        let manual = preferredSupplementalRoute(group.compactMap(\.routes.manual))

        let routes = ShadowClientRemoteHostRoutes(
            active: active,
            local: local,
            remote: remote,
            manual: manual
        )
        return routes
    }

    private static func preferredSupplementalRoute(
        _ endpoints: [ShadowClientRemoteHostEndpoint]
    ) -> ShadowClientRemoteHostEndpoint? {
        endpoints.sorted { lhs, rhs in
            let lhsRank = runtimeRouteRank(lhs.host)
            let rhsRank = runtimeRouteRank(rhs.host)
            if lhsRank == rhsRank {
                return lhs.host.localizedCaseInsensitiveCompare(rhs.host) == .orderedAscending
            }
            return lhsRank < rhsRank
        }.first
    }

    private static func preferredLocalSupplementalRoute(
        active: ShadowClientRemoteHostEndpoint,
        candidateRoutes: [ShadowClientRemoteHostEndpoint],
        explicitLocalRoutes: [ShadowClientRemoteHostEndpoint]
    ) -> ShadowClientRemoteHostEndpoint? {
        func isCandidateLocalNetworkHost(_ host: String) -> Bool {
            let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized.hasSuffix(".local") {
                return true
            }
            if normalized.hasPrefix("10.") || normalized.hasPrefix("192.168.") || normalized.hasPrefix("169.254.") {
                return true
            }
            if normalized.hasPrefix("fe80:") || normalized.hasPrefix("fd") || normalized.hasPrefix("fc") {
                return true
            }
            if normalized.hasPrefix("172."),
               let secondOctet = normalized.split(separator: ".").dropFirst().first,
               let secondOctetValue = Int(secondOctet),
               (16...31).contains(secondOctetValue)
            {
                return true
            }
            return false
        }

        let activeHost = active.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let candidateLocalRoutes = candidateRoutes.filter { endpoint in
            let normalizedHost = endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalizedHost.isEmpty, normalizedHost != activeHost else {
                return false
            }
            return isCandidateLocalNetworkHost(normalizedHost)
        }

        let combined = (explicitLocalRoutes + candidateLocalRoutes).reduce(into: [ShadowClientRemoteHostEndpoint]()) {
            partialResult, endpoint in
            guard !partialResult.contains(where: { $0 == endpoint }) else {
                return
            }
            partialResult.append(endpoint)
        }

        return preferredSupplementalRoute(combined)
    }

    private static func preferredRuntimeHostDescriptor(
        for selectedHost: ShadowClientRemoteHostDescriptor,
        latestResolvedHostDescriptors: [ShadowClientRemoteHostDescriptor],
        pairingRouteStore: ShadowClientPairingRouteStore
    ) async -> ShadowClientRemoteHostDescriptor {
        let routeGroupKey = mergeKey(for: selectedHost)
        let preferredHost = await effectivePreferredRoute(
            for: selectedHost,
            pairingRouteStore: pairingRouteStore
        )
        let knownRouteHosts = Set(
            selectedHost.routes.allEndpoints.map { $0.host.lowercased() }
        )
        let matchingDescriptors = latestResolvedHostDescriptors.filter {
            mergeKey(for: $0) == routeGroupKey || knownRouteHosts.contains($0.host.lowercased())
        }
        let reachableDescriptors = matchingDescriptors.filter(\.isReachable)
        let candidateDescriptors = reachableDescriptors.isEmpty ? matchingDescriptors : reachableDescriptors

        if let preferredHost,
           let normalizedPreferredHost = normalizeCandidate(preferredHost),
           let normalizedPreferredHostname = normalizedCandidateHost(normalizedPreferredHost),
           let preferredDescriptor = candidateDescriptors.first(where: {
               let activeCandidate = ShadowClientHostEndpointKit.candidateString(for: $0.routes.active)
               return activeCandidate == normalizedPreferredHost || $0.host.lowercased() == normalizedPreferredHostname
           }) {
            return preferredDescriptor
        }

        let currentActiveHost = selectedHost.routes.active.host.lowercased()
        if let activeDescriptor = candidateDescriptors.first(where: {
            $0.host.lowercased() == currentActiveHost
        }), !isLinkLocalRouteHost(activeDescriptor.host) {
            return activeDescriptor
        }

        if let exactDescriptor = candidateDescriptors.first(where: {
            $0.host.lowercased() == selectedHost.host.lowercased()
        }), !isLinkLocalRouteHost(exactDescriptor.host) {
            return exactDescriptor
        }

        if let nonLinkLocalDescriptor = candidateDescriptors.first(where: {
            !isLinkLocalRouteHost($0.host)
        }) {
            return nonLinkLocalDescriptor
        }

        if let localDescriptor = candidateDescriptors.first(where: {
            isLocalPairHost($0.host)
        }) {
            return localDescriptor
        }

        if let activeDescriptor = candidateDescriptors.first(where: {
            $0.host.lowercased() == currentActiveHost
        }) {
            return activeDescriptor
        }

        if let exactDescriptor = candidateDescriptors.first(where: {
            $0.host.lowercased() == selectedHost.host.lowercased()
        }) {
            return exactDescriptor
        }

        if let firstReachableDescriptor = candidateDescriptors.first {
            return firstReachableDescriptor
        }

        if let preferredHost {
            return ShadowClientRemoteHostDescriptor(
                host: preferredHost,
                displayName: selectedHost.displayName,
                pairStatus: selectedHost.pairStatus,
                currentGameID: selectedHost.currentGameID,
                serverState: selectedHost.serverState,
                httpsPort: selectedHost.httpsPort,
                appVersion: selectedHost.appVersion,
                gfeVersion: selectedHost.gfeVersion,
                uniqueID: selectedHost.uniqueID,
                lastError: selectedHost.lastError
            )
        }

        return selectedHost
    }

    private static func alternateRuntimeHostDescriptor(
        afterFailureOn currentDescriptor: ShadowClientRemoteHostDescriptor,
        selectedHost: ShadowClientRemoteHostDescriptor,
        latestResolvedHostDescriptors: [ShadowClientRemoteHostDescriptor]
    ) -> ShadowClientRemoteHostDescriptor? {
        let routeGroupKey = mergeKey(for: selectedHost)
        let knownRouteHosts = Set(
            selectedHost.routes.allEndpoints.map { $0.host.lowercased() }
        )
        let candidates = latestResolvedHostDescriptors.filter {
            mergeKey(for: $0) == routeGroupKey || knownRouteHosts.contains($0.host.lowercased())
        }
        let reachableCandidates = candidates.filter(\.isReachable)

        if let nonLinkLocalCandidate = reachableCandidates.first(where: {
            $0.host.lowercased() != currentDescriptor.host.lowercased() &&
                !isLinkLocalRouteHost($0.host)
        }) {
            return nonLinkLocalCandidate
        }

        if !isLocalPairHost(currentDescriptor.host),
           let localDescriptor = reachableCandidates.first(where: {
               isLocalPairHost($0.host) &&
                   $0.host.lowercased() != currentDescriptor.host.lowercased() &&
                   !isLinkLocalRouteHost($0.host)
           }) {
            return localDescriptor
        }

        if !isLocalPairHost(currentDescriptor.host),
           let localEndpoint = selectedHost.routes.local,
           localEndpoint.host.lowercased() != currentDescriptor.host.lowercased()
        {
            return ShadowClientRemoteHostDescriptor(
                activeRoute: localEndpoint,
                displayName: selectedHost.displayName,
                pairStatus: selectedHost.pairStatus,
                currentGameID: selectedHost.currentGameID,
                serverState: selectedHost.serverState,
                appVersion: selectedHost.appVersion,
                gfeVersion: selectedHost.gfeVersion,
                uniqueID: selectedHost.uniqueID,
                lastError: nil,
                routes: ShadowClientRemoteHostRoutes(
                    active: localEndpoint,
                    local: selectedHost.routes.local,
                    remote: selectedHost.routes.remote,
                    manual: selectedHost.routes.manual
                )
            )
        }

        return nil
    }

    private static func shouldRetryLaunchOnAlternateRoute(_ error: Error) -> Bool {
        let normalized = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("connection refused") ||
            normalized.contains("could not connect to the server") ||
            normalized.contains("a server with the specified hostname could not be found")
    }

    private static func markHostAsPaired(
        _ host: ShadowClientRemoteHostDescriptor,
        matching selectedHost: ShadowClientRemoteHostDescriptor,
        preferredHost: String?
    ) -> ShadowClientRemoteHostDescriptor {
        guard mergeKey(for: host) == mergeKey(for: selectedHost) else {
            return host
        }

        let normalizedPreferredHost = normalizeCandidate(preferredHost)
        let activeRoute = host.routes.allEndpoints.first(where: {
            $0.host.lowercased() == normalizedPreferredHost
        }) ?? host.routes.active
        let routes = ShadowClientRemoteHostRoutes(
            active: activeRoute,
            local: host.routes.local,
            remote: host.routes.remote,
            manual: host.routes.manual
        )

        return ShadowClientRemoteHostDescriptor(
            activeRoute: routes.active,
            displayName: host.displayName,
            pairStatus: .paired,
            currentGameID: host.currentGameID,
            serverState: host.serverState,
            appVersion: host.appVersion,
            gfeVersion: host.gfeVersion,
            uniqueID: host.uniqueID,
            serverCodecModeSupport: host.serverCodecModeSupport,
            lastError: host.lastError,
            routes: routes
        )
    }

    private static func persistentPreferredRouteOverrides(
        for hosts: [ShadowClientRemoteHostDescriptor],
        pairingRouteStore: ShadowClientPairingRouteStore
    ) async -> [String: String] {
        var routes: [String: String] = [:]
        for host in hosts {
            let mergeKey = mergeKey(for: host)
            guard let persistentKey = persistentRouteStoreKey(for: host),
                  let preferredHost = await pairingRouteStore.persistentPreferredHost(for: persistentKey),
                  let normalizedPreferredHost = normalizeCandidate(preferredHost)
            else {
                continue
            }
            routes[mergeKey] = normalizedPreferredHost
        }
        return routes
    }

    private static func sessionPreferredRouteOverrides(
        for hosts: [ShadowClientRemoteHostDescriptor],
        pairingRouteStore: ShadowClientPairingRouteStore
    ) async -> [String: String] {
        var routes: [String: String] = [:]
        for host in hosts {
            let sessionKey = sessionRouteStoreKey(for: host)
            guard let preferredHost = await pairingRouteStore.sessionPreferredHost(for: sessionKey),
                  let normalizedPreferredHost = normalizeCandidate(preferredHost)
            else {
                continue
            }
            routes[mergeKey(for: host)] = normalizedPreferredHost
        }
        return routes
    }

    private static func mergedPreferredRouteOverrides(
        persistentPreferredRoutesByKey: [String: String],
        sessionPreferredRoutesByKey: [String: String]
    ) -> [String: String] {
        persistentPreferredRoutesByKey.merging(sessionPreferredRoutesByKey) { _, sessionValue in
            sessionValue
        }
    }

    private static func effectivePreferredRouteOverrides(
        for hosts: [ShadowClientRemoteHostDescriptor],
        pairingRouteStore: ShadowClientPairingRouteStore
    ) async -> [String: String] {
        let persistentPreferredRoutes = await persistentPreferredRouteOverrides(
            for: hosts,
            pairingRouteStore: pairingRouteStore
        )
        let sessionPreferredRoutes = await sessionPreferredRouteOverrides(
            for: hosts,
            pairingRouteStore: pairingRouteStore
        )
        return mergedPreferredRouteOverrides(
            persistentPreferredRoutesByKey: persistentPreferredRoutes,
            sessionPreferredRoutesByKey: sessionPreferredRoutes
        )
    }

    private static func effectivePreferredRoute(
        for host: ShadowClientRemoteHostDescriptor,
        pairingRouteStore: ShadowClientPairingRouteStore
    ) async -> String? {
        if let sessionPreferredHost = await pairingRouteStore.sessionPreferredHost(
            for: sessionRouteStoreKey(for: host)
        ), let normalizedSessionPreferredHost = normalizeCandidate(sessionPreferredHost) {
            return normalizedSessionPreferredHost
        }

        guard let persistentKey = persistentRouteStoreKey(for: host),
              let persistentPreferredHost = await pairingRouteStore.persistentPreferredHost(for: persistentKey)
        else {
            return nil
        }

        return normalizeCandidate(persistentPreferredHost)
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

        let displayName = normalizedHostDisplayName(
            document.values["hostname"]?.first,
            fallbackHost: host
        )
        let pairStatus = parsePairStatus(document.values["PairStatus"]?.first)
        let serverState = document.values["state"]?.first ?? ""
        let rawCurrentGameID = Int(document.values["currentgame"]?.first ?? "") ?? 0
        let currentGameID = normalizeCurrentGameID(
            rawCurrentGameID,
            serverState: serverState
        )
        let httpsPort = Int(document.values["HttpsPort"]?.first ?? "") ?? fallbackHTTPSPort
        let localHost = normalizedRouteHost(document.values["LocalIP"]?.first)
        let externalHost = normalizedRouteHost(document.values["ExternalIP"]?.first)
        let manualHost = normalizedManualRouteHost(
            activeHost: host,
            localHost: localHost,
            remoteHost: externalHost
        )
        let serverCodecModeSupport = Int(
            document.values["ServerCodecModeSupport"]?.first ?? ""
        ) ?? 0

        return ShadowClientGameStreamServerInfo(
            host: host,
            localHost: localHost,
            remoteHost: externalHost,
            manualHost: manualHost,
            displayName: displayName,
            pairStatus: pairStatus,
            currentGameID: currentGameID,
            serverState: serverState,
            httpsPort: httpsPort,
            appVersion: document.values["appversion"]?.first,
            gfeVersion: document.values["GfeVersion"]?.first,
            uniqueID: document.values["uniqueid"]?.first,
            serverCodecModeSupport: serverCodecModeSupport
        )
    }

    private static func normalizedRouteHost(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func normalizedManualRouteHost(
        activeHost: String,
        localHost: String?,
        remoteHost: String?
    ) -> String? {
        let normalizedActiveHost = activeHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedActiveHost.isEmpty else {
            return nil
        }
        if normalizedActiveHost == localHost || normalizedActiveHost == remoteHost {
            return nil
        }
        return normalizedActiveHost
    }

    static func parseAppList(xml: String) throws -> [ShadowClientRemoteAppDescriptor] {
        let document = try ShadowClientXMLAppListParser.parse(xml: xml)
        try validateRoot(document.rootStatus)
        if isApolloPermissionDeniedSentinel(document.apps) {
            throw ShadowClientGameStreamError.responseRejected(
                code: 403,
                message: "Permission denied"
            )
        }

        return document.apps.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private static func isApolloPermissionDeniedSentinel(
        _ apps: [ShadowClientRemoteAppDescriptor]
    ) -> Bool {
        guard apps.count == 1, let app = apps.first else {
            return false
        }

        return app.id == 114_514 &&
            app.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare("Permission Denied") == .orderedSame
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

    private static func normalizedHostDisplayName(_ rawValue: String?, fallbackHost: String) -> String {
        guard let candidate = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines), !candidate.isEmpty else {
            return fallbackHost
        }

        let normalized = candidate.lowercased()
        if normalized == "unknown" || normalized == "unknown name" {
            return fallbackHost
        }

        return candidate
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
