import Foundation

enum ShadowClientRemoteHostCandidateFilter {
    static func filteredCandidates(
        discoveredHosts: [String],
        manualHost: String?,
        selfHostNames: Set<String>
    ) -> [String] {
        var candidates = discoveredHosts
        if let manualHost, !manualHost.isEmpty {
            candidates.append(manualHost)
        }

        let normalizedSelfHostNames = Set(
            selfHostNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )

        var seen: Set<String> = []
        return candidates.compactMap { candidate in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            let normalized = normalize(candidate: trimmed)
            guard !normalized.isEmpty else {
                return nil
            }

            guard !isLoopbackHost(normalized),
                  !normalizedSelfHostNames.contains(normalized)
            else {
                return nil
            }

            guard seen.insert(normalized).inserted else {
                return nil
            }
            return normalized
        }
    }

    private static func normalize(candidate: String) -> String {
        let withScheme = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(candidate)
        guard let url = URL(string: withScheme), let host = url.host?.lowercased() else {
            return candidate.lowercased()
        }
        if let port = url.port {
            return "\(host):\(port)"
        }
        return host
    }

    private static func isLoopbackHost(_ normalized: String) -> Bool {
        if normalized == "localhost" {
            return true
        }
        if normalized == "::1" {
            return true
        }
        if normalized.hasPrefix("127.") {
            return true
        }
        return false
    }
}
