import Foundation

enum ShadowClientSunshineENetPacketCodec {
    struct ParsedPacket: Sendable {
        struct Command: Sendable {
            let number: UInt8
            let flags: UInt8
            let channelID: UInt8
            let reliableSequenceNumber: UInt16
            let offset: Int
            let length: Int

            var isAcknowledgeRequired: Bool {
                (flags & ShadowClientSunshineENetPacketCodec.protocolCommandFlagAcknowledge) != 0
            }
        }

        let rawData: Data
        let peerID: UInt16
        let sessionID: UInt8
        let sentTime: UInt16?
        let commands: [Command]
    }

    struct VerifyConnect: Sendable {
        let commandChannelID: UInt8
        let commandReliableSequenceNumber: UInt16
        let receivedSentTime: UInt16
        let outgoingPeerID: UInt16
        let outgoingSessionID: UInt8
        let connectID: UInt32
    }

    static let maximumPeerID: UInt16 = 0x0FFF
    static let controlChannelCount: UInt32 = 0x30

    private static let protocolHeaderFlagSentTime: UInt16 = 1 << 15
    private static let protocolHeaderFlagCompressed: UInt16 = 1 << 14
    private static let protocolHeaderSessionShift: UInt16 = 12
    private static let protocolHeaderSessionMask: UInt16 = 3 << protocolHeaderSessionShift
    private static let protocolCommandMask: UInt8 = 0x0F
    private static let protocolCommandFlagAcknowledge: UInt8 = 1 << 7
    private static let protocolCommandAcknowledge: UInt8 = 1
    private static let protocolCommandConnect: UInt8 = 2
    private static let protocolCommandVerifyConnect: UInt8 = 3

    // ENet commandSizes[] from protocol.c
    private static let fixedCommandSizes: [UInt8: Int] = [
        1: 8, // acknowledge
        2: 48, // connect
        3: 44, // verify connect
        4: 8, // disconnect
        5: 4, // ping
        6: 6, // send reliable
        7: 8, // send unreliable
        8: 24, // send fragment
        9: 8, // send unsequenced
        10: 12, // bandwidth limit
        11: 16, // throttle configure
        12: 24, // send unreliable fragment
    ]

    static func makeConnectPacket(
        connectID: UInt32,
        connectData: UInt32,
        channelCount: UInt32 = controlChannelCount,
        sentTime: UInt16
    ) -> Data {
        var packet = Data()
        packet.reserveCapacity(52)

        let peerIDWithFlags = maximumPeerID | protocolHeaderFlagSentTime
        packet.appendUInt16BE(peerIDWithFlags)
        packet.appendUInt16BE(sentTime)

        packet.append(protocolCommandConnect | protocolCommandFlagAcknowledge)
        packet.append(0xFF)
        packet.appendUInt16BE(1) // first outgoing reliable sequence
        packet.appendUInt16BE(0) // outgoingPeerID = incomingPeerID for local peer index 0
        packet.append(0xFF) // incomingSessionID
        packet.append(0xFF) // outgoingSessionID
        packet.appendUInt32BE(1_392) // ENET_HOST_DEFAULT_MTU
        packet.appendUInt32BE(65_536) // ENET_PROTOCOL_MAXIMUM_WINDOW_SIZE
        packet.appendUInt32BE(channelCount)
        packet.appendUInt32BE(0) // incomingBandwidth
        packet.appendUInt32BE(0) // outgoingBandwidth
        packet.appendUInt32BE(5_000) // packetThrottleInterval
        packet.appendUInt32BE(2) // packetThrottleAcceleration
        packet.appendUInt32BE(2) // packetThrottleDeceleration
        // ENet transmits connectID without host/network byte swapping.
        packet.appendUInt32LE(connectID)
        packet.appendUInt32BE(connectData)
        return packet
    }

    static func makeAcknowledgePacket(
        outgoingPeerID: UInt16,
        outgoingSessionID: UInt8,
        outgoingReliableSequenceNumber: UInt16,
        commandChannelID: UInt8,
        receivedReliableSequenceNumber: UInt16,
        receivedSentTime: UInt16
    ) -> Data {
        var packet = Data()
        packet.reserveCapacity(10)

        let sessionBits = UInt16(outgoingSessionID & 0x03) << protocolHeaderSessionShift
        let peerIDWithSession = (outgoingPeerID & maximumPeerID) | sessionBits
        packet.appendUInt16BE(peerIDWithSession)

        packet.append(protocolCommandAcknowledge)
        packet.append(commandChannelID)
        packet.appendUInt16BE(outgoingReliableSequenceNumber)
        packet.appendUInt16BE(receivedReliableSequenceNumber)
        packet.appendUInt16BE(receivedSentTime)
        return packet
    }

    static func parsePacket(_ data: Data) -> ParsedPacket? {
        guard data.count >= 2 else {
            return nil
        }

        let rawPeerID = data.readUInt16BE(at: 0)
        if (rawPeerID & protocolHeaderFlagCompressed) != 0 {
            return nil
        }

        let peerID = rawPeerID & maximumPeerID
        let sessionID = UInt8((rawPeerID & protocolHeaderSessionMask) >> protocolHeaderSessionShift)
        let hasSentTime = (rawPeerID & protocolHeaderFlagSentTime) != 0
        let headerLength = hasSentTime ? 4 : 2
        guard data.count >= headerLength else {
            return nil
        }

        let sentTime = hasSentTime ? data.readUInt16BE(at: 2) : nil
        var commands: [ParsedPacket.Command] = []
        var cursor = headerLength

        while cursor + 4 <= data.count {
            let commandByte = data[cursor]
            let commandNumber = commandByte & protocolCommandMask
            guard let fixedSize = fixedCommandSizes[commandNumber] else {
                break
            }
            guard cursor + fixedSize <= data.count else {
                break
            }

            let payloadSize: Int
            switch commandNumber {
            case 6:
                payloadSize = Int(data.readUInt16BE(at: cursor + 4))
            case 7, 9:
                payloadSize = Int(data.readUInt16BE(at: cursor + 6))
            case 8, 12:
                payloadSize = Int(data.readUInt16BE(at: cursor + 6))
            default:
                payloadSize = 0
            }

            let totalLength = fixedSize + payloadSize
            guard cursor + totalLength <= data.count else {
                break
            }

            commands.append(
                .init(
                    number: commandNumber,
                    flags: commandByte,
                    channelID: data[cursor + 1],
                    reliableSequenceNumber: data.readUInt16BE(at: cursor + 2),
                    offset: cursor,
                    length: totalLength
                )
            )

            cursor += totalLength
        }

        return .init(
            rawData: data,
            peerID: peerID,
            sessionID: sessionID,
            sentTime: sentTime,
            commands: commands
        )
    }

    static func parseVerifyConnect(from packet: ParsedPacket) -> VerifyConnect? {
        guard let sentTime = packet.sentTime else {
            return nil
        }

        for command in packet.commands where command.number == protocolCommandVerifyConnect {
            guard command.length >= 44 else {
                continue
            }

            let base = command.offset
            return .init(
                commandChannelID: command.channelID,
                commandReliableSequenceNumber: command.reliableSequenceNumber,
                receivedSentTime: sentTime,
                outgoingPeerID: packet.rawData.readUInt16BE(at: base + 4),
                outgoingSessionID: packet.rawData[base + 7],
                connectID: packet.rawData.readUInt32LE(at: base + 40)
            )
        }

        return nil
    }
}

private extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    mutating func appendUInt32BE(_ value: UInt32) {
        var be = value.bigEndian
        Swift.withUnsafeBytes(of: &be) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var le = value.littleEndian
        Swift.withUnsafeBytes(of: &le) { append(contentsOf: $0) }
    }

    func readUInt16BE(at offset: Int) -> UInt16 {
        let upper = UInt16(self[offset]) << 8
        let lower = UInt16(self[offset + 1])
        return upper | lower
    }

    func readUInt32LE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset])
        let b1 = UInt32(self[offset + 1]) << 8
        let b2 = UInt32(self[offset + 2]) << 16
        let b3 = UInt32(self[offset + 3]) << 24
        return b0 | b1 | b2 | b3
    }
}
