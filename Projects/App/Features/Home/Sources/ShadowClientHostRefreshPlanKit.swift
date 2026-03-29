import Foundation
import ShadowClientFeatureConnection

enum ShadowClientHostRefreshPlanKit {
    private enum CandidateSource: Int {
        case preferred = 0
        case discovered = 1
        case cached = 2
    }

    private struct OrderedCandidate {
        let normalizedCandidate: String
        let source: CandidateSource
        let insertionOrder: Int
    }

    static func orderedCandidates(
        discoveredHosts: [String],
        cachedHosts: [String],
        preferredHost: String?
    ) -> [String] {
        var orderedCandidatesByValue: [String: OrderedCandidate] = [:]
        var insertionOrder = 0

        func register(_ candidate: String?, source: CandidateSource) {
            guard let normalizedCandidate = serviceDiscoveryCandidate(candidate) else {
                return
            }

            let orderedCandidate = OrderedCandidate(
                normalizedCandidate: normalizedCandidate,
                source: source,
                insertionOrder: insertionOrder
            )
            insertionOrder += 1

            guard let existingCandidate = orderedCandidatesByValue[normalizedCandidate] else {
                orderedCandidatesByValue[normalizedCandidate] = orderedCandidate
                return
            }

            if orderedCandidate.source.rawValue < existingCandidate.source.rawValue {
                orderedCandidatesByValue[normalizedCandidate] = orderedCandidate
            }
        }

        register(preferredHost, source: .preferred)
        for candidate in discoveredHosts {
            register(candidate, source: .discovered)
        }
        for candidate in cachedHosts {
            register(candidate, source: .cached)
        }

        return orderedCandidatesByValue.values
            .sorted { lhs, rhs in
                if lhs.source != rhs.source {
                    return lhs.source.rawValue < rhs.source.rawValue
                }
                if lhs.insertionOrder != rhs.insertionOrder {
                    return lhs.insertionOrder < rhs.insertionOrder
                }
                return lhs.normalizedCandidate.localizedCaseInsensitiveCompare(rhs.normalizedCandidate) == .orderedAscending
            }
            .map(\.normalizedCandidate)
    }

    private static func serviceDiscoveryCandidate(_ candidate: String?) -> String? {
        guard let parsed = parsedCandidateRoute(candidate) else {
            return normalizeCandidate(candidate)
        }

        if let port = parsed.port,
           let streamHTTPSPort = streamHTTPSPort(fromControlHTTPSPort: port) {
            return "\(parsed.host):\(streamHTTPSPort)"
        }

        return normalizeCandidate(candidate)
    }

    private static func parsedCandidateRoute(_ candidate: String?) -> (host: String, port: Int?)? {
        guard let normalized = normalizeCandidate(candidate) else {
            return nil
        }

        let urlCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(normalized)
        guard let parsed = URL(string: urlCandidate), let host = parsed.host else {
            return nil
        }

        let port = parsed.port.map {
            ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
                fromCandidatePort: $0
            )
        }

        return (host.lowercased(), port)
    }

    private static func streamHTTPSPort(fromControlHTTPSPort httpsPort: Int) -> Int? {
        let candidateStreamHTTPSPort = httpsPort - 6
        guard
            (ShadowClientGameStreamNetworkDefaults.minimumPort...ShadowClientGameStreamNetworkDefaults.maximumPort)
                .contains(candidateStreamHTTPSPort)
        else {
            return nil
        }

        let mappedHTTPPort = ShadowClientGameStreamNetworkDefaults.httpPort(
            forHTTPSPort: candidateStreamHTTPSPort
        )
        guard ShadowClientGameStreamNetworkDefaults.isLikelyHTTPPort(mappedHTTPPort) else {
            return nil
        }

        return candidateStreamHTTPSPort
    }

    private static func normalizeCandidate(_ candidate: String?) -> String? {
        guard let candidate else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let urlCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmed)
        guard let parsed = URL(string: urlCandidate), let host = parsed.host else {
            return trimmed.lowercased()
        }
        guard !ShadowClientRemoteHostCandidateFilter.isLoopbackHost(host.lowercased()) else {
            return nil
        }

        if let port = parsed.port {
            let canonicalPort = ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
                fromCandidatePort: port
            )
            return "\(host.lowercased()):\(canonicalPort)"
        }

        return host.lowercased()
    }
}
