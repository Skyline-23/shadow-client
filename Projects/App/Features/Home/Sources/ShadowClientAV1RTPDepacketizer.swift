import Foundation

/// Shadow Client-owned RTP depacketizer for Sunshine's NV video packet format.
/// The type name preserves protocol compatibility terminology only.
public struct ShadowClientMoonlightNVRTPDepacketizer: Sendable {
    public struct AssembledFrameMetadata: Sendable {
        public let frameIndex: UInt32
        public let firstStreamPacketIndex: UInt32
        public let frameHeaderType: UInt8?
        public let frameType: UInt8?
        public let frameHeaderSize: Int
        public let lastPacketPayloadLength: UInt16
    }

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
        let fecShardIndex: UInt32
        let fecDataShardCount: UInt32
        let payload: Data
    }

    private struct FirstPacketHeader {
        let frameHeaderSize: Int
        let lastPacketPayloadLength: UInt16
        let headerType: UInt8?
        let frameType: UInt8?
    }

    private struct ServerAppVersion: Comparable {
        let major: Int
        let minor: Int
        let patch: Int

        static func < (lhs: ServerAppVersion, rhs: ServerAppVersion) -> Bool {
            if lhs.major != rhs.major {
                return lhs.major < rhs.major
            }
            if lhs.minor != rhs.minor {
                return lhs.minor < rhs.minor
            }
            return lhs.patch < rhs.patch
        }
    }

    private enum FrameHeaderSelectionMode {
        case heuristic
        case fixed(defaultSize: Int, headerSizeForExtendedPrefix: Int?)
    }

    private var currentFrame = Data()
    private var decodingFrame = false
    private var currentFrameIndex: UInt32 = 0
    private var nextFrameIndex: UInt32?
    private var lastPacketInStream: UInt32?
    private var lastPacketPayloadLength: UInt16 = 0
    private var tailTruncationStrategy: TailTruncationStrategy
    private var frameHeaderSelectionMode: FrameHeaderSelectionMode = .heuristic
    private var currentFrameMetadata: AssembledFrameMetadata?
    private var lastCompletedFrameMetadata: AssembledFrameMetadata?

    public init(tailTruncationStrategy: TailTruncationStrategy = .trimUsingLastPacketLength) {
        self.tailTruncationStrategy = tailTruncationStrategy
    }

    public mutating func configureTailTruncationStrategy(_ strategy: TailTruncationStrategy) {
        tailTruncationStrategy = strategy
        lastPacketPayloadLength = 0
    }

    public mutating func configureFrameHeaderProfile(appVersion: String?) {
        frameHeaderSelectionMode = Self.frameHeaderSelectionMode(for: appVersion)
    }

    public mutating func reset() {
        currentFrame.removeAll(keepingCapacity: false)
        decodingFrame = false
        currentFrameIndex = 0
        nextFrameIndex = nil
        lastPacketInStream = nil
        lastPacketPayloadLength = 0
        currentFrameMetadata = nil
        lastCompletedFrameMetadata = nil
    }

    public mutating func consumeLastCompletedFrameMetadata() -> AssembledFrameMetadata? {
        let metadata = lastCompletedFrameMetadata
        lastCompletedFrameMetadata = nil
        return metadata
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

        // Moonlight consumes only data shards in the depacketizer stage.
        // FEC parity shards are handled by a dedicated FEC queue, so they must not
        // participate in AU assembly here. However, stream packet indices still
        // advance across parity shards, so keep the continuity watermark in sync.
        if packet.fecDataShardCount > 0, packet.fecShardIndex >= packet.fecDataShardCount {
            advanceStreamContinuityWatermark(for: packet.streamPacketIndex)
            return .noFrame
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
            currentFrameMetadata = AssembledFrameMetadata(
                frameIndex: packet.frameIndex,
                firstStreamPacketIndex: packet.streamPacketIndex,
                frameHeaderType: header.headerType,
                frameType: header.frameType,
                frameHeaderSize: frameHeaderSize,
                lastPacketPayloadLength: lastPacketPayloadLength
            )
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
        let completedMetadata = currentFrameMetadata
        decodingFrame = false
        currentFrameIndex = 0
        lastPacketPayloadLength = 0
        nextFrameIndex = packet.frameIndex &+ 1
        currentFrameMetadata = nil
        currentFrame.removeAll(keepingCapacity: true)
        guard !frame.isEmpty else {
            return .droppedCorruptFrame
        }
        lastCompletedFrameMetadata = completedMetadata
        return .frame(frame)
    }

    private mutating func dropFrameState() {
        decodingFrame = false
        currentFrameIndex = 0
        lastPacketPayloadLength = 0
        currentFrameMetadata = nil
        currentFrame.removeAll(keepingCapacity: true)
    }

    private mutating func advanceStreamContinuityWatermark(for streamPacketIndex: UInt32) {
        guard let lastPacketInStream else {
            lastPacketInStream = streamPacketIndex
            return
        }

        let expectedStreamPacketIndex = (lastPacketInStream &+ 1) & Self.streamPacketIndexMask
        if isBefore24(streamPacketIndex, expectedStreamPacketIndex) {
            return
        }
        self.lastPacketInStream = streamPacketIndex
    }

    private func parseVideoPacket(from payload: Data) -> ParsedPacket? {
        guard payload.count >= Self.nvVideoPacketHeaderSize else {
            return nil
        }

        guard let streamPacketIndexRaw = readUInt32LE(payload, at: 0),
              let frameIndex = readUInt32LE(payload, at: 4)
        else {
            return nil
        }
        let flagsIndex = payload.startIndex + 8
        let multiFecBlocksIndex = payload.startIndex + 11
        let flags = payload[flagsIndex]
        let multiFecBlocks = payload[multiFecBlocksIndex]
        let fecInfo = readUInt32LE(payload, at: 12) ?? 0

        let streamPacketIndex = (streamPacketIndexRaw >> 8) & Self.streamPacketIndexMask
        let fecCurrentBlockNumber = (multiFecBlocks >> 4) & 0x03
        let fecLastBlockNumber = (multiFecBlocks >> 6) & 0x03
        let fecShardIndex = (fecInfo & 0x003F_F000) >> 12
        let fecDataShardCount = (fecInfo & 0xFFC0_0000) >> 22
        let packetPayload = payload.dropFirst(Self.nvVideoPacketHeaderSize)

        return ParsedPacket(
            frameIndex: frameIndex,
            streamPacketIndex: streamPacketIndex,
            flags: flags,
            fecCurrentBlockNumber: fecCurrentBlockNumber,
            fecLastBlockNumber: fecLastBlockNumber,
            fecShardIndex: fecShardIndex,
            fecDataShardCount: fecDataShardCount,
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
        let headerType = payload.first
        let frameType: UInt8?
        if payload.count >= 4 {
            frameType = payload[payload.startIndex + 3]
        } else {
            frameType = nil
        }
        let lastPayloadLength: UInt16
        if tailTruncationStrategy == .trimUsingLastPacketLength {
            guard let parsedLength = readUInt16LE(payload, at: 4) else {
                return nil
            }
            lastPayloadLength = parsedLength
        } else {
            lastPayloadLength = 0
        }
        return FirstPacketHeader(
            frameHeaderSize: frameHeaderSize,
            lastPacketPayloadLength: lastPayloadLength,
            headerType: headerType,
            frameType: frameType
        )
    }

    private func selectFrameHeaderSize(for payload: Data) -> Int {
        switch frameHeaderSelectionMode {
        case .heuristic:
            return selectFrameHeaderSizeUsingHeuristics(for: payload)
        case let .fixed(defaultSize, headerSizeForExtendedPrefix):
            if let headerSizeForExtendedPrefix {
                guard let firstByte = payload.first else {
                    return 0
                }
                if firstByte == 0x01 {
                    return payload.count >= 8 ? 8 : 0
                }
                if firstByte == 0x81 {
                    return payload.count >= headerSizeForExtendedPrefix ? headerSizeForExtendedPrefix : 0
                }
            }
            return payload.count >= defaultSize ? defaultSize : 0
        }
    }

    private func selectFrameHeaderSizeUsingHeuristics(for payload: Data) -> Int {
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

    private static func frameHeaderSelectionMode(for appVersion: String?) -> FrameHeaderSelectionMode {
        guard let version = parseServerAppVersion(appVersion), version.major >= 5 else {
            return .heuristic
        }

        if version >= .init(major: 7, minor: 1, patch: 450) {
            return .fixed(defaultSize: 8, headerSizeForExtendedPrefix: 44)
        }
        if version >= .init(major: 7, minor: 1, patch: 446) {
            return .fixed(defaultSize: 8, headerSizeForExtendedPrefix: 41)
        }
        if version >= .init(major: 7, minor: 1, patch: 415) {
            return .fixed(defaultSize: 8, headerSizeForExtendedPrefix: 24)
        }
        if version >= .init(major: 7, minor: 1, patch: 350) {
            return .fixed(defaultSize: 8, headerSizeForExtendedPrefix: nil)
        }
        if version >= .init(major: 7, minor: 1, patch: 320) {
            return .fixed(defaultSize: 12, headerSizeForExtendedPrefix: nil)
        }
        return .fixed(defaultSize: 8, headerSizeForExtendedPrefix: nil)
    }

    private static func parseServerAppVersion(_ raw: String?) -> ServerAppVersion? {
        guard let raw else {
            return nil
        }
        let numericComponents = raw.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numericComponents.count >= 3 else {
            return nil
        }
        return .init(
            major: numericComponents[0],
            minor: numericComponents[1],
            patch: numericComponents[2]
        )
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
        return payload.prefix(expectedPayloadLength)
    }

    private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 1 < data.count else {
            return nil
        }
        let baseIndex = data.startIndex + offset
        return UInt16(data[baseIndex]) | (UInt16(data[baseIndex + 1]) << 8)
    }

    private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 3 < data.count else {
            return nil
        }
        let baseIndex = data.startIndex + offset
        return UInt32(data[baseIndex]) |
            (UInt32(data[baseIndex + 1]) << 8) |
            (UInt32(data[baseIndex + 2]) << 16) |
            (UInt32(data[baseIndex + 3]) << 24)
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
                return payload[index...]
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
