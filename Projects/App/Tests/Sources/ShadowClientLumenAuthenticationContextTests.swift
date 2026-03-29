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
            host: "wifi.skyline23.com",
            httpsPort: 47984
        )
    )
}

@Test("Lumen request context injects authorization header into HTTPS request data")
func lumenRequestContextInjectsAuthorizationHeaderIntoHTTPSRequestData() throws {
    let context = ShadowClientLumenHTTPSRequestContext(
        endpoint: .init(host: "wifi.skyline23.com", httpsPort: 48984),
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
    #expect(requestText.contains("Authorization: Basic YWRtaW46c2VjcmV0"))
}
