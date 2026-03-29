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
    private static let controlHTTPSPortOffsetFromStreamHTTPSPort = 6

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

    static func resolveControlEndpoints(
        host: String,
        httpsPort: Int,
        advertisedControlHTTPSPort: Int? = nil
    ) throws -> [ShadowClientLumenEndpoint] {
        let baseEndpoint = try resolveEndpoint(host: host, httpsPort: httpsPort)
        var endpoints: [ShadowClientLumenEndpoint] = []
        var seen = Set<String>()

        func append(_ endpoint: ShadowClientLumenEndpoint) {
            let key = "\(endpoint.host.lowercased()):\(endpoint.httpsPort)"
            guard seen.insert(key).inserted else {
                return
            }
            endpoints.append(endpoint)
        }

        if let advertisedControlHTTPSPort {
            append(
                .init(
                    host: baseEndpoint.host,
                    httpsPort: ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
                        fromCandidatePort: advertisedControlHTTPSPort
                    )
                )
            )
        }

        if let derivedControlHTTPSPort = derivedControlHTTPSPort(fromStreamHTTPSPort: baseEndpoint.httpsPort) {
            append(.init(host: baseEndpoint.host, httpsPort: derivedControlHTTPSPort))
        }

        append(baseEndpoint)
        return endpoints
    }

    func makePairingContext(
        host: String,
        httpsPort: Int
    ) async throws -> ShadowClientLumenHTTPSRequestContext {
        guard let context = try await makePairingContexts(
            host: host,
            httpsPort: httpsPort
        ).first else {
            throw ShadowClientGameStreamError.invalidHost
        }
        return context
    }

    func makePairingContexts(
        host: String,
        httpsPort: Int,
        advertisedControlHTTPSPort: Int? = nil
    ) async throws -> [ShadowClientLumenHTTPSRequestContext] {
        let endpoints = try Self.resolveControlEndpoints(
            host: host,
            httpsPort: httpsPort,
            advertisedControlHTTPSPort: advertisedControlHTTPSPort
        )
        let baseEndpoint = try Self.resolveEndpoint(host: host, httpsPort: httpsPort)
        let basePinnedCertificateDER = await pinnedCertificateStore.certificateDER(
            forHost: baseEndpoint.host,
            httpsPort: baseEndpoint.httpsPort
        )
        let clientCertificates = try? await identityStore.tlsClientCertificates()
        let clientCertificateIdentity = try? await identityStore.tlsClientIdentity()

        var contexts: [ShadowClientLumenHTTPSRequestContext] = []
        for endpoint in endpoints {
            let exactPinnedCertificateDER = await pinnedCertificateStore.certificateDER(
                forHost: endpoint.host,
                httpsPort: endpoint.httpsPort
            )
            contexts.append(
                .init(
                    endpoint: endpoint,
                    pinnedServerCertificateDER: exactPinnedCertificateDER ?? basePinnedCertificateDER,
                    clientCertificates: clientCertificates,
                    clientCertificateIdentity: clientCertificateIdentity,
                    authorizationHeaderValue: nil
                )
            )
        }
        return contexts
    }

    func makeAdminContext(
        host: String,
        httpsPort: Int,
        username: String,
        password: String
    ) async throws -> ShadowClientLumenHTTPSRequestContext {
        guard let context = try await makeAdminContexts(
            host: host,
            httpsPort: httpsPort,
            username: username,
            password: password
        ).first else {
            throw ShadowClientGameStreamError.requestFailed("Pair the host before using Lumen admin APIs.")
        }
        return context
    }

    func makeAdminContexts(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        advertisedControlHTTPSPort: Int? = nil
    ) async throws -> [ShadowClientLumenHTTPSRequestContext] {
        let credentials = try ShadowClientLumenAdminCredentials(
            username: username,
            password: password
        )

        let endpoints = try Self.resolveControlEndpoints(
            host: host,
            httpsPort: httpsPort,
            advertisedControlHTTPSPort: advertisedControlHTTPSPort
        )
        let baseEndpoint = try Self.resolveEndpoint(host: host, httpsPort: httpsPort)
        let basePinnedCertificateDER = await pinnedCertificateStore.certificateDER(
            forHost: baseEndpoint.host,
            httpsPort: baseEndpoint.httpsPort
        )

        var contexts: [ShadowClientLumenHTTPSRequestContext] = []
        for endpoint in endpoints {
            let exactPinnedCertificateDER = await pinnedCertificateStore.certificateDER(
                forHost: endpoint.host,
                httpsPort: endpoint.httpsPort
            )
            guard let pinnedServerCertificateDER = exactPinnedCertificateDER ?? basePinnedCertificateDER else {
                continue
            }

            contexts.append(
                .init(
                    endpoint: endpoint,
                    pinnedServerCertificateDER: pinnedServerCertificateDER,
                    clientCertificates: nil,
                    clientCertificateIdentity: nil,
                    authorizationHeaderValue: credentials.authorizationHeaderValue
                )
            )
        }

        return contexts
    }

    private static func derivedControlHTTPSPort(fromStreamHTTPSPort httpsPort: Int) -> Int? {
        let mappedHTTPPort = ShadowClientGameStreamNetworkDefaults.httpPort(forHTTPSPort: httpsPort)
        guard ShadowClientGameStreamNetworkDefaults.isLikelyHTTPPort(mappedHTTPPort) else {
            return nil
        }

        let controlHTTPSPort = httpsPort + controlHTTPSPortOffsetFromStreamHTTPSPort
        guard
            (ShadowClientGameStreamNetworkDefaults.minimumPort...ShadowClientGameStreamNetworkDefaults.maximumPort)
                .contains(controlHTTPSPort)
        else {
            return nil
        }
        return controlHTTPSPort
    }
}
