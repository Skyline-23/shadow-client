import Foundation

actor ShadowClientRealtimeAudioMoonlightRSFECQueue {
    private struct FECBlock: Sendable {
        let baseSequenceNumber: UInt16
        var baseTimestamp: UInt32?
        let primaryPayloadType: Int
        var blockSize: Int?
        var dataShards: [Data?]
        var dataTimestamps: [UInt32?]
        var parityShards: [Data?]
        var lastUpdatedUptime: TimeInterval

        init(
            baseSequenceNumber: UInt16,
            primaryPayloadType: Int,
            now: TimeInterval
        ) {
            self.baseSequenceNumber = baseSequenceNumber
            self.primaryPayloadType = primaryPayloadType
            baseTimestamp = nil
            blockSize = nil
            dataShards = Array(repeating: nil, count: Self.dataShardCount)
            dataTimestamps = Array(repeating: nil, count: Self.dataShardCount)
            parityShards = Array(repeating: nil, count: Self.parityShardCount)
            lastUpdatedUptime = now
        }

        private static let dataShardCount = 4
        private static let parityShardCount = 2
    }

    private struct FECShardHeader: Sendable {
        let shardIndex: Int
        let primaryPayloadType: Int
        let baseSequenceNumber: UInt16
        let baseTimestamp: UInt32
        let payload: Data
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

        static func divide(_ numerator: UInt8, by denominator: UInt8) -> UInt8? {
            guard denominator != 0 else {
                return nil
            }
            guard numerator != 0 else {
                return 0
            }
            let logNumerator = Int(tables.log[Int(numerator)])
            let logDenominator = Int(tables.log[Int(denominator)])
            var index = logNumerator - logDenominator
            if index < 0 {
                index += 255
            }
            return tables.exp[index]
        }
    }

    private static let dataShardCount = 4
    private static let parityShardCount = 2
    private static let totalShardCount = dataShardCount + parityShardCount
    private static let fecHeaderLength = 12
    private static let defaultTimestampStep: UInt32 = 5
    private static let maxTrackedBlocks = 96
    private static let maxRecoveredPayloads = 256
    private static let parityCoefficients: [[UInt8]] = [
        [0x77, 0x40, 0x38, 0x0E],
        [0xC7, 0xA7, 0x0D, 0x6C],
    ]

    private var blocksByBaseSequence: [UInt16: FECBlock] = [:]
    private var recoveredPayloadsBySequence: [UInt16: Data] = [:]
    private var lastObservedTimestampStep: UInt32 = defaultTimestampStep
    private var latestObservedBaseSequence: UInt16?

    func ingest(
        packetSequenceNumber: UInt16,
        packetTimestamp: UInt32,
        payloadType: Int,
        payload: Data,
        expectedPrimaryPayloadType: Int,
        wrapperPayloadType: Int
    ) {
        if payloadType == expectedPrimaryPayloadType {
            ingestDataPacket(
                packetSequenceNumber: packetSequenceNumber,
                packetTimestamp: packetTimestamp,
                payload: payload,
                expectedPrimaryPayloadType: expectedPrimaryPayloadType
            )
            return
        }

        guard payloadType == wrapperPayloadType,
              let shardHeader = Self.parseFECShardHeader(payload),
              shardHeader.primaryPayloadType == expectedPrimaryPayloadType
        else {
            return
        }

        ingestParityPacket(
            packetSequenceNumber: packetSequenceNumber,
            shardHeader: shardHeader
        )
    }

    func takeRecoveredPayload(sequenceNumber: UInt16) -> Data? {
        recoveredPayloadsBySequence.removeValue(forKey: sequenceNumber)
    }

    private func ingestDataPacket(
        packetSequenceNumber: UInt16,
        packetTimestamp: UInt32,
        payload: Data,
        expectedPrimaryPayloadType: Int
    ) {
        let shardOffset = Int(packetSequenceNumber % UInt16(Self.dataShardCount))
        let baseSequenceNumber = packetSequenceNumber &- UInt16(shardOffset)
        let now = ProcessInfo.processInfo.systemUptime

        var block = blocksByBaseSequence[baseSequenceNumber] ?? FECBlock(
            baseSequenceNumber: baseSequenceNumber,
            primaryPayloadType: expectedPrimaryPayloadType,
            now: now
        )

        guard block.primaryPayloadType == expectedPrimaryPayloadType else {
            blocksByBaseSequence.removeValue(forKey: baseSequenceNumber)
            return
        }

        guard matchOrSetBlockSize(payload.count, block: &block) else {
            blocksByBaseSequence.removeValue(forKey: baseSequenceNumber)
            return
        }

        block.dataShards[shardOffset] = payload
        block.dataTimestamps[shardOffset] = packetTimestamp
        if block.baseTimestamp == nil {
            if shardOffset == 0 {
                block.baseTimestamp = packetTimestamp
            } else {
                block.baseTimestamp = packetTimestamp &- UInt32(shardOffset) * lastObservedTimestampStep
            }
        }
        updateTimestampStep(using: &block, insertedShardIndex: shardOffset)
        recoveredPayloadsBySequence.removeValue(forKey: packetSequenceNumber)
        block.lastUpdatedUptime = now
        recoverMissingDataIfPossible(in: &block)
        blocksByBaseSequence[baseSequenceNumber] = block
        latestObservedBaseSequence = baseSequenceNumber
        trimState(anchorBaseSequence: baseSequenceNumber)
    }

    private func ingestParityPacket(
        packetSequenceNumber: UInt16,
        shardHeader: FECShardHeader
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        let baseSequenceNumber = shardHeader.baseSequenceNumber
        var block = blocksByBaseSequence[baseSequenceNumber] ?? FECBlock(
            baseSequenceNumber: baseSequenceNumber,
            primaryPayloadType: shardHeader.primaryPayloadType,
            now: now
        )

        guard block.primaryPayloadType == shardHeader.primaryPayloadType else {
            blocksByBaseSequence.removeValue(forKey: baseSequenceNumber)
            return
        }

        guard baseSequenceNumber % UInt16(Self.dataShardCount) == 0,
              shardHeader.shardIndex < Self.parityShardCount,
              matchOrSetBlockSize(shardHeader.payload.count, block: &block)
        else {
            blocksByBaseSequence.removeValue(forKey: baseSequenceNumber)
            return
        }

        block.baseTimestamp = shardHeader.baseTimestamp
        block.parityShards[shardHeader.shardIndex] = shardHeader.payload
        block.lastUpdatedUptime = now
        recoverMissingDataIfPossible(in: &block)
        blocksByBaseSequence[baseSequenceNumber] = block
        latestObservedBaseSequence = baseSequenceNumber
        trimState(anchorBaseSequence: packetSequenceNumber)
    }

    private func matchOrSetBlockSize(
        _ shardSize: Int,
        block: inout FECBlock
    ) -> Bool {
        guard shardSize > 0 else {
            return false
        }
        if let currentSize = block.blockSize {
            return currentSize == shardSize
        }
        block.blockSize = shardSize
        return true
    }

    private func recoverMissingDataIfPossible(in block: inout FECBlock) {
        guard let blockSize = block.blockSize else {
            return
        }

        let dataShardCount = block.dataShards.lazy.compactMap { $0 }.count
        let parityShardCount = block.parityShards.lazy.compactMap { $0 }.count
        guard dataShardCount + parityShardCount >= Self.dataShardCount else {
            return
        }

        let missingIndices = (0 ..< Self.dataShardCount).filter {
            block.dataShards[$0] == nil
        }
        guard !missingIndices.isEmpty,
              missingIndices.count <= Self.parityShardCount
        else {
            return
        }

        var recoveredByIndex: [Int: Data] = [:]

        if missingIndices.count == 1 {
            let missingIndex = missingIndices[0]
            guard let paritySelection = availableParityShard(from: block) else {
                return
            }
            guard let recovered = recoverSingleMissingShard(
                missingIndex: missingIndex,
                parityRow: paritySelection.rowIndex,
                parityShard: paritySelection.shard,
                dataShards: block.dataShards,
                blockSize: blockSize
            ) else {
                return
            }
            recoveredByIndex[missingIndex] = recovered
        } else if missingIndices.count == 2 {
            guard let parityShard0 = block.parityShards[0],
                  let parityShard1 = block.parityShards[1]
            else {
                return
            }
            guard let recovered = recoverTwoMissingShards(
                missingIndices: missingIndices,
                parityShard0: parityShard0,
                parityShard1: parityShard1,
                dataShards: block.dataShards,
                blockSize: blockSize
            ) else {
                return
            }
            recoveredByIndex.merge(recovered) { _, newValue in
                newValue
            }
        }

        guard !recoveredByIndex.isEmpty else {
            return
        }

        for (shardIndex, recoveredPayload) in recoveredByIndex {
            block.dataShards[shardIndex] = recoveredPayload
            if block.dataTimestamps[shardIndex] == nil {
                block.dataTimestamps[shardIndex] = estimatedTimestamp(
                    for: block,
                    shardIndex: shardIndex
                )
            }
            let sequenceNumber = block.baseSequenceNumber &+ UInt16(shardIndex)
            recoveredPayloadsBySequence[sequenceNumber] = recoveredPayload
        }
    }

    private func availableParityShard(
        from block: FECBlock
    ) -> (rowIndex: Int, shard: Data)? {
        for rowIndex in 0 ..< Self.parityShardCount {
            if let shard = block.parityShards[rowIndex] {
                return (rowIndex, shard)
            }
        }
        return nil
    }

    private func recoverSingleMissingShard(
        missingIndex: Int,
        parityRow: Int,
        parityShard: Data,
        dataShards: [Data?],
        blockSize: Int
    ) -> Data? {
        guard parityShard.count == blockSize else {
            return nil
        }

        let rowCoefficients = Self.parityCoefficients[parityRow]
        let divisor = rowCoefficients[missingIndex]
        guard divisor != 0 else {
            return nil
        }

        let parityBytes = [UInt8](parityShard)
        var recoveredBytes = Array(repeating: UInt8(0), count: blockSize)
        let knownDataBytes = dataShards.map { shard in
            shard.map { [UInt8]($0) }
        }

        for byteOffset in 0 ..< blockSize {
            var rhs = parityBytes[byteOffset]
            for shardIndex in 0 ..< Self.dataShardCount where shardIndex != missingIndex {
                guard let shardBytes = knownDataBytes[shardIndex], shardBytes.count == blockSize else {
                    continue
                }
                let coefficient = rowCoefficients[shardIndex]
                rhs ^= GF256.multiply(coefficient, shardBytes[byteOffset])
            }
            guard let recovered = GF256.divide(rhs, by: divisor) else {
                return nil
            }
            recoveredBytes[byteOffset] = recovered
        }

        return Data(recoveredBytes)
    }

    private func recoverTwoMissingShards(
        missingIndices: [Int],
        parityShard0: Data,
        parityShard1: Data,
        dataShards: [Data?],
        blockSize: Int
    ) -> [Int: Data]? {
        guard missingIndices.count == 2,
              parityShard0.count == blockSize,
              parityShard1.count == blockSize
        else {
            return nil
        }

        let firstMissing = missingIndices[0]
        let secondMissing = missingIndices[1]

        let c00 = Self.parityCoefficients[0][firstMissing]
        let c01 = Self.parityCoefficients[0][secondMissing]
        let c10 = Self.parityCoefficients[1][firstMissing]
        let c11 = Self.parityCoefficients[1][secondMissing]

        let determinant = GF256.multiply(c00, c11) ^ GF256.multiply(c10, c01)
        guard determinant != 0 else {
            return nil
        }

        let parityBytes0 = [UInt8](parityShard0)
        let parityBytes1 = [UInt8](parityShard1)
        let knownDataBytes = dataShards.map { shard in
            shard.map { [UInt8]($0) }
        }

        var recoveredFirst = Array(repeating: UInt8(0), count: blockSize)
        var recoveredSecond = Array(repeating: UInt8(0), count: blockSize)

        for byteOffset in 0 ..< blockSize {
            var rhs0 = parityBytes0[byteOffset]
            var rhs1 = parityBytes1[byteOffset]

            for shardIndex in 0 ..< Self.dataShardCount {
                guard shardIndex != firstMissing,
                      shardIndex != secondMissing,
                      let shardBytes = knownDataBytes[shardIndex],
                      shardBytes.count == blockSize
                else {
                    continue
                }

                rhs0 ^= GF256.multiply(
                    Self.parityCoefficients[0][shardIndex],
                    shardBytes[byteOffset]
                )
                rhs1 ^= GF256.multiply(
                    Self.parityCoefficients[1][shardIndex],
                    shardBytes[byteOffset]
                )
            }

            let numeratorFirst = GF256.multiply(rhs0, c11) ^ GF256.multiply(rhs1, c01)
            let numeratorSecond = GF256.multiply(c00, rhs1) ^ GF256.multiply(c10, rhs0)

            guard let recoveredByteFirst = GF256.divide(numeratorFirst, by: determinant),
                  let recoveredByteSecond = GF256.divide(numeratorSecond, by: determinant)
            else {
                return nil
            }

            recoveredFirst[byteOffset] = recoveredByteFirst
            recoveredSecond[byteOffset] = recoveredByteSecond
        }

        return [
            firstMissing: Data(recoveredFirst),
            secondMissing: Data(recoveredSecond),
        ]
    }

    private func estimatedTimestamp(
        for block: FECBlock,
        shardIndex: Int
    ) -> UInt32 {
        if let existingTimestamp = block.dataTimestamps[shardIndex] {
            return existingTimestamp
        }
        let step = max(1, lastObservedTimestampStep)
        if let baseTimestamp = block.baseTimestamp {
            return baseTimestamp &+ UInt32(shardIndex) * step
        }

        if let known = nearestKnownTimestamp(for: block, shardIndex: shardIndex) {
            if known.shardIndex < shardIndex {
                return known.timestamp &+ UInt32(shardIndex - known.shardIndex) * step
            }
            return known.timestamp &- UInt32(known.shardIndex - shardIndex) * step
        }
        return UInt32(shardIndex) * step
    }

    private func nearestKnownTimestamp(
        for block: FECBlock,
        shardIndex: Int
    ) -> (shardIndex: Int, timestamp: UInt32)? {
        var bestCandidate: (shardIndex: Int, timestamp: UInt32, distance: Int)?
        for index in 0 ..< Self.dataShardCount {
            guard let timestamp = block.dataTimestamps[index] else {
                continue
            }
            let distance = abs(index - shardIndex)
            if let currentBest = bestCandidate {
                if distance < currentBest.distance {
                    bestCandidate = (index, timestamp, distance)
                }
            } else {
                bestCandidate = (index, timestamp, distance)
            }
        }
        if let bestCandidate {
            return (bestCandidate.shardIndex, bestCandidate.timestamp)
        }
        return nil
    }

    private func updateTimestampStep(
        using block: inout FECBlock,
        insertedShardIndex: Int
    ) {
        guard let insertedTimestamp = block.dataTimestamps[insertedShardIndex] else {
            return
        }

        var candidateStep: UInt32?

        if let baseTimestamp = block.baseTimestamp,
           insertedShardIndex > 0
        {
            let delta = timestampDistanceForward(from: baseTimestamp, to: insertedTimestamp)
            let denominator = max(1, insertedShardIndex)
            let step = max(1, delta / UInt32(denominator))
            candidateStep = step
        }

        for index in 0 ..< Self.dataShardCount where index != insertedShardIndex {
            guard let knownTimestamp = block.dataTimestamps[index] else {
                continue
            }
            let sequenceGap = abs(insertedShardIndex - index)
            guard sequenceGap > 0 else {
                continue
            }
            let lowerTimestamp: UInt32
            let upperTimestamp: UInt32
            if index < insertedShardIndex {
                lowerTimestamp = knownTimestamp
                upperTimestamp = insertedTimestamp
            } else {
                lowerTimestamp = insertedTimestamp
                upperTimestamp = knownTimestamp
            }
            let delta = timestampDistanceForward(from: lowerTimestamp, to: upperTimestamp)
            let step = max(1, delta / UInt32(sequenceGap))
            if let existingCandidate = candidateStep {
                candidateStep = min(existingCandidate, step)
            } else {
                candidateStep = step
            }
        }

        if let candidateStep {
            lastObservedTimestampStep = max(1, candidateStep)
        }
    }

    private func trimState(anchorBaseSequence: UInt16) {
        if blocksByBaseSequence.count > Self.maxTrackedBlocks {
            let orderedBlockKeys = blocksByBaseSequence.keys.sorted {
                let lhsDistance = sequenceDistanceForward(from: $0, to: anchorBaseSequence)
                let rhsDistance = sequenceDistanceForward(from: $1, to: anchorBaseSequence)
                return lhsDistance < rhsDistance
            }
            let retained = Set(orderedBlockKeys.prefix(Self.maxTrackedBlocks))
            blocksByBaseSequence = blocksByBaseSequence.filter { retained.contains($0.key) }
        }

        if recoveredPayloadsBySequence.count > Self.maxRecoveredPayloads {
            let orderedRecoveredKeys = recoveredPayloadsBySequence.keys.sorted {
                let lhsDistance = sequenceDistanceForward(from: $0, to: anchorBaseSequence)
                let rhsDistance = sequenceDistanceForward(from: $1, to: anchorBaseSequence)
                return lhsDistance < rhsDistance
            }
            let retained = Set(orderedRecoveredKeys.prefix(Self.maxRecoveredPayloads))
            recoveredPayloadsBySequence = recoveredPayloadsBySequence.filter {
                retained.contains($0.key)
            }
        }
    }

    private static func parseFECShardHeader(_ payload: Data) -> FECShardHeader? {
        guard payload.count >= fecHeaderLength else {
            return nil
        }

        let shardIndex = Int(payload[payload.startIndex])
        guard shardIndex >= 0, shardIndex < parityShardCount else {
            return nil
        }

        let primaryPayloadType = Int(payload[payload.startIndex + 1] & 0x7F)
        guard (96 ... 127).contains(primaryPayloadType) else {
            return nil
        }

        let baseSequenceNumber = (UInt16(payload[payload.startIndex + 2]) << 8) |
            UInt16(payload[payload.startIndex + 3])
        let baseTimestamp = (UInt32(payload[payload.startIndex + 4]) << 24) |
            (UInt32(payload[payload.startIndex + 5]) << 16) |
            (UInt32(payload[payload.startIndex + 6]) << 8) |
            UInt32(payload[payload.startIndex + 7])

        guard payload.count > fecHeaderLength else {
            return nil
        }

        let shardPayload = Data(payload[payload.index(payload.startIndex, offsetBy: fecHeaderLength) ..< payload.endIndex])
        guard !shardPayload.isEmpty else {
            return nil
        }

        return FECShardHeader(
            shardIndex: shardIndex,
            primaryPayloadType: primaryPayloadType,
            baseSequenceNumber: baseSequenceNumber,
            baseTimestamp: baseTimestamp,
            payload: shardPayload
        )
    }

    private func sequenceDistanceForward(
        from: UInt16,
        to: UInt16
    ) -> UInt16 {
        to &- from
    }

    private func timestampDistanceForward(
        from: UInt32,
        to: UInt32
    ) -> UInt32 {
        to &- from
    }
}
