import Foundation
import ShadowClientFeatureConnection

struct ShadowClientManualHostEntryKit {
    static func normalizedDraft(_ draft: String, portDraft: String = "") -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let candidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmed)
        guard let url = URL(string: candidate), let host = url.host else {
            if let port = parsedPort(from: portDraft) {
                return normalizedHostCandidate(host: trimmed, port: port)
            }
            return trimmed.lowercased()
        }

        if let port = url.port ?? parsedPort(from: portDraft) {
            return normalizedHostCandidate(host: host, port: port)
        }

        return host.lowercased()
    }

    static func canSubmit(_ draft: String, portDraft: String = "") -> Bool {
        let trimmedPort = portDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedPort.isEmpty, parsedPort(from: trimmedPort) == nil {
            return false
        }
        return !normalizedDraft(draft, portDraft: portDraft).isEmpty
    }

    private static func parsedPort(from draft: String) -> Int? {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let port = Int(trimmed),
              (1...65_535).contains(port) else {
            return nil
        }
        return port
    }

    private static func normalizedHostCandidate(host: String, port: Int) -> String {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else {
            return ""
        }
        let canonicalPort = ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
            fromCandidatePort: port
        )

        return "\(normalizedHost):\(canonicalPort)"
    }
}
