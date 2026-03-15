import Foundation

enum ShadowClientRemoteHostCandidateFilter {
    static func filteredCandidates(
        discoveredHosts: [String],
        manualHost: String?,
        localInterfaceHosts: Set<String>
    ) -> [String] {
        var candidates = discoveredHosts
        if let manualHost, !manualHost.isEmpty {
            candidates.append(manualHost)
        }

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
                  !isLinkLocalHost(normalized),
                  !localInterfaceHosts.contains(normalized)
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

    static func isLoopbackHost(_ normalized: String) -> Bool {
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

    static func isLinkLocalHost(_ normalized: String) -> Bool {
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix(ShadowClientHostClassificationDefaults.linkLocalIPv6Prefix) {
            return true
        }
        if trimmed.hasPrefix("\(ShadowClientHostClassificationDefaults.uniqueLocalIPv6PrefixFC):") ||
            trimmed.hasPrefix("\(ShadowClientHostClassificationDefaults.uniqueLocalIPv6PrefixFD):")
        {
            return true
        }
        let parts = trimmed.split(separator: ".")
        if parts.count == 4,
           parts[0] == Substring(String(ShadowClientHostClassificationDefaults.linkLocalIPv4FirstOctet)),
           parts[1] == Substring(String(ShadowClientHostClassificationDefaults.linkLocalIPv4SecondOctet))
        {
            return true
        }
        return false
    }
}
