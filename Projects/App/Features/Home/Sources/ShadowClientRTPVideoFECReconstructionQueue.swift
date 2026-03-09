import Foundation

struct ShadowClientRTPVideoFECReconstructionQueue: Sendable {
    struct IngestResult: Sendable {
        var orderedDataPackets: [ShadowClientRTPPacket]
        var droppedUnrecoverableBlock: Bool

        static let empty = IngestResult(orderedDataPackets: [], droppedUnrecoverableBlock: false)

        mutating func merge(_ other: IngestResult) {
            if !other.orderedDataPackets.isEmpty {
                orderedDataPackets.append(contentsOf: other.orderedDataPackets)
            }
            droppedUnrecoverableBlock = droppedUnrecoverableBlock || other.droppedUnrecoverableBlock
        }
    }

    private struct FECMetadata: Sendable {
        let frameIndex: UInt32
        let blockNumber: UInt8
        let lastBlockNumber: UInt8
        let fecIndex: Int
        let dataShards: Int
        let parityShards: Int
        let baseSequenceNumber: UInt16

        var totalShards: Int {
            dataShards + parityShards
        }
    }

    private struct BlockState: Sendable {
        let frameIndex: UInt32
        let blockNumber: UInt8
        let lastBlockNumber: UInt8
        let dataShards: Int
        let parityShards: Int
        let baseSequenceNumber: UInt16
        let samplePayloadType: Int
        let sampleChannel: Int
        let sampleIsRTP: Bool
        let samplePayloadOffset: Int
        let fixedPacketSize: Int?
        let sampleHeader: UInt8
        let sampleTimestamp: UInt32
        let sampleSSRC: UInt32
        var packetsByFECIndex: [Int: ShadowClientRTPPacket]

        var totalShards: Int {
            dataShards + parityShards
        }

        var receivedShardCount: Int {
            packetsByFECIndex.count
        }

        mutating func insert(_ packet: ShadowClientRTPPacket, metadata: FECMetadata) {
            packetsByFECIndex[metadata.fecIndex] = packet
        }
    }

    private struct FrameState: Sendable {
        let frameIndex: UInt32
        let lastBlockNumber: UInt8
        var expectedBlockNumber: UInt8
        var completedBlocks: [UInt8: [ShadowClientRTPPacket]]
        var currentBlock: BlockState?
    }

    private var activeFrame: FrameState?
    private var lastCompletedFrameIndex: UInt32?
    private var lastDroppedFrameIndex: UInt32?
    private let fixedShardPayloadSize: Int?
    private let multiFECCapable: Bool

    init(
        fixedShardPayloadSize: Int? = Int(ShadowClientRTSPAnnounceProfile.packetSize),
        multiFECCapable: Bool = true
    ) {
        if let fixedShardPayloadSize, fixedShardPayloadSize > 0 {
            self.fixedShardPayloadSize = fixedShardPayloadSize
        } else {
            self.fixedShardPayloadSize = nil
        }
        self.multiFECCapable = multiFECCapable
    }

    mutating func ingest(_ packet: ShadowClientRTPPacket) -> IngestResult {
        guard let metadata = parseMetadata(from: packet.payload, sequenceNumber: packet.sequenceNumber) else {
            return .empty
        }

        if let lastCompletedFrameIndex,
           !Self.isBefore32(lastCompletedFrameIndex, metadata.frameIndex)
        {
            return .empty
        }

        if let droppedFrame = lastDroppedFrameIndex {
            if metadata.frameIndex == droppedFrame {
                return .empty
            }
            if Self.isBefore32(droppedFrame, metadata.frameIndex) {
                lastDroppedFrameIndex = nil
            }
        }

        guard metadata.fecIndex >= 0,
              metadata.fecIndex < metadata.totalShards,
              metadata.dataShards > 0,
              metadata.totalShards <= 255
        else {
            return .empty
        }

        if activeFrame == nil {
            return beginFrame(with: packet, metadata: metadata)
        }

        guard var frame = activeFrame else {
            return .empty
        }

        if Self.isBefore32(metadata.frameIndex, frame.frameIndex) {
            return .empty
        }

        if frame.frameIndex != metadata.frameIndex {
            var result = dropActiveFrame(unrecoverable: true)
            result.merge(beginFrame(with: packet, metadata: metadata))
            return result
        }

        if metadata.lastBlockNumber != frame.lastBlockNumber {
            return dropActiveFrame(unrecoverable: true)
        }

        if var block = frame.currentBlock {
            if metadata.blockNumber == block.blockNumber {
                guard metadata.dataShards == block.dataShards,
                      metadata.parityShards == block.parityShards,
                      metadata.baseSequenceNumber == block.baseSequenceNumber
                else {
                    return dropActiveFrame(unrecoverable: true)
                }

                block.insert(packet, metadata: metadata)
                frame.currentBlock = block
                activeFrame = frame
                return finalizeCurrentBlockIfRecoverable()
            }

            if metadata.blockNumber < block.blockNumber {
                activeFrame = frame
                return .empty
            }

            activeFrame = frame
            var result = finalizeCurrentBlockOnTransition()
            guard var transitionedFrame = activeFrame else {
                return result
            }

            if metadata.blockNumber != transitionedFrame.expectedBlockNumber {
                result.merge(dropActiveFrame(unrecoverable: true))
                return result
            }

            transitionedFrame.currentBlock = makeBlockState(from: packet, metadata: metadata)
            activeFrame = transitionedFrame
            result.merge(finalizeCurrentBlockIfRecoverable())
            return result
        }

        if metadata.blockNumber < frame.expectedBlockNumber {
            activeFrame = frame
            return .empty
        }

        guard metadata.blockNumber == frame.expectedBlockNumber else {
            activeFrame = frame
            return dropActiveFrame(unrecoverable: true)
        }

        frame.currentBlock = makeBlockState(from: packet, metadata: metadata)
        activeFrame = frame
        return finalizeCurrentBlockIfRecoverable()
    }

    mutating func flush() -> IngestResult {
        dropActiveFrame(unrecoverable: true)
    }

    private mutating func beginFrame(
        with packet: ShadowClientRTPPacket,
        metadata: FECMetadata
    ) -> IngestResult {
        guard metadata.blockNumber == 0 else {
            lastDroppedFrameIndex = metadata.frameIndex
            return IngestResult(orderedDataPackets: [], droppedUnrecoverableBlock: true)
        }

        activeFrame = FrameState(
            frameIndex: metadata.frameIndex,
            lastBlockNumber: metadata.lastBlockNumber,
            expectedBlockNumber: 0,
            completedBlocks: [:],
            currentBlock: makeBlockState(from: packet, metadata: metadata)
        )
        return finalizeCurrentBlockIfRecoverable()
    }

    private mutating func finalizeCurrentBlockIfRecoverable() -> IngestResult {
        guard var frame = activeFrame, let block = frame.currentBlock else {
            return .empty
        }

        guard block.receivedShardCount >= block.dataShards else {
            return .empty
        }

        guard let orderedDataPackets = reconstructOrderedDataPackets(from: block) else {
            if block.receivedShardCount >= block.totalShards {
                return dropActiveFrame(unrecoverable: true)
            }
            return .empty
        }

        frame.currentBlock = nil
        frame.completedBlocks[block.blockNumber] = orderedDataPackets
        frame.expectedBlockNumber = block.blockNumber &+ 1
        activeFrame = frame
        return emitCompletedFrameIfReady()
    }

    private mutating func finalizeCurrentBlockOnTransition() -> IngestResult {
        guard var frame = activeFrame, let block = frame.currentBlock else {
            return .empty
        }

        frame.currentBlock = nil
        activeFrame = frame

        guard let orderedDataPackets = reconstructOrderedDataPackets(from: block) else {
            return dropActiveFrame(unrecoverable: true)
        }

        guard var updatedFrame = activeFrame else {
            return .empty
        }
        updatedFrame.completedBlocks[block.blockNumber] = orderedDataPackets
        updatedFrame.expectedBlockNumber = block.blockNumber &+ 1
        activeFrame = updatedFrame
        return emitCompletedFrameIfReady()
    }

    private mutating func emitCompletedFrameIfReady() -> IngestResult {
        guard let frame = activeFrame,
              frame.currentBlock == nil
        else {
            return .empty
        }

        let expectedTerminalBlock = frame.lastBlockNumber &+ 1
        guard frame.expectedBlockNumber == expectedTerminalBlock else {
            return .empty
        }

        let blockCount = Int(frame.lastBlockNumber) + 1
        guard frame.completedBlocks.count >= blockCount else {
            return .empty
        }

        var orderedFramePackets: [ShadowClientRTPPacket] = []
        for blockNumber in 0 ... frame.lastBlockNumber {
            guard let blockPackets = frame.completedBlocks[blockNumber] else {
                return .empty
            }
            orderedFramePackets.append(contentsOf: blockPackets)
        }

        lastCompletedFrameIndex = frame.frameIndex
        lastDroppedFrameIndex = nil
        activeFrame = nil

        return IngestResult(
            orderedDataPackets: orderedFramePackets,
            droppedUnrecoverableBlock: false
        )
    }

    private mutating func dropActiveFrame(unrecoverable: Bool) -> IngestResult {
        guard unrecoverable else {
            return .empty
        }

        if let activeFrame {
            lastDroppedFrameIndex = activeFrame.frameIndex
        }
        activeFrame = nil
        return IngestResult(orderedDataPackets: [], droppedUnrecoverableBlock: true)
    }

    private func makeBlockState(
        from packet: ShadowClientRTPPacket,
        metadata: FECMetadata
    ) -> BlockState {
        var state = BlockState(
            frameIndex: metadata.frameIndex,
            blockNumber: metadata.blockNumber,
            lastBlockNumber: metadata.lastBlockNumber,
            dataShards: metadata.dataShards,
            parityShards: metadata.parityShards,
            baseSequenceNumber: metadata.baseSequenceNumber,
            samplePayloadType: packet.payloadType,
            sampleChannel: packet.channel,
            sampleIsRTP: packet.isRTP,
            samplePayloadOffset: packet.payloadOffset,
            fixedPacketSize: fixedShardPayloadSize.map { $0 + packet.payloadOffset },
            sampleHeader: packet.rawBytes.count > 0 ? packet.rawBytes[0] : 0,
            sampleTimestamp: Self.readUInt32BE(packet.rawBytes, at: 4) ?? 0,
            sampleSSRC: Self.readUInt32BE(packet.rawBytes, at: 8) ?? 0,
            packetsByFECIndex: [:]
        )
        state.insert(packet, metadata: metadata)
        return state
    }

    private func reconstructOrderedDataPackets(from block: BlockState) -> [ShadowClientRTPPacket]? {
        var normalizedShardBytes = Array<[UInt8]?>(repeating: nil, count: block.totalShards)
        var maxShardLength = 0
        for (index, packet) in block.packetsByFECIndex {
            guard index >= 0, index < block.totalShards else {
                continue
            }
            let bytes = Array(packet.rawBytes)
            normalizedShardBytes[index] = bytes
            if bytes.count > maxShardLength {
                maxShardLength = bytes.count
            }
        }

        let shardSize = max(maxShardLength, block.fixedPacketSize ?? 0)
        guard shardSize > 0 else {
            return nil
        }

        for index in 0 ..< block.totalShards {
            if var bytes = normalizedShardBytes[index], bytes.count < shardSize {
                bytes.append(contentsOf: repeatElement(UInt8(0), count: shardSize - bytes.count))
                normalizedShardBytes[index] = bytes
            }
        }

        let missingDataIndices = (0 ..< block.dataShards).filter { normalizedShardBytes[$0] == nil }
        if !missingDataIndices.isEmpty {
            guard let reconstructedDataShards = Self.reconstructMissingDataShards(
                shards: normalizedShardBytes,
                dataShards: block.dataShards,
                parityShards: block.parityShards,
                shardSize: shardSize
            ) else {
                return nil
            }

            for missingDataIndex in missingDataIndices {
                normalizedShardBytes[missingDataIndex] = reconstructedDataShards[missingDataIndex]
            }
        }

        var orderedPackets: [ShadowClientRTPPacket] = []
        orderedPackets.reserveCapacity(block.dataShards)

        for dataIndex in 0 ..< block.dataShards {
            if let packet = block.packetsByFECIndex[dataIndex] {
                orderedPackets.append(packet)
                continue
            }

            guard var recoveredBytes = normalizedShardBytes[dataIndex] else {
                return nil
            }

            Self.patchRecoveredPacketHeaderMinimal(
                packetBytes: &recoveredBytes,
                payloadOffset: block.samplePayloadOffset,
                frameIndex: block.frameIndex,
                blockNumber: block.blockNumber,
                lastBlockNumber: block.lastBlockNumber,
                sampleHeader: block.sampleHeader,
                sequenceNumber: block.baseSequenceNumber &+ UInt16(dataIndex),
                timestamp: block.sampleTimestamp,
                ssrc: block.sampleSSRC
            )
            let recoveredPacketBytes = Data(recoveredBytes)
            let parsedRecoveredPacket = Self.makeRecoveredPacket(
                packetBytes: recoveredPacketBytes,
                channel: block.sampleChannel,
                isRTP: block.sampleIsRTP
            )
            guard let recoveredPacket = parsedRecoveredPacket,
                  Self.isRecoveredPacketSane(
                payload: recoveredPacket.payload,
                dataShardIndex: dataIndex,
                dataShards: block.dataShards
            ) else {
                return nil
            }
            orderedPackets.append(recoveredPacket)
        }

        return orderedPackets
    }

    private static func isRecoveredPacketSane(
        payload: Data,
        dataShardIndex: Int,
        dataShards: Int
    ) -> Bool {
        guard payload.count > 8 else {
            return false
        }

        let flags = payload[8]
        let containsPicData: UInt8 = 0x01
        let eof: UInt8 = 0x02
        let sof: UInt8 = 0x04
        let knownFlags = containsPicData | eof | sof

        guard (flags & ~knownFlags) == 0 else {
            return false
        }

        if dataShardIndex == 0, (flags & sof) == 0 {
            return false
        }
        if dataShardIndex == dataShards - 1, (flags & eof) == 0 {
            return false
        }
        if dataShardIndex > 0, dataShardIndex < dataShards - 1, (flags & containsPicData) == 0 {
            return false
        }
        return true
    }

    private static func patchRecoveredPacketHeaderMinimal(
        packetBytes: inout [UInt8],
        payloadOffset: Int,
        frameIndex: UInt32,
        blockNumber: UInt8,
        lastBlockNumber: UInt8,
        sampleHeader: UInt8,
        sequenceNumber: UInt16,
        timestamp: UInt32,
        ssrc: UInt32
    ) {
        guard packetBytes.count >= payloadOffset + 12 else {
            return
        }

        packetBytes[0] = sampleHeader
        packetBytes[2] = UInt8(sequenceNumber >> 8)
        packetBytes[3] = UInt8(truncatingIfNeeded: sequenceNumber)
        writeUInt32BE(timestamp, to: &packetBytes, at: 4)
        writeUInt32BE(ssrc, to: &packetBytes, at: 8)

        // Mirror Moonlight behavior: patch frame-index and block-id fields in the
        // recovered NV packet while preserving the reconstructed payload bytes.
        writeUInt32LE(frameIndex, to: &packetBytes, at: payloadOffset + 4)
        packetBytes[payloadOffset + 11] = (blockNumber << 4) | (lastBlockNumber << 6)
    }

    private static func reconstructMissingDataShards(
        shards: [[UInt8]?],
        dataShards: Int,
        parityShards: Int,
        shardSize: Int
    ) -> [[UInt8]]? {
        let totalShards = dataShards + parityShards
        guard totalShards <= shards.count else {
            return nil
        }

        var availableIndices: [Int] = []
        availableIndices.reserveCapacity(dataShards)
        for index in 0 ..< totalShards where shards[index] != nil {
            availableIndices.append(index)
            if availableIndices.count == dataShards {
                break
            }
        }

        guard availableIndices.count == dataShards else {
            return nil
        }

        var decodeMatrix = Array(
            repeating: Array(repeating: UInt8(0), count: dataShards),
            count: dataShards
        )
        for row in 0 ..< dataShards {
            decodeMatrix[row] = coefficientRow(
                forShardIndex: availableIndices[row],
                dataShards: dataShards,
                parityShards: parityShards
            )
        }

        guard let inverseMatrix = invertMatrix(decodeMatrix) else {
            return nil
        }

        var selectedShards: [[UInt8]] = []
        selectedShards.reserveCapacity(dataShards)
        for index in availableIndices {
            guard let shard = shards[index] else {
                return nil
            }
            selectedShards.append(shard)
        }

        var reconstructedData = Array(
            repeating: [UInt8](repeating: 0, count: shardSize),
            count: dataShards
        )

        for outputIndex in 0 ..< dataShards {
            var outputShard = [UInt8](repeating: 0, count: shardSize)
            for inputIndex in 0 ..< dataShards {
                let coefficient = inverseMatrix[outputIndex][inputIndex]
                guard coefficient != 0 else {
                    continue
                }
                let sourceShard = selectedShards[inputIndex]
                if coefficient == 1 {
                    for byteIndex in 0 ..< shardSize {
                        outputShard[byteIndex] ^= sourceShard[byteIndex]
                    }
                } else {
                    for byteIndex in 0 ..< shardSize {
                        outputShard[byteIndex] ^= GF256.multiply(coefficient, sourceShard[byteIndex])
                    }
                }
            }
            reconstructedData[outputIndex] = outputShard
        }

        return reconstructedData
    }

    private static func coefficientRow(
        forShardIndex shardIndex: Int,
        dataShards: Int,
        parityShards: Int
    ) -> [UInt8] {
        if shardIndex < dataShards {
            var row = Array(repeating: UInt8(0), count: dataShards)
            row[shardIndex] = 1
            return row
        }

        let parityRow = shardIndex - dataShards
        var row = Array(repeating: UInt8(0), count: dataShards)
        for dataIndex in 0 ..< dataShards {
            let value = UInt8((parityShards + dataIndex) ^ parityRow)
            row[dataIndex] = GF256.inverse(value) ?? 0
        }
        return row
    }

    private static func invertMatrix(_ matrix: [[UInt8]]) -> [[UInt8]]? {
        let n = matrix.count
        guard n > 0, matrix.allSatisfy({ $0.count == n }) else {
            return nil
        }

        var a = matrix
        var inverse = Array(repeating: Array(repeating: UInt8(0), count: n), count: n)
        for i in 0 ..< n {
            inverse[i][i] = 1
        }

        for col in 0 ..< n {
            var pivotRow = col
            while pivotRow < n, a[pivotRow][col] == 0 {
                pivotRow += 1
            }
            guard pivotRow < n else {
                return nil
            }

            if pivotRow != col {
                a.swapAt(pivotRow, col)
                inverse.swapAt(pivotRow, col)
            }

            let pivot = a[col][col]
            guard let inversePivot = GF256.inverse(pivot) else {
                return nil
            }

            if inversePivot != 1 {
                for index in 0 ..< n {
                    a[col][index] = GF256.multiply(a[col][index], inversePivot)
                    inverse[col][index] = GF256.multiply(inverse[col][index], inversePivot)
                }
            }

            for row in 0 ..< n where row != col {
                let factor = a[row][col]
                guard factor != 0 else {
                    continue
                }
                for index in 0 ..< n {
                    a[row][index] ^= GF256.multiply(factor, a[col][index])
                    inverse[row][index] ^= GF256.multiply(factor, inverse[col][index])
                }
            }
        }

        return inverse
    }

    private func parseMetadata(
        from payload: Data,
        sequenceNumber: UInt16
    ) -> FECMetadata? {
        let bytes = payload.startIndex == 0 ? payload : Data(payload)
        guard bytes.count >= 16,
              let frameIndex = Self.readUInt32LE(bytes, at: 4),
              let fecInfo = Self.readUInt32LE(bytes, at: 12)
        else {
            return nil
        }

        let multiFecBlocks = bytes[11]
        let blockNumber: UInt8
        let lastBlockNumber: UInt8
        if multiFECCapable {
            blockNumber = (multiFecBlocks >> 4) & 0x03
            lastBlockNumber = (multiFecBlocks >> 6) & 0x03
        } else {
            blockNumber = 0
            lastBlockNumber = 0
        }
        let fecIndex = Int((fecInfo & 0x003F_F000) >> 12)
        let dataShards = Int((fecInfo & 0xFFC0_0000) >> 22)
        let fecPercent: Int = Int((fecInfo & 0x0000_0FF0) >> 4)
        let parityShards: Int
        if dataShards > 0 {
            parityShards = (dataShards * fecPercent + 99) / 100
        } else {
            parityShards = 0
        }
        let baseSequenceNumber = sequenceNumber &- UInt16(truncatingIfNeeded: fecIndex)

        return .init(
            frameIndex: frameIndex,
            blockNumber: blockNumber,
            lastBlockNumber: lastBlockNumber,
            fecIndex: fecIndex,
            dataShards: dataShards,
            parityShards: parityShards,
            baseSequenceNumber: baseSequenceNumber
        )
    }

    private static func readUInt32LE(_ bytes: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, bytes.count >= offset + 4 else {
            return nil
        }
        return UInt32(bytes[offset]) |
            (UInt32(bytes[offset + 1]) << 8) |
            (UInt32(bytes[offset + 2]) << 16) |
            (UInt32(bytes[offset + 3]) << 24)
    }

    private static func readUInt32BE(_ bytes: Data, at offset: Int) -> UInt32? {
        guard offset >= 0, bytes.count >= offset + 4 else {
            return nil
        }
        return (UInt32(bytes[offset]) << 24) |
            (UInt32(bytes[offset + 1]) << 16) |
            (UInt32(bytes[offset + 2]) << 8) |
            UInt32(bytes[offset + 3])
    }

    private static func writeUInt32LE(_ value: UInt32, to bytes: inout [UInt8], at offset: Int) {
        guard offset >= 0, bytes.count >= offset + 4 else {
            return
        }
        bytes[offset] = UInt8(truncatingIfNeeded: value)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 16)
        bytes[offset + 3] = UInt8(truncatingIfNeeded: value >> 24)
    }

    private static func writeUInt32BE(_ value: UInt32, to bytes: inout [UInt8], at offset: Int) {
        guard offset >= 0, bytes.count >= offset + 4 else {
            return
        }
        bytes[offset] = UInt8(truncatingIfNeeded: value >> 24)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value >> 16)
        bytes[offset + 2] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[offset + 3] = UInt8(truncatingIfNeeded: value)
    }

    private static func makeRecoveredPacket(
        packetBytes: Data,
        channel: Int,
        isRTP: Bool
    ) -> ShadowClientRTPPacket? {
        guard let parsed = try? ShadowClientRTPPacketPayloadParser.parse(packetBytes) else {
            return nil
        }

        return ShadowClientRTPPacket(
            isRTP: isRTP,
            channel: channel,
            sequenceNumber: parsed.sequenceNumber,
            marker: parsed.marker,
            payloadType: parsed.payloadType,
            payloadOffset: parsed.payloadOffset,
            rawBytes: parsed.rawBytes,
            payload: parsed.payload
        )
    }

    private static func isBefore32(_ lhs: UInt32, _ rhs: UInt32) -> Bool {
        Int32(bitPattern: lhs &- rhs) < 0
    }

    private enum GF256 {
        private static let primitivePolynomial: UInt16 = 0x11D

        private static let tables: (exp: [UInt8], log: [UInt8]) = {
            var expTable = Array(repeating: UInt8(0), count: 512)
            var logTable = Array(repeating: UInt8(0), count: 256)
            var value: UInt16 = 1
            for index in 0 ..< 255 {
                expTable[index] = UInt8(value)
                logTable[Int(value)] = UInt8(index)
                value <<= 1
                if (value & 0x100) != 0 {
                    value ^= primitivePolynomial
                }
            }
            for index in 255 ..< 512 {
                expTable[index] = expTable[index - 255]
            }
            return (expTable, logTable)
        }()

        static func multiply(_ lhs: UInt8, _ rhs: UInt8) -> UInt8 {
            guard lhs != 0, rhs != 0 else {
                return 0
            }
            let logLHS = Int(tables.log[Int(lhs)])
            let logRHS = Int(tables.log[Int(rhs)])
            return tables.exp[logLHS + logRHS]
        }

        static func inverse(_ value: UInt8) -> UInt8? {
            guard value != 0 else {
                return nil
            }
            let logValue = Int(tables.log[Int(value)])
            return tables.exp[255 - logValue]
        }
    }
}
