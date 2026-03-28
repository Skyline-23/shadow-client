import Foundation
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
            expiresInSeconds: 598,
            pollIntervalSeconds: 2
        )
    )
}
