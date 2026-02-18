import Foundation
import Testing

@Test("ENet connect packet encodes control fields in big-endian order except host-order connectID")
func enetConnectPacketEncodesFieldsWithHostOrderConnectID() throws {
    let fields = ENetConnectPacketFields(
        reliableSequenceNumber: 0x1234,
        outgoingPeerID: 0x4567,
        incomingSessionID: 0x89,
        outgoingSessionID: 0xAB,
        mtu: 0x0102_0304,
        windowSize: 0x1122_3344,
        channelCount: 0x5566_7788,
        incomingBandwidth: 0x99AA_BBCC,
        outgoingBandwidth: 0xDDEE_FF00,
        packetThrottleInterval: 0x1020_3040,
        packetThrottleAcceleration: 0x5060_7080,
        packetThrottleDeceleration: 0x90A0_B0C0,
        connectID: 0x0D1E_2F3A,
        data: 0x4B5C_6D7E
    )

    let packet = TestENetControlPacketCodec.makeConnectPacket(fields)

    #expect(packet.count == 48)
    #expect(packet[0] == 0x82) // CONNECT | ACKNOWLEDGE
    #expect(packet[1] == 0xFF)
    #expect(Array(packet[2...3]) == [0x12, 0x34])
    #expect(Array(packet[4...5]) == [0x45, 0x67])
    #expect(packet[6] == 0x89)
    #expect(packet[7] == 0xAB)
    #expect(Array(packet[8...11]) == [0x01, 0x02, 0x03, 0x04])
    #expect(Array(packet[12...15]) == [0x11, 0x22, 0x33, 0x44])
    #expect(Array(packet[16...19]) == [0x55, 0x66, 0x77, 0x88])
    #expect(Array(packet[20...23]) == [0x99, 0xAA, 0xBB, 0xCC])
    #expect(Array(packet[24...27]) == [0xDD, 0xEE, 0xFF, 0x00])
    #expect(Array(packet[28...31]) == [0x10, 0x20, 0x30, 0x40])
    #expect(Array(packet[32...35]) == [0x50, 0x60, 0x70, 0x80])
    #expect(Array(packet[36...39]) == [0x90, 0xA0, 0xB0, 0xC0])
    // ENet transmits connectID in host order (little-endian on supported platforms).
    #expect(Array(packet[40...43]) == [0x3A, 0x2F, 0x1E, 0x0D])
    #expect(Array(packet[44...47]) == [0x4B, 0x5C, 0x6D, 0x7E])
}

@Test("ENet verify-connect parser decodes control fields in big-endian order except host-order connectID")
func enetVerifyConnectParserDecodesFieldsWithHostOrderConnectID() throws {
    var packet = Data()
    packet.append(0x83) // VERIFY_CONNECT | ACKNOWLEDGE
    packet.append(0xFF)
    packet.append(contentsOf: [0xBE, 0xEF]) // reliableSequenceNumber
    packet.append(contentsOf: [0xCA, 0xFE]) // outgoingPeerID
    packet.append(0x12) // incomingSessionID
    packet.append(0x34) // outgoingSessionID
    packet.append(contentsOf: [0x01, 0x23, 0x45, 0x67]) // mtu
    packet.append(contentsOf: [0x89, 0xAB, 0xCD, 0xEF]) // windowSize
    packet.append(contentsOf: [0x10, 0x20, 0x30, 0x40]) // channelCount
    packet.append(contentsOf: [0x50, 0x60, 0x70, 0x80]) // incomingBandwidth
    packet.append(contentsOf: [0x90, 0xA0, 0xB0, 0xC0]) // outgoingBandwidth
    packet.append(contentsOf: [0x0A, 0x0B, 0x0C, 0x0D]) // packetThrottleInterval
    packet.append(contentsOf: [0x0E, 0x0F, 0x1A, 0x1B]) // packetThrottleAcceleration
    packet.append(contentsOf: [0x1C, 0x1D, 0x2A, 0x2B]) // packetThrottleDeceleration
    packet.append(contentsOf: [0x2C, 0x2D, 0x3A, 0x3B]) // connectID

    let parsed = try TestENetControlPacketCodec.parseVerifyConnectPacket(packet)

    #expect(parsed.reliableSequenceNumber == 0xBEEF)
    #expect(parsed.outgoingPeerID == 0xCAFE)
    #expect(parsed.incomingSessionID == 0x12)
    #expect(parsed.outgoingSessionID == 0x34)
    #expect(parsed.mtu == 0x0123_4567)
    #expect(parsed.windowSize == 0x89AB_CDEF)
    #expect(parsed.channelCount == 0x1020_3040)
    #expect(parsed.incomingBandwidth == 0x5060_7080)
    #expect(parsed.outgoingBandwidth == 0x90A0_B0C0)
    #expect(parsed.packetThrottleInterval == 0x0A0B_0C0D)
    #expect(parsed.packetThrottleAcceleration == 0x0E0F_1A1B)
    #expect(parsed.packetThrottleDeceleration == 0x1C1D_2A2B)
    #expect(parsed.connectID == 0x3B3A_2D2C)
}

@Test("ENet acknowledge packet generation preserves big-endian sequence and sent-time fields")
func enetAcknowledgePacketGenerationUsesBigEndianOrder() {
    let packet = TestENetControlPacketCodec.makeAcknowledgePacket(
        channelID: 0x05,
        reliableSequenceNumber: 0xA1B2,
        receivedSentTime: 0xC3D4
    )

    #expect(packet.count == 8)
    #expect(packet[0] == 0x01) // ACKNOWLEDGE
    #expect(packet[1] == 0x05)
    #expect(Array(packet[2...3]) == [0xA1, 0xB2]) // header.reliableSequenceNumber
    #expect(Array(packet[4...5]) == [0xA1, 0xB2]) // acknowledge.receivedReliableSequenceNumber
    #expect(Array(packet[6...7]) == [0xC3, 0xD4]) // acknowledge.receivedSentTime
}

private struct ENetConnectPacketFields {
    let reliableSequenceNumber: UInt16
    let outgoingPeerID: UInt16
    let incomingSessionID: UInt8
    let outgoingSessionID: UInt8
    let mtu: UInt32
    let windowSize: UInt32
    let channelCount: UInt32
    let incomingBandwidth: UInt32
    let outgoingBandwidth: UInt32
    let packetThrottleInterval: UInt32
    let packetThrottleAcceleration: UInt32
    let packetThrottleDeceleration: UInt32
    let connectID: UInt32
    let data: UInt32
}

private struct ENetVerifyConnectPacketFields {
    let reliableSequenceNumber: UInt16
    let outgoingPeerID: UInt16
    let incomingSessionID: UInt8
    let outgoingSessionID: UInt8
    let mtu: UInt32
    let windowSize: UInt32
    let channelCount: UInt32
    let incomingBandwidth: UInt32
    let outgoingBandwidth: UInt32
    let packetThrottleInterval: UInt32
    let packetThrottleAcceleration: UInt32
    let packetThrottleDeceleration: UInt32
    let connectID: UInt32
}

private enum TestENetControlPacketCodec {
    private static let commandAcknowledge: UInt8 = 1
    private static let commandConnectWithAcknowledgeFlag: UInt8 = 0x82
    private static let commandVerifyConnectWithAcknowledgeFlag: UInt8 = 0x83
    private static let controlChannelID: UInt8 = 0xFF

    static func makeConnectPacket(_ fields: ENetConnectPacketFields) -> Data {
        var packet = Data()
        packet.append(commandConnectWithAcknowledgeFlag)
        packet.append(controlChannelID)
        packet.append(contentsOf: bytesBE(fields.reliableSequenceNumber))
        packet.append(contentsOf: bytesBE(fields.outgoingPeerID))
        packet.append(fields.incomingSessionID)
        packet.append(fields.outgoingSessionID)
        packet.append(contentsOf: bytesBE(fields.mtu))
        packet.append(contentsOf: bytesBE(fields.windowSize))
        packet.append(contentsOf: bytesBE(fields.channelCount))
        packet.append(contentsOf: bytesBE(fields.incomingBandwidth))
        packet.append(contentsOf: bytesBE(fields.outgoingBandwidth))
        packet.append(contentsOf: bytesBE(fields.packetThrottleInterval))
        packet.append(contentsOf: bytesBE(fields.packetThrottleAcceleration))
        packet.append(contentsOf: bytesBE(fields.packetThrottleDeceleration))
        packet.append(contentsOf: bytesLE(fields.connectID))
        packet.append(contentsOf: bytesBE(fields.data))
        return packet
    }

    static func parseVerifyConnectPacket(_ packet: Data) throws -> ENetVerifyConnectPacketFields {
        guard packet.count == 44, packet[0] == commandVerifyConnectWithAcknowledgeFlag else {
            throw ENetCodecError.invalidPacket
        }

        return ENetVerifyConnectPacketFields(
            reliableSequenceNumber: try readUInt16BE(from: packet, at: 2),
            outgoingPeerID: try readUInt16BE(from: packet, at: 4),
            incomingSessionID: packet[6],
            outgoingSessionID: packet[7],
            mtu: try readUInt32BE(from: packet, at: 8),
            windowSize: try readUInt32BE(from: packet, at: 12),
            channelCount: try readUInt32BE(from: packet, at: 16),
            incomingBandwidth: try readUInt32BE(from: packet, at: 20),
            outgoingBandwidth: try readUInt32BE(from: packet, at: 24),
            packetThrottleInterval: try readUInt32BE(from: packet, at: 28),
            packetThrottleAcceleration: try readUInt32BE(from: packet, at: 32),
            packetThrottleDeceleration: try readUInt32BE(from: packet, at: 36),
            connectID: try readUInt32LE(from: packet, at: 40)
        )
    }

    static func makeAcknowledgePacket(
        channelID: UInt8,
        reliableSequenceNumber: UInt16,
        receivedSentTime: UInt16
    ) -> Data {
        var packet = Data()
        packet.append(commandAcknowledge)
        packet.append(channelID)
        packet.append(contentsOf: bytesBE(reliableSequenceNumber))
        packet.append(contentsOf: bytesBE(reliableSequenceNumber))
        packet.append(contentsOf: bytesBE(receivedSentTime))
        return packet
    }

    private static func readUInt16BE(from data: Data, at offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 1 < data.count else {
            throw ENetCodecError.invalidPacket
        }

        return (UInt16(data[offset]) << 8) | UInt16(data[offset + 1])
    }

    private static func readUInt32BE(from data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 3 < data.count else {
            throw ENetCodecError.invalidPacket
        }

        return (UInt32(data[offset]) << 24) |
            (UInt32(data[offset + 1]) << 16) |
            (UInt32(data[offset + 2]) << 8) |
            UInt32(data[offset + 3])
    }

    private static func readUInt32LE(from data: Data, at offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 3 < data.count else {
            throw ENetCodecError.invalidPacket
        }

        return UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    private static func bytesBE<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        let bigEndianValue = value.bigEndian
        return withUnsafeBytes(of: bigEndianValue) { Array($0) }
    }

    private static func bytesLE<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        let littleEndianValue = value.littleEndian
        return withUnsafeBytes(of: littleEndianValue) { Array($0) }
    }
}

private enum ENetCodecError: Error {
    case invalidPacket
}
