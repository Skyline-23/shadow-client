import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Lumen admin credentials trim whitespace and build basic authorization")
func lumenAdminCredentialsTrimWhitespaceAndBuildBasicAuthorization() throws {
    let credentials = try ShadowClientLumenAdminCredentials(
        username: " admin ",
        password: " secret "
    )

    #expect(credentials.username == "admin")
    #expect(credentials.password == "secret")
    #expect(credentials.authorizationHeaderValue == "Basic YWRtaW46c2VjcmV0")
}

@Test("Lumen endpoint resolver canonicalizes host and HTTPS port")
func lumenEndpointResolverCanonicalizesHostAndHTTPSPort() throws {
    let endpoint = try ShadowClientLumenAuthenticationContextBuilder.resolveEndpoint(
        host: "wifi.skyline23.com:47984",
        httpsPort: 48984
    )

    #expect(
        endpoint == .init(
            connectHost: "wifi.skyline23.com",
            authorityHost: "wifi.skyline23.com",
            httpsPort: 47984
        )
    )
}

@Test("Lumen auth context builder prefers control HTTPS endpoint for stream routes")
func lumenAuthContextBuilderPrefersControlHTTPSEndpointForStreamRoutes() throws {
    let endpoints = try ShadowClientLumenAuthenticationContextBuilder.resolveControlEndpoints(
        host: "wifi.skyline23.com:48984",
        httpsPort: 48984
    )

    #expect(
        endpoints == [
            .init(connectHost: "wifi.skyline23.com", authorityHost: "wifi.skyline23.com", httpsPort: 48990),
            .init(connectHost: "wifi.skyline23.com", authorityHost: "wifi.skyline23.com", httpsPort: 48984),
        ]
    )
}

@Test("Lumen admin contexts reuse stream pin for derived control endpoint")
func lumenAdminContextsReuseStreamPinForDerivedControlEndpoint() async throws {
    let suiteName = "ShadowClientLumenAuthenticationContextTests.\(UUID().uuidString)"
    let identityStore = ShadowClientPairingIdentityStore(defaultsSuiteName: suiteName)
    let pinnedCertificateStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: suiteName)
    let pinnedCertificate = Data([0x01, 0x02, 0x03])
    await pinnedCertificateStore.setCertificateDER(
        pinnedCertificate,
        forHost: "wifi.skyline23.com",
        httpsPort: 48984
    )
    let builder = ShadowClientLumenAuthenticationContextBuilder(
        identityStore: identityStore,
        pinnedCertificateStore: pinnedCertificateStore
    )

    let contexts = try await builder.makeAdminContexts(
        route: .init(
            connectHost: "192.168.0.50",
            authorityHost: "wifi.skyline23.com",
            httpsPort: 48984
        ),
        username: "admin",
        password: "secret"
    )

    #expect(
        contexts.first?.endpoint == .init(
            connectHost: "192.168.0.50",
            authorityHost: "wifi.skyline23.com",
            httpsPort: 48990
        )
    )
    #expect(contexts.first?.pinnedServerCertificateDER == pinnedCertificate)
}

@Test("Lumen request context injects authorization header into HTTPS request data")
func lumenRequestContextInjectsAuthorizationHeaderIntoHTTPSRequestData() throws {
    let context = ShadowClientLumenHTTPSRequestContext(
        endpoint: .init(
            connectHost: "192.168.0.50",
            authorityHost: "wifi.skyline23.com",
            httpsPort: 48984
        ),
        pinnedServerCertificateDER: nil,
        clientCertificates: nil,
        clientCertificateIdentity: nil,
        authorizationHeaderValue: "Basic YWRtaW46c2VjcmV0"
    )

    let request = try context.makeRequestData(
        path: "/api/clients/list",
        method: "GET"
    )
    let requestText = String(decoding: request.requestData, as: UTF8.self)

    #expect(request.url.absoluteString == "https://wifi.skyline23.com:48984/api/clients/list")
    #expect(request.connectHost == "192.168.0.50")
    #expect(requestText.contains("Authorization: Basic YWRtaW46c2VjcmV0"))
}
