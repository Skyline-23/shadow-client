import Darwin
import Foundation
import Network

enum ShadowClientUDPDatagramSocketError: Error {
    case unsupportedAddress(String)
    case socketFailure(String)
}

actor ShadowClientUDPDatagramSocket {
    private enum SocketAddress {
        case ipv4(sockaddr_in)
        case ipv6(sockaddr_in6)

        var family: Int32 {
            switch self {
            case .ipv4:
                return AF_INET
            case .ipv6:
                return AF_INET6
            }
        }

        var length: socklen_t {
            switch self {
            case .ipv4:
                return socklen_t(MemoryLayout<sockaddr_in>.size)
            case .ipv6:
                return socklen_t(MemoryLayout<sockaddr_in6>.size)
            }
        }
    }

    private let descriptor: Int32
    private let addressFamily: Int32
    private var isClosed = false
    private var receiveBuffer: [UInt8] = Array(
        repeating: 0,
        count: ShadowClientRealtimeSessionDefaults.maximumTransportReadLength
    )

    init(
        localHost: NWEndpoint.Host?,
        localPort: UInt16?,
        remoteHost: NWEndpoint.Host,
        remotePort: UInt16
    ) throws {
        guard let remoteAddress = Self.makeAddress(from: remoteHost, port: remotePort) else {
            throw ShadowClientUDPDatagramSocketError.unsupportedAddress(
                "Unsupported remote UDP endpoint: \(String(describing: remoteHost)):\(remotePort)"
            )
        }
        addressFamily = remoteAddress.family

        descriptor = socket(addressFamily, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else {
            throw ShadowClientUDPDatagramSocketError.socketFailure(
                "socket() failed: \(String(cString: strerror(errno)))"
            )
        }

        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 250_000)
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        var receiveBufferSize: Int32 = 4 * 1_024 * 1_024
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVBUF,
            &receiveBufferSize,
            socklen_t(MemoryLayout<Int32>.size)
        )
        var sendBufferSize: Int32 = 1 * 1_024 * 1_024
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_SNDBUF,
            &sendBufferSize,
            socklen_t(MemoryLayout<Int32>.size)
        )
        var noSigPipe: Int32 = 1
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_NOSIGPIPE,
            &noSigPipe,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var localAddress = Self.makeLocalAddress(
            from: localHost,
            port: localPort,
            family: addressFamily
        )
        let bindStatus = Self.withSockaddrPointer(to: &localAddress) { sockaddrPointer, addressLength in
            bind(descriptor, sockaddrPointer, addressLength)
        }
        if bindStatus != 0 {
            let message = "bind() failed: \(String(cString: strerror(errno)))"
            Darwin.close(descriptor)
            throw ShadowClientUDPDatagramSocketError.socketFailure(message)
        }

        var connectedRemoteAddress = remoteAddress
        let connectStatus = Self.withSockaddrPointer(to: &connectedRemoteAddress) { sockaddrPointer, addressLength in
            connect(descriptor, sockaddrPointer, addressLength)
        }
        if connectStatus != 0 {
            let message = "connect() failed: \(String(cString: strerror(errno)))"
            Darwin.close(descriptor)
            throw ShadowClientUDPDatagramSocketError.socketFailure(message)
        }
    }

    func send(_ datagram: Data) throws {
        let sentBytes = datagram.withUnsafeBytes { bytes in
            Darwin.send(
                descriptor,
                bytes.baseAddress,
                datagram.count,
                0
            )
        }

        if sentBytes < 0 {
            throw ShadowClientUDPDatagramSocketError.socketFailure(
                "send() failed: \(String(cString: strerror(errno)))"
            )
        }
    }

    func receive(maximumLength: Int) throws -> Data? {
        if receiveBuffer.count < maximumLength {
            receiveBuffer = Array(repeating: 0, count: maximumLength)
        }
        let receivedBytes = receiveBuffer.withUnsafeMutableBytes { bytes in
            Darwin.recv(
                descriptor,
                bytes.baseAddress,
                min(maximumLength, bytes.count),
                0
            )
        }

        if receivedBytes < 0 {
            let errorCode = errno
            if errorCode == EAGAIN || errorCode == EWOULDBLOCK || errorCode == EINTR {
                return nil
            }
            if errorCode == EBADF, isSocketMarkedClosed() {
                return nil
            }
            throw ShadowClientUDPDatagramSocketError.socketFailure(
                "recv() failed (\(errorCode)): \(String(cString: strerror(errorCode)))"
            )
        }

        guard receivedBytes > 0 else {
            return nil
        }
        return receiveBuffer.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return Data()
            }
            return Data(bytes: baseAddress, count: receivedBytes)
        }
    }

    func localEndpointDescription() -> String {
        var address = sockaddr_storage()
        var addressLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let status = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(descriptor, sockaddrPointer, &addressLength)
            }
        }
        guard status == 0 else {
            return "ephemeral:unknown"
        }

        switch Int32(address.ss_family) {
        case AF_INET:
            return withUnsafePointer(to: &address) { pointer -> String in
                pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sockaddrInPointer in
                    var ipv4 = sockaddrInPointer.pointee.sin_addr
                    let port = CFSwapInt16BigToHost(sockaddrInPointer.pointee.sin_port)
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    let converted = inet_ntop(
                        AF_INET,
                        &ipv4,
                        &buffer,
                        socklen_t(INET_ADDRSTRLEN)
                    )
                    guard converted != nil else {
                        return "0.0.0.0:\(port)"
                    }
                    return "\(String(cString: buffer)):\(port)"
                }
            }
        case AF_INET6:
            return withUnsafePointer(to: &address) { pointer -> String in
                pointer.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { sockaddrIn6Pointer in
                    var ipv6 = sockaddrIn6Pointer.pointee.sin6_addr
                    let port = CFSwapInt16BigToHost(sockaddrIn6Pointer.pointee.sin6_port)
                    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    let converted = inet_ntop(
                        AF_INET6,
                        &ipv6,
                        &buffer,
                        socklen_t(INET6_ADDRSTRLEN)
                    )
                    guard converted != nil else {
                        return ":::\(port)"
                    }
                    return "\(String(cString: buffer)):\(port)"
                }
            }
        default:
            return "ephemeral:unknown"
        }
    }

    func close() {
        if !isClosed {
            isClosed = true
            Darwin.close(descriptor)
        }
    }

    private func isSocketMarkedClosed() -> Bool {
        isClosed
    }

    private static func makeLocalAddress(
        from host: NWEndpoint.Host?,
        port: UInt16?,
        family: Int32
    ) -> SocketAddress {
        switch family {
        case AF_INET:
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = CFSwapInt16HostToBig(port ?? 0)
            if let host, let parsed = parseIPv4Host(host) {
                address.sin_addr = parsed
            } else {
                address.sin_addr = in_addr(s_addr: CFSwapInt32HostToBig(INADDR_ANY))
            }
            return .ipv4(address)
        default:
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = CFSwapInt16HostToBig(port ?? 0)
            if let host, let parsed = parseIPv6Host(host) {
                address.sin6_addr = parsed
            } else {
                address.sin6_addr = in6addr_any
            }
            return .ipv6(address)
        }
    }

    private static func makeAddress(
        from host: NWEndpoint.Host,
        port: UInt16
    ) -> SocketAddress? {
        if let parsedIPv4 = parseIPv4Host(host) {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = CFSwapInt16HostToBig(port)
            address.sin_addr = parsedIPv4
            return .ipv4(address)
        }

        if let parsedIPv6 = parseIPv6Host(host) {
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = CFSwapInt16HostToBig(port)
            address.sin6_addr = parsedIPv6
            return .ipv6(address)
        }

        return nil
    }

    private static func parseIPv4Host(_ host: NWEndpoint.Host) -> in_addr? {
        let hostString = String(describing: host)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? ""
        guard !hostString.isEmpty else {
            return nil
        }

        var parsed = in_addr()
        let result = hostString.withCString { cString in
            inet_pton(AF_INET, cString, &parsed)
        }
        guard result == 1 else {
            return nil
        }
        return parsed
    }

    private static func parseIPv6Host(_ host: NWEndpoint.Host) -> in6_addr? {
        let hostString = String(describing: host).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostString.isEmpty else {
            return nil
        }

        var parsed = in6_addr()
        let result = hostString.withCString { cString in
            inet_pton(AF_INET6, cString, &parsed)
        }
        guard result == 1 else {
            return nil
        }
        return parsed
    }

    private static func resolvedConnectionHostCandidates(for host: String) -> [NWEndpoint.Host] {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            return [.init(host)]
        }

        if parseIPv4Host(.init(trimmedHost)) != nil || parseIPv6Host(.init(trimmedHost)) != nil {
            return [.init(trimmedHost)]
        }

        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var resultPointer: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(trimmedHost, nil, &hints, &resultPointer)
        guard status == 0, let resultPointer else {
            return [.init(trimmedHost)]
        }
        defer { freeaddrinfo(resultPointer) }

        var seen = Set<String>()
        var candidates: [(host: String, rank: Int)] = []

        for pointer in sequence(first: resultPointer, next: { $0.pointee.ai_next }) {
            guard let sockaddrPointer = pointer.pointee.ai_addr else {
                continue
            }
            let hostString = numericHostString(from: sockaddrPointer, length: pointer.pointee.ai_addrlen)
            guard let hostString else {
                continue
            }
            let normalized = hostString.lowercased()
            guard seen.insert(normalized).inserted else {
                continue
            }
            candidates.append((host: hostString, rank: connectionHostRank(hostString)))
        }

        if candidates.isEmpty {
            return [.init(trimmedHost)]
        }

        return candidates
            .sorted {
                if $0.rank == $1.rank {
                    return $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending
                }
                return $0.rank < $1.rank
            }
            .map { .init($0.host) }
    }

    private static func numericHostString(
        from address: UnsafeMutablePointer<sockaddr>,
        length: socklen_t
    ) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            address,
            length,
            &buffer,
            socklen_t(buffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard status == 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    private static func connectionHostRank(_ host: String) -> Int {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("169.254.") || normalized.hasPrefix("fe80:") {
            return 10
        }
        if normalized.contains(":") {
            return 1
        }
        return 0
    }

    private static func withSockaddrPointer<T>(
        to address: inout SocketAddress,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T
    ) rethrows -> T {
        switch address {
        case var .ipv4(value):
            defer { address = .ipv4(value) }
            return try withUnsafePointer(to: &value) { pointer in
                try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    try body(sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        case var .ipv6(value):
            defer { address = .ipv6(value) }
            return try withUnsafePointer(to: &value) { pointer in
                try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    try body(sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }
    }
}
