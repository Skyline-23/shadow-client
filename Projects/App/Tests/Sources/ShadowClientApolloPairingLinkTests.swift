import CryptoKit
import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Apollo pairing link parser extracts host, port, pin, passphrase, and host name")
func apolloPairingLinkParserExtractsFields() {
    let url = URL(string: "art://wifi.skyline23.com:47989?pin=ABCD1234&passphrase=open-sesame&name=LivingRoom-PC")!

    let link = ShadowClientApolloPairingLink.parse(url)

    #expect(
        link == .init(
            host: "wifi.skyline23.com",
            pairPort: 47989,
            pin: "ABCD1234",
            passphrase: "open-sesame",
            hostName: "LivingRoom-PC"
        )
    )
}

@Test("Apollo pairing link token matches uppercase SHA256 of pin, salt, and passphrase")
func apolloPairingTokenMatchesExpectedDigest() {
    let expected = SHA256
        .hash(data: Data("1234A1B2C3D4otp-pass".utf8))
        .map { String(format: "%02X", $0) }
        .joined()

    #expect(
        ShadowClientApolloPairingLink.otpAuthToken(
            pin: "1234",
            saltHex: "A1B2C3D4",
            passphrase: "otp-pass"
        ) == expected
    )
}
