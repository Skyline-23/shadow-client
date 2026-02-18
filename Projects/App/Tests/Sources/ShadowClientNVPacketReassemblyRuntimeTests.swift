import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Moonlight NV reassembly assembles frame without RTP marker on EOF packet")
func moonlightNVReassemblyAssemblesFrameWithoutMarker() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let frameIndex: UInt32 = 42

    let startPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 1_200,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x10, 0x11],
        frameHeader: moonlightFrameHeader(lastPayloadLength: moonlightCompactFrameHeaderSize + 3)
    )
    let endPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 1_201,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0x20, 0x21, 0x22, 0x99]
    )

    #expect(depacketizer.ingest(payload: startPacket, marker: false) == nil)
    let frame = depacketizer.ingest(payload: endPacket, marker: false)

    #expect(frame == Data([0x10, 0x11, 0x20, 0x21, 0x22]))
}

@Test("Moonlight NV reassembly does not flush frame on RTP marker without EOF flag")
func moonlightNVReassemblyIgnoresMarkerWithoutEOF() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let frameIndex: UInt32 = 77

    let startPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 1_500,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x31],
        frameHeader: moonlightFrameHeader(lastPayloadLength: moonlightCompactFrameHeaderSize + 2)
    )
    let middlePacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 1_501,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData,
        payloadBytes: [0x32, 0x33]
    )

    #expect(depacketizer.ingest(payload: startPacket, marker: false) == nil)
    #expect(depacketizer.ingest(payload: middlePacket, marker: true) == nil)
}

@Test("Moonlight NV reassembly preserves stream continuity across 24-bit packet index wrap")
func moonlightNVReassemblyHandlesPacketIndexWraparound() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let frameIndex: UInt32 = 18

    let wrapStartPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 0x00FF_FFFF,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0xA0],
        frameHeader: moonlightFrameHeader(lastPayloadLength: moonlightCompactFrameHeaderSize + 1)
    )
    let wrapEndPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 0,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0xB0, 0xFF]
    )

    #expect(depacketizer.ingest(payload: wrapStartPacket, marker: false) == nil)
    let frame = depacketizer.ingest(payload: wrapEndPacket, marker: true)

    #expect(frame == Data([0xA0, 0xB0]))
}

@Test("Moonlight NV reassembly rejects stale frame index and recovers on next expected frame")
func moonlightNVReassemblyRejectsStaleFramesAndRecovers() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()

    let firstFramePacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 10,
        frameIndex: 90,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: [0x11, 0x12],
        frameHeader: moonlightFrameHeader(lastPayloadLength: moonlightCompactFrameHeaderSize + 2)
    )
    let staleFramePacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 11,
        frameIndex: 89,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: [0x20],
        frameHeader: moonlightFrameHeader(lastPayloadLength: moonlightCompactFrameHeaderSize + 1)
    )
    let recoveredFramePacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 12,
        frameIndex: 91,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: [0x30, 0x31, 0x32],
        frameHeader: moonlightFrameHeader(lastPayloadLength: moonlightCompactFrameHeaderSize + 3)
    )

    #expect(depacketizer.ingest(payload: firstFramePacket, marker: true) == Data([0x11, 0x12]))
    #expect(depacketizer.ingest(payload: staleFramePacket, marker: true) == nil)
    #expect(depacketizer.ingest(payload: recoveredFramePacket, marker: true) == Data([0x30, 0x31, 0x32]))
}

@Test("Moonlight NV reassembly supports 44-byte frame header variant for generic codec packets")
func moonlightNVReassemblySupportsFortyFourByteFrameHeaderVariant() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let payload = Data([0xDE, 0xAD])

    let packet = makeSyntheticNVVideoPacket(
        streamPacketIndex: 3_100,
        frameIndex: 512,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: Array(payload),
        frameHeader: moonlightFrameHeader(
            lastPayloadLength: moonlightExtendedFrameHeaderSize + UInt16(payload.count),
            firstByte: 0x81,
            size: Int(moonlightExtendedFrameHeaderSize)
        )
    )

    let frame = depacketizer.ingest(payload: packet, marker: false)
    #expect(frame == payload)
}

private let nvVideoPacketFlagContainsPicData: UInt8 = 0x01
private let nvVideoPacketFlagEOF: UInt8 = 0x02
private let nvVideoPacketFlagSOF: UInt8 = 0x04
private let moonlightCompactFrameHeaderSize: UInt16 = 8
private let moonlightExtendedFrameHeaderSize: UInt16 = 44

private func makeSyntheticNVVideoPacket(
    streamPacketIndex: UInt32,
    frameIndex: UInt32,
    flags: UInt8,
    payloadBytes: [UInt8],
    frameHeader: Data? = nil
) -> Data {
    var packetPayload = Data()
    if let frameHeader {
        packetPayload.append(frameHeader)
    }
    packetPayload.append(contentsOf: payloadBytes)

    var packet = Data()
    packet.append(contentsOf: littleEndianBytes(streamPacketIndex << 8))
    packet.append(contentsOf: littleEndianBytes(frameIndex))
    packet.append(flags)
    packet.append(0x00) // extraFlags
    packet.append(0x10) // multiFecFlags
    packet.append(0x00) // multiFecBlocks (current block 0, last block 0)
    packet.append(contentsOf: littleEndianBytes(UInt32(0))) // fecInfo
    packet.append(packetPayload)
    return packet
}

private func moonlightFrameHeader(
    lastPayloadLength: UInt16,
    firstByte: UInt8 = 0x01,
    size: Int = Int(moonlightCompactFrameHeaderSize)
) -> Data {
    precondition(size >= 6, "Moonlight frame headers must be at least 6 bytes")
    var header = Data(repeating: 0, count: size)
    header[0] = firstByte
    header[3] = 0x01

    let lastPayloadLengthBytes = littleEndianBytes(lastPayloadLength)
    header[4] = lastPayloadLengthBytes[0]
    header[5] = lastPayloadLengthBytes[1]
    return header
}

private func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    let littleEndianValue = value.littleEndian
    return withUnsafeBytes(of: littleEndianValue) { Array($0) }
}
