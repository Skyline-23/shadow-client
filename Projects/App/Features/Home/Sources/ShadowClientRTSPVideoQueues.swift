import Foundation

actor ShadowClientVideoDecodeQueue {
    private let capacity: Int
    private var bufferedUnits: [ShadowClientRealtimeRTSPSessionRuntime.VideoAccessUnit?]
    private var headIndex = 0
    private var bufferedCount = 0
    private var closed = false
    private var waitingContinuations: [CheckedContinuation<ShadowClientRealtimeRTSPSessionRuntime.VideoAccessUnit?, Never>] = []

    init(capacity: Int) {
        self.capacity = max(2, capacity)
        self.bufferedUnits = Array(repeating: nil, count: self.capacity)
    }

    func enqueue(_ accessUnit: ShadowClientRealtimeRTSPSessionRuntime.VideoAccessUnit) -> Bool {
        guard !closed else {
            return false
        }

        if !waitingContinuations.isEmpty {
            let continuation = waitingContinuations.removeFirst()
            continuation.resume(returning: accessUnit)
            return false
        }

        var droppedOldest = false
        if bufferedCount >= capacity {
            bufferedUnits[headIndex] = nil
            headIndex = (headIndex + 1) % capacity
            bufferedCount -= 1
            droppedOldest = true
        }
        let tailIndex = (headIndex + bufferedCount) % capacity
        bufferedUnits[tailIndex] = accessUnit
        bufferedCount += 1
        return droppedOldest
    }

    func next() async -> ShadowClientRealtimeRTSPSessionRuntime.VideoAccessUnit? {
        if bufferedCount > 0 {
            let unit = bufferedUnits[headIndex]
            bufferedUnits[headIndex] = nil
            headIndex = (headIndex + 1) % capacity
            bufferedCount -= 1
            return unit
        }
        if closed {
            return nil
        }

        return await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }

    func nextWithBackpressureTrim(
        maxBufferedUnits: Int,
        allowTrim: Bool = true
    ) async -> (
        unit: ShadowClientRealtimeRTSPSessionRuntime.VideoAccessUnit?,
        droppedCount: Int,
        remainingBufferedCount: Int
    ) {
        let boundedMaxBufferedUnits = max(1, min(maxBufferedUnits, capacity))
        var droppedCount = 0
        if allowTrim, bufferedCount > boundedMaxBufferedUnits {
            droppedCount = bufferedCount - boundedMaxBufferedUnits
            var dropsRemaining = droppedCount
            while dropsRemaining > 0 {
                bufferedUnits[headIndex] = nil
                headIndex = (headIndex + 1) % capacity
                bufferedCount -= 1
                dropsRemaining -= 1
            }
        }

        if bufferedCount > 0 {
            let unit = bufferedUnits[headIndex]
            bufferedUnits[headIndex] = nil
            headIndex = (headIndex + 1) % capacity
            bufferedCount -= 1
            return (unit, droppedCount, bufferedCount)
        }
        if closed {
            return (nil, droppedCount, 0)
        }

        let unit = await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
        return (unit, droppedCount, 0)
    }

    func close() {
        guard !closed else {
            return
        }
        closed = true
        bufferedUnits = Array(repeating: nil, count: capacity)
        headIndex = 0
        bufferedCount = 0
        let continuations = waitingContinuations
        waitingContinuations.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume(returning: nil)
        }
    }

    func removeAll() {
        bufferedUnits = Array(repeating: nil, count: capacity)
        headIndex = 0
        bufferedCount = 0
    }

    func bufferedUnitCount() -> Int {
        bufferedCount
    }

    func trimToMostRecent(maxBufferedUnits: Int) -> Int {
        let boundedMaxBufferedUnits = max(1, min(maxBufferedUnits, capacity))
        guard bufferedCount > boundedMaxBufferedUnits else {
            return 0
        }

        let droppedCount = bufferedCount - boundedMaxBufferedUnits
        var dropsRemaining = droppedCount
        while dropsRemaining > 0 {
            bufferedUnits[headIndex] = nil
            headIndex = (headIndex + 1) % capacity
            bufferedCount -= 1
            dropsRemaining -= 1
        }
        return droppedCount
    }
}

actor ShadowClientVideoPacketQueue {
    private static let dropLogInterval = 120

    private let capacity: Int
    private let pressureSignalInterval: Int
    private let maxIngressSheddingBurstPackets: Int
    private var bufferedPackets: [ShadowClientRealtimeRTSPSessionRuntime.VideoTransportPacket?]
    private var headIndex = 0
    private var bufferedCount = 0
    private var closed = false
    private var droppedOldestCount = 0
    private var droppedSinceLastPressureSignal = 0
    private var droppingIncomingUntilFrameBoundary = false
    private var droppedIncomingPacketCount = 0
    private var waitingContinuations: [CheckedContinuation<ShadowClientRealtimeRTSPSessionRuntime.VideoTransportPacket?, Never>] = []

    init(
        capacity: Int,
        pressureSignalInterval: Int = ShadowClientRealtimeSessionDefaults.videoReceiveQueuePressureSignalInterval,
        maxIngressSheddingBurstPackets: Int = ShadowClientRealtimeSessionDefaults.videoReceiveQueueIngressSheddingMaximumBurstPackets
    ) {
        self.capacity = max(4, capacity)
        self.pressureSignalInterval = max(1, pressureSignalInterval)
        self.maxIngressSheddingBurstPackets = max(1, maxIngressSheddingBurstPackets)
        self.bufferedPackets = Array(repeating: nil, count: self.capacity)
    }

    struct EnqueueResult: Sendable {
        let droppedOldest: Bool
        let droppedCountForLog: Int?
        let droppedCountForPressureSignal: Int?
        let droppedIncomingCountForLog: Int?
    }

    func enqueue(_ packet: ShadowClientRealtimeRTSPSessionRuntime.VideoTransportPacket) -> EnqueueResult {
        guard !closed else {
            return .init(
                droppedOldest: false,
                droppedCountForLog: nil,
                droppedCountForPressureSignal: nil,
                droppedIncomingCountForLog: nil
            )
        }

        var ingressSheddingResumeCountForLog: Int?
        if droppingIncomingUntilFrameBoundary {
            droppedIncomingPacketCount += 1
            let shouldLogDroppedIncomingCount = droppedIncomingPacketCount.isMultiple(
                of: ShadowClientRealtimeSessionDefaults.videoReceiveQueueIngressDropLogInterval
            )
            let droppedIncomingCountForLog = shouldLogDroppedIncomingCount
                ? droppedIncomingPacketCount
                : nil
            let reachedFrameBoundary = ShadowClientRealtimeRTSPSessionRuntime.isLikelyVideoFrameBoundary(
                marker: packet.marker,
                payload: packet.payload
            )
            let reachedIngressSheddingBurstLimit =
                droppedIncomingPacketCount >= maxIngressSheddingBurstPackets
            if reachedFrameBoundary || reachedIngressSheddingBurstLimit {
                if reachedIngressSheddingBurstLimit {
                    ingressSheddingResumeCountForLog = droppedIncomingPacketCount
                }
                droppingIncomingUntilFrameBoundary = false
                droppedIncomingPacketCount = 0
                if !reachedIngressSheddingBurstLimit {
                    return .init(
                        droppedOldest: false,
                        droppedCountForLog: nil,
                        droppedCountForPressureSignal: nil,
                        droppedIncomingCountForLog: droppedIncomingCountForLog
                    )
                }
            } else {
                return .init(
                    droppedOldest: false,
                    droppedCountForLog: nil,
                    droppedCountForPressureSignal: nil,
                    droppedIncomingCountForLog: droppedIncomingCountForLog
                )
            }
        }

        if !waitingContinuations.isEmpty {
            let continuation = waitingContinuations.removeFirst()
            continuation.resume(returning: packet)
            return .init(
                droppedOldest: false,
                droppedCountForLog: nil,
                droppedCountForPressureSignal: nil,
                droppedIncomingCountForLog: nil
            )
        }

        var droppedOldest = false
        var droppedCountForLog: Int?
        var droppedCountForPressureSignal: Int?
        if bufferedCount >= capacity {
            let alignmentDropBudget = min(
                bufferedCount,
                max(
                    1,
                    ShadowClientRealtimeSessionDefaults.videoReceiveQueuePressureTrimAlignmentMaximumExtraPackets
                )
            )
            let droppedForBoundaryAlignment = dropHeadPacketsUntilLikelyFrameBoundary(
                maxDrops: alignmentDropBudget
            )
            let droppedCount = max(1, droppedForBoundaryAlignment)

            droppedOldest = true
            droppedOldestCount += droppedCount
            droppedSinceLastPressureSignal += droppedCount
            if droppedOldestCount == droppedCount ||
                droppedOldestCount.isMultiple(of: Self.dropLogInterval)
            {
                droppedCountForLog = droppedOldestCount
            }
            if droppedOldestCount == droppedCount {
                droppedCountForPressureSignal = droppedCount
                droppedSinceLastPressureSignal = 0
            } else if droppedSinceLastPressureSignal >= pressureSignalInterval {
                droppedCountForPressureSignal = droppedSinceLastPressureSignal
                droppedSinceLastPressureSignal = 0
            }
        }
        let tailIndex = (headIndex + bufferedCount) % capacity
        bufferedPackets[tailIndex] = packet
        bufferedCount += 1
        return .init(
            droppedOldest: droppedOldest,
            droppedCountForLog: droppedCountForLog,
            droppedCountForPressureSignal: droppedCountForPressureSignal,
            droppedIncomingCountForLog: ingressSheddingResumeCountForLog
        )
    }

    func next() async -> ShadowClientRealtimeRTSPSessionRuntime.VideoTransportPacket? {
        if bufferedCount > 0 {
            let packet = bufferedPackets[headIndex]
            bufferedPackets[headIndex] = nil
            headIndex = (headIndex + 1) % capacity
            bufferedCount -= 1
            return packet
        }
        if closed {
            return nil
        }

        return await withCheckedContinuation { continuation in
            waitingContinuations.append(continuation)
        }
    }

    func close() {
        guard !closed else {
            return
        }
        closed = true
        bufferedPackets = Array(repeating: nil, count: capacity)
        headIndex = 0
        bufferedCount = 0
        droppedOldestCount = 0
        droppedSinceLastPressureSignal = 0
        droppingIncomingUntilFrameBoundary = false
        droppedIncomingPacketCount = 0
        let continuations = waitingContinuations
        waitingContinuations.removeAll(keepingCapacity: false)
        for continuation in continuations {
            continuation.resume(returning: nil)
        }
    }

    func removeAll() {
        bufferedPackets = Array(repeating: nil, count: capacity)
        headIndex = 0
        bufferedCount = 0
        droppedOldestCount = 0
        droppedSinceLastPressureSignal = 0
        droppingIncomingUntilFrameBoundary = false
        droppedIncomingPacketCount = 0
    }

    func trimToMostRecent(maxBufferedPackets: Int) -> Int {
        let boundedMaxBufferedPackets = max(1, min(maxBufferedPackets, capacity))
        guard bufferedCount > boundedMaxBufferedPackets else {
            return 0
        }

        var droppedCount = bufferedCount - boundedMaxBufferedPackets
        var dropsRemaining = droppedCount
        while dropsRemaining > 0 {
            dropHeadPacket()
            dropsRemaining -= 1
        }

        // When we trim under pressure, advance to the next likely frame boundary so
        // depacketization resumes from a clean frame start rather than a partial AU.
        if droppedCount > 0, bufferedCount > 0 {
            let alignmentDropBudget = min(
                bufferedCount,
                ShadowClientRealtimeSessionDefaults.videoReceiveQueuePressureTrimAlignmentMaximumExtraPackets
            )
            var alignmentDrops = 0
            while alignmentDrops < alignmentDropBudget,
                  let packet = bufferedPackets[headIndex]
            {
                dropHeadPacket()
                alignmentDrops += 1
                if ShadowClientRealtimeRTSPSessionRuntime.isLikelyVideoFrameBoundary(
                    marker: packet.marker,
                    payload: packet.payload
                ) {
                    break
                }
            }
            droppedCount += alignmentDrops
        }

        return droppedCount
    }

    private func dropHeadPacket() {
        guard bufferedCount > 0 else {
            return
        }
        bufferedPackets[headIndex] = nil
        headIndex = (headIndex + 1) % capacity
        bufferedCount -= 1
    }

    private func dropHeadPacketsUntilLikelyFrameBoundary(maxDrops: Int) -> Int {
        let boundedMaxDrops = max(1, maxDrops)
        var droppedCount = 0
        while droppedCount < boundedMaxDrops,
              bufferedCount > 0
        {
            let droppedPacket = bufferedPackets[headIndex]
            dropHeadPacket()
            droppedCount += 1
            if let droppedPacket,
               ShadowClientRealtimeRTSPSessionRuntime.isLikelyVideoFrameBoundary(
                   marker: droppedPacket.marker,
                   payload: droppedPacket.payload
               )
            {
                break
            }
        }
        return droppedCount
    }
}
