import Foundation
import ShadowClientFeatureConnection

struct ShadowClientHostCatalogRefreshPlan: Equatable {
    let discoveredCandidates: [String]
    let refreshCandidates: [String]
    let preferredRefreshCandidate: String?
    let preferredAuthorityHost: String?

    var signature: String {
        "\(refreshCandidates.joined(separator: "|"))||\(preferredRefreshCandidate ?? "")||\(preferredAuthorityHost ?? "")"
    }
}

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

    static func makeCatalogRefreshPlan(
        autoFindHosts: Bool,
        discoveredHosts: [ShadowClientDiscoveredHost],
        cachedHosts: [String],
        preferredHost: String?,
        hiddenCandidates: Set<String>
    ) -> ShadowClientHostCatalogRefreshPlan {
        let discoveredCandidates = discoveredHosts
            .map(\.probeCandidate)
            .filter { !hiddenCandidates.contains(normalizedStoredConnectionCandidate($0)) }
        let visibleCachedHosts = cachedHosts
            .filter { !hiddenCandidates.contains(normalizedStoredConnectionCandidate($0)) }
        let visiblePreferredHost = preferredHost.flatMap {
            let normalizedPreferredHost = normalizedStoredConnectionCandidate($0)
            return hiddenCandidates.contains(normalizedPreferredHost) ? nil : $0
        }

        let refreshCandidates = ShadowClientHostCatalogKit.refreshCandidates(
            autoFindHosts: autoFindHosts,
            discoveredHosts: discoveredCandidates,
            cachedHosts: visibleCachedHosts,
            manualHost: visiblePreferredHost
        )
        let preferredRefreshCandidate = resolvedPreferredConnectCandidate(
            visiblePreferredHost,
            discoveredCandidates: discoveredCandidates,
            availableCandidates: refreshCandidates
        )
        let preferredAuthorityHost = preferredAuthorityHost(
            preferredCandidate: visiblePreferredHost,
            discoveredHosts: discoveredHosts,
            preferredRefreshCandidate: preferredRefreshCandidate
        )

        return ShadowClientHostCatalogRefreshPlan(
            discoveredCandidates: discoveredCandidates,
            refreshCandidates: refreshCandidates,
            preferredRefreshCandidate: preferredRefreshCandidate,
            preferredAuthorityHost: preferredAuthorityHost
        )
    }

    static func resolvedPreferredConnectCandidate(
        _ preferredCandidate: String?,
        discoveredCandidates: [String],
        availableCandidates: [String]
    ) -> String? {
        if preferredCandidate == nil {
            if discoveredCandidates.count == 1 {
                return discoveredCandidates[0]
            }
            if discoveredCandidates.isEmpty, availableCandidates.count == 1 {
                return availableCandidates[0]
            }
            return nil
        }

        if let discoveredPreferred = resolvedPreferredHostCandidate(
            preferredCandidate,
            availableCandidates: discoveredCandidates
        ) {
            return discoveredPreferred
        }

        let preferredCandidate = resolvedPreferredHostCandidate(
            preferredCandidate,
            availableCandidates: availableCandidates
        )

        guard let preferredCandidate else {
            return nil
        }

        guard !discoveredCandidates.isEmpty,
              !discoveredCandidates.contains(preferredCandidate),
              discoveredCandidates.count == 1
        else {
            return preferredCandidate
        }

        return discoveredCandidates[0]
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

    private static func authorityHost(from candidate: String?) -> String? {
        guard let candidate else {
            return nil
        }

        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let urlCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmed)
        guard let parsed = URL(string: urlCandidate), let host = parsed.host?.lowercased(), !host.isEmpty else {
            return trimmed.lowercased()
        }

        guard !ShadowClientRemoteHostCandidateFilter.isLoopbackHost(host) else {
            return nil
        }

        return host
    }

    private static func preferredAuthorityHost(
        preferredCandidate: String?,
        discoveredHosts: [ShadowClientDiscoveredHost],
        preferredRefreshCandidate: String?
    ) -> String? {
        if let preferredAuthorityHost = authorityHost(from: preferredCandidate) {
            return preferredAuthorityHost
        }

        if let preferredRefreshCandidate = normalizeCandidate(preferredRefreshCandidate) {
            return discoveredHosts
                .first(where: { normalizeCandidate($0.probeCandidate) == preferredRefreshCandidate })?
                .authorityHost
        }

        let discoveredAuthorityHosts = discoveredHosts.compactMap { discoveredHost -> String? in
            guard discoveredHost.authorityHost != nil,
                  normalizeCandidate(discoveredHost.probeCandidate) != nil else {
                return nil
            }

            return discoveredHost.authorityHost
        }

        guard discoveredAuthorityHosts.count == 1 else {
            return nil
        }

        return discoveredAuthorityHosts[0]
    }

    private static func normalizedStoredConnectionCandidate(_ candidate: String) -> String {
        candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func resolvedPreferredHostCandidate(
        _ preferredCandidate: String?,
        availableCandidates: [String]
    ) -> String? {
        guard let preferredCandidate else {
            return nil
        }

        let normalizedPreferred = normalizedStoredConnectionCandidate(preferredCandidate)
        guard !normalizedPreferred.isEmpty else {
            return nil
        }

        if availableCandidates.contains(normalizedPreferred) {
            return normalizedPreferred
        }

        let urlCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(normalizedPreferred)
        guard let url = URL(string: urlCandidate),
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty,
              url.port == nil
        else {
            return nil
        }

        let matchingCandidates = availableCandidates.filter {
            let candidateURL = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing($0)
            guard let parsed = URL(string: candidateURL),
                  let candidateHost = parsed.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            else {
                return false
            }
            return candidateHost == host
        }

        return matchingCandidates.count == 1 ? matchingCandidates[0] : nil
    }
}
