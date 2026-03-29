import Foundation
import Security
import Testing
@testable import ShadowClientFeatureHome

@Test("Lumen admin client parser returns the current paired client profile")
func lumenAdminClientParserReturnsCurrentClientProfile() throws {
    let data = Data(
        """
        {
          "status": true,
          "named_certs": [
            {
              "name": "Other Device",
              "uuid": "OTHER-UUID",
              "display_mode": "",
              "perm": 65535,
              "always_use_virtual_display": false,
              "connected": false
            },
            {
              "name": "Current Device",
              "uuid": "CURRENT-UUID",
              "display_mode": "2560x1440x120",
              "perm": 65535,
              "always_use_virtual_display": true,
              "connected": true
            }
          ]
        }
        """.utf8
    )

    let profile = try NativeShadowClientLumenAdminClient.parseCurrentClientProfile(
        data: data,
        currentClientUUID: "CURRENT-UUID"
    )

    #expect(
        profile == .init(
            name: "Current Device",
            uuid: "CURRENT-UUID",
            displayModeOverride: "2560x1440x120",
            permissions: 65535,
            allowClientCommands: true,
            alwaysUseVirtualDisplay: true,
            connected: true
        )
    )
}

@Test("Lumen admin client parser returns nil when the current client is missing")
func lumenAdminClientParserReturnsNilWhenCurrentClientIsMissing() throws {
    let data = Data(
        """
        {
          "status": true,
          "named_certs": [
            {
              "name": "Other Device",
              "uuid": "OTHER-UUID",
              "display_mode": "",
              "perm": 65535,
              "always_use_virtual_display": false,
              "connected": false
            }
          ]
        }
        """.utf8
    )

    let profile = try NativeShadowClientLumenAdminClient.parseCurrentClientProfile(
        data: data,
        currentClientUUID: "CURRENT-UUID"
    )

    #expect(profile == nil)
}

@Test("Lumen admin client fetches current profile over pinned HTTPS transport")
func lumenAdminClientFetchesCurrentProfileOverPinnedHTTPSTransport() async throws {
    let suiteName = "ShadowClientLumenAdminClientTests.\(UUID().uuidString)"
    let identityStore = ShadowClientPairingIdentityStore(defaultsSuiteName: suiteName)
    let pinnedCertificateStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: suiteName)
    await pinnedCertificateStore.setCertificateDER(
        Data([0x01, 0x02, 0x03]),
        forHost: "wifi.skyline23.com",
        httpsPort: 48984
    )
    let currentClientUUID = await identityStore.uniqueID()
    let transport = RecordingLumenAdminHTTPTransport(
        response: .init(
            statusCode: 200,
            body: Data(
                """
                {
                  "status": true,
                  "named_certs": [
                    {
                      "name": "Current Device",
                      "uuid": "\(currentClientUUID)",
                      "display_mode": "2560x1440x120",
                      "perm": 65535,
                      "always_use_virtual_display": true,
                      "connected": true
                    }
                  ]
                }
                """.utf8
            ),
            presentedLeafCertificateDER: nil
        )
    )
    let client = NativeShadowClientLumenAdminClient(
        identityStore: identityStore,
        authenticationContextBuilder: ShadowClientLumenAuthenticationContextBuilder(
            identityStore: identityStore,
            pinnedCertificateStore: pinnedCertificateStore
        ),
        transport: transport
    )

    let profile = try await client.fetchCurrentClientProfile(
        host: "wifi.skyline23.com:48984",
        httpsPort: 48984,
        username: "admin",
        password: "secret"
    )
    let request = await transport.lastRequest
    let requestText = String(decoding: request?.requestData ?? Data(), as: UTF8.self)

    #expect(profile?.name == "Current Device")
    #expect(request?.url.absoluteString == "https://wifi.skyline23.com:48984/api/clients/list")
    #expect(requestText.contains("Authorization: Basic YWRtaW46c2VjcmV0"))
}

private actor RecordingLumenAdminHTTPTransport: ShadowClientLumenHTTPTransport {
    struct Request: Sendable {
        let url: URL
        let requestData: Data
    }

    private let response: ShadowClientGameStreamHTTPTransport.HTTPSResponse
    private(set) var lastRequest: Request?

    init(response: ShadowClientGameStreamHTTPTransport.HTTPSResponse) {
        self.response = response
    }

    func request(
        url: URL,
        requestData: Data,
        pinnedServerCertificateDER: Data?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?,
        timeout: TimeInterval
    ) async throws -> ShadowClientGameStreamHTTPTransport.HTTPSResponse {
        _ = pinnedServerCertificateDER
        _ = clientCertificates
        _ = clientCertificateIdentity
        _ = timeout
        lastRequest = .init(url: url, requestData: requestData)
        return response
    }
}
