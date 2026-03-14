import CryptoKit
import Foundation

public struct ShadowClientApolloOTPPairingRequest: Equatable, Sendable {
    public let host: String
    public let pairPort: Int?
    public let pin: String
    public let passphrase: String
    public let hostName: String?

    public init(
        host: String,
        pairPort: Int?,
        pin: String,
        passphrase: String,
        hostName: String? = nil
    ) {
        self.host = host
        self.pairPort = pairPort
        self.pin = pin
        self.passphrase = passphrase
        self.hostName = hostName
    }

    public var hostAddress: String {
        if let pairPort {
            return "\(host):\(pairPort)"
        }
        return host
    }

    public static func otpAuthToken(pin: String, saltHex: String, passphrase: String) -> String {
        let digest = SHA256.hash(data: Data((pin + saltHex + passphrase).utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }
}
