import Foundation

enum ShadowClientRTSPTransportHeaderParser {
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
        guard let headerValue else {
            return nil
        }

        let trimmed = headerValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let bytes = Data(trimmed.utf8)
        guard bytes.count == 16 else {
            return nil
        }
        return bytes
    }
}
