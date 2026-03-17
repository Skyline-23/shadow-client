import Darwin
import Foundation
import ShadowClientFeatureConnection

enum ShadowClientHostCatalogKit {
    static func cachedCandidateHosts(
        from descriptors: [ShadowClientRemoteHostDescriptor]
    ) -> [String] {
        var seen: Set<String> = []
        var results: [String] = []

        for host in descriptors {
            for endpoint in host.routes.allEndpoints {
                let connectCandidate = connectCandidateString(for: endpoint)
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

    private static func connectCandidateString(for endpoint: ShadowClientRemoteHostEndpoint) -> String {
        let normalizedHost = endpoint.host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedHost.isEmpty else {
            return ""
        }

        guard let connectPort = ShadowClientGameStreamNetworkDefaults.mappedHTTPPort(
            forHTTPSPort: endpoint.httpsPort
        ) else {
            return ShadowClientHostEndpointKit.candidateString(for: endpoint)
        }

        if connectPort == ShadowClientGameStreamNetworkDefaults.defaultHTTPPort {
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

        var preferredExplicitCandidateByHost: [String: String] = [:]
        var explicitPortsByHost: [String: Set<Int>] = [:]
        for candidate in parsedCandidates {
            guard let explicitPort = candidate.explicitPort,
                  explicitPort != ShadowClientGameStreamNetworkDefaults.defaultHTTPPort
            else {
                continue
            }

            explicitPortsByHost[candidate.host, default: []].insert(explicitPort)
            let explicitCandidate = "\(candidate.host):\(explicitPort)"
            let existing = preferredExplicitCandidateByHost[candidate.host]
            if existing == nil || explicitCandidate.localizedCaseInsensitiveCompare(existing!) == .orderedAscending {
                preferredExplicitCandidateByHost[candidate.host] = explicitCandidate
            }
        }

        let apolloPortDelta = abs(ShadowClientGameStreamNetworkDefaults.httpsOffsetFromHTTPPort)
        for (host, explicitPorts) in explicitPortsByHost {
            let sortedPorts = explicitPorts.sorted()
            guard sortedPorts.count > 1 else {
                continue
            }

            var preferredConnectPort: Int?
            for port in sortedPorts {
                let pairedHTTPSPort = port + ShadowClientGameStreamNetworkDefaults.httpsOffsetFromHTTPPort
                if explicitPorts.contains(pairedHTTPSPort) {
                    preferredConnectPort = max(preferredConnectPort ?? port, port)
                    continue
                }

                if explicitPorts.contains(port - apolloPortDelta) {
                    preferredConnectPort = max(preferredConnectPort ?? port, port)
                }
            }

            if let preferredConnectPort {
                preferredExplicitCandidateByHost[host] = "\(host):\(preferredConnectPort)"
            }
        }

        var seen: Set<String> = []
        var results: [String] = []
        for candidate in parsedCandidates {
            let canonicalCandidate = preferredExplicitCandidateByHost[candidate.host] ?? candidate.original
            guard seen.insert(canonicalCandidate).inserted else {
                continue
            }
            results.append(canonicalCandidate)
        }

        return results
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

        values.formUnion(currentMachineHostNames())
        return values
    }

    private static func currentMachineHostNames() -> Set<String> {
        var values = Set<String>()
        let reportedHostNames = [currentMachineHostName(), ProcessInfo.processInfo.hostName]

        for reportedHostName in reportedHostNames {
            let normalizedHostName = reportedHostName
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
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
