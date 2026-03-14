import CryptoKit
import Foundation

public struct ShadowClientApolloPairingLink: Equatable, Sendable {
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
        hostName: String?
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

    public static func parse(_ url: URL) -> ShadowClientApolloPairingLink? {
        guard url.scheme?.caseInsensitiveCompare("art") == .orderedSame,
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let queryItems = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
            ($0.name.lowercased(), $0.value ?? "")
        })
        let pin = queryItems["pin"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let passphrase = queryItems["passphrase"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard pin.count >= 4, passphrase.count >= 4 else {
            return nil
        }

        let hostName = queryItems["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .init(
            host: host,
            pairPort: components.port,
            pin: pin,
            passphrase: passphrase,
            hostName: hostName?.isEmpty == true ? nil : hostName
        )
    }

    public static func otpAuthToken(pin: String, saltHex: String, passphrase: String) -> String {
        let digest = SHA256.hash(data: Data((pin + saltHex + passphrase).utf8))
        return digest.map { String(format: "%02X", $0) }.joined()
    }
}

extension Notification.Name {
    static let shadowClientApolloPairingLinkReceived = Notification.Name("shadowClientApolloPairingLinkReceived")
}
