import Foundation
@preconcurrency import Security
import ShadowClientFeatureConnection

struct ShadowClientLumenAdminCredentials: Equatable, Sendable {
    let username: String
    let password: String

    init(username: String, password: String) throws {
        let trimmedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPassword = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUsername.isEmpty, !trimmedPassword.isEmpty else {
            throw ShadowClientGameStreamError.requestFailed("Lumen admin credentials are required.")
        }

        self.username = trimmedUsername
        self.password = trimmedPassword
    }

    var authorizationHeaderValue: String {
        let credentialData = Data("\(username):\(password)".utf8).base64EncodedString()
        return "Basic \(credentialData)"
    }
}

struct ShadowClientLumenEndpoint: Equatable, Sendable {
    let host: String
    let httpsPort: Int

    func url(
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = ShadowClientGameStreamNetworkDefaults.httpsScheme
        components.host = host
        components.port = httpsPort
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw ShadowClientGameStreamError.invalidURL
        }
        return url
    }
}

struct ShadowClientLumenHTTPSRequestContext: Sendable {
    let endpoint: ShadowClientLumenEndpoint
    let pinnedServerCertificateDER: Data?
    let clientCertificates: [SecCertificate]?
    let clientCertificateIdentity: SecIdentity?
    let authorizationHeaderValue: String?

    func makeRequestData(
        path: String,
        method: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) throws -> (url: URL, requestData: Data) {
        let url = try endpoint.url(path: path, queryItems: queryItems)
        var resolvedHeaders = headers
        if let authorizationHeaderValue {
            resolvedHeaders["Authorization"] = authorizationHeaderValue
        }

        return (
            url,
            ShadowClientGameStreamHTTPTransport.makeHTTPRequestData(
                url: url,
                host: endpoint.host,
                method: method,
                headers: resolvedHeaders,
                body: body
            )
        )
    }
}

struct ShadowClientLumenAuthenticationContextBuilder {
    private let identityStore: ShadowClientPairingIdentityStore
    private let pinnedCertificateStore: ShadowClientPinnedHostCertificateStore

    init(
        identityStore: ShadowClientPairingIdentityStore,
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore
    ) {
        self.identityStore = identityStore
        self.pinnedCertificateStore = pinnedCertificateStore
    }

    static func resolveEndpoint(
        host: String,
        httpsPort: Int
    ) throws -> ShadowClientLumenEndpoint {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw ShadowClientGameStreamError.invalidHost
        }

        let candidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(normalized)
        guard let url = URL(string: candidate), let parsedHost = url.host else {
            throw ShadowClientGameStreamError.invalidHost
        }

        let candidatePort = url.port ?? httpsPort
        let resolvedPort = ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
            fromCandidatePort: candidatePort
        )
        return .init(host: parsedHost, httpsPort: resolvedPort)
    }

    func makePairingContext(
        host: String,
        httpsPort: Int
    ) async throws -> ShadowClientLumenHTTPSRequestContext {
        let endpoint = try Self.resolveEndpoint(host: host, httpsPort: httpsPort)
        return .init(
            endpoint: endpoint,
            pinnedServerCertificateDER: await pinnedCertificateStore.certificateDER(
                forHost: endpoint.host,
                httpsPort: endpoint.httpsPort
            ),
            clientCertificates: try? await identityStore.tlsClientCertificates(),
            clientCertificateIdentity: try? await identityStore.tlsClientIdentity(),
            authorizationHeaderValue: nil
        )
    }

    func makeAdminContext(
        host: String,
        httpsPort: Int,
        username: String,
        password: String
    ) async throws -> ShadowClientLumenHTTPSRequestContext {
        let endpoint = try Self.resolveEndpoint(host: host, httpsPort: httpsPort)
        guard let pinnedServerCertificateDER = await pinnedCertificateStore.certificateDER(
            forHost: endpoint.host,
            httpsPort: endpoint.httpsPort
        ) else {
            throw ShadowClientGameStreamError.requestFailed("Pair the host before using Lumen admin APIs.")
        }

        let credentials = try ShadowClientLumenAdminCredentials(
            username: username,
            password: password
        )
        return .init(
            endpoint: endpoint,
            pinnedServerCertificateDER: pinnedServerCertificateDER,
            clientCertificates: nil,
            clientCertificateIdentity: nil,
            authorizationHeaderValue: credentials.authorizationHeaderValue
        )
    }
}
