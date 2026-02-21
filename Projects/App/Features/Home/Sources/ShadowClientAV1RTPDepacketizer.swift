import Foundation

public struct ShadowClientMoonlightNVRTPDepacketizer: Sendable {
    public enum IngestResult: Sendable {
        case noFrame
        case frame(Data)
        case droppedCorruptFrame
    }

    public enum TailTruncationStrategy: Sendable {
        case trimUsingLastPacketLength
        case passthroughForAnnexBCodecs
    }

    private static let nvVideoPacketHeaderSize = 16
    private static let streamPacketIndexMask: UInt32 = 0x00FF_FFFF
    private static let flagContainsPicData: UInt8 = 0x01
    private static let flagEOF: UInt8 = 0x02
    private static let flagSOF: UInt8 = 0x04
    private static let allowedFlags: UInt8 = flagContainsPicData | flagEOF | flagSOF

    private struct ParsedPacket {
        let frameIndex: UInt32
        let streamPacketIndex: UInt32
        let flags: UInt8
        let fecCurrentBlockNumber: UInt8
        let fecLastBlockNumber: UInt8
        let payload: Data
    }

    private struct FirstPacketHeader {
        let frameHeaderSize: Int
        let lastPacketPayloadLength: UInt16
    }

    private var currentFrame = Data()
    private var decodingFrame = false
    private var currentFrameIndex: UInt32 = 0
    private var nextFrameIndex: UInt32?
    private var lastPacketInStream: UInt32?
    private var lastPacketPayloadLength: UInt16 = 0
    private var tailTruncationStrategy: TailTruncationStrategy

    public init(tailTruncationStrategy: TailTruncationStrategy = .trimUsingLastPacketLength) {
        self.tailTruncationStrategy = tailTruncationStrategy
    }

    public mutating func configureTailTruncationStrategy(_ strategy: TailTruncationStrategy) {
        tailTruncationStrategy = strategy
        lastPacketPayloadLength = 0
    }

    public mutating func reset() {
        currentFrame.removeAll(keepingCapacity: false)
        decodingFrame = false
        currentFrameIndex = 0
        nextFrameIndex = nil
        lastPacketInStream = nil
        lastPacketPayloadLength = 0
    }

    public mutating func ingest(payload: Data, marker: Bool) -> Data? {
        switch ingestWithStatus(payload: payload, marker: marker) {
        case let .frame(frame):
            return frame
        case .noFrame, .droppedCorruptFrame:
            return nil
        }
    }

    public mutating func ingestWithStatus(payload: Data, marker: Bool) -> IngestResult {
        _ = marker

        guard let packet = parseVideoPacket(from: payload) else {
            dropFrameState()
            return .droppedCorruptFrame
        }

        let relevantFlags = packet.flags & Self.allowedFlags

        let firstPacket = isFirstPacket(
            flags: relevantFlags,
            fecBlockNumber: packet.fecCurrentBlockNumber
        )
        let lastPacket = isLastPacket(
            flags: relevantFlags,
            fecCurrentBlockNumber: packet.fecCurrentBlockNumber,
            fecLastBlockNumber: packet.fecLastBlockNumber
        )

        if let nextFrameIndex, isBefore32(packet.frameIndex, nextFrameIndex) {
            return .noFrame
        }

        if let lastPacketInStream {
            let expectedStreamPacketIndex = (lastPacketInStream &+ 1) & Self.streamPacketIndexMask
            if isBefore24(packet.streamPacketIndex, expectedStreamPacketIndex) {
                return .noFrame
            }
        }

        guard validateStreamContinuity(
            packet: packet,
            firstPacket: firstPacket,
            hasSOF: (relevantFlags & Self.flagSOF) != 0
        ) else {
            nextFrameIndex = packet.frameIndex &+ 1
            dropFrameState()
            return .droppedCorruptFrame
        }

        guard validateFrameContinuity(
            packet: packet,
            firstPacket: firstPacket
        ) else {
            nextFrameIndex = packet.frameIndex &+ 1
            dropFrameState()
            return .droppedCorruptFrame
        }

        lastPacketInStream = packet.streamPacketIndex
        let containsPictureData = (relevantFlags & Self.flagContainsPicData) != 0

        var packetPayload = packet.payload
        var frameHeaderSize = 0
        if firstPacket {
            guard let header = parseFirstPacketHeader(from: packetPayload) else {
                dropFrameState()
                return .droppedCorruptFrame
            }

            frameHeaderSize = header.frameHeaderSize
            lastPacketPayloadLength = header.lastPacketPayloadLength
            if frameHeaderSize > 0 {
                packetPayload.removeFirst(frameHeaderSize)
            }
            if tailTruncationStrategy == .passthroughForAnnexBCodecs {
                packetPayload = trimLeadingBytesUntilAnnexBStartCode(packetPayload)
            }
        }

        if lastPacket && tailTruncationStrategy == .trimUsingLastPacketLength {
            guard let truncatedPayload = truncateLastPacketPayload(
                packetPayload,
                frameHeaderSize: frameHeaderSize
            ) else {
                nextFrameIndex = packet.frameIndex &+ 1
                dropFrameState()
                return .droppedCorruptFrame
            }
            packetPayload = truncatedPayload
        }

        if containsPictureData, !packetPayload.isEmpty {
            currentFrame.append(packetPayload)
        }

        guard lastPacket else {
            return .noFrame
        }

        let frame = currentFrame
        decodingFrame = false
        currentFrameIndex = 0
        lastPacketPayloadLength = 0
        nextFrameIndex = packet.frameIndex &+ 1
        currentFrame.removeAll(keepingCapacity: true)
        guard !frame.isEmpty else {
            return .droppedCorruptFrame
        }
        return .frame(frame)
    }

    private mutating func dropFrameState() {
        decodingFrame = false
        currentFrameIndex = 0
        lastPacketPayloadLength = 0
        currentFrame.removeAll(keepingCapacity: true)
    }

    private func parseVideoPacket(from payload: Data) -> ParsedPacket? {
        guard payload.count >= Self.nvVideoPacketHeaderSize else {
            return nil
        }

        let streamPacketIndexRaw = readUInt32LE(payload, at: 0)
        let frameIndex = readUInt32LE(payload, at: 4)
        let flags = payload[8]
        let multiFecBlocks = payload[11]

        let streamPacketIndex = (streamPacketIndexRaw >> 8) & Self.streamPacketIndexMask
        let fecCurrentBlockNumber = (multiFecBlocks >> 4) & 0x03
        let fecLastBlockNumber = (multiFecBlocks >> 6) & 0x03
        let packetPayload = Data(payload.dropFirst(Self.nvVideoPacketHeaderSize))

        return ParsedPacket(
            frameIndex: frameIndex,
            streamPacketIndex: streamPacketIndex,
            flags: flags,
            fecCurrentBlockNumber: fecCurrentBlockNumber,
            fecLastBlockNumber: fecLastBlockNumber,
            payload: packetPayload
        )
    }

    private func isFirstPacket(flags: UInt8, fecBlockNumber: UInt8) -> Bool {
        let normalizedFlags = flags & ~Self.flagContainsPicData
        let isFrameStart = normalizedFlags == Self.flagSOF || normalizedFlags == (Self.flagSOF | Self.flagEOF)
        return isFrameStart && fecBlockNumber == 0
    }

    private func isLastPacket(
        flags: UInt8,
        fecCurrentBlockNumber: UInt8,
        fecLastBlockNumber: UInt8
    ) -> Bool {
        return (flags & Self.flagEOF) != 0 && fecCurrentBlockNumber == fecLastBlockNumber
    }

    private mutating func validateStreamContinuity(
        packet: ParsedPacket,
        firstPacket: Bool,
        hasSOF: Bool
    ) -> Bool {
        guard let lastPacketInStream else {
            return firstPacket
        }

        let expectedStreamPacketIndex = (lastPacketInStream &+ 1) & Self.streamPacketIndexMask
        if !hasSOF, packet.streamPacketIndex != expectedStreamPacketIndex {
            return false
        }

        return true
    }

    private mutating func validateFrameContinuity(
        packet: ParsedPacket,
        firstPacket: Bool
    ) -> Bool {
        if firstPacket {
            decodingFrame = true
            currentFrameIndex = packet.frameIndex
            currentFrame.removeAll(keepingCapacity: true)
            return true
        }

        guard decodingFrame else {
            return false
        }
        guard currentFrameIndex == packet.frameIndex else {
            return false
        }
        return true
    }

    private func parseFirstPacketHeader(from payload: Data) -> FirstPacketHeader? {
        guard payload.count >= 6 else {
            return nil
        }
        let frameHeaderSize = selectFrameHeaderSize(for: payload)
        guard frameHeaderSize <= payload.count else {
            return nil
        }
        let lastPayloadLength: UInt16
        if tailTruncationStrategy == .trimUsingLastPacketLength {
            lastPayloadLength = readUInt16LE(payload, at: 4)
        } else {
            lastPayloadLength = 0
        }
        return FirstPacketHeader(
            frameHeaderSize: frameHeaderSize,
            lastPacketPayloadLength: lastPayloadLength
        )
    }

    private func selectFrameHeaderSize(for payload: Data) -> Int {
        guard let firstByte = payload.first else {
            return 0
        }

        if firstByte == 0x01 {
            return payload.count >= 8 ? 8 : 0
        }

        if firstByte == 0x81 {
            if payload.count >= 44 {
                return 44
            }
            if payload.count >= 41 {
                return 41
            }
            if payload.count >= 24 {
                return 24
            }
            if payload.count >= 8 {
                return 8
            }
            return 0
        }

        if payload.count >= 12 {
            return 12
        }
        return payload.count >= 8 ? 8 : 0
    }

    private func truncateLastPacketPayload(
        _ payload: Data,
        frameHeaderSize: Int
    ) -> Data? {
        let payloadLength = Int(lastPacketPayloadLength)
        guard payloadLength > frameHeaderSize else {
            return nil
        }
        let expectedPayloadLength = payloadLength - frameHeaderSize
        guard expectedPayloadLength <= payload.count else {
            return nil
        }
        return Data(payload.prefix(expectedPayloadLength))
    }

    private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        return UInt32(data[offset]) |
            (UInt32(data[offset + 1]) << 8) |
            (UInt32(data[offset + 2]) << 16) |
            (UInt32(data[offset + 3]) << 24)
    }

    private func trimLeadingBytesUntilAnnexBStartCode(_ payload: Data) -> Data {
        guard !payload.isEmpty else {
            return payload
        }

        if hasAnnexBStartCode(in: payload, at: payload.startIndex) {
            return payload
        }

        let searchLimit = max(payload.startIndex, min(payload.endIndex - 3, 64))
        var index = payload.startIndex + 1
        while index <= searchLimit {
            if hasAnnexBStartCode(in: payload, at: index) {
                return Data(payload[index...])
            }
            index += 1
        }
        return payload
    }

    private func hasAnnexBStartCode(in payload: Data, at index: Int) -> Bool {
        guard index + 2 < payload.endIndex else {
            return false
        }
        if payload[index] == 0 && payload[index + 1] == 0 && payload[index + 2] == 1 {
            return true
        }
        guard index + 3 < payload.endIndex else {
            return false
        }
        return payload[index] == 0 &&
            payload[index + 1] == 0 &&
            payload[index + 2] == 0 &&
            payload[index + 3] == 1
    }

    private func isBefore24(_ lhs: UInt32, _ rhs: UInt32) -> Bool {
        let difference = (lhs &- rhs) & Self.streamPacketIndexMask
        return difference > (Self.streamPacketIndexMask / 2)
    }

    private func isBefore32(_ lhs: UInt32, _ rhs: UInt32) -> Bool {
        let difference = lhs &- rhs
        return difference > (UInt32.max / 2)
    }
}

public typealias ShadowClientAV1RTPDepacketizer = ShadowClientMoonlightNVRTPDepacketizer
