import Foundation
import Security
import ShadowClientFeatureConnection

public struct ShadowClientLumenAdminClientProfile: Equatable, Sendable {
    public struct Command: Equatable, Sendable, Codable {
        public let cmd: String
        public let elevated: Bool

        public init(cmd: String, elevated: Bool) {
            self.cmd = cmd
            self.elevated = elevated
        }
    }

    public let name: String
    public let uuid: String
    public let displayModeOverride: String
    public let permissions: UInt32
    public let allowClientCommands: Bool
    public let alwaysUseVirtualDisplay: Bool
    public let connected: Bool
    public let doCommands: [Command]
    public let undoCommands: [Command]

    public init(
        name: String = "",
        uuid: String,
        displayModeOverride: String,
        permissions: UInt32 = 0,
        allowClientCommands: Bool = true,
        alwaysUseVirtualDisplay: Bool,
        connected: Bool,
        doCommands: [Command] = [],
        undoCommands: [Command] = []
    ) {
        self.name = name
        self.uuid = uuid
        self.displayModeOverride = displayModeOverride
        self.permissions = permissions
        self.allowClientCommands = allowClientCommands
        self.alwaysUseVirtualDisplay = alwaysUseVirtualDisplay
        self.connected = connected
        self.doCommands = doCommands
        self.undoCommands = undoCommands
    }
}

public protocol ShadowClientLumenAdminClient: Sendable {
    func fetchCurrentClientProfile(
        host: String,
        httpsPort: Int,
        username: String,
        password: String
    ) async throws -> ShadowClientLumenAdminClientProfile?

    func updateCurrentClientProfile(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        profile: ShadowClientLumenAdminClientProfile
    ) async throws -> ShadowClientLumenAdminClientProfile

    func disconnectCurrentClient(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        uuid: String
    ) async throws

    func unpairCurrentClient(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        uuid: String
    ) async throws

    func approvePairingRequest(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        pairingID: String
    ) async throws
}

public struct NativeShadowClientLumenAdminClient: ShadowClientLumenAdminClient {
    private let identityStore: ShadowClientPairingIdentityStore
    private let pinnedCertificateStore: ShadowClientPinnedHostCertificateStore

    public init(
        identityStore: ShadowClientPairingIdentityStore = .shared,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore = .shared
    ) {
        self.identityStore = identityStore
        self.pinnedCertificateStore = pinnedCertificateStore
    }

    public func fetchCurrentClientProfile(
        host: String,
        httpsPort: Int,
        username: String,
        password: String
    ) async throws -> ShadowClientLumenAdminClientProfile? {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            throw ShadowClientGameStreamError.requestFailed("Lumen admin credentials are required.")
        }

        let endpoint = try parseHostEndpoint(
            host: host,
            fallbackPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPPort
        )
        guard let pinnedCertificateDER = await pinnedCertificateStore.certificateDER(
            forHost: endpoint.host,
            httpsPort: httpsPort
        ) else {
            throw ShadowClientGameStreamError.requestFailed("Pair the host before using Lumen admin APIs.")
        }

        let delegate = ShadowClientLumenAdminURLSessionDelegate(
            pinnedServerCertificateDER: pinnedCertificateDER
        )
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer {
            session.invalidateAndCancel()
        }

        var components = URLComponents()
        components.scheme = ShadowClientGameStreamNetworkDefaults.httpsScheme
        components.host = endpoint.host
        components.port = httpsPort
        components.path = "/api/clients/list"
        guard let url = components.url else {
            throw ShadowClientGameStreamError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = ShadowClientGameStreamNetworkDefaults.defaultRequestTimeout
        let credentialData = Data("\(trimmedUsername):\(trimmedPassword)".utf8).base64EncodedString()
        request.setValue("Basic \(credentialData)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ShadowClientGameStreamError.invalidResponse
            }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                throw ShadowClientGameStreamError.responseRejected(
                    code: httpResponse.statusCode,
                    message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                )
            }

            let currentClientUUID = await identityStore.uniqueID()
            return try Self.parseCurrentClientProfile(
                data: data,
                currentClientUUID: currentClientUUID
            )
        } catch {
            throw ShadowClientGameStreamHTTPTransport.requestFailureError(
                error,
                tlsFailure: delegate.tlsFailure
            )
        }
    }

    public func updateCurrentClientProfile(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        profile: ShadowClientLumenAdminClientProfile
    ) async throws -> ShadowClientLumenAdminClientProfile {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            throw ShadowClientGameStreamError.requestFailed("Lumen admin credentials are required.")
        }

        let endpoint = try parseHostEndpoint(
            host: host,
            fallbackPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPPort
        )
        guard let pinnedCertificateDER = await pinnedCertificateStore.certificateDER(
            forHost: endpoint.host,
            httpsPort: httpsPort
        ) else {
            throw ShadowClientGameStreamError.requestFailed("Pair the host before using Lumen admin APIs.")
        }

        let delegate = ShadowClientLumenAdminURLSessionDelegate(
            pinnedServerCertificateDER: pinnedCertificateDER
        )
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer {
            session.invalidateAndCancel()
        }

        var components = URLComponents()
        components.scheme = ShadowClientGameStreamNetworkDefaults.httpsScheme
        components.host = endpoint.host
        components.port = httpsPort
        components.path = "/api/clients/update"
        guard let url = components.url else {
            throw ShadowClientGameStreamError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ShadowClientGameStreamNetworkDefaults.defaultRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let credentialData = Data("\(trimmedUsername):\(trimmedPassword)".utf8).base64EncodedString()
        request.setValue("Basic \(credentialData)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            LumenUpdateClientPayload(
                uuid: profile.uuid,
                name: profile.name,
                displayMode: profile.displayModeOverride,
                permissions: profile.permissions,
                allowClientCommands: profile.allowClientCommands,
                alwaysUseVirtualDisplay: profile.alwaysUseVirtualDisplay,
                doCommands: profile.doCommands,
                undoCommands: profile.undoCommands
            )
        )

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ShadowClientGameStreamError.invalidResponse
            }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                throw ShadowClientGameStreamError.responseRejected(
                    code: httpResponse.statusCode,
                    message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                )
            }
            return profile
        } catch {
            throw ShadowClientGameStreamHTTPTransport.requestFailureError(
                error,
                tlsFailure: delegate.tlsFailure
            )
        }
    }

    public func disconnectCurrentClient(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        uuid: String
    ) async throws {
        try await postSimpleClientAction(
            host: host,
            httpsPort: httpsPort,
            username: username,
            password: password,
            path: "/api/clients/disconnect",
            body: LumenUUIDPayload(uuid: uuid)
        )
    }

    public func unpairCurrentClient(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        uuid: String
    ) async throws {
        try await postSimpleClientAction(
            host: host,
            httpsPort: httpsPort,
            username: username,
            password: password,
            path: "/api/clients/unpair",
            body: LumenUUIDPayload(uuid: uuid)
        )
    }

    public func approvePairingRequest(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        pairingID: String
    ) async throws {
        let trimmedPairingID = pairingID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPairingID.isEmpty else {
            throw ShadowClientGameStreamError.requestFailed("Pairing ID is required.")
        }

        try await postSimpleClientAction(
            host: host,
            httpsPort: httpsPort,
            username: username,
            password: password,
            path: "/api/pairing/approve",
            body: LumenPairingDecisionPayload(pairingID: trimmedPairingID)
        )
    }

    static func parseCurrentClientProfile(
        data: Data,
        currentClientUUID: String
    ) throws -> ShadowClientLumenAdminClientProfile? {
        let payload = try JSONDecoder().decode(LumenClientsListPayload.self, from: data)
        return payload.namedCerts.first {
            $0.uuid.caseInsensitiveCompare(currentClientUUID) == .orderedSame
        }?.profile
    }

    private func parseHostEndpoint(
        host: String,
        fallbackPort: Int
    ) throws -> (host: String, port: Int) {
        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ShadowClientGameStreamError.invalidHost
        }

        if let url = URL(string: trimmed), let urlHost = url.host {
            return (urlHost, url.port ?? fallbackPort)
        }

        if let hostRange = trimmed.range(of: ":"), !trimmed.contains("]") {
            let hostname = String(trimmed[..<hostRange.lowerBound])
            let portString = String(trimmed[hostRange.upperBound...])
            if let port = Int(portString), !hostname.isEmpty {
                return (hostname, port)
            }
        }

        return (trimmed, fallbackPort)
    }

    private func postSimpleClientAction<Body: Encodable>(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        path: String,
        body: Body
    ) async throws {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            throw ShadowClientGameStreamError.requestFailed("Lumen admin credentials are required.")
        }

        let endpoint = try parseHostEndpoint(
            host: host,
            fallbackPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPPort
        )
        guard let pinnedCertificateDER = await pinnedCertificateStore.certificateDER(
            forHost: endpoint.host,
            httpsPort: httpsPort
        ) else {
            throw ShadowClientGameStreamError.requestFailed("Pair the host before using Lumen admin APIs.")
        }

        let delegate = ShadowClientLumenAdminURLSessionDelegate(
            pinnedServerCertificateDER: pinnedCertificateDER
        )
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer {
            session.invalidateAndCancel()
        }

        var components = URLComponents()
        components.scheme = ShadowClientGameStreamNetworkDefaults.httpsScheme
        components.host = endpoint.host
        components.port = httpsPort
        components.path = path
        guard let url = components.url else {
            throw ShadowClientGameStreamError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = ShadowClientGameStreamNetworkDefaults.defaultRequestTimeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let credentialData = Data("\(trimmedUsername):\(trimmedPassword)".utf8).base64EncodedString()
        request.setValue("Basic \(credentialData)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (_, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw ShadowClientGameStreamError.invalidResponse
            }
            guard (200 ... 299).contains(httpResponse.statusCode) else {
                throw ShadowClientGameStreamError.responseRejected(
                    code: httpResponse.statusCode,
                    message: HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
                )
            }
        } catch {
            throw ShadowClientGameStreamHTTPTransport.requestFailureError(
                error,
                tlsFailure: delegate.tlsFailure
            )
        }
    }
}

private struct LumenClientsListPayload: Decodable {
    let namedCerts: [LumenNamedCert]

    enum CodingKeys: String, CodingKey {
        case namedCerts = "named_certs"
    }
}

private struct LumenNamedCert: Decodable {
    let name: String
    let uuid: String
    let displayMode: String
    let permissions: UInt32
    let allowClientCommands: Bool
    let alwaysUseVirtualDisplay: Bool
    let connected: Bool
    let doCommands: [LumenCommand]
    let undoCommands: [LumenCommand]

    enum CodingKeys: String, CodingKey {
        case name
        case uuid
        case displayMode = "display_mode"
        case permissions = "perm"
        case allowClientCommands = "allow_client_commands"
        case alwaysUseVirtualDisplay = "always_use_virtual_display"
        case connected
        case doCommands = "do"
        case undoCommands = "undo"
    }

    var profile: ShadowClientLumenAdminClientProfile {
        .init(
            name: name,
            uuid: uuid,
            displayModeOverride: displayMode,
            permissions: permissions,
            allowClientCommands: allowClientCommands,
            alwaysUseVirtualDisplay: alwaysUseVirtualDisplay,
            connected: connected,
            doCommands: doCommands.map(\.profileCommand),
            undoCommands: undoCommands.map(\.profileCommand)
        )
    }
}

private struct LumenCommand: Codable {
    let cmd: String
    let elevated: Bool

    var profileCommand: ShadowClientLumenAdminClientProfile.Command {
        .init(cmd: cmd, elevated: elevated)
    }
}

private struct LumenUpdateClientPayload: Encodable {
    let uuid: String
    let name: String
    let displayMode: String
    let permissions: UInt32
    let allowClientCommands: Bool
    let alwaysUseVirtualDisplay: Bool
    let doCommands: [ShadowClientLumenAdminClientProfile.Command]
    let undoCommands: [ShadowClientLumenAdminClientProfile.Command]

    enum CodingKeys: String, CodingKey {
        case uuid
        case name
        case displayMode = "display_mode"
        case permissions = "perm"
        case allowClientCommands = "allow_client_commands"
        case alwaysUseVirtualDisplay = "always_use_virtual_display"
        case doCommands = "do"
        case undoCommands = "undo"
    }
}

private struct LumenUUIDPayload: Encodable {
    let uuid: String
}

private struct LumenPairingDecisionPayload: Encodable {
    let pairingID: String

    enum CodingKeys: String, CodingKey {
        case pairingID = "pairingId"
    }
}

private final class ShadowClientLumenAdminURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    private let pinnedServerCertificateDER: Data
    private let lock = NSLock()
    private var recordedTLSFailure: ShadowClientGameStreamTLSFailure?

    init(pinnedServerCertificateDER: Data) {
        self.pinnedServerCertificateDER = pinnedServerCertificateDER
        super.init()
    }

    var tlsFailure: ShadowClientGameStreamTLSFailure? {
        lock.lock()
        defer { lock.unlock() }
        return recordedTLSFailure
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge: challenge, completionHandler: completionHandler)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        handle(challenge: challenge, completionHandler: completionHandler)
    }

    private func handle(
        challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust,
              let certificateChain = SecTrustCopyCertificateChain(serverTrust) as? [SecCertificate],
              let leafCertificate = certificateChain.first
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let leafDER = SecCertificateCopyData(leafCertificate) as Data
        guard leafDER == pinnedServerCertificateDER else {
            recordTLSFailure(.serverCertificateMismatch)
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private func recordTLSFailure(_ failure: ShadowClientGameStreamTLSFailure) {
        lock.lock()
        recordedTLSFailure = failure
        lock.unlock()
    }
}
