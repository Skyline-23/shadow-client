import CryptoKit
import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Apollo OTP pairing request token matches uppercase SHA256 of pin, salt, and passphrase")
func apolloPairingRequestTokenMatchesExpectedDigest() {
    let expected = SHA256
        .hash(data: Data("1234A1B2C3D4otp-pass".utf8))
        .map { String(format: "%02X", $0) }
        .joined()

    #expect(
        ShadowClientApolloOTPPairingRequest.otpAuthToken(
            pin: "1234",
            saltHex: "A1B2C3D4",
            passphrase: "otp-pass"
        ) == expected
    )
}

@Test("Apollo OTP pairing state does not expose a local PIN")
func apolloOTPPairingStateDoesNotExposeLocalPIN() {
    let state = ShadowClientRemotePairingState.pairingOTP(host: "wifi.skyline23.com")

    #expect(state.activePIN == nil)
    #expect(state.isInProgress)
}
