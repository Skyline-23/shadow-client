import Foundation
import Security
import Testing
@testable import ShadowClientFeatureHome

@Test("Lumen pairing client parser decodes pairing session payload")
func lumenPairingClientParserDecodesPairingSessionPayload() throws {
    let data = Data(
        """
        {
          "status": true,
          "pairing": {
            "pairingId": "pairing-123",
            "userCode": "AB12CD",
            "deviceName": "Living Room Apple TV",
            "platform": "tvos",
            "clientId": "CLIENT-123",
            "trustedClientUuid": "CLIENT-123",
            "publicKeyPresent": true,
            "clientTrusted": true,
            "clientCertificateRequired": true,
            "status": "approved",
            "serverUniqueId": "HOST-123",
            "serviceType": "_shadow._tcp",
            "controlHttpsPort": 47984,
            "preferredControlHttpsUrl": "https://192.168.0.20:48990",
            "controlHttpsUrls": [
              "https://192.168.0.20:48990",
              "https://wifi.skyline23.com:48990"
            ],
            "expiresInSeconds": 598,
            "pollIntervalSeconds": 2
          }
        }
        """.utf8
    )

    let session = try NativeShadowClientLumenPairingClient.parsePairingSession(data: data)

    #expect(
        session == .init(
            pairingID: "pairing-123",
            userCode: "AB12CD",
            deviceName: "Living Room Apple TV",
            platform: "tvos",
            clientID: "CLIENT-123",
            trustedClientUUID: "CLIENT-123",
            publicKeyPresent: true,
            clientTrusted: true,
            clientCertificateRequired: true,
            status: .approved,
            serverUniqueID: "HOST-123",
            serviceType: "_shadow._tcp",
            controlHTTPSPort: 47984,
            preferredControlHTTPSURL: "https://192.168.0.20:48990",
            controlHTTPSURLs: [
                "https://192.168.0.20:48990",
                "https://wifi.skyline23.com:48990",
            ],
            expiresInSeconds: 598,
            pollIntervalSeconds: 2
        )
    )
}

@Test("Lumen pairing client starts pairing over pinned HTTPS stream transport")
func lumenPairingClientStartsPairingOverPinnedHTTPSStreamTransport() async throws {
    let suiteName = "ShadowClientLumenPairingClientTests.\(UUID().uuidString)"
    let identityStore = ShadowClientPairingIdentityStore(defaultsSuiteName: suiteName)
    let pinnedCertificateStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: suiteName)
    let transport = RecordingLumenHTTPTransport(
        response: .init(
            statusCode: 200,
            body: pairingSessionPayloadData(),
            presentedLeafCertificateDER: Data([0x01, 0x02, 0x03])
        )
    )
    let client = NativeShadowClientLumenPairingClient(
        identityStore: identityStore,
        pinnedCertificateStore: pinnedCertificateStore,
        authenticationContextBuilder: ShadowClientLumenAuthenticationContextBuilder(
            identityStore: identityStore,
            pinnedCertificateStore: pinnedCertificateStore
        ),
        transport: transport
    )

    let session = try await client.startPairing(
        host: "wifi.skyline23.com:48984",
        httpsPort: 48984,
        deviceName: "Office iPad",
        platform: "ios"
    )

    let request = await transport.lastRequest
    let expectedClientID = await identityStore.uniqueID()
    let requestText = String(decoding: request?.requestData ?? Data(), as: UTF8.self)

    #expect(session.pairingID == "pairing-123")
    #expect(request?.url.absoluteString == "https://wifi.skyline23.com:48984/api/pairing/start")
    #expect(requestText.contains("POST /api/pairing/start HTTP/1.1"))
    #expect(requestText.contains("Host: wifi.skyline23.com:48984"))
    #expect(requestText.contains("Content-Type: application/json"))
    #expect(requestText.contains("\"deviceName\":\"Office iPad\""))
    #expect(requestText.contains("\"platform\":\"ios\""))
    #expect(requestText.contains("\"\(expectedClientID)\""))
    #expect(requestText.contains("BEGIN CERTIFICATE"))
}

@Test("Lumen pairing client requests status over pinned HTTPS stream transport")
func lumenPairingClientRequestsStatusOverPinnedHTTPSStreamTransport() async throws {
    let suiteName = "ShadowClientLumenPairingClientTests.\(UUID().uuidString)"
    let identityStore = ShadowClientPairingIdentityStore(defaultsSuiteName: suiteName)
    let pinnedCertificateStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: suiteName)
    let transport = RecordingLumenHTTPTransport(
        response: .init(
            statusCode: 200,
            body: pairingSessionPayloadData(),
            presentedLeafCertificateDER: nil
        )
    )
    let client = NativeShadowClientLumenPairingClient(
        identityStore: identityStore,
        pinnedCertificateStore: pinnedCertificateStore,
        authenticationContextBuilder: ShadowClientLumenAuthenticationContextBuilder(
            identityStore: identityStore,
            pinnedCertificateStore: pinnedCertificateStore
        ),
        transport: transport
    )

    let session = try await client.fetchPairingStatus(
        host: "wifi.skyline23.com:48984",
        httpsPort: 48984,
        pairingID: " pairing-123 "
    )

    let request = await transport.lastRequest
    let requestText = String(decoding: request?.requestData ?? Data(), as: UTF8.self)

    #expect(session.status == .approved)
    #expect(
        request?.url.absoluteString ==
            "https://wifi.skyline23.com:48984/api/pairing/status?pairingId=pairing-123"
    )
    #expect(requestText.contains("GET /api/pairing/status?pairingId=pairing-123 HTTP/1.1"))
    #expect(!requestText.contains("Content-Type: application/json"))
}

private actor RecordingLumenHTTPTransport: ShadowClientLumenHTTPTransport {
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

private func pairingSessionPayloadData() -> Data {
    Data(
        """
        {
          "status": true,
          "pairing": {
            "pairingId": "pairing-123",
            "userCode": "AB12CD",
            "deviceName": "Living Room Apple TV",
            "platform": "tvos",
            "clientId": "CLIENT-123",
            "trustedClientUuid": "CLIENT-123",
            "publicKeyPresent": true,
            "clientTrusted": true,
            "clientCertificateRequired": true,
            "status": "approved",
            "serverUniqueId": "HOST-123",
            "serviceType": "_shadow._tcp",
            "controlHttpsPort": 47984,
            "preferredControlHttpsUrl": "https://192.168.0.20:48990",
            "controlHttpsUrls": [
              "https://192.168.0.20:48990",
              "https://wifi.skyline23.com:48990"
            ],
            "expiresInSeconds": 598,
            "pollIntervalSeconds": 2
          }
        }
        """.utf8
    )
}
