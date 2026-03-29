import Foundation
@preconcurrency import Security
import ShadowClientFeatureConnection

public struct ShadowClientLumenRequestRoute: Equatable, Sendable {
    public let connectHost: String
    public let authorityHost: String
    public let httpsPort: Int

    public init(connectHost: String, authorityHost: String, httpsPort: Int) {
        self.connectHost = connectHost.trimmingCharacters(in: .whitespacesAndNewlines)
        self.authorityHost = authorityHost.trimmingCharacters(in: .whitespacesAndNewlines)
        self.httpsPort = httpsPort
    }
}

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
    let connectHost: String
    let authorityHost: String
    let httpsPort: Int

    init(host: String, httpsPort: Int) {
        self.connectHost = host
        self.authorityHost = host
        self.httpsPort = httpsPort
    }

    init(connectHost: String, authorityHost: String, httpsPort: Int) {
        self.connectHost = connectHost
        self.authorityHost = authorityHost
        self.httpsPort = httpsPort
    }

    var host: String { authorityHost }

    func url(
        path: String,
        queryItems: [URLQueryItem] = []
    ) throws -> URL {
        var components = URLComponents()
        components.scheme = ShadowClientGameStreamNetworkDefaults.httpsScheme
        components.host = authorityHost
        components.port = httpsPort
        components.path = path
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else {
            throw ShadowClientGameStreamError.invalidURL
        }
        return url
    }
}

struct ShadowClientLumenPreparedHTTPSRequest: Sendable {
    let url: URL
    let connectHost: String
    let requestData: Data
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
    ) throws -> ShadowClientLumenPreparedHTTPSRequest {
        let url = try endpoint.url(path: path, queryItems: queryItems)
        var resolvedHeaders = headers
        if let authorizationHeaderValue {
            resolvedHeaders["Authorization"] = authorizationHeaderValue
        }

        return .init(
            url: url,
            connectHost: endpoint.connectHost,
            requestData: ShadowClientGameStreamHTTPTransport.makeHTTPRequestData(
                url: url,
                host: endpoint.authorityHost,
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
        try resolveEndpoint(
            connectHost: host,
            authorityHost: host,
            httpsPort: httpsPort
        )
    }

    static func resolveEndpoint(
        route: ShadowClientLumenRequestRoute
    ) throws -> ShadowClientLumenEndpoint {
        try resolveEndpoint(
            connectHost: route.connectHost,
            authorityHost: route.authorityHost,
            httpsPort: route.httpsPort
        )
    }

    static func resolveEndpoint(
        connectHost: String,
        authorityHost: String,
        httpsPort: Int
    ) throws -> ShadowClientLumenEndpoint {
        let normalizedConnectHost = connectHost.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAuthorityHost = authorityHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedConnectHost.isEmpty, !normalizedAuthorityHost.isEmpty else {
            throw ShadowClientGameStreamError.invalidHost
        }

        let connectCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(normalizedConnectHost)
        let authorityCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(normalizedAuthorityHost)
        guard let connectURL = URL(string: connectCandidate), let parsedConnectHost = connectURL.host,
              let authorityURL = URL(string: authorityCandidate), let parsedAuthorityHost = authorityURL.host
        else {
            throw ShadowClientGameStreamError.invalidHost
        }

        let candidatePort = authorityURL.port ?? connectURL.port ?? httpsPort
        let resolvedPort = ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
            fromCandidatePort: candidatePort
        )
        return .init(
            connectHost: parsedConnectHost,
            authorityHost: parsedAuthorityHost,
            httpsPort: resolvedPort
        )
    }

    static func resolveControlEndpoints(
        host: String,
        httpsPort: Int,
        advertisedControlHTTPSPort: Int? = nil
    ) throws -> [ShadowClientLumenEndpoint] {
        try resolveControlEndpoints(
            connectHost: host,
            authorityHost: host,
            httpsPort: httpsPort,
            advertisedControlHTTPSPort: advertisedControlHTTPSPort
        )
    }

    static func resolveControlEndpoints(
        route: ShadowClientLumenRequestRoute,
        advertisedControlHTTPSPort: Int? = nil
    ) throws -> [ShadowClientLumenEndpoint] {
        try resolveControlEndpoints(
            connectHost: route.connectHost,
            authorityHost: route.authorityHost,
            httpsPort: route.httpsPort,
            advertisedControlHTTPSPort: advertisedControlHTTPSPort
        )
    }

    static func resolveControlEndpoints(
        connectHost: String,
        authorityHost: String,
        httpsPort: Int,
        advertisedControlHTTPSPort: Int? = nil
    ) throws -> [ShadowClientLumenEndpoint] {
        let baseEndpoint = try resolveEndpoint(
            connectHost: connectHost,
            authorityHost: authorityHost,
            httpsPort: httpsPort
        )
        var endpoints: [ShadowClientLumenEndpoint] = []
        var seen = Set<String>()

        func append(_ endpoint: ShadowClientLumenEndpoint) {
            let key = "\(endpoint.connectHost.lowercased())|\(endpoint.authorityHost.lowercased()):\(endpoint.httpsPort)"
            guard seen.insert(key).inserted else {
                return
            }
            endpoints.append(endpoint)
        }

        if let advertisedControlHTTPSPort {
            append(
                .init(
                    connectHost: baseEndpoint.connectHost,
                    authorityHost: baseEndpoint.authorityHost,
                    httpsPort: ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
                        fromCandidatePort: advertisedControlHTTPSPort
                    )
                )
            )
        }

        if let derivedControlHTTPSPort = derivedControlHTTPSPort(fromStreamHTTPSPort: baseEndpoint.httpsPort) {
            append(
                .init(
                    connectHost: baseEndpoint.connectHost,
                    authorityHost: baseEndpoint.authorityHost,
                    httpsPort: derivedControlHTTPSPort
                )
            )
        }

        append(baseEndpoint)
        return endpoints
    }

    func makePairingContext(
        host: String,
        httpsPort: Int
    ) async throws -> ShadowClientLumenHTTPSRequestContext {
        try await makePairingContext(
            route: .init(
                connectHost: host,
                authorityHost: host,
                httpsPort: httpsPort
            )
        )
    }

    func makePairingContext(
        route: ShadowClientLumenRequestRoute
    ) async throws -> ShadowClientLumenHTTPSRequestContext {
        guard let context = try await makePairingContexts(route: route).first else {
            throw ShadowClientGameStreamError.invalidHost
        }
        return context
    }

    func makePairingContexts(
        host: String,
        httpsPort: Int,
        advertisedControlHTTPSPort: Int? = nil
    ) async throws -> [ShadowClientLumenHTTPSRequestContext] {
        try await makePairingContexts(
            route: .init(
                connectHost: host,
                authorityHost: host,
                httpsPort: httpsPort
            ),
            advertisedControlHTTPSPort: advertisedControlHTTPSPort
        )
    }

    func makePairingContexts(
        route: ShadowClientLumenRequestRoute,
        advertisedControlHTTPSPort: Int? = nil
    ) async throws -> [ShadowClientLumenHTTPSRequestContext] {
        let endpoints = try Self.resolveControlEndpoints(
            route: route,
            advertisedControlHTTPSPort: advertisedControlHTTPSPort
        )
        let baseEndpoint = try Self.resolveEndpoint(route: route)
        return try await makeHTTPSRequestContexts(
            endpoints: endpoints,
            baseEndpoint: baseEndpoint,
            authorizationHeaderValue: nil,
            includeClientIdentity: true,
            requirePinnedServerCertificate: false
        )
    }

    func makeAdminContext(
        host: String,
        httpsPort: Int,
        username: String,
        password: String
    ) async throws -> ShadowClientLumenHTTPSRequestContext {
        try await makeAdminContext(
            route: .init(
                connectHost: host,
                authorityHost: host,
                httpsPort: httpsPort
            ),
            username: username,
            password: password
        )
    }

    func makeAdminContext(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String
    ) async throws -> ShadowClientLumenHTTPSRequestContext {
        guard let context = try await makeAdminContexts(
            route: route,
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
        try await makeAdminContexts(
            route: .init(
                connectHost: host,
                authorityHost: host,
                httpsPort: httpsPort
            ),
            username: username,
            password: password,
            advertisedControlHTTPSPort: advertisedControlHTTPSPort
        )
    }

    func makeAdminContexts(
        route: ShadowClientLumenRequestRoute,
        username: String,
        password: String,
        advertisedControlHTTPSPort: Int? = nil
    ) async throws -> [ShadowClientLumenHTTPSRequestContext] {
        let credentials = try ShadowClientLumenAdminCredentials(
            username: username,
            password: password
        )

        let endpoints = try Self.resolveControlEndpoints(
            route: route,
            advertisedControlHTTPSPort: advertisedControlHTTPSPort
        )
        let baseEndpoint = try Self.resolveEndpoint(route: route)
        return try await makeHTTPSRequestContexts(
            endpoints: endpoints,
            baseEndpoint: baseEndpoint,
            authorizationHeaderValue: credentials.authorizationHeaderValue,
            includeClientIdentity: false,
            requirePinnedServerCertificate: true
        )
    }

    private func makeHTTPSRequestContexts(
        endpoints: [ShadowClientLumenEndpoint],
        baseEndpoint: ShadowClientLumenEndpoint,
        authorizationHeaderValue: String?,
        includeClientIdentity: Bool,
        requirePinnedServerCertificate: Bool
    ) async throws -> [ShadowClientLumenHTTPSRequestContext] {
        let basePinnedCertificateDER = await pinnedCertificateDER(for: baseEndpoint)
        let clientCertificates = includeClientIdentity ? (try? await identityStore.tlsClientCertificates()) : nil
        let clientCertificateIdentity = includeClientIdentity ? (try? await identityStore.tlsClientIdentity()) : nil

        var contexts: [ShadowClientLumenHTTPSRequestContext] = []
        for endpoint in endpoints {
            let pinnedServerCertificateDER = await pinnedCertificateDER(for: endpoint) ?? basePinnedCertificateDER
            if requirePinnedServerCertificate, pinnedServerCertificateDER == nil {
                continue
            }

            contexts.append(
                .init(
                    endpoint: endpoint,
                    pinnedServerCertificateDER: pinnedServerCertificateDER,
                    clientCertificates: clientCertificates,
                    clientCertificateIdentity: clientCertificateIdentity,
                    authorizationHeaderValue: authorizationHeaderValue
                )
            )
        }
        return contexts
    }

    private func pinnedCertificateDER(for endpoint: ShadowClientLumenEndpoint) async -> Data? {
        if let authorityCertificate = await pinnedCertificateStore.certificateDER(
            forHost: endpoint.authorityHost,
            httpsPort: endpoint.httpsPort
        ) {
            return authorityCertificate
        }

        if endpoint.connectHost.caseInsensitiveCompare(endpoint.authorityHost) != .orderedSame {
            return await pinnedCertificateStore.certificateDER(
                forHost: endpoint.connectHost,
                httpsPort: endpoint.httpsPort
            )
        }

        return nil
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
