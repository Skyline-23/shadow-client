import Foundation
import Security

public struct ShadowClientApolloAdminClientProfile: Equatable, Sendable {
    public let uuid: String
    public let displayModeOverride: String
    public let alwaysUseVirtualDisplay: Bool
    public let connected: Bool

    public init(
        uuid: String,
        displayModeOverride: String,
        alwaysUseVirtualDisplay: Bool,
        connected: Bool
    ) {
        self.uuid = uuid
        self.displayModeOverride = displayModeOverride
        self.alwaysUseVirtualDisplay = alwaysUseVirtualDisplay
        self.connected = connected
    }
}

public protocol ShadowClientApolloAdminClient: Sendable {
    func fetchCurrentClientProfile(
        host: String,
        httpsPort: Int,
        username: String,
        password: String
    ) async throws -> ShadowClientApolloAdminClientProfile?
}

public struct NativeShadowClientApolloAdminClient: ShadowClientApolloAdminClient {
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
    ) async throws -> ShadowClientApolloAdminClientProfile? {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            throw ShadowClientGameStreamError.requestFailed("Apollo admin credentials are required.")
        }

        let endpoint = try parseHostEndpoint(
            host: host,
            fallbackPort: ShadowClientGameStreamNetworkDefaults.defaultHTTPPort
        )
        guard let pinnedCertificateDER = await pinnedCertificateStore.certificateDER(forHost: endpoint.host) else {
            throw ShadowClientGameStreamError.requestFailed("Pair the host before using Apollo admin APIs.")
        }

        let delegate = ShadowClientApolloAdminURLSessionDelegate(
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

    static func parseCurrentClientProfile(
        data: Data,
        currentClientUUID: String
    ) throws -> ShadowClientApolloAdminClientProfile? {
        let payload = try JSONDecoder().decode(ApolloClientsListPayload.self, from: data)
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
}

private struct ApolloClientsListPayload: Decodable {
    let namedCerts: [ApolloNamedCert]

    enum CodingKeys: String, CodingKey {
        case namedCerts = "named_certs"
    }
}

private struct ApolloNamedCert: Decodable {
    let uuid: String
    let displayMode: String
    let alwaysUseVirtualDisplay: Bool
    let connected: Bool

    enum CodingKeys: String, CodingKey {
        case uuid
        case displayMode = "display_mode"
        case alwaysUseVirtualDisplay = "always_use_virtual_display"
        case connected
    }

    var profile: ShadowClientApolloAdminClientProfile {
        .init(
            uuid: uuid,
            displayModeOverride: displayMode,
            alwaysUseVirtualDisplay: alwaysUseVirtualDisplay,
            connected: connected
        )
    }
}

private final class ShadowClientApolloAdminURLSessionDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
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
