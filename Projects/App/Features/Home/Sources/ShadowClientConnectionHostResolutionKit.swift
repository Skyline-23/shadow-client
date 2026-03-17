import Foundation
import ShadowClientFeatureConnection

enum ShadowClientConnectionHostResolutionKit {
    static func resolvedConnectHost(
        requestedHost: String,
        discoveredHosts: [ShadowClientDiscoveredHost],
        knownHosts: [ShadowClientRemoteHostDescriptor]
    ) -> String {
        let trimmed = requestedHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let normalizedRequestedCandidate = normalizedCandidate(trimmed)
        let normalizedRequestedHost = normalizedHost(trimmed)

        for host in knownHosts {
            for endpoint in host.routes.allEndpoints {
                let candidate = connectCandidateString(for: endpoint)
                guard !candidate.isEmpty else {
                    continue
                }

                if normalizedCandidate(candidate) == normalizedRequestedCandidate {
                    return candidate
                }
            }
        }

        for discoveredHost in discoveredHosts {
            if normalizedCandidate(discoveredHost.probeCandidate) == normalizedRequestedCandidate {
                return discoveredHost.probeCandidate
            }
        }

        guard let normalizedRequestedHost else {
            return trimmed
        }

        for host in knownHosts {
            for endpoint in host.routes.allEndpoints {
                let endpointHost = endpoint.host
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                guard endpointHost == normalizedRequestedHost else {
                    continue
                }
                return connectCandidateString(for: endpoint)
            }
        }

        if let discoveredHost = discoveredHosts.first(where: {
            $0.host.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).lowercased() == normalizedRequestedHost
        }) {
            return discoveredHost.probeCandidate
        }

        return trimmed
    }

    private static func connectCandidateString(for endpoint: ShadowClientRemoteHostEndpoint) -> String {
        let normalizedHost = endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else {
            return ""
        }

        guard let httpPort = ShadowClientGameStreamNetworkDefaults.mappedHTTPPort(
            forHTTPSPort: endpoint.httpsPort
        ) else {
            return normalizedHost
        }

        if httpPort == ShadowClientGameStreamNetworkDefaults.defaultHTTPPort {
            return normalizedHost
        }

        return "\(normalizedHost):\(httpPort)"
    }

    private static func normalizedCandidate(_ candidate: String) -> String {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let withScheme = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmed)
        guard let url = URL(string: withScheme),
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty
        else {
            return trimmed.lowercased()
        }

        guard let port = url.port else {
            return host
        }

        return "\(host):\(port)"
    }

    private static func normalizedHost(_ candidate: String) -> String? {
        let withScheme = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(candidate)
        guard let url = URL(string: withScheme),
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty
        else {
            let normalized = candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return normalized.isEmpty ? nil : normalized
        }

        return host
    }
}
