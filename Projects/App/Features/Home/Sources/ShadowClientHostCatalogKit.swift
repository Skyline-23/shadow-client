import Darwin
import Foundation

enum ShadowClientHostCatalogKit {
    static func refreshCandidates(
        autoFindHosts: Bool,
        discoveredHosts: [String],
        cachedHosts: [String],
        manualHost: String?
    ) -> [String] {
        let candidates = (autoFindHosts ? discoveredHosts : []) + cachedHosts
        return ShadowClientRemoteHostCandidateFilter.filteredCandidates(
            discoveredHosts: candidates,
            manualHost: manualHost,
            localInterfaceHosts: currentMachineInterfaceHosts()
        )
    }

    static func currentMachineInterfaceHosts() -> Set<String> {
        var values = Set<String>()
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let interfaces else {
            return values
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
}
