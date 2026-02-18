import Foundation

enum ShadowClientRTSPTransportHeaderParser {
    private static let sunshineTokenQuoteCharacters = CharacterSet(charactersIn: "\"'")

    static func parseServerPort(from transportHeader: String) -> UInt16? {
        let lower = transportHeader.lowercased()
        guard let range = lower.range(of: "server_port=") else {
            return nil
        }

        let suffix = lower[range.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        guard !digits.isEmpty, let port = UInt16(digits) else {
            return nil
        }
        guard port > 0 else {
            return nil
        }
        return port
    }

    static func parseSunshinePingPayload(from headerValue: String?) -> Data? {
        for token in sunshineTokens(from: headerValue) {
            let bytes = Data(token.utf8)
            if bytes.count == 16 {
                return bytes
            }
        }
        return nil
    }

    static func parseSunshineControlConnectData(from headerValue: String?) -> UInt32? {
        for token in sunshineTokens(from: headerValue) {
            if token.lowercased().hasPrefix("0x") {
                let hexValue = String(token.dropFirst(2))
                guard !hexValue.isEmpty else {
                    continue
                }
                if let parsed = UInt32(hexValue, radix: 16) {
                    return parsed
                }
                continue
            }

            if let parsed = UInt32(token) {
                return parsed
            }
        }
        return nil
    }

    private static func sunshineTokens(from headerValue: String?) -> [String] {
        guard let headerValue else {
            return []
        }

        let trimmed = headerValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        return trimmed
            .split(whereSeparator: { character in
                character == ";" || character == "," || character.isWhitespace
            })
            .map { token in
                token.trimmingCharacters(in: sunshineTokenQuoteCharacters)
            }
            .filter { !$0.isEmpty }
    }
}
