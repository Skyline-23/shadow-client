import Foundation

struct ShadowClientManualHostEntryKit {
    static func normalizedHostDraft(_ draft: String) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let candidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmed)
        guard let url = URL(string: candidate), let host = url.host else {
            return trimmed
        }

        if let port = url.port {
            return "\(host.lowercased()):\(port)"
        }

        return host.lowercased()
    }

    static func normalizedPortDraft(_ draft: String) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let digitsOnly = trimmed.filter(\.isNumber)
        guard digitsOnly == trimmed,
              let parsedPort = Int(digitsOnly),
              (1...65_535).contains(parsedPort)
        else {
            return ""
        }

        return String(parsedPort)
    }

    static func normalizedDraft(_ draft: String) -> String {
        normalizedDraft(hostDraft: draft, portDraft: "")
    }

    static func normalizedDraft(hostDraft: String, portDraft: String) -> String {
        let normalizedHost = normalizedHostDraft(hostDraft)
        guard !normalizedHost.isEmpty else {
            return ""
        }

        let trimmedPort = portDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPort.isEmpty else {
            return normalizedHost
        }

        let normalizedPort = normalizedPortDraft(trimmedPort)
        guard !normalizedPort.isEmpty else {
            return ""
        }

        let candidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(normalizedHost)
        guard let parsed = URL(string: candidate), let host = parsed.host else {
            return "\(normalizedHost):\(normalizedPort)"
        }

        return "\(host.lowercased()):\(normalizedPort)"
    }

    static func canSubmit(_ draft: String) -> Bool {
        canSubmit(hostDraft: draft, portDraft: "")
    }

    static func canSubmit(hostDraft: String, portDraft: String) -> Bool {
        !normalizedDraft(hostDraft: hostDraft, portDraft: portDraft).isEmpty
    }
}
