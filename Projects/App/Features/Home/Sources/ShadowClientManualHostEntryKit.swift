import Foundation

struct ShadowClientManualHostEntryKit {
    static func normalizedDraft(_ draft: String) -> String {
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

    static func canSubmit(_ draft: String) -> Bool {
        !normalizedDraft(draft).isEmpty
    }
}
