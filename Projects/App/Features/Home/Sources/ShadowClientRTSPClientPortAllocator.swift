import Foundation
import Network
import Darwin

enum ShadowClientRTSPClientPortAllocator {
    typealias PortAvailabilityProbe = @Sendable (_ host: NWEndpoint.Host?, _ port: UInt16) -> Bool

    static func selectClientPortBase(
        preferred: UInt16,
        localHost: NWEndpoint.Host?,
        attemptCount: Int = ShadowClientRTSPProtocolProfile.clientPortProbeCount,
        isPortAvailable: PortAvailabilityProbe = { host, port in
            isUDPPortAvailable(localHost: host, port: port)
        }
    ) -> UInt16 {
        let normalizedPreferred = normalizeEvenPortBase(preferred)
        var candidate = normalizedPreferred

        for _ in 0..<max(attemptCount, 1) {
            guard candidate < UInt16.max else {
                break
            }
            let audioPort = candidate &+ 1
            if isPortAvailable(localHost, candidate), isPortAvailable(localHost, audioPort) {
                return candidate
            }
            candidate &+= 2
            if candidate >= UInt16.max {
                break
            }
        }

        return normalizedPreferred
    }

    private static func normalizeEvenPortBase(_ value: UInt16) -> UInt16 {
        value.isMultiple(of: 2) ? value : value &- 1
    }

    private static func isUDPPortAvailable(
        localHost: NWEndpoint.Host?,
        port: UInt16
    ) -> Bool {
        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else {
            return false
        }
        defer { close(socketDescriptor) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = CFSwapInt16HostToBig(port)

        if let host = localHost, let ipv4 = parseIPv4Address(from: host) {
            let conversionResult = ipv4.withCString { pointer in
                inet_pton(AF_INET, pointer, &address.sin_addr)
            }
            if conversionResult != 1 {
                address.sin_addr = in_addr(s_addr: CFSwapInt32HostToBig(INADDR_ANY))
            }
        } else {
            address.sin_addr = in_addr(s_addr: CFSwapInt32HostToBig(INADDR_ANY))
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(socketDescriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        return bindResult == 0
    }

    private static func parseIPv4Address(from host: NWEndpoint.Host) -> String? {
        let raw = String(describing: host).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty, !raw.contains(":") else {
            return nil
        }
        return raw
    }
}
