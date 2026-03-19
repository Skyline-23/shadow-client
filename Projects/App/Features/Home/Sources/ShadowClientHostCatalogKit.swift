import Darwin
import Foundation
import ShadowClientFeatureConnection

enum ShadowClientHostCatalogKit {
    static func cachedCandidateHosts(
        from descriptors: [ShadowClientRemoteHostDescriptor]
    ) -> [String] {
        let distinctHTTPSPortsByHost = distinctHTTPSPortsByHost(
            descriptors.flatMap { $0.routes.allEndpoints }
        )
        var seen: Set<String> = []
        var results: [String] = []

        for host in descriptors {
            for endpoint in host.routes.allEndpoints {
                let connectCandidate = connectCandidateString(
                    for: endpoint,
                    preserveExplicitDefaultConnectPort:
                        (distinctHTTPSPortsByHost[normalizedHostKey(for: endpoint.host)]?.count ?? 0) > 1
                )
                guard !connectCandidate.isEmpty,
                      seen.insert(connectCandidate).inserted
                else {
                    continue
                }
                results.append(connectCandidate)
            }
        }

        return results
    }

    static func refreshCandidates(
        autoFindHosts: Bool,
        discoveredHosts: [String],
        cachedHosts: [String],
        manualHost: String?
    ) -> [String] {
        let candidates = (autoFindHosts ? discoveredHosts : []) + cachedHosts
        let filteredCandidates = ShadowClientRemoteHostCandidateFilter.filteredCandidates(
            discoveredHosts: candidates,
            manualHost: manualHost,
            localInterfaceHosts: currentMachineInterfaceHosts()
        )
        return canonicalizedConnectCandidates(filteredCandidates)
    }

    private static func connectCandidateString(
        for endpoint: ShadowClientRemoteHostEndpoint,
        preserveExplicitDefaultConnectPort: Bool = false
    ) -> String {
        let normalizedHost = endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else {
            return ""
        }

        guard let connectPort = ShadowClientGameStreamNetworkDefaults.mappedHTTPPort(
            forHTTPSPort: endpoint.httpsPort
        ) else {
            if endpoint.httpsPort == ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort {
                return normalizedHost
            }
            return "\(normalizedHost):\(endpoint.httpsPort)"
        }

        if connectPort == ShadowClientGameStreamNetworkDefaults.defaultHTTPPort,
           !preserveExplicitDefaultConnectPort {
            return normalizedHost
        }

        return "\(normalizedHost):\(connectPort)"
    }

    private static func canonicalizedConnectCandidates(_ candidates: [String]) -> [String] {
        struct ParsedCandidate {
            let original: String
            let host: String
            let explicitPort: Int?
        }

        let parsedCandidates = candidates.compactMap { candidate -> ParsedCandidate? in
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return nil
            }

            let urlCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmed)
            guard let url = URL(string: urlCandidate), let host = url.host?.lowercased() else {
                return ParsedCandidate(original: trimmed.lowercased(), host: trimmed.lowercased(), explicitPort: nil)
            }

            return ParsedCandidate(
                original: trimmed.lowercased(),
                host: host,
                explicitPort: url.port
            )
        }

        var hostsWithExplicitCandidates: Set<String> = []
        for candidate in parsedCandidates {
            guard candidate.explicitPort != nil else {
                continue
            }
            hostsWithExplicitCandidates.insert(candidate.host)
        }

        var seen: Set<String> = []
        var results: [String] = []
        for candidate in parsedCandidates {
            if candidate.explicitPort == nil,
               hostsWithExplicitCandidates.contains(candidate.host) {
                continue
            }

            guard seen.insert(candidate.original).inserted else {
                continue
            }
            results.append(candidate.original)
        }

        return results
    }

    private static func distinctHTTPSPortsByHost(
        _ endpoints: [ShadowClientRemoteHostEndpoint]
    ) -> [String: Set<Int>] {
        var values: [String: Set<Int>] = [:]
        for endpoint in endpoints {
            let normalizedHost = normalizedHostKey(for: endpoint.host)
            guard !normalizedHost.isEmpty else {
                continue
            }
            values[normalizedHost, default: []].insert(endpoint.httpsPort)
        }
        return values
    }

    private static func normalizedHostKey(for host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func currentMachineInterfaceHosts() -> Set<String> {
        var values = Set<String>()
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let interfaces else {
            return currentMachineHostNames()
        }
        defer { freeifaddrs(interfaces) }

        for pointer in sequence(first: interfaces, next: { $0.pointee.ifa_next }) {
            guard let addressPointer = pointer.pointee.ifa_addr else {
                continue
            }
            let addressFamily = addressPointer.pointee.sa_family
            let stringBufferLength = Int(NI_MAXHOST)
            var stringBuffer = [CChar](repeating: 0, count: stringBufferLength)

            switch Int32(addressFamily) {
            case AF_INET:
                let address = addressPointer.withMemoryRebound(
                    to: sockaddr_in.self,
                    capacity: 1
                ) { $0 }
                guard inet_ntop(
                    AF_INET,
                    &address.pointee.sin_addr,
                    &stringBuffer,
                    socklen_t(stringBufferLength)
                ) != nil
                else {
                    continue
                }
            case AF_INET6:
                let address = addressPointer.withMemoryRebound(
                    to: sockaddr_in6.self,
                    capacity: 1
                ) { $0 }
                guard inet_ntop(
                    AF_INET6,
                    &address.pointee.sin6_addr,
                    &stringBuffer,
                    socklen_t(stringBufferLength)
                ) != nil
                else {
                    continue
                }
            default:
                continue
            }

            let normalized = String(cString: stringBuffer).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty,
                  !ShadowClientRemoteHostCandidateFilter.isLoopbackHost(normalized),
                  !ShadowClientRemoteHostCandidateFilter.isLinkLocalHost(normalized)
            else {
                continue
            }
            values.insert(normalized)
        }

        return values
    }

    private static func currentMachineHostNames() -> Set<String> {
        var values = Set<String>()
        let reportedHostNames = [currentMachineHostName(), ProcessInfo.processInfo.hostName]

        for reportedHostName in reportedHostNames {
            let normalizedHostName = reportedHostName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalizedHostName.isEmpty else {
                continue
            }
            values.insert(normalizedHostName)

            if let shortHostName = normalizedHostName.split(separator: ".").first,
               !shortHostName.isEmpty {
                values.insert(String(shortHostName))
            }
        }

        return values
    }

    private static func currentMachineHostName() -> String {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        guard gethostname(&buffer, buffer.count) == 0 else {
            return ""
        }
        return String(cString: buffer)
    }
}
