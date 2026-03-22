import Darwin
import Foundation

public protocol ShadowClientWakeOnLANClient: Sendable {
    func sendMagicPacket(macAddress: String, port: UInt16) async throws -> Int
}

public enum ShadowClientWakeOnLANError: Error, Equatable, Sendable {
    case invalidMACAddress
    case noBroadcastAddressesAvailable
    case sendFailed(String)
}

extension ShadowClientWakeOnLANError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidMACAddress:
            return "Wake on LAN requires a valid MAC address."
        case .noBroadcastAddressesAvailable:
            return "No broadcast-capable network interface is available."
        case let .sendFailed(message):
            return message
        }
    }
}

enum ShadowClientWakeOnLANKit {
    static let defaultPort: UInt16 = 9

    static func normalizedMACAddress(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let hexDigits = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .filter(\.isHexDigit)
        guard hexDigits.count == 12 else {
            return nil
        }
        guard hexDigits != String(repeating: "0", count: 12) else {
            return nil
        }

        var octets: [String] = []
        octets.reserveCapacity(6)
        var index = hexDigits.startIndex
        while index < hexDigits.endIndex {
            let nextIndex = hexDigits.index(index, offsetBy: 2)
            octets.append(String(hexDigits[index..<nextIndex]))
            index = nextIndex
        }
        return octets.joined(separator: ":")
    }

    static func macBytes(from rawValue: String?) -> [UInt8]? {
        guard let normalized = normalizedMACAddress(rawValue) else {
            return nil
        }

        return normalized
            .split(separator: ":")
            .compactMap { UInt8($0, radix: 16) }
    }

    static func parsedPort(from rawValue: String?) -> UInt16? {
        guard let rawValue else {
            return nil
        }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let port = UInt16(trimmed),
              port > 0 else {
            return nil
        }
        return port
    }

    static func resolvedPort(from rawValue: String?) -> UInt16 {
        parsedPort(from: rawValue) ?? defaultPort
    }

    static func magicPacket(for macBytes: [UInt8]) -> Data {
        var payload = Data(repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            payload.append(contentsOf: macBytes)
        }
        return payload
    }
}

public struct NativeShadowClientWakeOnLANClient: ShadowClientWakeOnLANClient {
    public init() {}

    public func sendMagicPacket(macAddress: String, port: UInt16) async throws -> Int {
        guard let macBytes = ShadowClientWakeOnLANKit.macBytes(from: macAddress) else {
            throw ShadowClientWakeOnLANError.invalidMACAddress
        }

        let payload = ShadowClientWakeOnLANKit.magicPacket(for: macBytes)
        let broadcastAddresses = Self.broadcastAddresses()
        guard !broadcastAddresses.isEmpty else {
            throw ShadowClientWakeOnLANError.noBroadcastAddressesAvailable
        }

        var sentPackets = 0
        var lastError: String?
        for address in broadcastAddresses {
            do {
                try Self.send(payload: payload, toIPv4Broadcast: address, port: port)
                sentPackets += 1
            } catch {
                lastError = error.localizedDescription
            }
        }

        if sentPackets == 0 {
            throw ShadowClientWakeOnLANError.sendFailed(
                lastError ?? "Unable to send Wake-on-LAN packet."
            )
        }

        return sentPackets
    }

    private static func broadcastAddresses() -> [String] {
        var results: Set<String> = ["255.255.255.255"]
        var interfacesPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfacesPointer) == 0, let interfacesPointer else {
            return Array(results).sorted()
        }
        defer { freeifaddrs(interfacesPointer) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = interfacesPointer
        while let current = pointer?.pointee {
            defer { pointer = current.ifa_next }

            let flags = Int32(current.ifa_flags)
            guard (flags & IFF_UP) != 0,
                  (flags & IFF_LOOPBACK) == 0,
                  let addressPointer = current.ifa_addr,
                  let maskPointer = current.ifa_netmask,
                  addressPointer.pointee.sa_family == UInt8(AF_INET),
                  maskPointer.pointee.sa_family == UInt8(AF_INET)
            else {
                continue
            }

            let address = addressPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            let mask = maskPointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            let addressValue = UInt32(bigEndian: address.sin_addr.s_addr)
            let maskValue = UInt32(bigEndian: mask.sin_addr.s_addr)
            let broadcastValue = addressValue | ~maskValue
            results.insert(Self.string(forIPv4Address: broadcastValue))
        }

        return Array(results).sorted()
    }

    private static func send(payload: Data, toIPv4Broadcast address: String, port: UInt16) throws {
        var socketAddress = sockaddr_in()
        socketAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        socketAddress.sin_family = sa_family_t(AF_INET)
        socketAddress.sin_port = port.bigEndian

        let converted = address.withCString { cString in
            inet_pton(AF_INET, cString, &socketAddress.sin_addr)
        }
        guard converted == 1 else {
            throw ShadowClientWakeOnLANError.sendFailed("Invalid broadcast address \(address)")
        }

        let descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else {
            let code = errno
            throw ShadowClientWakeOnLANError.sendFailed(
                "Wake-on-LAN socket failed (\(code)): \(String(cString: strerror(code)))"
            )
        }
        defer { Darwin.close(descriptor) }

        var enableBroadcast: Int32 = 1
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_BROADCAST,
            &enableBroadcast,
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

        let sentBytes = payload.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return -1
            }
            return withUnsafePointer(to: &socketAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    Darwin.sendto(
                        descriptor,
                        baseAddress,
                        payload.count,
                        0,
                        sockaddrPointer,
                        socklen_t(MemoryLayout<sockaddr_in>.size)
                    )
                }
            }
        }

        guard sentBytes == payload.count else {
            let code = errno
            throw ShadowClientWakeOnLANError.sendFailed(
                "Wake-on-LAN send failed (\(code)): \(String(cString: strerror(code)))"
            )
        }
    }

    private static func string(forIPv4Address value: UInt32) -> String {
        let octet1 = (value >> 24) & 0xFF
        let octet2 = (value >> 16) & 0xFF
        let octet3 = (value >> 8) & 0xFF
        let octet4 = value & 0xFF
        return "\(octet1).\(octet2).\(octet3).\(octet4)"
    }
}
