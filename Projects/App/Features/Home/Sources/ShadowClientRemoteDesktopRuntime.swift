import Combine
import Darwin
import Foundation
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
    public let isSaved: Bool
    public let displayName: String
    public let pairStatus: ShadowClientRemoteHostPairStatus
    public let currentGameID: Int
    public let serverState: String
    public let appVersion: String?
    public let gfeVersion: String?
    public let uniqueID: String?
    public let macAddress: String?
    public let serverCodecModeSupport: Int
    public let controlHTTPSPort: Int?
    public let lastError: String?
    public let routes: ShadowClientRemoteHostRoutes

    public init(
        host: String,
        isSaved: Bool = false,
        displayName: String,
        pairStatus: ShadowClientRemoteHostPairStatus,
        currentGameID: Int,
        serverState: String,
        httpsPort: Int,
        appVersion: String?,
        gfeVersion: String?,
        uniqueID: String?,
        macAddress: String? = nil,
        serverCodecModeSupport: Int = 0,
        controlHTTPSPort: Int? = nil,
        lastError: String?,
        localHost: String? = nil,
        remoteHost: String? = nil,
        manualHost: String? = nil
    ) {
        self.id = Self.stableIdentifier(host: host, uniqueID: uniqueID)
        self.isSaved = isSaved
        self.displayName = displayName
        self.pairStatus = pairStatus
        self.currentGameID = currentGameID
        self.serverState = serverState
        self.appVersion = appVersion
        self.gfeVersion = gfeVersion
        self.uniqueID = uniqueID
        self.macAddress = macAddress
        self.serverCodecModeSupport = serverCodecModeSupport
        self.controlHTTPSPort = controlHTTPSPort
        self.lastError = lastError
        self.routes = ShadowClientRemoteHostRoutes(
            active: .init(host: host, httpsPort: httpsPort),
            local: localHost.map { .init(host: $0, httpsPort: httpsPort) },
            remote: remoteHost.map { .init(host: $0, httpsPort: httpsPort) },
            manual: manualHost.map { .init(host: $0, httpsPort: httpsPort) }
        )
    }

    public init(
        activeRoute: ShadowClientRemoteHostEndpoint,
        isSaved: Bool = false,
        displayName: String,
        pairStatus: ShadowClientRemoteHostPairStatus,
        currentGameID: Int,
        serverState: String,
        appVersion: String?,
        gfeVersion: String?,
        uniqueID: String?,
        macAddress: String? = nil,
        serverCodecModeSupport: Int = 0,
        controlHTTPSPort: Int? = nil,
        lastError: String?,
        routes: ShadowClientRemoteHostRoutes
    ) {
        self.id = Self.stableIdentifier(host: activeRoute.host, uniqueID: uniqueID)
        self.isSaved = isSaved
        self.displayName = displayName
        self.pairStatus = pairStatus
        self.currentGameID = currentGameID
        self.serverState = serverState
        self.appVersion = appVersion
        self.gfeVersion = gfeVersion
        self.uniqueID = uniqueID
        self.macAddress = macAddress
        self.serverCodecModeSupport = serverCodecModeSupport
        self.controlHTTPSPort = controlHTTPSPort
        self.lastError = lastError
        self.routes = routes
    }

    public var host: String { routes.active.host }
    public var httpsPort: Int { routes.active.httpsPort }

    public var isPendingResolution: Bool {
        isSaved &&
            lastError == nil &&
            uniqueID == nil &&
            appVersion == nil &&
            gfeVersion == nil &&
            currentGameID == 0 &&
            serverState.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            routes.local == nil &&
            routes.remote == nil &&
            routes.manual == nil &&
            displayName.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(host) == .orderedSame
    }

    private static func stableIdentifier(host: String, uniqueID: String?) -> String {
        if let uniqueID {
            let normalizedUniqueID = uniqueID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !normalizedUniqueID.isEmpty {
                return "uniqueid:\(normalizedUniqueID)"
            }
        }
        return host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public var isReachable: Bool {
        lastError == nil && !isPendingResolution
    }

    public var statusLabel: String {
        authenticationState.statusLabel
    }

    public var detailLabel: String {
        if currentGameID > 0 {
            return "Active game ID: \(currentGameID)"
        }
        return authenticationState.detailLabel
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

public enum ShadowClientLumenAdminClientState: Equatable, Sendable {
    case idle
    case loading
    case saving
    case loaded
    case failed(String)
}

public enum ShadowClientRemoteHostWakeState: Equatable, Sendable {
    case idle
    case sending
    case sent(String)
    case failed(String)

    public var label: String {
        switch self {
        case .idle:
            return "Ready to send a magic packet."
        case .sending:
            return "Sending magic packet..."
        case let .sent(message):
            return message
        case let .failed(message):
            return message
        }
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
    let macAddress: String?
    let serverCodecModeSupport: Int
    let controlHTTPSPort: Int?

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
        macAddress: String? = nil,
        serverCodecModeSupport: Int = 0,
        controlHTTPSPort: Int? = nil
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
        self.macAddress = macAddress
        self.serverCodecModeSupport = serverCodecModeSupport
        self.controlHTTPSPort = controlHTTPSPort
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
    func fetchServerInfo(host: String) async throws -> ShadowClientGameStreamServerInfo
    func fetchServerInfo(
        host: String,
        pinnedServerCertificateDER: Data?
    ) async throws -> ShadowClientGameStreamServerInfo
    func fetchServerInfo(
        host: String,
        preferredAuthorityHost: String?,
        advertisedControlHTTPSPort: Int?,
        pinnedServerCertificateDER: Data?
    ) async throws -> ShadowClientGameStreamServerInfo
    func fetchAppList(host: String, httpsPort: Int?) async throws -> [ShadowClientRemoteAppDescriptor]
    func fetchAppList(
        host: String,
        httpsPort: Int?,
        preferredAuthorityHost: String?,
        advertisedControlHTTPSPort: Int?,
        pinnedServerCertificateDER: Data?
    ) async throws -> [ShadowClientRemoteAppDescriptor]
}

public extension ShadowClientGameStreamMetadataClient {
    func fetchServerInfo(
        host: String,
        pinnedServerCertificateDER _: Data?
    ) async throws -> ShadowClientGameStreamServerInfo {
        try await fetchServerInfo(host: host)
    }

    func fetchServerInfo(
        host: String,
        preferredAuthorityHost _: String?,
        advertisedControlHTTPSPort _: Int?,
        pinnedServerCertificateDER: Data?
    ) async throws -> ShadowClientGameStreamServerInfo {
        try await fetchServerInfo(host: host, pinnedServerCertificateDER: pinnedServerCertificateDER)
    }

    func fetchAppList(
        host: String,
        httpsPort: Int?,
        preferredAuthorityHost _: String?,
        advertisedControlHTTPSPort _: Int?,
        pinnedServerCertificateDER _: Data?
    ) async throws -> [ShadowClientRemoteAppDescriptor] {
        try await fetchAppList(host: host, httpsPort: httpsPort)
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
    public let displayScalePercent: Int
    public let requestHiDPI: Bool
    public let prioritizeNetworkTraffic: Bool
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
        displayScalePercent: Int = 100,
        requestHiDPI: Bool = false,
        prioritizeNetworkTraffic: Bool = false,
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
        self.displayScalePercent = max(20, min(200, displayScalePercent))
        self.requestHiDPI = requestHiDPI
        self.prioritizeNetworkTraffic = prioritizeNetworkTraffic
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
    case keyDown(keyCode: UInt16, characters: String?, modifiers: UInt8 = 0)
    case keyUp(keyCode: UInt16, characters: String?, modifiers: UInt8 = 0)
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
    static let modifierShift: UInt8 = 0x01
    static let modifierControl: UInt8 = 0x02
    static let modifierAlternate: UInt8 = 0x04

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
        clientCertificateCredential: URLCredential?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?
    ) async throws -> String {
        try await ShadowClientGameStreamHTTPTransport.requestXML(
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
    private let authenticationContextBuilder: ShadowClientLumenAuthenticationContextBuilder
    private let transport: any ShadowClientGameStreamRequestTransporting
    private let lumenTransport: any ShadowClientLumenHTTPTransport
    private let defaultHTTPPort: Int
    private let defaultHTTPSPort: Int

    public init(
        identityStore: ShadowClientPairingIdentityStore = .shared,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared,
        transport: any ShadowClientGameStreamRequestTransporting = NativeShadowClientGameStreamRequestTransport(),
        defaultHTTPPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPPort,
        defaultHTTPSPort: Int = ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
    ) {
        self.init(
            identityStore: identityStore,
            pinnedCertificateStore: pinnedCertificateStore,
            authenticationContextBuilder: ShadowClientLumenAuthenticationContextBuilder(
                identityStore: identityStore,
                pinnedCertificateStore: pinnedCertificateStore
            ),
            transport: transport,
            lumenTransport: NativeShadowClientLumenHTTPTransport(),
            defaultHTTPPort: defaultHTTPPort,
            defaultHTTPSPort: defaultHTTPSPort
        )
    }

    init(
        identityStore: ShadowClientPairingIdentityStore,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore,
        authenticationContextBuilder: ShadowClientLumenAuthenticationContextBuilder,
        transport: any ShadowClientGameStreamRequestTransporting,
        lumenTransport: any ShadowClientLumenHTTPTransport,
        defaultHTTPPort: Int,
        defaultHTTPSPort: Int
    ) {
        self.identityStore = identityStore
        self.pinnedCertificateStore = pinnedCertificateStore
        self.authenticationContextBuilder = authenticationContextBuilder
        self.transport = transport
        self.lumenTransport = lumenTransport
        self.defaultHTTPPort = defaultHTTPPort
        self.defaultHTTPSPort = defaultHTTPSPort
    }

    public func fetchServerInfo(host: String) async throws -> ShadowClientGameStreamServerInfo {
        try await fetchServerInfo(
            host: host,
            preferredAuthorityHost: nil,
            advertisedControlHTTPSPort: nil,
            pinnedServerCertificateDER: nil
        )
    }

    public func fetchServerInfo(
        host: String,
        pinnedServerCertificateDER overridePinnedCertificateDER: Data?
    ) async throws -> ShadowClientGameStreamServerInfo {
        try await fetchServerInfo(
            host: host,
            preferredAuthorityHost: nil,
            advertisedControlHTTPSPort: nil,
            pinnedServerCertificateDER: overridePinnedCertificateDER
        )
    }

    public func fetchServerInfo(
        host: String,
        preferredAuthorityHost: String?,
        advertisedControlHTTPSPort: Int?,
        pinnedServerCertificateDER overridePinnedCertificateDER: Data?
    ) async throws -> ShadowClientGameStreamServerInfo {
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPSPort)
        let pinnedCertificateDER: Data?
        if let overridePinnedCertificateDER {
            pinnedCertificateDER = overridePinnedCertificateDER
        } else {
            pinnedCertificateDER = await pinnedCertificateStore.certificateDER(
                forHost: endpoint.host,
                httpsPort: endpoint.port
            )
        }

        if let lumenDescriptor = try await fetchLumenHostDescriptor(
            connectHost: endpoint.host,
            authorityHost: Self.normalizedAuthorityHost(preferredAuthorityHost) ?? endpoint.host,
            streamHTTPSPort: endpoint.port,
            controlHTTPSPort: advertisedControlHTTPSPort,
            pinnedServerCertificateDER: pinnedCertificateDER
        ) {
            await registerServerIdentity(
                info: lumenDescriptor,
                requestedHost: endpoint.host,
                requestedHTTPSPort: endpoint.port,
                pinnedCertificateDER: pinnedCertificateDER
            )
            return lumenDescriptor
        }

        if pinnedCertificateDER == nil {
            do {
                let httpXML = try await requestXML(
                    host: endpoint.host,
                    port: ShadowClientGameStreamNetworkDefaults.httpPort(forHTTPSPort: endpoint.port),
                    scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
                    command: "serverinfo",
                    overridePinnedCertificateDER: pinnedCertificateDER
                )

                let info = try ShadowClientGameStreamXMLParsers.parseServerInfo(
                    xml: httpXML,
                    host: endpoint.host,
                    fallbackHTTPSPort: endpoint.port
                )
                await registerServerIdentity(
                    info: info,
                    requestedHost: endpoint.host,
                    requestedHTTPSPort: endpoint.port,
                    pinnedCertificateDER: pinnedCertificateDER
                )
                return info
            } catch let httpError as ShadowClientGameStreamError {
                do {
                    let httpsXML = try await requestXML(
                        host: endpoint.host,
                        port: endpoint.port,
                        scheme: ShadowClientGameStreamNetworkDefaults.httpsScheme,
                        command: "serverinfo",
                        overridePinnedCertificateDER: pinnedCertificateDER
                    )

                    let info = try ShadowClientGameStreamXMLParsers.parseServerInfo(
                        xml: httpsXML,
                        host: endpoint.host,
                        fallbackHTTPSPort: endpoint.port
                    )
                    await registerServerIdentity(
                        info: info,
                        requestedHost: endpoint.host,
                        requestedHTTPSPort: endpoint.port,
                        pinnedCertificateDER: pinnedCertificateDER
                    )
                    return info
                } catch let httpsError as ShadowClientGameStreamError {
                    if Self.shouldSynthesizeUnpairedServerInfo(
                        primaryHTTPError: httpError,
                        httpsError: httpsError
                    ) {
                        return Self.makeUnauthorizedServerInfo(
                            host: endpoint.host,
                            fallbackHTTPSPort: endpoint.port,
                            controlHTTPSPort: advertisedControlHTTPSPort
                        )
                    }
                    throw Self.combinedFallbackFailure(
                        primary: httpError,
                        fallbackLabel: "HTTPS fallback",
                        fallback: httpsError
                    )
                }
            }
        }

        do {
            let httpsXML = try await requestXML(
                host: endpoint.host,
                port: endpoint.port,
                scheme: ShadowClientGameStreamNetworkDefaults.httpsScheme,
                command: "serverinfo",
                overridePinnedCertificateDER: pinnedCertificateDER
            )

            let info = try ShadowClientGameStreamXMLParsers.parseServerInfo(
                xml: httpsXML,
                host: endpoint.host,
                fallbackHTTPSPort: endpoint.port
            )
            await registerServerIdentity(
                info: info,
                requestedHost: endpoint.host,
                requestedHTTPSPort: endpoint.port,
                pinnedCertificateDER: pinnedCertificateDER
            )
            return info
        } catch let httpsError as ShadowClientGameStreamError {
            if Self.isUnauthorizedCertificateError(httpsError) {
                if pinnedCertificateDER != nil {
                    if Self.isPinnedTrustFailure(httpsError) {
                        await pinnedCertificateStore.markRejectedHost(endpoint.host)
                    }
                    throw httpsError
                }
                if Self.shouldSkipPlainHTTPFallback(host: endpoint.host, httpsError: httpsError) {
                    return Self.makeUnauthorizedServerInfo(
                        host: endpoint.host,
                        fallbackHTTPSPort: endpoint.port,
                        controlHTTPSPort: advertisedControlHTTPSPort
                    )
                }
                do {
                    let httpXML = try await requestXML(
                        host: endpoint.host,
                        port: ShadowClientGameStreamNetworkDefaults.httpPort(forHTTPSPort: endpoint.port),
                        scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
                        command: "serverinfo",
                        overridePinnedCertificateDER: pinnedCertificateDER
                    )

                    let info = try ShadowClientGameStreamXMLParsers.parseServerInfo(
                        xml: httpXML,
                        host: endpoint.host,
                        fallbackHTTPSPort: endpoint.port
                    )
                    await registerServerIdentity(
                        info: info,
                        requestedHost: endpoint.host,
                        requestedHTTPSPort: endpoint.port,
                        pinnedCertificateDER: pinnedCertificateDER
                    )
                    return info
                } catch let httpError as ShadowClientGameStreamError {
                    if Self.isAppTransportSecurityBlockedError(httpError) {
                        return Self.makeUnauthorizedServerInfo(
                            host: endpoint.host,
                            fallbackHTTPSPort: endpoint.port,
                            controlHTTPSPort: advertisedControlHTTPSPort
                        )
                    }
                } catch {}

                return Self.makeUnauthorizedServerInfo(
                    host: endpoint.host,
                    fallbackHTTPSPort: endpoint.port,
                    controlHTTPSPort: advertisedControlHTTPSPort
                )
            }

            if Self.shouldSkipPlainHTTPFallback(host: endpoint.host, httpsError: httpsError) {
                throw httpsError
            }
            do {
                let httpXML = try await requestXML(
                    host: endpoint.host,
                    port: ShadowClientGameStreamNetworkDefaults.httpPort(forHTTPSPort: endpoint.port),
                    scheme: ShadowClientGameStreamNetworkDefaults.httpScheme,
                    command: "serverinfo",
                    overridePinnedCertificateDER: pinnedCertificateDER
                )

                let info = try ShadowClientGameStreamXMLParsers.parseServerInfo(
                    xml: httpXML,
                    host: endpoint.host,
                    fallbackHTTPSPort: endpoint.port
                )
                await registerServerIdentity(
                    info: info,
                    requestedHost: endpoint.host,
                    requestedHTTPSPort: endpoint.port,
                    pinnedCertificateDER: pinnedCertificateDER
                )
                return info
            } catch let httpError as ShadowClientGameStreamError {
                if Self.isAppTransportSecurityBlockedError(httpError) {
                    throw httpsError
                }
                if pinnedCertificateDER != nil {
                    throw Self.combinedFallbackFailure(
                        primary: httpsError,
                        fallback: httpError
                    )
                }
                throw httpError
            }
        }
    }

    private struct LumenDiscoveryEnvelope: Decodable {
        let host: LumenDiscoveryHostPayload
    }

    private struct LumenDiscoveryHostPayload: Decodable {
        let displayName: String
        let pairStatus: String
        let currentGameID: Int
        let serverState: String
        let streamHttpsPort: Int?
        let controlHttpsPort: Int?
        let serverUniqueId: String?
        let authorityHost: String?
        let serverCodecModeSupport: Int?
    }

    private struct LumenAppListEnvelope: Decodable {
        let apps: [LumenAppPayload]
    }

    private struct LumenAppPayload: Decodable {
        let id: Int?
        let title: String?
        let name: String?
        let hdrSupported: Bool?
        let isAppCollectorGame: Bool?
    }

    private func fetchLumenHostDescriptor(
        connectHost: String,
        authorityHost: String,
        streamHTTPSPort: Int,
        controlHTTPSPort: Int?,
        pinnedServerCertificateDER: Data?
    ) async throws -> ShadowClientGameStreamServerInfo? {
        let route = ShadowClientLumenRequestRoute(
            connectHost: connectHost,
            authorityHost: authorityHost,
            httpsPort: streamHTTPSPort
        )
        let requestContexts = try await authenticationContextBuilder.makePairingContexts(
            route: route,
            advertisedControlHTTPSPort: controlHTTPSPort
        )
        var lastError: Error?

        for requestContext in requestContexts {
            let request = try requestContext.makeRequestData(
                path: "/api/discovery/host",
                method: "GET"
            )

            do {
                let response = try await lumenTransport.request(
                    url: request.url,
                    connectHost: request.connectHost,
                    requestData: request.requestData,
                    pinnedServerCertificateDER: requestContext.pinnedServerCertificateDER ?? pinnedServerCertificateDER,
                    clientCertificates: requestContext.clientCertificates,
                    clientCertificateIdentity: requestContext.clientCertificateIdentity,
                    timeout: ShadowClientGameStreamNetworkDefaults.defaultRequestTimeout
                )

                let payload = try JSONDecoder().decode(LumenDiscoveryEnvelope.self, from: response.body)
                return Self.parseLumenDiscoveryHost(
                    payload.host,
                    connectHost: connectHost,
                    authorityHost: authorityHost,
                    fallbackHTTPSPort: streamHTTPSPort,
                    fallbackControlHTTPSPort: controlHTTPSPort
                )
            } catch let error as ShadowClientGameStreamError {
                lastError = error
            } catch {
                lastError = ShadowClientGameStreamHTTPTransport.requestFailureError(error)
            }
        }

        if let lastError {
            if case let ShadowClientGameStreamError.responseRejected(code, _) = lastError, code == 404 {
                return nil
            }
        }

        return nil
    }

    private static func parseLumenDiscoveryHost(
        _ payload: LumenDiscoveryHostPayload,
        connectHost: String,
        authorityHost: String,
        fallbackHTTPSPort: Int,
        fallbackControlHTTPSPort: Int?
    ) -> ShadowClientGameStreamServerInfo {
        let resolvedAuthorityHost = normalizedDiscoveredRouteHost(payload.authorityHost) ?? normalizedDiscoveredRouteHost(authorityHost)
        let remoteHost = resolvedAuthorityHost != normalizedDiscoveredRouteHost(connectHost) ? resolvedAuthorityHost : nil
        let displayName = normalizedDiscoveredHostDisplayName(payload.displayName, fallbackHost: connectHost)
        let pairStatus = ShadowClientRemoteHostPairStatus(rawValue: payload.pairStatus) ?? .unknown

        return ShadowClientGameStreamServerInfo(
            host: connectHost,
            localHost: nil,
            remoteHost: remoteHost,
            manualHost: nil,
            displayName: displayName,
            pairStatus: pairStatus,
            currentGameID: payload.currentGameID,
            serverState: payload.serverState,
            httpsPort: payload.streamHttpsPort ?? fallbackHTTPSPort,
            appVersion: nil,
            gfeVersion: nil,
            uniqueID: payload.serverUniqueId,
            macAddress: nil,
            serverCodecModeSupport: payload.serverCodecModeSupport ?? 0,
            controlHTTPSPort: payload.controlHttpsPort ?? fallbackControlHTTPSPort
        )
    }

    private static func normalizedAuthorityHost(_ value: String?) -> String? {
        normalizedDiscoveredRouteHost(value)
    }

    private static func normalizedDiscoveredRouteHost(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = trimmed.lowercased()
        guard !ShadowClientRemoteHostCandidateFilter.isLoopbackHost(normalized) else {
            return nil
        }

        return trimmed
    }

    private static func normalizedDiscoveredHostDisplayName(_ value: String?, fallbackHost: String) -> String {
        guard let value else {
            return fallbackHost
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return fallbackHost
        }

        let normalized = trimmed.lowercased()
        if normalized == "unknown" || normalized == "unknown name" {
            return fallbackHost
        }

        return trimmed
    }

    public func fetchAppList(host: String, httpsPort: Int?) async throws -> [ShadowClientRemoteAppDescriptor] {
        try await fetchAppList(
            host: host,
            httpsPort: httpsPort,
            preferredAuthorityHost: nil,
            advertisedControlHTTPSPort: nil,
            pinnedServerCertificateDER: nil
        )
    }

    public func fetchAppList(
        host: String,
        httpsPort: Int?,
        preferredAuthorityHost: String?,
        advertisedControlHTTPSPort: Int?,
        pinnedServerCertificateDER overridePinnedCertificateDER: Data?
    ) async throws -> [ShadowClientRemoteAppDescriptor] {
        let endpoint = try Self.parseHostEndpoint(host: host, fallbackPort: defaultHTTPSPort)
        let resolvedHTTPSPort = httpsPort ?? endpoint.port
        let pinnedCertificateDER: Data?
        if let overridePinnedCertificateDER {
            pinnedCertificateDER = overridePinnedCertificateDER
        } else {
            pinnedCertificateDER = await pinnedCertificateStore.certificateDER(
                forHost: endpoint.host,
                httpsPort: resolvedHTTPSPort
            )
        }

        guard pinnedCertificateDER != nil else {
            throw ShadowClientGameStreamError.requestFailed(
                "Host requires a paired HTTPS certificate before app list queries."
            )
        }

        let normalizedAuthorityHost = Self.normalizedAuthorityHost(preferredAuthorityHost) ?? endpoint.host
        return try await fetchLumenAppList(
            connectHost: endpoint.host,
            authorityHost: normalizedAuthorityHost,
            streamHTTPSPort: resolvedHTTPSPort,
            controlHTTPSPort: advertisedControlHTTPSPort,
            pinnedServerCertificateDER: pinnedCertificateDER
        ) ?? []
    }

    private func fetchLumenAppList(
        connectHost: String,
        authorityHost: String,
        streamHTTPSPort: Int,
        controlHTTPSPort: Int?,
        pinnedServerCertificateDER: Data?
    ) async throws -> [ShadowClientRemoteAppDescriptor]? {
        let route = ShadowClientLumenRequestRoute(
            connectHost: connectHost,
            authorityHost: authorityHost,
            httpsPort: streamHTTPSPort
        )
        let requestContexts = try await authenticationContextBuilder.makePairingContexts(
            route: route,
            advertisedControlHTTPSPort: controlHTTPSPort
        )
        var lastError: Error?

        for requestContext in requestContexts {
            let request = try requestContext.makeRequestData(
                path: "/api/discovery/apps",
                method: "GET"
            )

            do {
                let response = try await lumenTransport.request(
                    url: request.url,
                    connectHost: request.connectHost,
                    requestData: request.requestData,
                    pinnedServerCertificateDER: requestContext.pinnedServerCertificateDER ?? pinnedServerCertificateDER,
                    clientCertificates: requestContext.clientCertificates,
                    clientCertificateIdentity: requestContext.clientCertificateIdentity,
                    timeout: ShadowClientGameStreamNetworkDefaults.defaultRequestTimeout
                )

                let payload = try JSONDecoder().decode(LumenAppListEnvelope.self, from: response.body)
                return Self.parseLumenAppList(payload.apps)
            } catch let error as ShadowClientGameStreamError {
                lastError = error
            } catch {
                lastError = ShadowClientGameStreamHTTPTransport.requestFailureError(error)
            }
        }

        if let lastError {
            if case let ShadowClientGameStreamError.responseRejected(code, _) = lastError, code == 404 {
                return nil
            }
            throw lastError
        }

        return nil
    }

    private static func parseLumenAppList(
        _ payloads: [LumenAppPayload]
    ) -> [ShadowClientRemoteAppDescriptor] {
        payloads.compactMap { payload in
            guard let id = payload.id, id > 0 else {
                return nil
            }

            let title = (payload.title ?? payload.name ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else {
                return nil
            }

            return .init(
                id: id,
                title: title,
                hdrSupported: payload.hdrSupported ?? false,
                isAppCollectorGame: payload.isAppCollectorGame ?? false
            )
        }
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

    private static func isPinnedTrustFailure(_ error: ShadowClientGameStreamError) -> Bool {
        switch error {
        case let .responseRejected(_, message), let .requestFailed(message):
            let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.contains("certificate verification failed") ||
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

    private static func shouldSynthesizeUnpairedServerInfo(
        primaryHTTPError: ShadowClientGameStreamError,
        httpsError: ShadowClientGameStreamError
    ) -> Bool {
        guard case let .requestFailed(httpMessage) = primaryHTTPError else {
            return false
        }
        let normalizedHTTPMessage = httpMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard normalizedHTTPMessage.contains("connection refused") ||
                normalizedHTTPMessage.contains("could not connect")
        else {
            return false
        }

        guard case let .responseRejected(code, _) = httpsError else {
            return false
        }
        return code == 404
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
        fallbackHTTPSPort: Int,
        controlHTTPSPort: Int? = nil
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
            uniqueID: nil,
            controlHTTPSPort: controlHTTPSPort
        )
    }

    private static func combinedFallbackFailure(
        primary: ShadowClientGameStreamError,
        fallbackLabel: String = "HTTP fallback",
        fallback: ShadowClientGameStreamError
    ) -> ShadowClientGameStreamError {
        .requestFailed(
            "\(primary.localizedDescription) (\(fallbackLabel) also failed: \(fallback.localizedDescription))"
        )
    }

    private func requestXML(
        host: String,
        port: Int,
        scheme: String,
        command: String,
        overridePinnedCertificateDER: Data? = nil
    ) async throws -> String {
        let uniqueID = await identityStore.uniqueID()
        let pinnedCertificateDER: Data?
        if let overridePinnedCertificateDER {
            pinnedCertificateDER = overridePinnedCertificateDER
        } else {
            pinnedCertificateDER = if scheme == ShadowClientGameStreamNetworkDefaults.httpsScheme {
                await pinnedCertificateStore.certificateDER(forHost: host, httpsPort: port)
            } else {
                nil
            }
        }
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
        return try await transport.requestXML(
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

    private func registerServerIdentity(
        info: ShadowClientGameStreamServerInfo,
        requestedHost: String,
        requestedHTTPSPort: Int,
        pinnedCertificateDER: Data?
    ) async {
        guard let uniqueID = info.uniqueID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !uniqueID.isEmpty
        else {
            return
        }

        await pinnedCertificateStore.bindHost(
            requestedHost,
            httpsPort: requestedHTTPSPort,
            toMachineID: uniqueID
        )
        for host in [info.host, info.localHost, info.remoteHost, info.manualHost].compactMap({ $0 }) {
            await pinnedCertificateStore.bindHost(
                host,
                httpsPort: info.httpsPort,
                toMachineID: uniqueID
            )
        }
        await pinnedCertificateStore.clearRejectedHost(requestedHost)

        if let pinnedCertificateDER {
            await pinnedCertificateStore.setCertificateDER(pinnedCertificateDER, forMachineID: uniqueID)
            await pinnedCertificateStore.setCertificateDER(
                pinnedCertificateDER,
                forHost: requestedHost,
                httpsPort: requestedHTTPSPort
            )
        }
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

        let resolvedPort = ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
            fromCandidatePort: url.port ?? fallbackPort
        )
        return (parsedHost, resolvedPort)
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
        preferredAuthorityHost: String?,
        preferredControlHTTPSPort: Int?
    )
    case pairSelectedHost(username: String?, password: String?)
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
    case wakeSelectedHost(macAddress: String, port: UInt16)
    case refreshSelectedHostApps
    case refreshSelectedHostLumenAdmin(username: String, password: String)
    case updateSelectedHostLumenAdmin(
        username: String,
        password: String,
        displayModeOverride: String,
        alwaysUseVirtualDisplay: Bool
    )
    case disconnectSelectedHostLumenAdmin(username: String, password: String)
    case unpairSelectedHostLumenAdmin(username: String, password: String)
}

private struct ShadowClientLaunchRequestContext: Sendable {
    let hostKey: String
    let appID: Int
    let appTitle: String?
    let settings: ShadowClientGameStreamLaunchSettings
}

private struct ShadowClientLumenRouteCandidate: Equatable, Sendable {
    let connectEndpoint: ShadowClientRemoteHostEndpoint
    let authorityEndpoint: ShadowClientRemoteHostEndpoint

    var requestRoute: ShadowClientLumenRequestRoute {
        .init(
            connectHost: connectEndpoint.host,
            authorityHost: authorityEndpoint.host,
            httpsPort: authorityEndpoint.httpsPort
        )
    }
}

private struct ShadowClientPersistedRemoteHostCatalog: Codable {
    let hosts: [ShadowClientPersistedRemoteHostRecord]
}

private struct ShadowClientPersistedRemoteHostRecord: Codable {
    let activeHost: String
    let httpsPort: Int
    let isSaved: Bool?
    let displayName: String
    let pairStatusRawValue: String
    let currentGameID: Int
    let serverState: String
    let appVersion: String?
    let gfeVersion: String?
    let uniqueID: String?
    let macAddress: String?
    let lastError: String?
    let localHost: String?
    let remoteHost: String?
    let manualHost: String?

    init(descriptor: ShadowClientRemoteHostDescriptor) {
        activeHost = descriptor.host
        httpsPort = descriptor.httpsPort
        isSaved = descriptor.isSaved
        displayName = descriptor.displayName
        pairStatusRawValue = descriptor.pairStatus.rawValue
        currentGameID = descriptor.currentGameID
        serverState = descriptor.serverState
        appVersion = descriptor.appVersion
        gfeVersion = descriptor.gfeVersion
        uniqueID = descriptor.uniqueID
        macAddress = descriptor.macAddress
        lastError = descriptor.lastError
        localHost = descriptor.routes.local?.host
        remoteHost = descriptor.routes.remote?.host
        manualHost = descriptor.routes.manual?.host
    }

    var descriptor: ShadowClientRemoteHostDescriptor {
        ShadowClientRemoteHostDescriptor(
            host: activeHost,
            isSaved: isSaved ?? false,
            displayName: displayName,
            pairStatus: ShadowClientRemoteHostPairStatus(rawValue: pairStatusRawValue) ?? .unknown,
            currentGameID: currentGameID,
            serverState: serverState,
            httpsPort: httpsPort,
            appVersion: appVersion,
            gfeVersion: gfeVersion,
            uniqueID: uniqueID,
            macAddress: macAddress,
            lastError: lastError,
            localHost: localHost,
            remoteHost: remoteHost,
            manualHost: manualHost
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
        let persistableHosts = hosts.filter { $0.pairStatus == .paired || $0.isSaved }
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

    private struct PendingHostRefreshRequest: Equatable {
        let candidates: [String]
        let preferredHost: String?
        let preferredAuthorityHost: String?
        let preferredControlHTTPSPort: Int?
    }

    private typealias LumenPairingRoute = ShadowClientLumenRouteCandidate

    @Published public private(set) var hosts: [ShadowClientRemoteHostDescriptor] = []
    @Published public private(set) var apps: [ShadowClientRemoteAppDescriptor] = []
    @Published public private(set) var hostState: ShadowClientRemoteHostCatalogState = .idle
    @Published public private(set) var appState: ShadowClientRemoteAppCatalogState = .idle
    @Published public private(set) var selectedHostID: String?
    @Published public private(set) var pairingState: ShadowClientRemotePairingState = .idle
    @Published public private(set) var launchState: ShadowClientRemoteLaunchState = .idle
    @Published public private(set) var activeSession: ShadowClientActiveRemoteSession?
    @Published public private(set) var sessionIssue: ShadowClientRemoteSessionIssue?
    @Published public private(set) var selectedHostLumenAdminProfile: ShadowClientLumenAdminClientProfile?
    @Published public private(set) var selectedHostLumenAdminState: ShadowClientLumenAdminClientState = .idle
    @Published public private(set) var selectedHostWakeState: ShadowClientRemoteHostWakeState = .idle
    public let sessionPresentationMode: ShadowClientRemoteSessionPresentationMode
    public let sessionSurfaceContext: ShadowClientRealtimeSessionSurfaceContext

    private let metadataClient: any ShadowClientGameStreamMetadataClient
    private let controlClient: any ShadowClientGameStreamControlClient
    private let pairingClient: any ShadowClientLumenPairingClient
    private let wakeOnLANClient: any ShadowClientWakeOnLANClient
    private let lumenAdminClient: any ShadowClientLumenAdminClient
    private let clipboardClient: any ShadowClientClipboardClient
    private let sessionConnectionClient: any ShadowClientRemoteSessionConnectionClient
    private let sessionInputClient: any ShadowClientRemoteSessionInputClient
    private let inputSendQueue: ShadowClientRemoteInputSendQueue
    private let pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    private let pairingRouteStore: ShadowClientPairingRouteStore
    private let hostAliasResolver: @Sendable ([String]) async -> [String: Set<String>]
    private let persistence: ShadowClientRemoteDesktopPersistence
    private let inputKeepAliveInterval: Duration
    private let clipboardSyncInterval: Duration
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "RemoteDesktopRuntime")
    private let commandContinuation: AsyncStream<ShadowClientRemoteDesktopCommand>.Continuation
    private var commandLoopTask: Task<Void, Never>?
    private var refreshHostsTask: Task<Void, Never>?
    private var activeHostRefreshRequest: PendingHostRefreshRequest?
    private var pendingHostRefreshRequest: PendingHostRefreshRequest?
    private var refreshAppsTask: Task<Void, Never>?
    private var pairTask: Task<Void, Never>?
    private var launchTask: Task<Void, Never>?
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
    private var clipboardReadUnavailable = false
    private var clipboardWriteUnavailable = false
    private var clipboardActionRequiresActiveStream = false
    private var hostTerminationIssue: ShadowClientRemoteSessionIssue?

    public init(
        metadataClient: any ShadowClientGameStreamMetadataClient = NativeGameStreamMetadataClient(),
        controlClient: any ShadowClientGameStreamControlClient = NativeGameStreamControlClient(),
        pairingClient: any ShadowClientLumenPairingClient = NativeShadowClientLumenPairingClient(),
        wakeOnLANClient: any ShadowClientWakeOnLANClient = NativeShadowClientWakeOnLANClient(),
        lumenAdminClient: any ShadowClientLumenAdminClient = NativeShadowClientLumenAdminClient(),
        clipboardClient: any ShadowClientClipboardClient = NativeShadowClientClipboardClient(),
        sessionConnectionClient: any ShadowClientRemoteSessionConnectionClient = NoopShadowClientRemoteSessionConnectionClient(),
        sessionInputClient: any ShadowClientRemoteSessionInputClient = NoopShadowClientRemoteSessionInputClient(),
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared,
        pairingRouteStore: ShadowClientPairingRouteStore = .shared,
        hostAliasResolver: (@Sendable ([String]) async -> [String: Set<String>])? = nil,
        inputKeepAliveInterval: Duration = .seconds(3),
        clipboardSyncInterval: Duration = .milliseconds(750),
        defaults: UserDefaults = .standard
    ) {
        let (commandStream, commandContinuation) = AsyncStream.makeStream(of: ShadowClientRemoteDesktopCommand.self)
        let persistence = ShadowClientRemoteDesktopPersistence(defaults: defaults)
        let persistedHosts = Self.normalizedPersistedHosts(persistence.loadCachedHosts())
        let persistedFingerprint = persistence.loadSessionFingerprint()

        self.metadataClient = metadataClient
        self.controlClient = controlClient
        self.pairingClient = pairingClient
        self.wakeOnLANClient = wakeOnLANClient
        self.lumenAdminClient = lumenAdminClient
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
        self.pinnedCertificateStore = pinnedCertificateStore
        self.pairingRouteStore = pairingRouteStore
        if let hostAliasResolver {
            self.hostAliasResolver = hostAliasResolver
        } else {
            self.hostAliasResolver = { hosts in
                await Self.resolveHostAliases(hosts)
            }
        }
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
        inputKeepAliveTask?.cancel()
        renderStateFailureObservation?.cancel()
    }

    @MainActor
    private func process(command: ShadowClientRemoteDesktopCommand) async {
        switch command {
        case let .refreshHosts(candidates, preferredHost, preferredAuthorityHost, preferredControlHTTPSPort):
            performRefreshHosts(
                candidates: candidates,
                preferredHost: preferredHost,
                preferredAuthorityHost: preferredAuthorityHost,
                preferredControlHTTPSPort: preferredControlHTTPSPort
            )
        case let .pairSelectedHost(username, password):
            performPairSelectedHost(username: username, password: password)
        case let .deleteHost(hostID):
            await performDeleteHost(hostID)
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
        case let .wakeSelectedHost(macAddress, port):
            performWakeSelectedHost(macAddress: macAddress, port: port)
        case .refreshSelectedHostApps:
            performRefreshSelectedHostApps()
        case let .refreshSelectedHostLumenAdmin(username, password):
            performRefreshSelectedHostLumenAdmin(username: username, password: password)
        case let .updateSelectedHostLumenAdmin(username, password, displayModeOverride, alwaysUseVirtualDisplay):
            performUpdateSelectedHostLumenAdmin(
                username: username,
                password: password,
                displayModeOverride: displayModeOverride,
                alwaysUseVirtualDisplay: alwaysUseVirtualDisplay
            )
        case let .disconnectSelectedHostLumenAdmin(username, password):
            performDisconnectSelectedHostLumenAdmin(
                username: username,
                password: password
            )
        case let .unpairSelectedHostLumenAdmin(username, password):
            performUnpairSelectedHostLumenAdmin(
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
    public var selectedHostAuthenticationState: ShadowClientRemoteHostAuthenticationState? {
        guard let selectedHost else {
            return nil
        }

        return selectedHost.authenticationState(
            adminState: selectedHostLumenAdminState,
            adminProfile: selectedHostLumenAdminProfile
        )
    }

    @MainActor
    public var activePairingCode: String? {
        pairingState.activeCode
    }

    @MainActor
    public func refreshHosts(
        candidates: [String],
        preferredHost: String? = nil,
        preferredAuthorityHost: String? = nil,
        preferredControlHTTPSPort: Int? = nil
    ) {
        commandContinuation.yield(
            .refreshHosts(
                candidates: candidates,
                preferredHost: preferredHost,
                preferredAuthorityHost: preferredAuthorityHost,
                preferredControlHTTPSPort: preferredControlHTTPSPort
            )
        )
    }

    @MainActor
    private func performRefreshHosts(
        candidates: [String],
        preferredHost: String? = nil,
        preferredAuthorityHost: String? = nil,
        preferredControlHTTPSPort: Int? = nil
    ) {
        let existingHosts = latestResolvedHostDescriptors.isEmpty ? hosts : latestResolvedHostDescriptors
        let selectedPublishedHost = selectedHost
        let normalizedCandidates = ShadowClientHostRefreshPlanKit.orderedCandidates(
            discoveredHosts: candidates,
            cachedHosts: ShadowClientHostCatalogKit.cachedCandidateHosts(from: existingHosts),
            preferredHost: preferredHost
        )
        let request = PendingHostRefreshRequest(
            candidates: normalizedCandidates,
            preferredHost: Self.normalizeCandidate(preferredHost),
            preferredAuthorityHost: Self.normalizedAuthorityHost(preferredAuthorityHost),
            preferredControlHTTPSPort: preferredControlHTTPSPort
        )
        logger.notice(
            "Host refresh scheduled candidates=\(normalizedCandidates.joined(separator: ","), privacy: .public) preferred=\((request.preferredHost ?? "nil"), privacy: .public) authority=\((request.preferredAuthorityHost ?? "nil"), privacy: .public) control-port=\((request.preferredControlHTTPSPort.map(String.init) ?? "nil"), privacy: .public)"
        )
        latestHostCandidates = normalizedCandidates
        guard !normalizedCandidates.isEmpty else {
            refreshHostsTask?.cancel()
            refreshHostsTask = nil
            activeHostRefreshRequest = nil
            pendingHostRefreshRequest = nil
            refreshAppsTask?.cancel()
            hosts = []
            latestResolvedHostDescriptors = []
            apps = []
            cachedAppsByHostID = [:]
            selectedHostID = nil
            clearSelectedHostLumenAdminState()
            clearSelectedHostWakeState()
            pendingSelectedHostID = nil
            hostState = .idle
            appState = .idle
            pairingState = .idle
            launchState = .idle
            return
        }

        if launchState.isTransitioning || activeSession != nil {
            logger.notice(
                "Skipping host metadata refresh while session transition is active"
            )
            return
        }

        if refreshHostsTask != nil {
            if request == activeHostRefreshRequest || request == pendingHostRefreshRequest {
                return
            }
            pendingHostRefreshRequest = request
            return
        }

        hostState = .loading
        activeHostRefreshRequest = request
        let metadataClient = metadataClient
        let pairingRouteStore = pairingRouteStore
        let pinnedCertificateStore = self.pinnedCertificateStore
        let hostAliasResolver = self.hostAliasResolver
        let preferredAuthorityHost = request.preferredAuthorityHost
        let preferredControlHTTPSPort = request.preferredControlHTTPSPort
        refreshHostsTask = Task { [weak self] in
            let hostAliasesByHost = await hostAliasResolver(
                normalizedCandidates + existingHosts.flatMap { descriptor in
                    descriptor.routes.allEndpoints.map(\.host)
                }
            )
            let existingPreferredRoutes = await Self.preferredRouteOverrides(
                for: existingHosts,
                pairingRouteStore: pairingRouteStore
            )
            let preferredAnchorHost = Self.preferredAnchorHost(
                from: existingHosts,
                selectedHost: selectedPublishedHost,
                preferredHost: preferredHost
            )
            let descriptors = await withTaskGroup(
                of: ShadowClientRemoteHostDescriptor.self,
                returning: [ShadowClientRemoteHostDescriptor].self
            ) { group in
                for host in normalizedCandidates {
                    group.addTask {
                        await Self.fetchHostDescriptor(
                            host: host,
                            metadataClient: metadataClient,
                            existingHosts: existingHosts,
                            preferredRoutesByKey: existingPreferredRoutes,
                            preferredHost: preferredHost,
                            preferredAuthorityHost: preferredAuthorityHost,
                            advertisedControlHTTPSPort: preferredControlHTTPSPort,
                            preferredAnchorHost: preferredAnchorHost,
                            hostAliasesByHost: hostAliasesByHost,
                            pinnedCertificateStore: pinnedCertificateStore
                        )
                    }
                }

                var resolved: [ShadowClientRemoteHostDescriptor] = []
                for await descriptor in group {
                    resolved.append(descriptor)
                }
                return resolved
            }

            let machineBoundDescriptors = await Self.descriptorsWithBoundMachineIdentity(
                descriptors,
                pinnedCertificateStore: pinnedCertificateStore
            )
            let sorted = machineBoundDescriptors.sorted(by: Self.compareHosts)
            await Self.synchronizePinnedCertificates(
                across: sorted,
                pinnedCertificateStore: pinnedCertificateStore
            )
            let pairedHostKeys = await Self.pairedHostKeys(
                for: sorted,
                existingHosts: existingHosts,
                pinnedCertificateStore: pinnedCertificateStore
            )
            let preferredRoutes = await Self.preferredRouteOverrides(
                for: sorted,
                pairingRouteStore: pairingRouteStore
            )
            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                self.refreshHostsTask = nil
                self.activeHostRefreshRequest = nil
                let preferredNormalized = Self.normalizeCandidate(preferredHost)
                let mergedHosts = Self.mergeResolvedHosts(
                    sorted,
                    selectedHostID: self.selectedHostID,
                    preferredHost: preferredNormalized,
                    preferredRoutesByKey: preferredRoutes,
                    pairedHostKeys: pairedHostKeys,
                    hostAliasesByHost: hostAliasesByHost
                )
                let publishedHosts = Self.deduplicatedHostDescriptorsByID(mergedHosts)
                    .filter(Self.shouldPublishHostDescriptor)
                let hostSummary = publishedHosts.map { descriptor in
                    let endpoints = descriptor.routes.allEndpoints
                        .map { "\($0.host):\($0.httpsPort)" }
                        .joined(separator: ",")
                    let uniqueID = descriptor.uniqueID ?? "nil"
                    let error = descriptor.lastError ?? "nil"
                    return "[id=\(descriptor.id) uniqueID=\(uniqueID) active=\(descriptor.host):\(descriptor.httpsPort) routes=\(endpoints) error=\(error)]"
                }
                self.logger.notice(
                    "Published remote desktop hosts count=\(publishedHosts.count, privacy: .public) \(hostSummary.joined(separator: " "), privacy: .public)"
                )
                self.hosts = publishedHosts
                self.latestResolvedHostDescriptors = publishedHosts
                self.persistence.saveCachedHosts(publishedHosts)

                if publishedHosts.isEmpty {
                    self.hostState = .failed("No hosts resolved.")
                    self.selectedHostID = nil
                    self.apps = []
                    self.appState = .idle
                    return
                }

                self.hostState = .loaded

                if let pendingSelectedHostID = self.pendingSelectedHostID,
                   let pendingSelectedHost = Self.resolveHostSelection(
                       pendingSelectedHostID,
                       in: publishedHosts
                   )
                {
                    self.selectedHostID = pendingSelectedHost.id
                    self.pendingSelectedHostID = nil
                } else {
                    self.pendingSelectedHostID = nil
                    if let selectedHostID = self.selectedHostID,
                       let selectedHost = Self.resolveHostSelection(selectedHostID, in: publishedHosts)
                    {
                        self.selectedHostID = selectedHost.id
                    } else if let preferredNormalized,
                              let preferred = publishedHosts.first(where: {
                                  Self.candidateMatchesDescriptor(preferredNormalized, matches: $0)
                              })
                    {
                        self.selectedHostID = preferred.id
                    } else {
                        self.selectedHostID = publishedHosts.first?.id
                    }
                }

                self.performRefreshSelectedHostApps()

                if let pendingHostRefreshRequest = self.pendingHostRefreshRequest {
                    self.pendingHostRefreshRequest = nil
                    self.performRefreshHosts(
                        candidates: pendingHostRefreshRequest.candidates,
                        preferredHost: pendingHostRefreshRequest.preferredHost,
                        preferredAuthorityHost: pendingHostRefreshRequest.preferredAuthorityHost,
                        preferredControlHTTPSPort: pendingHostRefreshRequest.preferredControlHTTPSPort
                    )
                }
            }
        }
    }

    @MainActor
    public func pairSelectedHost(username: String? = nil, password: String? = nil) {
        commandContinuation.yield(
            .pairSelectedHost(
                username: username,
                password: password
            )
        )
    }

    @MainActor
    public func deleteHost(_ hostID: String) {
        commandContinuation.yield(.deleteHost(hostID))
    }

    @MainActor
    public func saveHostCandidate(_ host: String) {
        guard let normalizedHost = Self.normalizeCandidate(host) else {
            return
        }

        let updatedHosts = Self.upsertingSavedHostCandidate(
            normalizedHost,
            into: latestResolvedHostDescriptors.isEmpty ? hosts : latestResolvedHostDescriptors
        )
        hosts = updatedHosts
        latestResolvedHostDescriptors = updatedHosts
        persistence.saveCachedHosts(updatedHosts)

        if let savedHost = Self.resolveHostSelection(normalizedHost, in: updatedHosts) {
            selectedHostID = savedHost.id
        }
    }

    @MainActor
    public func updateSavedHostCandidate(
        forHostID hostID: String,
        host: String
    ) {
        guard let normalizedHost = Self.normalizeCandidate(host) else {
            return
        }

        let sourceHosts = latestResolvedHostDescriptors.isEmpty ? hosts : latestResolvedHostDescriptors
        let updatedHosts = Self.updatingSavedHostCandidate(
            normalizedHost,
            forHostID: hostID,
            in: sourceHosts
        )
        hosts = updatedHosts
        latestResolvedHostDescriptors = updatedHosts
        persistence.saveCachedHosts(updatedHosts)

        if let updatedHost = updatedHosts.first(where: {
            $0.routes.allEndpoints.contains(where: { endpoint in
                Self.candidate(normalizedHost, matches: endpoint)
            })
        }) {
            selectedHostID = updatedHost.id
        }
    }

    @MainActor
    public func rememberPreferredHostRoute(_ host: String) async {
        guard let normalizedHost = Self.normalizeCandidate(host) else {
            return
        }

        let anchorHost = Self.preferredRouteAnchorHost(
            selectedHost: selectedHost,
            hosts: hosts
        )
        guard let anchorHost else {
            return
        }

        await persistPreferredRoute(connectRoute: normalizedHost, for: anchorHost)

        let updatedHosts = Self.upsertingManualRoute(
            normalizedHost,
            forHostID: anchorHost.id,
            in: hosts
        )
        hosts = updatedHosts
        latestResolvedHostDescriptors = Self.upsertingManualRoute(
            normalizedHost,
            forHostID: anchorHost.id,
            in: latestResolvedHostDescriptors
        )
        persistence.saveCachedHosts(updatedHosts)
    }

    private func persistPreferredRoute(
        connectRoute: String?,
        authorityHost: String? = nil,
        for anchorHost: ShadowClientRemoteHostDescriptor
    ) async {
        let normalizedRoute = Self.normalizeCandidate(connectRoute)
        let normalizedAuthorityHost = Self.normalizedAuthorityHost(authorityHost)
        let pairRouteKey = Self.pairRouteStoreKey(for: anchorHost)
        let mergeRouteKey = Self.mergeKey(for: anchorHost)
        await pairingRouteStore.setPreferredHost(normalizedRoute, for: pairRouteKey)
        await pairingRouteStore.setPreferredHost(normalizedRoute, for: mergeRouteKey)
        await pairingRouteStore.setPreferredAuthorityHost(normalizedAuthorityHost, for: pairRouteKey)
        await pairingRouteStore.setPreferredAuthorityHost(normalizedAuthorityHost, for: mergeRouteKey)
    }

    @MainActor
    private func performPairSelectedHost(username: String?, password: String?) {
        guard let selectedHost else {
            pairingState = .failed("Select host first.")
            return
        }
        pairTask?.cancel()
        pairGeneration &+= 1
        let currentPairGeneration = pairGeneration
        let pairingClient = pairingClient
        let lumenAdminClient = lumenAdminClient
        let pairingRouteStore = pairingRouteStore
        let currentHosts = latestResolvedHostDescriptors.isEmpty ? hosts : latestResolvedHostDescriptors
        let currentLatestHostCandidates = latestHostCandidates
        let trimmedUsername = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password?.trimmingCharacters(in: .whitespacesAndNewlines)
        pairTask = Task { [weak self] in
            do {
                let pairRouteKey = Self.pairRouteStoreKey(for: selectedHost)
                let storedPreferredPairHost = await pairingRouteStore.preferredHost(for: pairRouteKey)
                let pairCandidates = Self.pairHostCandidates(
                    for: selectedHost,
                    hosts: currentHosts,
                    latestHostCandidates: currentLatestHostCandidates,
                    preferredPairHost: storedPreferredPairHost
                )

                await MainActor.run { [weak self] in
                    self?.pairingState = .pairing(
                        host: selectedHost.displayName.isEmpty ? selectedHost.host : selectedHost.displayName,
                        code: ""
                    )
                }

                let pairingDeadline = Date().addingTimeInterval(
                    ShadowClientPairingDefaults.retryDeadlineSeconds
                )
                let maximumPairAttempts = ShadowClientPairingDefaults.maximumAttempts
                var lastError: Error?
                var pairedRoute: String?
                var pairedAuthorityHost: String?

                candidateLoop: for candidate in pairCandidates {
                    var pairAttemptCount = 0
                    while true {
                        pairAttemptCount += 1
                        do {
                            let startedPairing = try await pairingClient.startPairing(
                                route: candidate.requestRoute,
                                deviceName: nil,
                                platform: nil
                            )
                            let controlRoutes = Self.lumenPairingRoutes(
                                for: startedPairing,
                                fallbackRoute: .init(
                                    connectEndpoint: candidate.connectEndpoint,
                                    authorityEndpoint: .init(
                                        host: candidate.authorityEndpoint.host,
                                        httpsPort: startedPairing.controlHTTPSPort ?? candidate.authorityEndpoint.httpsPort
                                    )
                                )
                            )

                            await MainActor.run { [weak self] in
                                self?.pairingState = .pairing(
                                    host: selectedHost.displayName.isEmpty ? selectedHost.host : selectedHost.displayName,
                                    code: startedPairing.userCode
                                )
                            }

                            if let trimmedUsername,
                               let trimmedPassword,
                               !trimmedUsername.isEmpty,
                               !trimmedPassword.isEmpty,
                               startedPairing.status == .pending {
                                try await Self.approveLumenPairingRequest(
                                    routes: controlRoutes,
                                    lumenAdminClient: lumenAdminClient,
                                    username: trimmedUsername,
                                    password: trimmedPassword,
                                    pairingID: startedPairing.pairingID
                                )
                            }

                            let approvedRoute = try await Self.awaitLumenPairingApproval(
                                pairingClient: pairingClient,
                                routeCandidates: controlRoutes,
                                initialSession: startedPairing
                            )
                            let refreshEndpoint = Self.preferredRefreshEndpoint(for: approvedRoute)
                            pairedRoute = Self.serializedExactHostCandidate(for: refreshEndpoint)
                            pairedAuthorityHost = Self.preferredAuthorityHostCandidate(
                                for: selectedHost,
                                connectEndpoint: refreshEndpoint
                            )
                            if let self {
                                await self.persistPreferredRoute(
                                    connectRoute: pairedRoute,
                                    authorityHost: pairedAuthorityHost,
                                    for: selectedHost
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

                if let lastError, pairedRoute == nil {
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
                            preferredHost: pairedRoute
                        )
                    }
                    self.latestResolvedHostDescriptors = self.latestResolvedHostDescriptors.map {
                        Self.markHostAsPaired(
                            $0,
                            matching: selectedHost,
                            preferredHost: pairedRoute
                        )
                    }
                    self.performRefreshSelectedHostApps()
                    let candidates = self.latestHostCandidates.isEmpty
                        ? self.hosts.map(Self.activeRouteCandidate(for:))
                        : self.latestHostCandidates
                    self.refreshHosts(
                        candidates: candidates,
                        preferredHost: pairedRoute ?? Self.activeExactRouteCandidate(for: selectedHost),
                        preferredAuthorityHost: pairedAuthorityHost,
                        preferredControlHTTPSPort: Self.preferredControlHTTPSPortCandidate(for: selectedHost)
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

    private static func awaitLumenPairingApproval(
        pairingClient: any ShadowClientLumenPairingClient,
        routeCandidates: [LumenPairingRoute],
        initialSession: ShadowClientLumenPairingSession
    ) async throws -> LumenPairingRoute {
        var currentRoutes = routeCandidates
        var currentSession = initialSession

        while true {
            switch currentSession.status {
            case .approved:
                return currentRoutes.first
                    ?? .init(
                        connectEndpoint: .init(host: "", httpsPort: currentSession.controlHTTPSPort ?? 0),
                        authorityEndpoint: .init(host: "", httpsPort: currentSession.controlHTTPSPort ?? 0)
                    )
            case .rejected:
                throw ShadowClientGameStreamError.requestFailed("Shadow pairing request was rejected.")
            case .expired:
                throw ShadowClientGameStreamError.requestFailed("Shadow pairing request expired before approval.")
            case .pending:
                let pollIntervalSeconds = max(1, currentSession.pollIntervalSeconds)
                try await Task.sleep(for: .seconds(pollIntervalSeconds))
                try Task.checkCancellation()
                let (updatedSession, successfulRoute) = try await Self.fetchLumenPairingStatus(
                    pairingClient: pairingClient,
                    routeCandidates: currentRoutes,
                    pairingID: currentSession.pairingID
                )
                currentSession = updatedSession
                currentRoutes = Self.lumenPairingRoutes(
                    for: updatedSession,
                    fallbackRoute: successfulRoute
                )
            }
        }
    }

    private static func approveLumenPairingRequest(
        routes: [LumenPairingRoute],
        lumenAdminClient: any ShadowClientLumenAdminClient,
        username: String,
        password: String,
        pairingID: String
    ) async throws {
        var lastError: Error?
        for route in routes {
            do {
                try await lumenAdminClient.approvePairingRequest(
                    route: route.requestRoute,
                    username: username,
                    password: password,
                    pairingID: pairingID
                )
                return
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }
    }

    private static func fetchLumenPairingStatus(
        pairingClient: any ShadowClientLumenPairingClient,
        routeCandidates: [LumenPairingRoute],
        pairingID: String
    ) async throws -> (ShadowClientLumenPairingSession, LumenPairingRoute) {
        var lastError: Error?
        for route in routeCandidates {
            do {
                let session = try await pairingClient.fetchPairingStatus(
                    route: route.requestRoute,
                    pairingID: pairingID
                )
                return (session, route)
            } catch {
                lastError = error
            }
        }

        throw lastError ?? ShadowClientGameStreamError.requestFailed("Shadow pairing status request failed.")
    }

    private static func lumenPairingRoutes(
        for session: ShadowClientLumenPairingSession,
        fallbackRoute: LumenPairingRoute
    ) -> [LumenPairingRoute] {
        var routes: [LumenPairingRoute] = []
        var seenRoutes = Set<String>()

        func append(connectHost: String, authorityHost: String, httpsPort: Int) {
            let trimmedConnectHost = connectHost.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedAuthorityHost = authorityHost.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedConnectHost.isEmpty, !trimmedAuthorityHost.isEmpty else {
                return
            }

            let routeKey = "\(trimmedConnectHost.lowercased())|\(trimmedAuthorityHost.lowercased()):\(httpsPort)"
            guard seenRoutes.insert(routeKey).inserted else {
                return
            }

            routes.append(
                .init(
                    connectEndpoint: .init(host: trimmedConnectHost, httpsPort: httpsPort),
                    authorityEndpoint: .init(host: trimmedAuthorityHost, httpsPort: httpsPort)
                )
            )
        }

        func append(urlString: String?) {
            guard
                let urlString,
                let url = URL(string: urlString),
                let host = url.host
            else {
                return
            }

            let httpsPort = url.port ?? session.controlHTTPSPort ?? fallbackRoute.authorityEndpoint.httpsPort
            let connectHost: String
            if isLocalPairHost(host) || isLinkLocalRouteHost(host) {
                connectHost = host
            } else {
                connectHost = fallbackRoute.connectEndpoint.host
            }
            append(connectHost: connectHost, authorityHost: host, httpsPort: httpsPort)
        }

        append(urlString: session.preferredControlHTTPSURL)
        session.controlHTTPSURLs.forEach { append(urlString: $0) }
        append(
            connectHost: fallbackRoute.connectEndpoint.host,
            authorityHost: fallbackRoute.authorityEndpoint.host,
            httpsPort: fallbackRoute.authorityEndpoint.httpsPort
        )
        return routes
    }

    @MainActor
    private func performDeleteHost(_ hostID: String) async {
        guard let host = Self.resolveHostSelection(hostID, in: hosts) else {
            return
        }

        let mergeKey = Self.mergeKey(for: host)
        let remainingHosts = hosts.filter { $0.id != host.id }

        hosts = remainingHosts
        latestResolvedHostDescriptors = latestResolvedHostDescriptors.filter { $0.id != host.id }
        cachedAppsByHostID.removeValue(forKey: host.id)
        persistence.saveCachedHosts(remainingHosts)

        if selectedHostID == host.id {
            selectedHostID = remainingHosts.first?.id
            apps = []
            appState = remainingHosts.isEmpty ? .idle : appState
            clearSelectedHostLumenAdminState()
            clearSelectedHostWakeState()
        }

        await self.pairingRouteStore.setPreferredHost(nil, for: Self.pairRouteStoreKey(for: host))
        await self.pairingRouteStore.setPreferredHost(nil, for: mergeKey)
        await self.pairingRouteStore.setPreferredAuthorityHost(nil, for: Self.pairRouteStoreKey(for: host))
        await self.pairingRouteStore.setPreferredAuthorityHost(nil, for: mergeKey)
        if let normalizedMachineID = Self.normalizedUniqueID(host.uniqueID) {
            await self.pinnedCertificateStore.removeCertificates(forMachineID: normalizedMachineID)
        }
        let routeHosts = Set(
            host.routes.allEndpoints.map { endpoint in
                endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
        )
        for endpoint in host.routes.allEndpoints {
            await self.pinnedCertificateStore.removeCertificate(
                forHost: endpoint.host,
                httpsPort: endpoint.httpsPort
            )
        }
        for routeHost in routeHosts {
            await self.pinnedCertificateStore.removeCertificate(forHost: routeHost)
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

        let isReconfiguringActiveSession =
            activeSession?.appID == appID &&
            activeSession?.host.lowercased() == selectedHost.host.lowercased()
        let selectedHostKey = Self.mergeKey(for: selectedHost)
        let launchedAppTitle = appTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let launchSettingsToUse = Self.normalizeAudioLaunchSettings(
            Self.normalizeCodecLaunchSettings(
                launchSettingsApplyingPersistentFallback(settings),
                serverCodecModeSupport: selectedHost.serverCodecModeSupport
            ),
            maximumOutputChannels: ShadowClientAudioOutputCapabilityKit.currentMaximumOutputChannels()
        )
        let duplicateLaunchRequestInFlight = launchState.isTransitioning &&
            lastLaunchRequestContext?.hostKey == selectedHostKey &&
            lastLaunchRequestContext?.appID == appID &&
            lastLaunchRequestContext?.settings == launchSettingsToUse
        if duplicateLaunchRequestInFlight {
            logger.notice(
                "Ignoring duplicate launch request while previous launch is still transitioning appID=\(appID, privacy: .public) hostKey=\(selectedHostKey, privacy: .public)"
            )
            return
        }
        launchState = isReconfiguringActiveSession
            ? .optimizing("Optimizing Display...")
            : .launching
        refreshAppsTask?.cancel()
        clearSessionIssueState()
        stopInputKeepAliveLoop()
        if !isReconfiguringActiveSession {
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
                    runtimeHost: resolvedHostDescriptor.host,
                    knownHosts: Set(selectedHost.routes.allEndpoints.map {
                        $0.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    }),
                    localRouteHosts: Set([selectedHost.routes.local?.host, selectedHost.routes.active.host]
                        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                        .filter { Self.isLocalPairHost($0) })
                )
                runtimeLogger.notice(
                    "Launch session URL raw=\(initialLaunchResult.sessionURL ?? "<nil>", privacy: .public) rewritten=\(connectedSessionURL, privacy: .public) runtimeHost=\(resolvedHostDescriptor.host, privacy: .public)"
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
                        connectError: error,
                        settings: launchSettingsToUse
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
                        runtimeHost: resolvedHostDescriptor.host,
                        knownHosts: Set(selectedHost.routes.allEndpoints.map {
                            $0.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        }),
                        localRouteHosts: Set([selectedHost.routes.local?.host, selectedHost.routes.active.host]
                            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                            .filter { Self.isLocalPairHost($0) })
                    )
                    runtimeLogger.notice(
                        "Forced launch session URL raw=\(forcedLaunchResult.sessionURL ?? "<nil>", privacy: .public) rewritten=\(forcedSessionURL, privacy: .public) runtimeHost=\(resolvedHostDescriptor.host, privacy: .public)"
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
                        await self.persistPreferredRoute(
                            connectRoute: Self.activeExactRouteCandidate(for: resolvedHostDescriptor),
                            for: selectedHost
                        )
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
        launchGeneration &+= 1

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
        if let selectedHost,
           let controlClient,
           let pairingRouteStore
        {
            let runtimeHost = await Self.preferredRuntimeHostDescriptor(
                for: selectedHost,
                latestResolvedHostDescriptors: latestResolvedHostDescriptors,
                pairingRouteStore: pairingRouteStore
            )
            try? await controlClient.cancelActiveSession(
                host: runtimeHost.host,
                httpsPort: runtimeHost.httpsPort
            )
            await MainActor.run { [weak self] in
                guard let self else {
                    return
                }
                let candidates = latestHostCandidates.isEmpty
                    ? [Self.activeRouteCandidate(for: selectedHost)]
                    : latestHostCandidates
                self.refreshHosts(
                    candidates: candidates,
                    preferredHost: Self.activeExactRouteCandidate(for: runtimeHost),
                    preferredAuthorityHost: Self.preferredAuthorityHostCandidate(
                        for: runtimeHost,
                        connectEndpoint: runtimeHost.routes.active
                    ),
                    preferredControlHTTPSPort: Self.preferredControlHTTPSPortCandidate(for: runtimeHost)
                )
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
            if Self.shouldTearDownSessionAfterRTSPTimeout(failureMessage: message) {
                performLocalActiveSessionTeardown()
                return
            }
            if attemptRuntimeStreamReconnect(afterFailureMessage: message) {
                return
            }
            attemptRuntimeCodecRecovery(afterFailureMessage: message)
        case .idle, .connecting, .waitingForFirstFrame, .rendering:
            return
        }
    }

    @MainActor
    private func performLocalActiveSessionTeardown() {
        let previousLaunchTask = prepareActiveSessionClear()
        Task {
            await completeActiveSessionClear(previousLaunchTask: previousLaunchTask)
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
                "Lumen clipboard sync failed for host=\(endpoint.host, privacy: .public): \(error.localizedDescription, privacy: .public)"
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
                "Lumen clipboard pull failed for host=\(endpoint.host, privacy: .public): \(error.localizedDescription, privacy: .public)"
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
        clipboardReadUnavailable = false
        clipboardWriteUnavailable = false
        clipboardActionRequiresActiveStream = false
        hostTerminationIssue = nil
        sessionIssue = nil
    }

    @MainActor
    private func clearClipboardWriteIssue() {
        clipboardWriteUnavailable = false
        clipboardActionRequiresActiveStream = false
        refreshSessionIssue()
    }

    @MainActor
    private func clearClipboardReadIssue() {
        clipboardReadUnavailable = false
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
        case .readUnavailable:
            clipboardReadUnavailable = true
        case .writeUnavailable:
            clipboardWriteUnavailable = true
        case .requiresActiveStream:
            clipboardActionRequiresActiveStream = true
        }
        refreshSessionIssue()
    }

    @MainActor
    private func refreshSessionIssue() {
        sessionIssue = hostTerminationIssue ?? Self.sessionIssue(
            clipboardReadUnavailable: clipboardReadUnavailable,
            clipboardWriteUnavailable: clipboardWriteUnavailable,
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
        clipboardReadUnavailable: Bool,
        clipboardWriteUnavailable: Bool,
        clipboardActionRequiresActiveStream: Bool
    ) -> ShadowClientRemoteSessionIssue? {
        ShadowClientRemoteSessionIssueKit.sessionIssue(
            clipboardReadUnavailable: clipboardReadUnavailable,
            clipboardWriteUnavailable: clipboardWriteUnavailable,
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

    private static func shouldRetryRuntimeStreamReconnect(
        failureMessage: String,
        settings: ShadowClientGameStreamLaunchSettings
    ) -> Bool {
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
        if reconnectSignatures.contains(where: normalized.contains) {
            return true
        }

        let hevcRuntimeRecoveryReconnectSignatures = [
            "hevc runtime recovery exhausted",
        ]
        if (settings.preferredCodec == .h265 || settings.preferredCodec == .auto) &&
            hevcRuntimeRecoveryReconnectSignatures.contains(where: normalized.contains) {
            return true
        }

        return false
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
        guard Self.shouldRetryRuntimeStreamReconnect(
            failureMessage: message,
            settings: launchRequest.settings
        ) else {
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
        runtimeHost: String,
        knownHosts: Set<String> = [],
        localRouteHosts: Set<String> = []
    ) throws -> String {
        guard let sessionURL = launchResult.sessionURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !sessionURL.isEmpty
        else {
            throw ShadowClientGameStreamError.requestFailed(
                "Host did not return a remote session URL."
            )
        }
        return rewrittenSessionURL(
            sessionURL,
            runtimeHost: runtimeHost,
            knownHosts: knownHosts,
            localRouteHosts: localRouteHosts
        )
    }

    static func rewrittenSessionURL(
        _ sessionURL: String,
        runtimeHost: String,
        knownHosts: Set<String> = [],
        localRouteHosts: Set<String> = []
    ) -> String {
        let trimmed = sessionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              let sessionHost = components.host
        else {
            return trimmed
        }

        let normalizedSessionHost = sessionHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard shouldRewriteSessionURLHost(normalizedSessionHost) else {
            return trimmed
        }

        guard let rewrittenHost = preferredSessionRouteHost(
            runtimeHost: runtimeHost,
            knownHosts: knownHosts,
            localRouteHosts: localRouteHosts
        ) else {
            return trimmed
        }

        components.host = rewrittenHost
        return components.string ?? trimmed
    }

    private static func shouldRetryForcedLaunch(
        launchVerb: String,
        connectError: any Error,
        settings: ShadowClientGameStreamLaunchSettings
    ) -> Bool {
        if shouldRetryCodecFallback(connectError: connectError) {
            return true
        }

        if forcedLaunchSettings(
            from: settings,
            connectError: connectError
        ).preferredCodec != settings.preferredCodec {
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

    private static func shouldTearDownSessionAfterRTSPTimeout(failureMessage: String) -> Bool {
        let normalized = failureMessage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            return false
        }

        let teardownSignatures = [
            "rtsp udp video timeout",
            "timed out waiting for first frame",
            "transport connection timed out",
            "no message available on stream",
        ]
        return teardownSignatures.contains(where: normalized.contains)
    }

    private static func shouldRewriteSessionURLHost(_ host: String) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedHost.contains("%") {
            return true
        }

        return isLocalPairHost(normalizedHost) ||
            ShadowClientRemoteHostCandidateFilter.isLoopbackHost(normalizedHost) ||
            ShadowClientRemoteHostCandidateFilter.isLinkLocalHost(normalizedHost)
    }

    private static func preferredSessionRouteHost(
        runtimeHost: String,
        knownHosts: Set<String>,
        localRouteHosts: Set<String>
    ) -> String? {
        let normalizedRuntimeHost = runtimeHost.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedRuntimeHost.isEmpty,
           isUsableSessionRouteHost(normalizedRuntimeHost)
        {
            return normalizedRuntimeHost
        }

        let localCandidates = localRouteHosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        if let candidate = localCandidates.first(where: isUsableSessionRouteHost) {
            return candidate
        }

        let knownCandidates = knownHosts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .sorted()
        return knownCandidates.first(where: isUsableSessionRouteHost)
    }

    private static func isUsableSessionRouteHost(_ host: String) -> Bool {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else {
            return false
        }

        return !ShadowClientRemoteHostCandidateFilter.isLoopbackHost(normalizedHost) &&
            !ShadowClientRemoteHostCandidateFilter.isLinkLocalHost(normalizedHost)
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

        if let runtimeError = connectError as? ShadowClientRealtimeSessionRuntimeError {
            switch runtimeError {
            case .unsupportedCodec:
                return true
            case let .transportFailure(reason):
                switch reason {
                case .timedOutWaitingForFirstFrame,
                     .udpVideoNoStartupDatagrams,
                     .udpVideoProlongedDatagramInactivityAfterStartup:
                    return true
                case .message:
                    break
                }
            case .invalidSessionURL, .connectionClosed:
                break
            }
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
        let base = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = base.lowercased()
        let transportFailureBase = userFacingTransportFailureMessage(normalizedError: normalized)
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
            if let transportFailureBase {
                return transportFailureBase
            }
            return base
        }

        let resolvedBase = transportFailureBase ??
            (base.isEmpty ? "Remote session launch failed." : base)
        return ([resolvedBase] + hints).joined(separator: "\n")
    }

    private static func userFacingTransportFailureMessage(
        normalizedError: String
    ) -> String? {
        guard !normalizedError.isEmpty else {
            return nil
        }

        if normalizedError.contains("lumen transport requires negotiated session id ping support") ||
            normalizedError.contains("lumen transport requires encrypted control stream v2 support")
        {
            return "Remote session startup failed during encrypted transport negotiation."
        }

        if normalizedError.contains("rtsp describe failed") ||
            normalizedError.contains("rtsp track parse failed")
        {
            return "Remote session startup failed while reading the host stream description."
        }

        if normalizedError.contains("rtsp audio setup failed") ||
            normalizedError.contains("rtsp video setup failed") ||
            normalizedError.contains("rtsp control setup failed")
        {
            return "Remote session startup failed while negotiating stream channels."
        }

        if normalizedError.contains("rtsp announce failed") {
            return "Remote session startup failed while preparing stream parameters."
        }

        if normalizedError.contains("rtsp play failed") {
            return "Remote session startup failed while starting playback."
        }

        if normalizedError.contains("could not connect to remote session") {
            return "Remote session startup failed before media playback began."
        }

        return nil
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
        case .prores:
            return [.prores]
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
            forceHardwareDecoding: settings.forceHardwareDecoding,
            resolutionScalePercent: settings.resolutionScalePercent,
            requestHiDPI: settings.requestHiDPI,
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
            // Sunshine always advertises ServerCodecModeSupport, but Lumen can omit it.
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
        case .prores:
            return .prores
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
                prioritizeNetworkTraffic: settings.prioritizeNetworkTraffic,
                forceHardwareDecoding: settings.forceHardwareDecoding,
                resolutionScalePercent: settings.resolutionScalePercent,
                requestHiDPI: settings.requestHiDPI,
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
            prioritizeNetworkTraffic: settings.prioritizeNetworkTraffic,
            forceHardwareDecoding: settings.forceHardwareDecoding,
            resolutionScalePercent: settings.resolutionScalePercent,
            requestHiDPI: settings.requestHiDPI,
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
            displayScalePercent: settings.resolutionScalePercent,
            requestHiDPI: settings.requestHiDPI,
            prioritizeNetworkTraffic: settings.prioritizeNetworkTraffic,
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
        case .h264, .h265, .prores:
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
        case .prores:
            return negotiatedCodec == .prores
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
    public func wakeSelectedHost(macAddress: String, port: UInt16) {
        commandContinuation.yield(
            .wakeSelectedHost(
                macAddress: macAddress,
                port: port
            )
        )
    }

    @MainActor
    private func performSelectHost(_ hostID: String) {
        pendingSelectedHostID = hostID
        guard let resolvedHost = Self.resolveHostSelection(hostID, in: hosts) else {
            return
        }

        pendingSelectedHostID = nil
        selectedHostID = resolvedHost.id
        clearSelectedHostLumenAdminState()
        clearSelectedHostWakeState()
        performRefreshSelectedHostApps()
    }

    @MainActor
    public func refreshSelectedHostApps() {
        commandContinuation.yield(.refreshSelectedHostApps)
    }

    @MainActor
    public func refreshSelectedHostLumenAdmin(username: String, password: String) {
        commandContinuation.yield(
            .refreshSelectedHostLumenAdmin(
                username: username,
                password: password
            )
        )
    }

    @MainActor
    public func updateSelectedHostLumenAdmin(
        username: String,
        password: String,
        displayModeOverride: String,
        alwaysUseVirtualDisplay: Bool
    ) {
        commandContinuation.yield(
            .updateSelectedHostLumenAdmin(
                username: username,
                password: password,
                displayModeOverride: displayModeOverride,
                alwaysUseVirtualDisplay: alwaysUseVirtualDisplay
            )
        )
    }

    @MainActor
    public func disconnectSelectedHostLumenAdmin(username: String, password: String) {
        commandContinuation.yield(
            .disconnectSelectedHostLumenAdmin(
                username: username,
                password: password
            )
        )
    }

    @MainActor
    public func unpairSelectedHostLumenAdmin(username: String, password: String) {
        commandContinuation.yield(
            .unpairSelectedHostLumenAdmin(
                username: username,
                password: password
            )
        )
    }

    @MainActor
    private func performRefreshSelectedHostApps() {
        appRefreshGeneration &+= 1
        let refreshGeneration = appRefreshGeneration

        if launchState.isTransitioning || activeSession != nil {
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

        guard selectedHost.authenticationState.canRefreshApps else {
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
                let preferredAuthorityHost = Self.preferredAuthorityHostCandidate(
                    for: resolvedHostDescriptor,
                    connectEndpoint: resolvedHostDescriptor.routes.active
                )
                let resolved = try await metadataClient.fetchAppList(
                    host: resolvedHostDescriptor.host,
                    httpsPort: resolvedHostDescriptor.httpsPort,
                    preferredAuthorityHost: preferredAuthorityHost,
                    advertisedControlHTTPSPort: resolvedHostDescriptor.controlHTTPSPort,
                    pinnedServerCertificateDER: nil
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
                        await self.persistPreferredRoute(
                            connectRoute: Self.activeExactRouteCandidate(for: resolvedHostDescriptor),
                            for: hostDescriptor
                        )
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
                        self.appState = .failed(message)
                    } else {
                        self.apps = fallbackApps
                        self.appState = .loaded
                    }
                }
            }
        }
    }

    @MainActor
    private func performRefreshSelectedHostLumenAdmin(
        username: String,
        password: String
    ) {
        guard let selectedHost else {
            clearSelectedHostLumenAdminState()
            clearSelectedHostWakeState()
            return
        }

        guard selectedHost.authenticationState.canConnect else {
            selectedHostLumenAdminProfile = nil
            selectedHostLumenAdminState = .failed("Pair this host before syncing Lumen client metadata.")
            return
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            selectedHostLumenAdminProfile = nil
            selectedHostLumenAdminState = .failed("Lumen admin credentials are required.")
            return
        }

        selectedHostLumenAdminState = .loading
        selectedHostLumenAdminProfile = nil

        let lumenAdminClient = lumenAdminClient
        let requestRoute = Self.preferredLumenRequestRoute(for: selectedHost)
        let selectedHostID = selectedHost.id
        Task { [weak self] in
            do {
                let profile = try await lumenAdminClient.fetchCurrentClientProfile(
                    route: requestRoute,
                    username: trimmedUsername,
                    password: trimmedPassword
                )
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostLumenAdminProfile = profile
                    self.selectedHostLumenAdminState = .loaded
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostLumenAdminProfile = nil
                    self.selectedHostLumenAdminState = .failed(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func performUpdateSelectedHostLumenAdmin(
        username: String,
        password: String,
        displayModeOverride: String,
        alwaysUseVirtualDisplay: Bool
    ) {
        guard let selectedHost,
              let currentProfile = selectedHostLumenAdminProfile
        else {
            selectedHostLumenAdminState = .failed("Sync Lumen client metadata first.")
            return
        }

        guard selectedHost.authenticationState.canConnect else {
            selectedHostLumenAdminProfile = nil
            selectedHostLumenAdminState = .failed("Pair this host before editing Lumen client metadata.")
            return
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            selectedHostLumenAdminState = .failed("Lumen admin credentials are required.")
            return
        }

        selectedHostLumenAdminState = .saving

        let lumenAdminClient = lumenAdminClient
        let requestRoute = Self.preferredLumenRequestRoute(for: selectedHost)
        let selectedHostID = selectedHost.id
        let updatedProfile = ShadowClientLumenAdminClientProfile(
            name: currentProfile.name,
            uuid: currentProfile.uuid,
            displayModeOverride: displayModeOverride.trimmingCharacters(in: .whitespacesAndNewlines),
            alwaysUseVirtualDisplay: alwaysUseVirtualDisplay,
            connected: currentProfile.connected,
            doCommands: currentProfile.doCommands,
            undoCommands: currentProfile.undoCommands
        )

        Task { [weak self] in
            do {
                let savedProfile = try await lumenAdminClient.updateCurrentClientProfile(
                    route: requestRoute,
                    username: trimmedUsername,
                    password: trimmedPassword,
                    profile: updatedProfile
                )
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostLumenAdminProfile = savedProfile
                    self.selectedHostLumenAdminState = .loaded
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostLumenAdminState = .failed(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func clearSelectedHostLumenAdminState() {
        selectedHostLumenAdminProfile = nil
        selectedHostLumenAdminState = .idle
    }

    @MainActor
    private func clearSelectedHostWakeState() {
        selectedHostWakeState = .idle
    }

    @MainActor
    private func performWakeSelectedHost(macAddress: String, port: UInt16) {
        guard let selectedHost else {
            selectedHostWakeState = .failed("Select a host first.")
            return
        }

        let normalizedMACAddress = macAddress.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ShadowClientWakeOnLANKit.normalizedMACAddress(normalizedMACAddress) != nil else {
            selectedHostWakeState = .failed("Enter a valid MAC address first.")
            return
        }

        selectedHostWakeState = .sending
        let selectedHostID = selectedHost.id

        Task { [weak self] in
            do {
                guard let self else {
                    return
                }
                let sentPacketCount = try await self.wakeOnLANClient.sendMagicPacket(
                    macAddress: normalizedMACAddress,
                    port: port
                )
                await MainActor.run {
                    guard self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostWakeState = .sent(
                        "Sent \(sentPacketCount) magic packet\(sentPacketCount == 1 ? "" : "s") on UDP \(port)."
                    )
                }
            } catch {
                await MainActor.run {
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostWakeState = .failed(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func performDisconnectSelectedHostLumenAdmin(
        username: String,
        password: String
    ) {
        guard let selectedHost,
              let currentProfile = selectedHostLumenAdminProfile
        else {
            selectedHostLumenAdminState = .failed("Sync Lumen client metadata first.")
            return
        }

        guard selectedHost.authenticationState.canConnect else {
            selectedHostLumenAdminProfile = nil
            selectedHostLumenAdminState = .failed("Pair this host before changing Lumen client connection state.")
            return
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            selectedHostLumenAdminState = .failed("Lumen admin credentials are required.")
            return
        }

        selectedHostLumenAdminState = .saving
        let lumenAdminClient = lumenAdminClient
        let requestRoute = Self.preferredLumenRequestRoute(for: selectedHost)
        let selectedHostID = selectedHost.id
        let uuid = currentProfile.uuid

        Task { [weak self] in
            do {
                try await lumenAdminClient.disconnectCurrentClient(
                    route: requestRoute,
                    username: trimmedUsername,
                    password: trimmedPassword,
                    uuid: uuid
                )
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    if let profile = self.selectedHostLumenAdminProfile {
                        self.selectedHostLumenAdminProfile = .init(
                            name: profile.name,
                            uuid: profile.uuid,
                            displayModeOverride: profile.displayModeOverride,
                            alwaysUseVirtualDisplay: profile.alwaysUseVirtualDisplay,
                            connected: false,
                            doCommands: profile.doCommands,
                            undoCommands: profile.undoCommands
                        )
                    }
                    self.selectedHostLumenAdminState = .loaded
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostLumenAdminState = .failed(error.localizedDescription)
                }
            }
        }
    }

    @MainActor
    private func performUnpairSelectedHostLumenAdmin(
        username: String,
        password: String
    ) {
        guard let selectedHost,
              let currentProfile = selectedHostLumenAdminProfile
        else {
            selectedHostLumenAdminState = .failed("Sync Lumen client metadata first.")
            return
        }

        guard selectedHost.authenticationState.canConnect else {
            selectedHostLumenAdminProfile = nil
            selectedHostLumenAdminState = .failed("Pair this host before unpairing the current Lumen client.")
            return
        }

        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            selectedHostLumenAdminState = .failed("Lumen admin credentials are required.")
            return
        }

        selectedHostLumenAdminState = .saving
        let lumenAdminClient = lumenAdminClient
        let requestRoute = Self.preferredLumenRequestRoute(for: selectedHost)
        let selectedHostID = selectedHost.id
        let uuid = currentProfile.uuid

        Task { [weak self] in
            do {
                try await lumenAdminClient.unpairCurrentClient(
                    route: requestRoute,
                    username: trimmedUsername,
                    password: trimmedPassword,
                    uuid: uuid
                )
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.clearSelectedHostLumenAdminState()
                    self.clearSelectedHostWakeState()
                    self.performRefreshHosts(
                        candidates: self.latestHostCandidates,
                        preferredHost: Self.activeExactRouteCandidate(for: selectedHost),
                        preferredAuthorityHost: Self.preferredAuthorityHostCandidate(
                            for: selectedHost,
                            connectEndpoint: selectedHost.routes.active
                        ),
                        preferredControlHTTPSPort: Self.preferredControlHTTPSPortCandidate(for: selectedHost)
                    )
                }
            } catch {
                await MainActor.run { [weak self] in
                    guard let self, self.selectedHostID == selectedHostID else {
                        return
                    }
                    self.selectedHostLumenAdminState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private static func fetchHostDescriptor(
        host: String,
        metadataClient: any ShadowClientGameStreamMetadataClient,
        existingHosts: [ShadowClientRemoteHostDescriptor],
        preferredRoutesByKey: [String: String],
        preferredHost: String?,
        preferredAuthorityHost: String?,
        advertisedControlHTTPSPort: Int?,
        preferredAnchorHost: ShadowClientRemoteHostDescriptor?,
        hostAliasesByHost: [String: Set<String>],
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    ) async -> ShadowClientRemoteHostDescriptor {
        Logger(subsystem: "com.skyline23.shadow-client", category: "RemoteDesktopRuntime").notice(
            "Host descriptor fetch start candidate=\(host, privacy: .public)"
        )
        do {
            let pinnedCertificateDER = await pinnedCertificate(
                forHostCandidate: host,
                existingHosts: existingHosts,
                preferredRoutesByKey: preferredRoutesByKey,
                preferredHost: preferredHost,
                preferredAnchorHost: preferredAnchorHost,
                hostAliasesByHost: hostAliasesByHost,
                pinnedCertificateStore: pinnedCertificateStore
            )
            let info = try await metadataClient.fetchServerInfo(
                host: host,
                preferredAuthorityHost: preferredAuthorityHost,
                advertisedControlHTTPSPort: advertisedControlHTTPSPort,
                pinnedServerCertificateDER: pinnedCertificateDER
            )
            let relatedHost = relatedDescriptor(
                forHostCandidate: host,
                existingHosts: existingHosts,
                preferredRoutesByKey: preferredRoutesByKey,
                preferredHost: preferredHost,
                preferredAnchorHost: preferredAnchorHost,
                hostAliasesByHost: hostAliasesByHost
            )
            let inheritedRoutes = inheritedAuthorityRoutes(
                forResolvedHost: info.host,
                resolvedLocalHost: info.localHost,
                relatedHost: relatedHost,
                preferredAuthorityHost: preferredAuthorityHost
            )
            Logger(subsystem: "com.skyline23.shadow-client", category: "RemoteDesktopRuntime").notice(
                "Host descriptor fetch succeeded candidate=\(host, privacy: .public) resolved-host=\(info.host, privacy: .public) https-port=\(info.httpsPort, privacy: .public)"
            )
            return ShadowClientRemoteHostDescriptor(
                host: info.host,
                isSaved: relatedHost?.isSaved ?? false,
                displayName: info.displayName,
                pairStatus: info.pairStatus,
                currentGameID: max(0, info.currentGameID),
                serverState: info.serverState,
                httpsPort: info.httpsPort,
                appVersion: info.appVersion,
                gfeVersion: info.gfeVersion,
                uniqueID: info.uniqueID,
                macAddress: info.macAddress,
                serverCodecModeSupport: info.serverCodecModeSupport,
                controlHTTPSPort: info.controlHTTPSPort ?? advertisedControlHTTPSPort,
                lastError: nil,
                localHost: info.localHost,
                remoteHost: info.remoteHost ?? inheritedRoutes.remoteHost,
                manualHost: info.manualHost ?? inheritedRoutes.manualHost
            )
        } catch {
            let message = error.localizedDescription.isEmpty
                ? "Could not query host serverinfo"
                : error.localizedDescription
            Logger(subsystem: "com.skyline23.shadow-client", category: "RemoteDesktopRuntime").error(
                "Host descriptor fetch failed candidate=\(host, privacy: .public) error=\(message, privacy: .public)"
            )
            if let preservedDescriptor = preservedDescriptor(
                forFailedHostCandidate: host,
                existingHosts: existingHosts,
                preferredRoutesByKey: preferredRoutesByKey,
                preferredHost: preferredHost,
                preferredAnchorHost: preferredAnchorHost,
                hostAliasesByHost: hostAliasesByHost,
                lastError: message
            ) {
                return preservedDescriptor
            }
            let parsedRoute = parsedCandidateRoute(host)
            let fallbackHost = parsedRoute?.host ?? host
            let fallbackHTTPSPort = parsedRoute?.port
                ?? ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
            return ShadowClientRemoteHostDescriptor(
                host: fallbackHost,
                isSaved: false,
                displayName: fallbackHost,
                pairStatus: .unknown,
                currentGameID: 0,
                serverState: "",
                httpsPort: fallbackHTTPSPort,
                appVersion: nil,
                gfeVersion: nil,
                uniqueID: nil,
                serverCodecModeSupport: 0,
                controlHTTPSPort: advertisedControlHTTPSPort,
                lastError: message
            )
        }
    }

    private static func inheritedAuthorityRoutes(
        forResolvedHost resolvedHost: String,
        resolvedLocalHost: String?,
        relatedHost: ShadowClientRemoteHostDescriptor?,
        preferredAuthorityHost: String?
    ) -> (remoteHost: String?, manualHost: String?) {
        let normalizedResolvedHost = resolvedHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedLocalHost = resolvedLocalHost?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        func normalizedAuthorityCandidate(_ host: String?) -> String? {
            guard let host = host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !host.isEmpty else {
                return nil
            }
            guard host != normalizedResolvedHost, host != normalizedLocalHost else {
                return nil
            }
            guard !isLocalPairHost(host), !isLinkLocalRouteHost(host) else {
                return nil
            }
            return host
        }

        let manualHost = normalizedAuthorityCandidate(relatedHost?.routes.manual?.host)
        let remoteHost = [
            relatedHost?.routes.remote?.host,
            relatedHost?.routes.active.host,
            preferredAuthorityHost,
        ]
        .compactMap(normalizedAuthorityCandidate)
        .first(where: { $0 != manualHost })

        return (remoteHost, manualHost)
    }

    private static func preservedDescriptor(
        forFailedHostCandidate candidateHost: String,
        existingHosts: [ShadowClientRemoteHostDescriptor],
        preferredRoutesByKey: [String: String],
        preferredHost: String?,
        preferredAnchorHost: ShadowClientRemoteHostDescriptor?,
        hostAliasesByHost: [String: Set<String>],
        lastError: String
    ) -> ShadowClientRemoteHostDescriptor? {
        if let existingDescriptor = matchedDescriptor(
            forHostCandidate: candidateHost,
            existingHosts: existingHosts,
            hostAliasesByHost: hostAliasesByHost
        ) {
            let activeRoute = existingDescriptor.routes.allEndpoints.first(where: { endpoint in
                candidate(candidateHost, matches: endpoint, hostAliasesByHost: hostAliasesByHost)
            }) ?? existingDescriptor.routes.active

            let routes = ShadowClientRemoteHostRoutes(
                active: activeRoute,
                local: existingDescriptor.routes.local,
                remote: existingDescriptor.routes.remote,
                manual: existingDescriptor.routes.manual
            )

            return ShadowClientRemoteHostDescriptor(
                activeRoute: routes.active,
                isSaved: existingDescriptor.isSaved,
                displayName: existingDescriptor.displayName,
                pairStatus: existingDescriptor.pairStatus,
                currentGameID: existingDescriptor.currentGameID,
                serverState: existingDescriptor.serverState,
                appVersion: existingDescriptor.appVersion,
                gfeVersion: existingDescriptor.gfeVersion,
                uniqueID: existingDescriptor.uniqueID,
                macAddress: existingDescriptor.macAddress,
                serverCodecModeSupport: existingDescriptor.serverCodecModeSupport,
                controlHTTPSPort: existingDescriptor.controlHTTPSPort,
                lastError: lastError,
                routes: routes
            )
        }

        let normalizedError = lastError
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalizedError.contains("certificate mismatch") {
            return nil
        }

        guard let preferredDescriptor = relatedDescriptor(
            forHostCandidate: candidateHost,
            existingHosts: existingHosts,
            preferredRoutesByKey: preferredRoutesByKey,
            preferredHost: preferredHost,
            preferredAnchorHost: preferredAnchorHost,
            hostAliasesByHost: hostAliasesByHost
        ) else {
            return nil
        }

        let activeRouteHost = parsedCandidateRoute(candidateHost)?.host ?? preferredDescriptor.routes.active.host
        let activeRoute = ShadowClientRemoteHostEndpoint(
            host: activeRouteHost,
            httpsPort: preferredDescriptor.routes.active.httpsPort
        )
        let manualRoute: ShadowClientRemoteHostEndpoint?
        if preferredDescriptor.routes.allEndpoints.contains(where: { endpoint in
            endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(activeRouteHost) == .orderedSame
        }) {
            manualRoute = preferredDescriptor.routes.manual
        } else {
            manualRoute = ShadowClientRemoteHostEndpoint(
                host: activeRouteHost,
                httpsPort: preferredDescriptor.routes.active.httpsPort
            )
        }

        let routes = ShadowClientRemoteHostRoutes(
            active: activeRoute,
            local: preferredDescriptor.routes.local,
            remote: preferredDescriptor.routes.remote,
            manual: manualRoute
        )

        return ShadowClientRemoteHostDescriptor(
            activeRoute: routes.active,
            isSaved: preferredDescriptor.isSaved,
            displayName: preferredDescriptor.displayName,
            pairStatus: preferredDescriptor.pairStatus,
            currentGameID: preferredDescriptor.currentGameID,
            serverState: preferredDescriptor.serverState,
            appVersion: preferredDescriptor.appVersion,
            gfeVersion: preferredDescriptor.gfeVersion,
            uniqueID: preferredDescriptor.uniqueID,
            macAddress: preferredDescriptor.macAddress,
            serverCodecModeSupport: preferredDescriptor.serverCodecModeSupport,
            controlHTTPSPort: preferredDescriptor.controlHTTPSPort,
            lastError: lastError,
            routes: routes
        )
    }

    private static func pinnedCertificate(
        forHostCandidate candidateHost: String,
        existingHosts: [ShadowClientRemoteHostDescriptor],
        preferredRoutesByKey: [String: String],
        preferredHost: String?,
        preferredAnchorHost: ShadowClientRemoteHostDescriptor?,
        hostAliasesByHost: [String: Set<String>],
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    ) async -> Data? {
        let candidateRoute = parsedCandidateRoute(candidateHost)
        if let candidateRoute,
           let exactRouteCertificate = await pinnedCertificateStore.certificateDER(
            forHost: candidateRoute.host,
            httpsPort: candidateRoute.port ?? ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
           ) {
            return exactRouteCertificate
        }

        guard candidateRoute?.port == nil else {
            return nil
        }

        let descriptor = relatedDescriptor(
            forHostCandidate: candidateHost,
            existingHosts: existingHosts,
            preferredRoutesByKey: preferredRoutesByKey,
            preferredHost: preferredHost,
            preferredAnchorHost: preferredAnchorHost,
            hostAliasesByHost: hostAliasesByHost
        )

        if let descriptor {
            for endpoint in descriptor.routes.allEndpoints {
                if let certificate = await pinnedCertificateStore.certificateDER(
                    forHost: endpoint.host,
                    httpsPort: endpoint.httpsPort
                ) {
                    return certificate
                }
            }
        }

        return nil
    }

    private static func relatedDescriptor(
        forHostCandidate candidateHost: String,
        existingHosts: [ShadowClientRemoteHostDescriptor],
        preferredRoutesByKey: [String: String],
        preferredHost: String?,
        preferredAnchorHost: ShadowClientRemoteHostDescriptor?,
        hostAliasesByHost: [String: Set<String>]
    ) -> ShadowClientRemoteHostDescriptor? {
        if let existingDescriptor = matchedDescriptor(
            forHostCandidate: candidateHost,
            existingHosts: existingHosts,
            hostAliasesByHost: hostAliasesByHost
        ) {
            return existingDescriptor
        }

        guard let normalizedCandidate = normalizeCandidate(candidateHost) else {
            return nil
        }

        if let preferredAnchorHost,
           let normalizedPreferredHost = normalizeCandidate(preferredHost),
           normalizedPreferredHost != normalizedCandidate,
           hostAliases(
            for: normalizedPreferredHost,
            hostAliasesByHost: hostAliasesByHost
           ).contains(normalizedCandidate) {
            return preferredAnchorHost
        }

        return existingHosts.first(where: { descriptor in
            guard let preferredRoute = preferredRoutesByKey[mergeKey(for: descriptor)],
                  let normalizedPreferredRoute = normalizeCandidate(preferredRoute) else {
                return false
            }
            return hostAliases(
                for: normalizedPreferredRoute,
                hostAliasesByHost: hostAliasesByHost
            ).contains(normalizedCandidate)
        })
    }

    private static func matchedDescriptor(
        forHostCandidate candidateHost: String,
        existingHosts: [ShadowClientRemoteHostDescriptor],
        hostAliasesByHost: [String: Set<String>]
    ) -> ShadowClientRemoteHostDescriptor? {
        let matchingDescriptors = existingHosts.filter { descriptor in
            descriptor.routes.allEndpoints.contains { endpoint in
                candidate(candidateHost, matches: endpoint, hostAliasesByHost: hostAliasesByHost)
            }
        }
        guard !matchingDescriptors.isEmpty else {
            return nil
        }

        if parsedCandidateRoute(candidateHost)?.port != nil {
            return matchingDescriptors.first
        }

        var distinctPhysicalHosts: [ShadowClientRemoteHostDescriptor] = []
        for descriptor in matchingDescriptors {
            if distinctPhysicalHosts.contains(where: {
                descriptorsBelongToSamePhysicalHost(
                    $0,
                    descriptor,
                    hostAliasesByHost: hostAliasesByHost
                )
            }) {
                continue
            }
            distinctPhysicalHosts.append(descriptor)
            if distinctPhysicalHosts.count > 1 {
                return nil
            }
        }

        return distinctPhysicalHosts.first
    }

    private static func preferredAnchorHost(
        from existingHosts: [ShadowClientRemoteHostDescriptor],
        selectedHost: ShadowClientRemoteHostDescriptor?,
        preferredHost: String?
    ) -> ShadowClientRemoteHostDescriptor? {
        if let selectedHost = preferredRouteAnchorHost(
            selectedHost: selectedHost,
            hosts: existingHosts
        ) {
            return selectedHost
        }

        guard normalizeCandidate(preferredHost) != nil else {
            return nil
        }

        let pairedOrIdentifiedHosts = existingHosts.filter { descriptor in
            descriptor.pairStatus == .paired || descriptor.uniqueID != nil
        }
        guard pairedOrIdentifiedHosts.count == 1 else {
            return nil
        }
        return pairedOrIdentifiedHosts.first
    }

    private static func preferredRouteAnchorHost(
        selectedHost: ShadowClientRemoteHostDescriptor?,
        hosts: [ShadowClientRemoteHostDescriptor]
    ) -> ShadowClientRemoteHostDescriptor? {
        guard let selectedHost,
              selectedHost.pairStatus == .paired || selectedHost.uniqueID != nil
        else {
            let pairedHosts = hosts.filter { $0.pairStatus == .paired || $0.uniqueID != nil }
            return pairedHosts.count == 1 ? pairedHosts.first : nil
        }

        if let matchingExistingHost = hosts.first(where: {
            descriptorsBelongToSamePhysicalHost($0, selectedHost)
        }) {
            return matchingExistingHost
        }

        return selectedHost
    }

    private static func synchronizePinnedCertificates(
        across hosts: [ShadowClientRemoteHostDescriptor],
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    ) async {
        let pairedOrIdentifiedHosts = hosts.filter { descriptor in
            descriptor.pairStatus == .paired || descriptor.uniqueID != nil
        }

        for group in clusterResolvedHosts(pairedOrIdentifiedHosts) {
            let serviceGroups = Dictionary(grouping: group, by: synchronizationGroupKey(for:))
                .values

            for serviceGroup in serviceGroups {
                let normalizedMachineID = serviceGroup.compactMap { normalizedUniqueID($0.uniqueID) }.first
                var certificate: Data?

                for descriptor in serviceGroup {
                    if let normalizedMachineID,
                       let machineCertificate = await pinnedCertificateStore.certificateDER(
                        forMachineID: normalizedMachineID
                       ) {
                        certificate = machineCertificate
                        break
                    }

                    for endpoint in descriptor.routes.allEndpoints {
                        let routeCertificate = await pinnedCertificateStore.certificateDER(
                            forHost: endpoint.host,
                            httpsPort: endpoint.httpsPort
                        )
                        if let existingCertificate = routeCertificate {
                            certificate = existingCertificate
                            break
                        }
                    }

                    if certificate != nil {
                        break
                    }
                }

                guard let certificate else {
                    continue
                }

                if let normalizedMachineID {
                    await pinnedCertificateStore.setCertificateDER(certificate, forMachineID: normalizedMachineID)
                }

                for descriptor in serviceGroup {
                    for endpoint in descriptor.routes.allEndpoints {
                        if let normalizedMachineID {
                            await pinnedCertificateStore.bindHost(
                                endpoint.host,
                                httpsPort: endpoint.httpsPort,
                                toMachineID: normalizedMachineID
                            )
                        }
                        await pinnedCertificateStore.setCertificateDER(
                            certificate,
                            forHost: endpoint.host,
                            httpsPort: endpoint.httpsPort
                        )
                    }
                }
            }
        }
    }

    private static func descriptorsWithBoundMachineIdentity(
        _ hosts: [ShadowClientRemoteHostDescriptor],
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    ) async -> [ShadowClientRemoteHostDescriptor] {
        var resolvedHosts: [ShadowClientRemoteHostDescriptor] = []
        resolvedHosts.reserveCapacity(hosts.count)

        for host in hosts {
            if normalizedUniqueID(host.uniqueID) != nil {
                resolvedHosts.append(host)
                continue
            }

            let normalizedError = host.lastError?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if normalizedError?.contains("certificate mismatch") == true {
                resolvedHosts.append(host)
                continue
            }

            var boundMachineID: String?
            for endpoint in host.routes.allEndpoints {
                let exactMachineID = await pinnedCertificateStore.machineID(
                    forHost: endpoint.host,
                    httpsPort: endpoint.httpsPort
                )
                if let machineID = exactMachineID {
                    boundMachineID = machineID
                    break
                }
            }

            guard let boundMachineID else {
                resolvedHosts.append(host)
                continue
            }

            resolvedHosts.append(
                ShadowClientRemoteHostDescriptor(
                    activeRoute: host.routes.active,
                    isSaved: host.isSaved,
                    displayName: host.displayName,
                    pairStatus: host.pairStatus,
                    currentGameID: host.currentGameID,
                    serverState: host.serverState,
                    appVersion: host.appVersion,
                    gfeVersion: host.gfeVersion,
                    uniqueID: boundMachineID,
                    macAddress: host.macAddress,
                    serverCodecModeSupport: host.serverCodecModeSupport,
                    controlHTTPSPort: host.controlHTTPSPort,
                    lastError: host.lastError,
                    routes: host.routes
                )
            )
        }

        return resolvedHosts
    }

    private static func fetchDirectHostDescriptor(
        hostAddress: String,
        metadataClient: any ShadowClientGameStreamMetadataClient
    ) async throws -> ShadowClientRemoteHostDescriptor {
        let info = try await metadataClient.fetchServerInfo(host: hostAddress)
        return ShadowClientRemoteHostDescriptor(
            host: info.host,
            isSaved: false,
            displayName: info.displayName,
            pairStatus: info.pairStatus,
            currentGameID: max(0, info.currentGameID),
            serverState: info.serverState,
            httpsPort: info.httpsPort,
            appVersion: info.appVersion,
            gfeVersion: info.gfeVersion,
            uniqueID: info.uniqueID,
            macAddress: info.macAddress,
            serverCodecModeSupport: info.serverCodecModeSupport,
            controlHTTPSPort: info.controlHTTPSPort,
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

        if error is ShadowClientGameStreamControlError {
            return false
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
    ) -> [ShadowClientLumenRouteCandidate] {
        var candidates: [ShadowClientRemoteHostEndpoint] = []

        if let preferredPairHost {
            let parsedRoute = parsedCandidateRoute(preferredPairHost)
            candidates.append(
                .init(
                    host: parsedRoute?.host ?? preferredPairHost,
                    httpsPort: parsedRoute?.port ?? selectedHost.httpsPort
                )
            )
        }

        if let uniqueID = selectedHost.uniqueID, !uniqueID.isEmpty {
            let matchingHosts = hosts.filter { $0.uniqueID == uniqueID }
            candidates.append(contentsOf: matchingHosts.map {
                .init(host: $0.host, httpsPort: $0.httpsPort)
            })
        }

        candidates.append(
            contentsOf: latestHostCandidates.map {
                let parsedRoute = parsedCandidateRoute($0)
                return .init(
                    host: parsedRoute?.host ?? $0,
                    httpsPort: parsedRoute?.port ?? selectedHost.httpsPort
                )
            }
        )
        candidates.append(.init(host: selectedHost.host, httpsPort: selectedHost.httpsPort))

        var seen: Set<String> = []
        let deduplicated = candidates.filter { candidate in
            let key = normalizeCandidate(
                serializedExactHostCandidate(for: candidate)
            ) ?? candidate.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else {
                return false
            }
            seen.insert(key)
            return true
        }

        return deduplicated.sorted {
            let lhsRank = pairHostCandidateRank(
                candidate: $0,
                selectedEndpoint: selectedHost.routes.active,
                preferredPairHost: preferredPairHost
            )
            let rhsRank = pairHostCandidateRank(
                candidate: $1,
                selectedEndpoint: selectedHost.routes.active,
                preferredPairHost: preferredPairHost
            )
            if lhsRank == rhsRank {
                return $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending
            }
            return lhsRank < rhsRank
        }.map { connectEndpoint in
            .init(
                connectEndpoint: connectEndpoint,
                authorityEndpoint: preferredAuthorityEndpoint(
                    for: selectedHost,
                    connectEndpoint: connectEndpoint
                )
            )
        }
    }

    private static func pairHostCandidateRank(
        candidate pairCandidate: ShadowClientRemoteHostEndpoint,
        selectedEndpoint: ShadowClientRemoteHostEndpoint,
        preferredPairHost: String?
    ) -> Int {
        let endpoint = pairCandidate
        let isRoutableLocalPairHost = isLocalPairHost(endpoint.host) && !isLinkLocalRouteHost(endpoint.host)
        if isRoutableLocalPairHost {
            if Self.candidate(preferredPairHost, matches: endpoint) {
                return 0
            }
            if endpoint == selectedEndpoint {
                return 1
            }
            return 2
        }
        if Self.candidate(preferredPairHost, matches: endpoint) {
            return 3
        }
        if endpoint == selectedEndpoint {
            return 4
        }
        if !isLinkLocalRouteHost(endpoint.host) {
            return 5
        }
        if isLocalPairHost(endpoint.host) {
            return 6
        }
        return 7
    }

    private static func preferredAuthorityEndpoint(
        for selectedHost: ShadowClientRemoteHostDescriptor,
        connectEndpoint: ShadowClientRemoteHostEndpoint
    ) -> ShadowClientRemoteHostEndpoint {
        if !isLocalPairHost(connectEndpoint.host), !isLinkLocalRouteHost(connectEndpoint.host) {
            return connectEndpoint
        }

        for endpoint in [
            selectedHost.routes.manual,
            selectedHost.routes.remote,
            selectedHost.routes.active,
            selectedHost.routes.local,
        ].compactMap({ $0 }) {
            if !isLocalPairHost(endpoint.host), !isLinkLocalRouteHost(endpoint.host) {
                return .init(host: endpoint.host, httpsPort: connectEndpoint.httpsPort)
            }
        }

        return connectEndpoint
    }

    private static func preferredAuthorityHostCandidate(
        for selectedHost: ShadowClientRemoteHostDescriptor,
        connectEndpoint: ShadowClientRemoteHostEndpoint
    ) -> String? {
        let authorityEndpoint = preferredAuthorityEndpoint(
            for: selectedHost,
            connectEndpoint: connectEndpoint
        )
        return normalizedAuthorityHost(authorityEndpoint.host)
    }

    private static func preferredControlHTTPSPortCandidate(
        for selectedHost: ShadowClientRemoteHostDescriptor
    ) -> Int? {
        if let controlHTTPSPort = selectedHost.controlHTTPSPort {
            return controlHTTPSPort
        }

        let controlHTTPSPort = selectedHost.routes.active.httpsPort + 6
        guard
            (ShadowClientGameStreamNetworkDefaults.minimumPort...ShadowClientGameStreamNetworkDefaults.maximumPort)
                .contains(controlHTTPSPort)
        else {
            return nil
        }

        return controlHTTPSPort
    }

    private static func preferredRefreshEndpoint(
        for route: ShadowClientLumenRouteCandidate
    ) -> ShadowClientRemoteHostEndpoint {
        let streamHTTPSPort = streamHTTPSPort(
            fromPreferredHTTPSPort: route.authorityEndpoint.httpsPort
        )
        return .init(
            host: route.connectEndpoint.host,
            httpsPort: streamHTTPSPort
        )
    }

    private static func preferredLumenRequestRoute(
        for selectedHost: ShadowClientRemoteHostDescriptor
    ) -> ShadowClientLumenRequestRoute {
        let connectEndpoint: ShadowClientRemoteHostEndpoint
        if let localEndpoint = selectedHost.routes.local,
           isLocalPairHost(localEndpoint.host),
           !isLinkLocalRouteHost(localEndpoint.host) {
            connectEndpoint = localEndpoint
        } else {
            connectEndpoint = selectedHost.routes.active
        }
        let authorityEndpoint = preferredAuthorityEndpoint(
            for: selectedHost,
            connectEndpoint: connectEndpoint
        )
        return .init(
            connectHost: connectEndpoint.host,
            authorityHost: authorityEndpoint.host,
            httpsPort: authorityEndpoint.httpsPort
        )
    }

    private static func pairRouteStoreKey(for selectedHost: ShadowClientRemoteHostDescriptor) -> String {
        if let uniqueID = selectedHost.uniqueID?.trimmingCharacters(in: .whitespacesAndNewlines),
           !uniqueID.isEmpty {
            return "uniqueid:\(uniqueID.lowercased())"
        }

        return "host:\(selectedHost.id)"
    }

    private static func isLocalPairHost(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return isIPAddressCandidate(normalized) || normalized.hasSuffix(".local") || !normalized.contains(".")
    }

    private static func isIPAddressCandidate(_ host: String) -> Bool {
        host.allSatisfy { $0.isNumber || $0 == "." || $0 == ":" }
    }

    private static func isLoopbackRouteHost(_ host: String) -> Bool {
        ShadowClientRemoteHostCandidateFilter.isLoopbackHost(
            host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    private static func isLinkLocalRouteHost(_ host: String) -> Bool {
        ShadowClientRemoteHostCandidateFilter.isLinkLocalHost(
            host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        )
    }

    private static func runtimeRouteRank(
        _ host: String,
        hostAliasesByHost: [String: Set<String>] = [:]
    ) -> Int {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return 100
        }
        if isLoopbackRouteHost(normalized) {
            return 100
        }
        if isLinkLocalRouteHost(normalized) {
            return 10
        }
        if isResolvedLocalDNSHost(normalized, hostAliasesByHost: hostAliasesByHost) {
            return 0
        }
        if isIPAddressCandidate(normalized) && isLocalPairHost(normalized) {
            return 1
        }
        return isLocalPairHost(normalized) ? 2 : 3
    }

    private static func isResolvedLocalDNSHost(
        _ host: String,
        hostAliasesByHost: [String: Set<String>]
    ) -> Bool {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, !isIPAddressCandidate(normalized) else {
            return false
        }
        guard normalized.hasSuffix(".local") || !normalized.contains(".") else {
            return false
        }
        let aliases = Self.hostAliases(for: normalized, hostAliasesByHost: hostAliasesByHost)
        return aliases.contains { alias in
            alias != normalized && isIPAddressCandidate(alias) && isLocalPairHost(alias)
        }
    }

    static func resolveHostAliases(_ hosts: [String]) async -> [String: Set<String>] {
        collapsedHostAliases(for: hosts)
    }

    private static func collapsedHostAliases(for hosts: [String]) -> [String: Set<String>] {
        let normalizedHosts = Set(
            hosts.compactMap { candidate in
                parsedCandidateRoute(candidate)?.host ??
                    candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            .filter { !$0.isEmpty }
        )
        guard !normalizedHosts.isEmpty else {
            return [:]
        }

        var aliasSets: [Set<String>] = normalizedHosts.map { host in
            resolvedAliases(forHost: host)
        }

        var merged = true
        while merged {
            merged = false
            outer: for lhsIndex in aliasSets.indices {
                for rhsIndex in aliasSets.indices where lhsIndex < rhsIndex {
                    if !aliasSets[lhsIndex].isDisjoint(with: aliasSets[rhsIndex]) {
                        aliasSets[lhsIndex].formUnion(aliasSets[rhsIndex])
                        aliasSets.remove(at: rhsIndex)
                        merged = true
                        break outer
                    }
                }
            }
        }

        var resolved: [String: Set<String>] = [:]
        for aliases in aliasSets {
            for host in aliases {
                resolved[host] = aliases
            }
        }
        return resolved
    }

    private static func resolvedAliases(forHost host: String) -> Set<String> {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return []
        }
        guard !isIPAddressCandidate(normalized) else {
            return [normalized]
        }

        var aliases: Set<String> = [normalized]
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var resultPointer: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(normalized, nil, &hints, &resultPointer)
        guard status == 0, let resultPointer else {
            return aliases
        }
        defer { freeaddrinfo(resultPointer) }

        for pointer in sequence(first: resultPointer, next: { $0.pointee.ai_next }) {
            guard let sockaddrPointer = pointer.pointee.ai_addr,
                  let hostString = numericHostString(
                    from: sockaddrPointer,
                    length: pointer.pointee.ai_addrlen
                  )
            else {
                continue
            }
            aliases.insert(hostString.lowercased())
        }

        return aliases
    }

    private static func numericHostString(
        from address: UnsafeMutablePointer<sockaddr>,
        length: socklen_t
    ) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            address,
            length,
            &buffer,
            socklen_t(buffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard status == 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    private static func hostAliases(
        for host: String,
        hostAliasesByHost: [String: Set<String>]
    ) -> Set<String> {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return []
        }
        return hostAliasesByHost[normalized] ?? [normalized]
    }

    private static func serializedHostCandidate(for endpoint: ShadowClientRemoteHostEndpoint) -> String {
        let normalizedHost = endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ShadowClientRemoteHostCandidateFilter.isLoopbackHost(normalizedHost.lowercased()) else {
            return ""
        }
        guard endpoint.httpsPort != ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort else {
            return normalizedHost
        }
        return "\(normalizedHost):\(endpoint.httpsPort)"
    }

    private static func serializedExactHostCandidate(for endpoint: ShadowClientRemoteHostEndpoint) -> String {
        let normalizedHost = endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ShadowClientRemoteHostCandidateFilter.isLoopbackHost(normalizedHost.lowercased()) else {
            return ""
        }
        return "\(normalizedHost):\(endpoint.httpsPort)"
    }

    private static func activeRouteCandidate(
        for descriptor: ShadowClientRemoteHostDescriptor
    ) -> String {
        serializedHostCandidate(for: descriptor.routes.active)
    }

    private static func activeExactRouteCandidate(
        for descriptor: ShadowClientRemoteHostDescriptor
    ) -> String {
        serializedExactHostCandidate(for: descriptor.routes.active)
    }

    private static func streamHTTPSPort(fromPreferredHTTPSPort httpsPort: Int) -> Int {
        let candidateStreamHTTPSPort = httpsPort - 6
        guard
            (ShadowClientGameStreamNetworkDefaults.minimumPort...ShadowClientGameStreamNetworkDefaults.maximumPort)
                .contains(candidateStreamHTTPSPort)
        else {
            return httpsPort
        }

        let mappedHTTPPort = ShadowClientGameStreamNetworkDefaults.httpPort(
            forHTTPSPort: candidateStreamHTTPSPort
        )
        guard ShadowClientGameStreamNetworkDefaults.isLikelyHTTPPort(mappedHTTPPort) else {
            return httpsPort
        }

        return candidateStreamHTTPSPort
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
        guard !ShadowClientRemoteHostCandidateFilter.isLoopbackHost(host.lowercased()) else {
            return nil
        }

        if let port = parsed.port {
            let canonicalPort = ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
                fromCandidatePort: port
            )
            return "\(host.lowercased()):\(canonicalPort)"
        }

        return host.lowercased()
    }

    private static func normalizedAuthorityHost(_ candidate: String?) -> String? {
        guard let candidate else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let urlCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmed)
        guard let parsed = URL(string: urlCandidate), let host = parsed.host?.lowercased(), !host.isEmpty else {
            return trimmed.lowercased()
        }
        guard !ShadowClientRemoteHostCandidateFilter.isLoopbackHost(host) else {
            return nil
        }

        return host
    }

    private static func parsedCandidateRoute(_ candidate: String?) -> (host: String, port: Int?)? {
        guard let normalized = normalizeCandidate(candidate) else {
            return nil
        }

        let urlCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(normalized)
        guard let parsed = URL(string: urlCandidate), let host = parsed.host else {
            return nil
        }

        let port = parsed.port.map {
            ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
                fromCandidatePort: $0
            )
        }

        return (host.lowercased(), port)
    }

    private static func candidate(
        _ candidate: String?,
        matches endpoint: ShadowClientRemoteHostEndpoint,
        hostAliasesByHost: [String: Set<String>] = [:]
    ) -> Bool {
        guard let parsed = parsedCandidateRoute(candidate) else {
            return false
        }

        let endpointHosts = hostAliases(
            for: endpoint.host,
            hostAliasesByHost: hostAliasesByHost
        )
        guard endpointHosts.contains(parsed.host) else {
            return false
        }

        return parsed.port == nil || parsed.port == endpoint.httpsPort
    }

    private static func candidateMatchesDescriptor(
        _ candidate: String?,
        matches descriptor: ShadowClientRemoteHostDescriptor,
        hostAliasesByHost: [String: Set<String>] = [:]
    ) -> Bool {
        if descriptor.id == candidate?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            return true
        }
        return descriptor.routes.allEndpoints.contains { endpoint in
            Self.candidate(candidate, matches: endpoint, hostAliasesByHost: hostAliasesByHost)
        }
    }

    private static func resolveHostSelection(
        _ selection: String,
        in hosts: [ShadowClientRemoteHostDescriptor]
    ) -> ShadowClientRemoteHostDescriptor? {
        let normalizedSelection = selection.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedSelection.isEmpty else {
            return nil
        }

        if let exactIDMatch = hosts.first(where: { $0.id == normalizedSelection }) {
            return exactIDMatch
        }

        return hosts.first(where: { candidateMatchesDescriptor(normalizedSelection, matches: $0) })
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

    private static func mergeResolvedHosts(
        _ hosts: [ShadowClientRemoteHostDescriptor],
        selectedHostID: String?,
        preferredHost: String?,
        preferredRoutesByKey: [String: String],
        pairedHostKeys: Set<String>,
        hostAliasesByHost: [String: Set<String>]
    ) -> [ShadowClientRemoteHostDescriptor] {
        let groupedHosts = clusterResolvedHosts(hosts, hostAliasesByHost: hostAliasesByHost)
        return groupedHosts.compactMap {
            mergeResolvedHostGroup(
                $0,
                selectedHostID: selectedHostID,
                preferredHost: preferredHost,
                preferredRoutesByKey: preferredRoutesByKey,
                pairedHostKeys: pairedHostKeys,
                hostAliasesByHost: hostAliasesByHost
            )
        }
        .sorted(by: compareHosts)
    }

    private static func deduplicatedHostDescriptorsByID(
        _ hosts: [ShadowClientRemoteHostDescriptor]
    ) -> [ShadowClientRemoteHostDescriptor] {
        var seen = Set<String>()
        return hosts.filter { descriptor in
            seen.insert(descriptor.id).inserted
        }
    }

    private static func upsertingManualRoute(
        _ candidateHost: String,
        forHostID hostID: String,
        in hosts: [ShadowClientRemoteHostDescriptor]
    ) -> [ShadowClientRemoteHostDescriptor] {
        hosts.map { descriptor in
            guard descriptor.id == hostID else {
                return descriptor
            }
            return withManualRoute(candidateHost, appliedTo: descriptor)
        }
    }

    private static func withManualRoute(
        _ candidateHost: String,
        appliedTo descriptor: ShadowClientRemoteHostDescriptor
    ) -> ShadowClientRemoteHostDescriptor {
        let parsedRoute = parsedCandidateRoute(candidateHost)
        let host = parsedRoute?.host ?? candidateHost
        let httpsPort = parsedRoute?.port ?? descriptor.httpsPort
        let manualEndpoint = ShadowClientRemoteHostEndpoint(host: host, httpsPort: httpsPort)
        let existingManual = descriptor.routes.manual
        if existingManual == manualEndpoint {
            return descriptor
        }

        let routes = ShadowClientRemoteHostRoutes(
            active: descriptor.routes.active,
            local: descriptor.routes.local,
            remote: descriptor.routes.remote,
            manual: manualEndpoint
        )

        return ShadowClientRemoteHostDescriptor(
            activeRoute: routes.active,
            isSaved: descriptor.isSaved,
            displayName: descriptor.displayName,
            pairStatus: descriptor.pairStatus,
            currentGameID: descriptor.currentGameID,
            serverState: descriptor.serverState,
            appVersion: descriptor.appVersion,
            gfeVersion: descriptor.gfeVersion,
            uniqueID: descriptor.uniqueID,
            macAddress: descriptor.macAddress,
            serverCodecModeSupport: descriptor.serverCodecModeSupport,
            controlHTTPSPort: descriptor.controlHTTPSPort,
            lastError: descriptor.lastError,
            routes: routes
        )
    }

    private static func upsertingSavedHostCandidate(
        _ candidateHost: String,
        into hosts: [ShadowClientRemoteHostDescriptor]
    ) -> [ShadowClientRemoteHostDescriptor] {
        let placeholder = savedHostPlaceholder(for: candidateHost)
        var updatedHosts: [ShadowClientRemoteHostDescriptor] = []
        var matched = false

        for descriptor in hosts {
            if let matchingEndpoint = descriptor.routes.allEndpoints.first(where: {
                candidate(candidateHost, matches: $0)
            }) {
                let routes = ShadowClientRemoteHostRoutes(
                    active: matchingEndpoint,
                    local: descriptor.routes.local,
                    remote: descriptor.routes.remote,
                    manual: descriptor.routes.manual
                )
                updatedHosts.append(
                    ShadowClientRemoteHostDescriptor(
                        activeRoute: routes.active,
                        isSaved: true,
                        displayName: descriptor.displayName,
                        pairStatus: descriptor.pairStatus,
                        currentGameID: descriptor.currentGameID,
                        serverState: descriptor.serverState,
                        appVersion: descriptor.appVersion,
                        gfeVersion: descriptor.gfeVersion,
                        uniqueID: descriptor.uniqueID,
                        macAddress: descriptor.macAddress,
                        serverCodecModeSupport: descriptor.serverCodecModeSupport,
                        controlHTTPSPort: descriptor.controlHTTPSPort,
                        lastError: descriptor.lastError,
                        routes: routes
                    )
                )
                matched = true
            } else {
                updatedHosts.append(descriptor)
            }
        }

        if !matched {
            updatedHosts.append(placeholder)
        }

        return deduplicatedHostDescriptorsByID(updatedHosts).sorted(by: compareHosts)
    }

    private static func savedHostPlaceholder(for candidateHost: String) -> ShadowClientRemoteHostDescriptor {
        let parsedRoute = parsedCandidateRoute(candidateHost)
        let fallbackHost = parsedRoute?.host ?? candidateHost
        let fallbackHTTPSPort = parsedRoute?.port
            ?? ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
        return ShadowClientRemoteHostDescriptor(
            host: fallbackHost,
            isSaved: true,
            displayName: fallbackHost,
            pairStatus: .unknown,
            currentGameID: 0,
            serverState: "",
            httpsPort: fallbackHTTPSPort,
            appVersion: nil,
            gfeVersion: nil,
            uniqueID: nil,
            serverCodecModeSupport: 0,
            lastError: nil
        )
    }

    private static func updatingSavedHostCandidate(
        _ candidateHost: String,
        forHostID hostID: String,
        in hosts: [ShadowClientRemoteHostDescriptor]
    ) -> [ShadowClientRemoteHostDescriptor] {
        hosts.map { descriptor in
            guard descriptor.id == hostID else {
                return descriptor
            }

            let parsedRoute = parsedCandidateRoute(candidateHost)
            let host = parsedRoute?.host ?? candidateHost
            let httpsPort = parsedRoute?.port ?? descriptor.httpsPort
            let requestedEndpoint = ShadowClientRemoteHostEndpoint(host: host, httpsPort: httpsPort)
            let activeRoute = descriptor.routes.allEndpoints.first(where: { $0 == requestedEndpoint }) ?? requestedEndpoint
            let usesKnownResolvedRoute = descriptor.routes.local == activeRoute ||
                descriptor.routes.remote == activeRoute ||
                descriptor.routes.active == activeRoute
            let manualRoute = usesKnownResolvedRoute ? nil : activeRoute
            let routes = ShadowClientRemoteHostRoutes(
                active: activeRoute,
                local: descriptor.routes.local,
                remote: descriptor.routes.remote,
                manual: manualRoute
            )

            return ShadowClientRemoteHostDescriptor(
                activeRoute: routes.active,
                isSaved: true,
                displayName: descriptor.displayName,
                pairStatus: descriptor.pairStatus,
                currentGameID: descriptor.currentGameID,
                serverState: descriptor.serverState,
                appVersion: descriptor.appVersion,
                gfeVersion: descriptor.gfeVersion,
                uniqueID: descriptor.uniqueID,
                macAddress: descriptor.macAddress,
                serverCodecModeSupport: descriptor.serverCodecModeSupport,
                controlHTTPSPort: descriptor.controlHTTPSPort,
                lastError: descriptor.lastError,
                routes: routes
            )
        }
        .sorted(by: compareHosts)
    }

    private static func shouldPublishHostDescriptor(
        _ descriptor: ShadowClientRemoteHostDescriptor
    ) -> Bool {
        return true
    }

    private static func normalizedPersistedHosts(
        _ hosts: [ShadowClientRemoteHostDescriptor]
    ) -> [ShadowClientRemoteHostDescriptor] {
        guard !hosts.isEmpty else {
            return []
        }

        let pairedHostKeys = Set(
            hosts
                .filter { $0.pairStatus == .paired }
                .map(mergeKey(for:))
        )
        let mergedHosts = mergeResolvedHosts(
            hosts,
            selectedHostID: nil,
            preferredHost: nil,
            preferredRoutesByKey: [:],
            pairedHostKeys: pairedHostKeys,
            hostAliasesByHost: Self.collapsedHostAliases(
                for: hosts.flatMap { descriptor in
                    descriptor.routes.allEndpoints.map(\.host)
                }
            )
        )
        return deduplicatedHostDescriptorsByID(mergedHosts)
    }

    private static func clusterResolvedHosts(
        _ hosts: [ShadowClientRemoteHostDescriptor],
        hostAliasesByHost: [String: Set<String>] = [:]
    ) -> [[ShadowClientRemoteHostDescriptor]] {
        var clusters: [[ShadowClientRemoteHostDescriptor]] = []

        for host in hosts {
            if let matchingClusterIndex = clusters.firstIndex(where: { cluster in
                cluster.contains(where: { clusteredHost in
                    descriptorsBelongToSamePhysicalHost(
                        clusteredHost,
                        host,
                        hostAliasesByHost: hostAliasesByHost
                    )
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
                            descriptorsBelongToSamePhysicalHost(
                                lhsHost,
                                rhsHost,
                                hostAliasesByHost: hostAliasesByHost
                            )
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
        pairedHostKeys: Set<String>,
        hostAliasesByHost: [String: Set<String>]
    ) -> ShadowClientRemoteHostDescriptor? {
        guard let primary = group.sorted(by: {
            compareMergePriority(
                lhs: $0,
                rhs: $1,
                selectedHostID: selectedHostID,
                preferredHost: preferredHost,
                preferredRoute: preferredRoutesByKey[mergeKey(for: $0)],
                hostAliasesByHost: hostAliasesByHost
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
            preferredRoute: preferredRoute,
            hostAliasesByHost: hostAliasesByHost
        )

        return ShadowClientRemoteHostDescriptor(
            activeRoute: mergedRoutes.active,
            isSaved: group.contains(where: \.isSaved),
            displayName: displayName,
            pairStatus: pairStatus,
            currentGameID: currentGameID,
            serverState: primary.serverState,
            appVersion: primary.appVersion,
            gfeVersion: primary.gfeVersion,
            uniqueID: primary.uniqueID,
            macAddress: group.compactMap(\.macAddress).first ?? primary.macAddress,
            serverCodecModeSupport: group.map(\.serverCodecModeSupport).first ?? primary.serverCodecModeSupport,
            controlHTTPSPort: group.compactMap(\.controlHTTPSPort).first ?? primary.controlHTTPSPort,
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
                let exactCertificate = await pinnedCertificateStore.certificateDER(
                    forHost: endpoint.host,
                    httpsPort: endpoint.httpsPort
                )
                if exactCertificate != nil {
                    pairedKeys.insert(mergeKey(for: host))
                    break
                }
            }
        }

        return pairedKeys
    }

    private static func synchronizationGroupKey(for host: ShadowClientRemoteHostDescriptor) -> String {
        let portKey = host.routes.allEndpoints
            .map(\.httpsPort)
            .sorted()
            .map(String.init)
            .joined(separator: ",")
        if let uniqueID = normalizedUniqueID(host.uniqueID) {
            return "uniqueid:\(uniqueID)|ports:\(portKey)"
        }
        let routeKey = routeIdentitySet(for: host).sorted().joined(separator: "|")
        return "routes:\(routeKey)|ports:\(portKey)"
    }

    private static func compareMergePriority(
        lhs: ShadowClientRemoteHostDescriptor,
        rhs: ShadowClientRemoteHostDescriptor,
        selectedHostID: String?,
        preferredHost: String?,
        preferredRoute: String?,
        hostAliasesByHost: [String: Set<String>]
    ) -> Bool {
        let lhsSelected = lhs.id == selectedHostID
        let rhsSelected = rhs.id == selectedHostID
        if lhsSelected != rhsSelected {
            return lhsSelected
        }

        let normalizedPreferredHost = normalizeCandidate(preferredHost ?? preferredRoute)
        let lhsPreferred = lhs.routes.allEndpoints.contains {
            candidate(normalizedPreferredHost, matches: $0, hostAliasesByHost: hostAliasesByHost)
        }
        let rhsPreferred = rhs.routes.allEndpoints.contains {
            candidate(normalizedPreferredHost, matches: $0, hostAliasesByHost: hostAliasesByHost)
        }
        if lhsPreferred != rhsPreferred {
            return lhsPreferred
        }

        if lhs.isSaved != rhs.isSaved {
            return lhs.isSaved
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

        let lhsHostRank = runtimeRouteRank(lhs.host, hostAliasesByHost: hostAliasesByHost)
        let rhsHostRank = runtimeRouteRank(rhs.host, hostAliasesByHost: hostAliasesByHost)
        if lhsHostRank != rhsHostRank {
            return lhsHostRank < rhsHostRank
        }

        return lhs.host.localizedCaseInsensitiveCompare(rhs.host) == .orderedAscending
    }

    private static func descriptorsBelongToSamePhysicalHost(
        _ lhs: ShadowClientRemoteHostDescriptor,
        _ rhs: ShadowClientRemoteHostDescriptor,
        hostAliasesByHost: [String: Set<String>] = [:]
    ) -> Bool {
        if let lhsUniqueID = lhs.uniqueID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           let rhsUniqueID = rhs.uniqueID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !lhsUniqueID.isEmpty,
           !rhsUniqueID.isEmpty
        {
            return lhsUniqueID == rhsUniqueID
        }

        let lhsRouteIdentities = routeIdentitySet(for: lhs, hostAliasesByHost: hostAliasesByHost)
        let rhsRouteIdentities = routeIdentitySet(for: rhs, hostAliasesByHost: hostAliasesByHost)
        if !lhsRouteIdentities.isDisjoint(with: rhsRouteIdentities) {
            return true
        }

        return false
    }

    private static func mergeKey(for host: ShadowClientRemoteHostDescriptor) -> String {
        if let uniqueID = normalizedUniqueID(host.uniqueID) {
            return "uniqueid:\(uniqueID)"
        }

        let routeIdentities = routeIdentitySet(for: host).sorted()
        if !routeIdentities.isEmpty {
            return "routes:\(routeIdentities.joined(separator: "|"))"
        }

        return "host:\(host.id)"
    }

    private static func routeIdentitySet(
        for host: ShadowClientRemoteHostDescriptor,
        hostAliasesByHost: [String: Set<String>] = [:]
    ) -> Set<String> {
        host.routes.allEndpoints.reduce(into: Set<String>()) { partialResult, endpoint in
            guard !isLoopbackRouteHost(endpoint.host) else {
                return
            }
            let identities = hostAliases(for: endpoint.host, hostAliasesByHost: hostAliasesByHost)
                .map { "\($0):\(endpoint.httpsPort)" }
            partialResult.formUnion(identities)
        }
    }

    private static func routeHostSet(
        for host: ShadowClientRemoteHostDescriptor,
        hostAliasesByHost: [String: Set<String>] = [:]
    ) -> Set<String> {
        host.routes.allEndpoints.reduce(into: Set<String>()) { partialResult, endpoint in
            guard !isLoopbackRouteHost(endpoint.host) else {
                return
            }
            partialResult.formUnion(hostAliases(for: endpoint.host, hostAliasesByHost: hostAliasesByHost))
        }
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
        preferredRoute: String?,
        hostAliasesByHost: [String: Set<String>]
    ) -> ShadowClientRemoteHostRoutes {
        let local = group.compactMap(\.routes.local).first(where: { !isLoopbackRouteHost($0.host) })
        let remote = group.compactMap(\.routes.remote).first
        let manual = group.compactMap(\.routes.manual).first
        let candidateRoutes = group
            .flatMap { $0.routes.allEndpoints }
            .reduce(into: [ShadowClientRemoteHostEndpoint]()) { partialResult, endpoint in
                guard !isLoopbackRouteHost(endpoint.host) else {
                    return
                }
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
            let lhsRank = runtimeRouteRank($0.host, hostAliasesByHost: hostAliasesByHost)
            let rhsRank = runtimeRouteRank($1.host, hostAliasesByHost: hostAliasesByHost)
            if lhsRank == rhsRank {
                return $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending
            }
            return lhsRank < rhsRank
        }
        let selectedReachableHost = group.first(where: {
            $0.id == selectedHostID && $0.isReachable
        })?.host.lowercased()
        let localReachableRoute = rankedActiveRouteCandidates.first(where: {
            $0.host.lowercased() == reachableLocalHost && !isLinkLocalRouteHost($0.host)
        })
        let localRoute = rankedActiveRouteCandidates.first(where: { isLocalPairHost($0.host) })
        let reachablePublicRoute = rankedActiveRouteCandidates.first(where: {
            !isLocalPairHost($0.host) && !isLinkLocalRouteHost($0.host)
        })
        let selectedReachableRoute = rankedActiveRouteCandidates.first(where: {
            $0.host.lowercased() == selectedReachableHost
        })
        let normalizedPreferredRoute = normalizeCandidate(preferredHost ?? preferredRoute)
        let preferredRouteCandidates = reachableHostNames.isEmpty
            ? candidateRoutes
            : activeRouteCandidates
        let preferredActiveRoute = preferredRouteCandidates.first(where: {
            candidate(normalizedPreferredRoute, matches: $0, hostAliasesByHost: hostAliasesByHost)
        })
        let savedActiveRoute = group
            .first(where: \.isSaved)?
            .routes
            .allEndpoints
            .first(where: { savedEndpoint in
                preferredRouteCandidates.contains(where: { $0 == savedEndpoint })
            })

        let active: ShadowClientRemoteHostEndpoint
        if let preferredActiveRoute {
            active = preferredActiveRoute
        } else if let savedActiveRoute {
            active = savedActiveRoute
        } else if reachableHostNames.isEmpty {
            active = reachablePublicRoute
                ?? localRoute
                ?? rankedActiveRouteCandidates.first
                ?? fallbackPrimary.routes.active
        } else {
            active = localReachableRoute
                ?? reachablePublicRoute
                ?? selectedReachableRoute
                ?? localRoute
                ?? rankedActiveRouteCandidates.first
                ?? fallbackPrimary.routes.active
        }

        return ShadowClientRemoteHostRoutes(
            active: active,
            local: local,
            remote: remote,
            manual: manual
        )
    }

    private static func preferredRuntimeRouteCandidate(
        for selectedHost: ShadowClientRemoteHostDescriptor,
        pairingRouteStore: ShadowClientPairingRouteStore
    ) async -> String? {
        let selectedActiveRoute = normalizeCandidate(activeExactRouteCandidate(for: selectedHost))
        if let selectedActiveRoute {
            return selectedActiveRoute
        }

        if let storedPairRoute = normalizeCandidate(
            await pairingRouteStore.preferredHost(for: pairRouteStoreKey(for: selectedHost))
        ) {
            return storedPairRoute
        }

        return normalizeCandidate(
            await pairingRouteStore.preferredHost(for: mergeKey(for: selectedHost))
        )
    }

    private static func preferredRuntimeHostDescriptor(
        for selectedHost: ShadowClientRemoteHostDescriptor,
        latestResolvedHostDescriptors: [ShadowClientRemoteHostDescriptor],
        pairingRouteStore: ShadowClientPairingRouteStore
    ) async -> ShadowClientRemoteHostDescriptor {
        let routeGroupKey = mergeKey(for: selectedHost)
        let knownRouteHosts = Set(
            selectedHost.routes.allEndpoints.map { $0.host.lowercased() }
        )
        let preferredRuntimeRoute = await preferredRuntimeRouteCandidate(
            for: selectedHost,
            pairingRouteStore: pairingRouteStore
        )
        let matchingDescriptors = latestResolvedHostDescriptors.filter {
            mergeKey(for: $0) == routeGroupKey || knownRouteHosts.contains($0.host.lowercased())
        }
        let reachableDescriptors = matchingDescriptors.filter(\.isReachable)
        let candidateDescriptors = reachableDescriptors.isEmpty ? matchingDescriptors : reachableDescriptors
        if let preferredRuntimeRoute,
           let preferredDescriptor = candidateDescriptors.first(where: {
               candidateMatchesDescriptor(preferredRuntimeRoute, matches: $0)
           })
        {
            return preferredDescriptor
        }
        let reachableLocalDescriptor = reachableDescriptors.first(where: {
            isLocalPairHost($0.host) && !isLinkLocalRouteHost($0.host)
        })
        let reachablePublicDescriptor = reachableDescriptors.first(where: {
            !isLocalPairHost($0.host) && !isLinkLocalRouteHost($0.host)
        })
        let publicDescriptor = candidateDescriptors.first(where: {
            !isLocalPairHost($0.host) && !isLinkLocalRouteHost($0.host)
        })

        if reachableDescriptors.isEmpty {
            if let publicDescriptor {
                return publicDescriptor
            }
        } else {
            if let reachableLocalDescriptor {
                return reachableLocalDescriptor
            }

            if let reachablePublicDescriptor {
                return reachablePublicDescriptor
            }
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
        let currentRoute = activeExactRouteCandidate(for: currentDescriptor)
        let candidates = latestResolvedHostDescriptors.filter {
            mergeKey(for: $0) == routeGroupKey || knownRouteHosts.contains($0.host.lowercased())
        }
        let reachableCandidates = candidates.filter(\.isReachable)

        if let nonLinkLocalCandidate = reachableCandidates.first(where: {
            !candidateMatchesDescriptor(currentRoute, matches: $0) &&
                !isLinkLocalRouteHost($0.host)
        }) {
            return nonLinkLocalCandidate
        }

        if !isLocalPairHost(currentDescriptor.host),
           let localDescriptor = reachableCandidates.first(where: {
               isLocalPairHost($0.host) &&
                   !candidateMatchesDescriptor(currentRoute, matches: $0) &&
                   !isLinkLocalRouteHost($0.host)
           }) {
            return localDescriptor
        }

        if !isLocalPairHost(currentDescriptor.host),
           let localEndpoint = selectedHost.routes.local,
           normalizeCandidate(serializedExactHostCandidate(for: localEndpoint)) !=
               normalizeCandidate(currentRoute)
        {
            return ShadowClientRemoteHostDescriptor(
                activeRoute: localEndpoint,
                isSaved: selectedHost.isSaved,
                displayName: selectedHost.displayName,
                pairStatus: selectedHost.pairStatus,
                currentGameID: selectedHost.currentGameID,
                serverState: selectedHost.serverState,
                appVersion: selectedHost.appVersion,
                gfeVersion: selectedHost.gfeVersion,
                uniqueID: selectedHost.uniqueID,
                macAddress: selectedHost.macAddress,
                serverCodecModeSupport: selectedHost.serverCodecModeSupport,
                controlHTTPSPort: selectedHost.controlHTTPSPort,
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
            candidate(normalizedPreferredHost, matches: $0)
        }) ?? host.routes.active
        let routes = ShadowClientRemoteHostRoutes(
            active: activeRoute,
            local: host.routes.local,
            remote: host.routes.remote,
            manual: host.routes.manual
        )

        return ShadowClientRemoteHostDescriptor(
            activeRoute: routes.active,
            isSaved: host.isSaved,
            displayName: host.displayName,
            pairStatus: .paired,
            currentGameID: host.currentGameID,
            serverState: host.serverState,
            appVersion: host.appVersion,
            gfeVersion: host.gfeVersion,
            uniqueID: host.uniqueID,
            macAddress: host.macAddress,
            serverCodecModeSupport: host.serverCodecModeSupport,
            controlHTTPSPort: host.controlHTTPSPort,
            lastError: host.lastError,
            routes: routes
        )
    }

    private static func preferredRouteOverrides(
        for hosts: [ShadowClientRemoteHostDescriptor],
        pairingRouteStore: ShadowClientPairingRouteStore
    ) async -> [String: String] {
        let keys = Set(hosts.map(mergeKey(for:)))
        var routes: [String: String] = [:]
        for key in keys {
            if let preferredHost = await pairingRouteStore.preferredHost(for: key) {
                routes[key] = normalizeCandidate(preferredHost)
            }
        }
        return routes
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
        let macAddress = ShadowClientWakeOnLANKit.normalizedMACAddress(
            document.values["mac"]?.first
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
            macAddress: macAddress,
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
        let normalized = trimmed.lowercased()
        guard !ShadowClientRemoteHostCandidateFilter.isLoopbackHost(normalized) else {
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
