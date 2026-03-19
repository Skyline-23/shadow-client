import Darwin
import Foundation
import ShadowClientFeatureConnection

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
                  !localInterfaceHosts.contains(hostForClassification(from: normalized))
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
            let canonicalPort = ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
                fromCandidatePort: port
            )
            return "\(host):\(canonicalPort)"
        }
        return host
    }

    static func isLoopbackHost(_ normalized: String) -> Bool {
        let host = hostForClassification(from: normalized)
        if host == "localhost" {
            return true
        }

        if let ipv4Address = parsedIPv4Address(from: host) {
            let value = UInt32(bigEndian: ipv4Address.s_addr)
            return UInt8((value >> 24) & 0xff) == 127
        }

        if let ipv6Address = parsedIPv6Address(from: host) {
            return withUnsafeBytes(of: ipv6Address) { bytes in
                bytes.dropLast().allSatisfy { $0 == 0 } && bytes.last == 1
            }
        }

        return false
    }

    static func isLinkLocalHost(_ normalized: String) -> Bool {
        let host = hostForClassification(from: normalized)

        if let ipv4Address = parsedIPv4Address(from: host) {
            let value = UInt32(bigEndian: ipv4Address.s_addr)
            let firstOctet = UInt8((value >> 24) & 0xff)
            let secondOctet = UInt8((value >> 16) & 0xff)
            return firstOctet == 169 && secondOctet == 254
        }

        if let ipv6Address = parsedIPv6Address(from: host) {
            return withUnsafeBytes(of: ipv6Address) { bytes in
                guard bytes.count >= 2 else {
                    return false
                }

                let firstByte = bytes[0]
                let secondByte = bytes[1]
                let isLinkLocal = firstByte == 0xfe && (secondByte & 0xc0) == 0x80
                let isUniqueLocal = (firstByte & 0xfe) == 0xfc
                return isLinkLocal || isUniqueLocal
            }
        }

        return false
    }

    private static func hostForClassification(from normalized: String) -> String {
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else {
            return ""
        }

        let withScheme = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmed)
        if let components = URLComponents(string: withScheme),
           let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !host.isEmpty
        {
            return stripIPv6ScopeIdentifier(from: host)
        }

        return stripIPv6ScopeIdentifier(from: trimmed)
    }

    private static func stripIPv6ScopeIdentifier(from host: String) -> String {
        String(host.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
    }

    private static func parsedIPv4Address(from host: String) -> in_addr? {
        var address = in_addr()
        guard inet_pton(AF_INET, host, &address) == 1 else {
            return nil
        }
        return address
    }

    private static func parsedIPv6Address(from host: String) -> in6_addr? {
        var address = in6_addr()
        guard inet_pton(AF_INET6, host, &address) == 1 else {
            return nil
        }
        return address
    }
}
