import Foundation

enum ShadowClientHostENetPacketCodecError: Error, Equatable {
    case reliablePayloadTooLarge(Int)
}

enum ShadowClientHostENetPacketCodec {
    struct ParsedPacket: Sendable {
        struct Command: Sendable {
            let number: UInt8
            let flags: UInt8
            let channelID: UInt8
            let reliableSequenceNumber: UInt16
            let offset: Int
            let length: Int

            var isAcknowledgeRequired: Bool {
                (flags & ShadowClientHostENetProtocolProfile.protocolCommandFlagAcknowledge) != 0
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

    struct Acknowledge: Sendable {
        let commandChannelID: UInt8
        let commandReliableSequenceNumber: UInt16
        let receivedReliableSequenceNumber: UInt16
        let receivedSentTime: UInt16
    }

    static let maximumPeerID: UInt16 = ShadowClientHostENetProtocolProfile.maximumPeerID
    static let controlChannelCount: UInt32 = ShadowClientHostENetProtocolProfile.controlChannelCount

    static func makeConnectPacket(
        connectID: UInt32,
        connectData: UInt32,
        channelCount: UInt32 = controlChannelCount,
        sentTime: UInt16
    ) -> Data {
        var packet = Data()
        packet.reserveCapacity(52)

        let peerIDWithFlags = maximumPeerID | ShadowClientHostENetProtocolProfile.protocolHeaderFlagSentTime
        packet.appendUInt16BE(peerIDWithFlags)
        packet.appendUInt16BE(sentTime)

        packet.append(
            ShadowClientHostENetProtocolProfile.protocolCommandConnect |
                ShadowClientHostENetProtocolProfile.protocolCommandFlagAcknowledge
        )
        packet.append(ShadowClientHostENetProtocolProfile.wildcardSessionID)
        packet.appendUInt16BE(ShadowClientHostENetProtocolProfile.firstOutgoingReliableSequence)
        // outgoingPeerID = incomingPeerID for local peer index 0
        packet.appendUInt16BE(ShadowClientHostENetProtocolProfile.localIncomingPeerID)
        packet.append(ShadowClientHostENetProtocolProfile.wildcardSessionID) // incomingSessionID
        packet.append(ShadowClientHostENetProtocolProfile.wildcardSessionID) // outgoingSessionID
        packet.appendUInt32BE(ShadowClientHostENetProtocolProfile.defaultMTU)
        packet.appendUInt32BE(ShadowClientHostENetProtocolProfile.maximumWindowSize)
        packet.appendUInt32BE(channelCount)
        packet.appendUInt32BE(0) // incomingBandwidth
        packet.appendUInt32BE(0) // outgoingBandwidth
        packet.appendUInt32BE(ShadowClientHostENetProtocolProfile.packetThrottleIntervalMs)
        packet.appendUInt32BE(ShadowClientHostENetProtocolProfile.packetThrottleAcceleration)
        packet.appendUInt32BE(ShadowClientHostENetProtocolProfile.packetThrottleDeceleration)
        // ENet transmits connectID without host/network byte swapping.
        packet.appendUInt32LE(connectID)
        packet.appendUInt32BE(connectData)
        return packet
    }

    static func makeAcknowledgePacket(
        outgoingPeerID: UInt16,
        outgoingSessionID: UInt8,
        commandChannelID: UInt8,
        receivedReliableSequenceNumber: UInt16,
        receivedSentTime: UInt16,
        sentTime: UInt16
    ) -> Data {
        var packet = Data()
        packet.reserveCapacity(12)

        let sessionBits = UInt16(outgoingSessionID & ShadowClientHostENetProtocolProfile.sessionValueMask) <<
            ShadowClientHostENetProtocolProfile.protocolHeaderSessionShift
        let peerIDWithSession =
            (outgoingPeerID & maximumPeerID) |
            sessionBits |
            ShadowClientHostENetProtocolProfile.protocolHeaderFlagSentTime
        packet.appendUInt16BE(peerIDWithSession)
        packet.appendUInt16BE(sentTime)

        packet.append(ShadowClientHostENetProtocolProfile.protocolCommandAcknowledge)
        packet.append(commandChannelID)
        packet.appendUInt16BE(receivedReliableSequenceNumber)
        packet.appendUInt16BE(receivedReliableSequenceNumber)
        packet.appendUInt16BE(receivedSentTime)
        return packet
    }

    static func makePingPacket(
        outgoingPeerID: UInt16,
        outgoingSessionID: UInt8,
        reliableSequenceNumber: UInt16,
        sentTime: UInt16
    ) -> Data {
        var packet = Data()
        packet.reserveCapacity(8)

        let sessionBits = UInt16(outgoingSessionID & ShadowClientHostENetProtocolProfile.sessionValueMask) <<
            ShadowClientHostENetProtocolProfile.protocolHeaderSessionShift
        let peerIDWithSession =
            (outgoingPeerID & maximumPeerID) |
            sessionBits |
            ShadowClientHostENetProtocolProfile.protocolHeaderFlagSentTime
        packet.appendUInt16BE(peerIDWithSession)
        packet.appendUInt16BE(sentTime)
        packet.append(
            ShadowClientHostENetProtocolProfile.protocolCommandPing |
                ShadowClientHostENetProtocolProfile.protocolCommandFlagAcknowledge
        )
        packet.append(ShadowClientHostENetProtocolProfile.wildcardSessionID)
        packet.appendUInt16BE(reliableSequenceNumber)
        return packet
    }

    static func makeSendReliablePacket(
        outgoingPeerID: UInt16,
        outgoingSessionID: UInt8,
        reliableSequenceNumber: UInt16,
        channelID: UInt8,
        sentTime: UInt16,
        payload: Data
    ) throws -> Data {
        guard payload.count <= Int(UInt16.max) else {
            throw ShadowClientHostENetPacketCodecError.reliablePayloadTooLarge(payload.count)
        }
        var packet = Data()
        packet.reserveCapacity(10 + payload.count)

        let sessionBits = UInt16(outgoingSessionID & ShadowClientHostENetProtocolProfile.sessionValueMask) <<
            ShadowClientHostENetProtocolProfile.protocolHeaderSessionShift
        let peerIDWithSession =
            (outgoingPeerID & maximumPeerID) |
            sessionBits |
            ShadowClientHostENetProtocolProfile.protocolHeaderFlagSentTime
        packet.appendUInt16BE(peerIDWithSession)
        packet.appendUInt16BE(sentTime)

        packet.append(
            ShadowClientHostENetProtocolProfile.protocolCommandSendReliable |
                ShadowClientHostENetProtocolProfile.protocolCommandFlagAcknowledge
        )
        packet.append(channelID)
        packet.appendUInt16BE(reliableSequenceNumber)
        packet.appendUInt16BE(UInt16(payload.count))
        packet.append(payload)
        return packet
    }

    static func makeControlMessagePayload(type: UInt16, payload: Data) -> Data {
        var message = Data()
        message.reserveCapacity(2 + payload.count)
        message.appendUInt16LE(type)
        message.append(payload)
        return message
    }

    static func parsePacket(_ data: Data) -> ParsedPacket? {
        guard data.count >= 2 else {
            return nil
        }

        let rawPeerID = data.readUInt16BE(at: 0)
        if (rawPeerID & ShadowClientHostENetProtocolProfile.protocolHeaderFlagCompressed) != 0 {
            return nil
        }

        let peerID = rawPeerID & maximumPeerID
        let sessionID = UInt8(
            (rawPeerID & ShadowClientHostENetProtocolProfile.protocolHeaderSessionMask) >>
                ShadowClientHostENetProtocolProfile.protocolHeaderSessionShift
        )
        let hasSentTime = (rawPeerID & ShadowClientHostENetProtocolProfile.protocolHeaderFlagSentTime) != 0
        let headerLength = hasSentTime ? 4 : 2
        guard data.count >= headerLength else {
            return nil
        }

        let sentTime = hasSentTime ? data.readUInt16BE(at: 2) : nil
        var commands: [ParsedPacket.Command] = []
        var cursor = headerLength

        while cursor + 4 <= data.count {
            let commandByte = data[cursor]
            let commandNumber = commandByte & ShadowClientHostENetProtocolProfile.protocolCommandMask
            guard let fixedSize = ShadowClientHostENetProtocolProfile.fixedCommandSizes[commandNumber] else {
                break
            }
            guard cursor + fixedSize <= data.count else {
                break
            }

            let payloadSize: Int
            switch commandNumber {
            case ShadowClientHostENetProtocolProfile.protocolCommandSendReliable:
                payloadSize = Int(data.readUInt16BE(at: cursor + 4))
            case ShadowClientHostENetProtocolProfile.protocolCommandSendUnreliable,
                ShadowClientHostENetProtocolProfile.protocolCommandSendUnsequenced:
                payloadSize = Int(data.readUInt16BE(at: cursor + 6))
            case ShadowClientHostENetProtocolProfile.protocolCommandSendFragment,
                ShadowClientHostENetProtocolProfile.protocolCommandSendUnreliableFragment:
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

        for command in packet.commands where command.number == ShadowClientHostENetProtocolProfile.protocolCommandVerifyConnect {
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

    static func parseAcknowledge(
        from packet: ParsedPacket,
        command: ParsedPacket.Command
    ) -> Acknowledge? {
        guard command.number == ShadowClientHostENetProtocolProfile.protocolCommandAcknowledge,
              command.length >= 8
        else {
            return nil
        }

        let base = command.offset
        return .init(
            commandChannelID: command.channelID,
            commandReliableSequenceNumber: command.reliableSequenceNumber,
            receivedReliableSequenceNumber: packet.rawData.readUInt16BE(at: base + 4),
            receivedSentTime: packet.rawData.readUInt16BE(at: base + 6)
        )
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

    mutating func appendUInt16LE(_ value: UInt16) {
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
