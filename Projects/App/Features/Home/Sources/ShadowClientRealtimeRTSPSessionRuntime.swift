import CoreVideo
import Darwin
import Foundation
import Network
import os

public enum ShadowClientRealtimeSessionRuntimeError: Error, Equatable, Sendable {
    case invalidSessionURL
    case connectionClosed
    case unsupportedCodec
    case transportFailure(String)
}

extension ShadowClientRealtimeSessionRuntimeError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidSessionURL:
            return "Remote session URL is invalid."
        case .connectionClosed:
            return "Remote session transport closed."
        case .unsupportedCodec:
            return "Remote session codec is not supported."
        case let .transportFailure(message):
            return message
        }
    }
}

private final class ShadowClientRealtimeUptimeSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var uptime: TimeInterval = 0

    func recordNow() {
        lock.lock()
        uptime = ProcessInfo.processInfo.systemUptime
        lock.unlock()
    }

    func current() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return uptime
    }

    func reset() {
        lock.lock()
        uptime = 0
        lock.unlock()
    }
}

private actor ShadowClientVideoDecodeQueue {
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

private actor ShadowClientVideoPacketQueue {
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

public actor ShadowClientRealtimeRTSPSessionRuntime {
    fileprivate struct VideoTransportPacket: Sendable {
        let payload: Data
        let marker: Bool
    }

    fileprivate struct VideoAccessUnit: Sendable {
        let codec: ShadowClientVideoCodec
        let parameterSets: [Data]
        let data: Data
        let depacketizerMetadata: ShadowClientAV1RTPDepacketizer.AssembledFrameMetadata?
    }

    private struct AV1DecodeSubmissionContext: Sendable {
        let accessUnitBytes: Int
        let decodeQueueBacklog: Int
        let depacketizerMetadata: ShadowClientAV1RTPDepacketizer.AssembledFrameMetadata?
    }

    struct VideoQueuePressureProfile: Equatable, Sendable {
        let receiveQueueCapacity: Int
        let receiveQueuePressureSignalInterval: Int
        let receiveQueuePressureTrimInterval: Int
        let receiveQueuePressureTrimToRecentPackets: Int
        let receiveQueueDropRecoveryThreshold: Int
        let receiveQueueIngressSheddingMaximumBurstPackets: Int
        let decodeQueueCapacity: Int
        let decodeQueueConsumerMaxBufferedUnits: Int
        let decodeQueueProducerSheddingHighWatermark: Int
        let decodeQueueProducerTrimToRecentUnits: Int
        let depacketizerDecodeQueueProbeIntervalPackets: Int
        let depacketizerDecodeQueueShedHighWatermark: Int
    }

    public let surfaceContext: ShadowClientRealtimeSessionSurfaceContext

    private let decoder: ShadowClientVideoToolboxDecoder
    private let connectTimeout: Duration
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "RealtimeSession")
    private let videoCodecSupport = ShadowClientVideoCodecSupport()
    private var rtspClient: ShadowClientRTSPInterleavedClient?
    private var receiveTask: Task<Void, Never>?
    private var depacketizeTask: Task<Void, Never>?
    private var decodeTask: Task<Void, Never>?
    private var stallMonitorTask: Task<Void, Never>?
    private var videoPacketQueue: ShadowClientVideoPacketQueue?
    private var videoDecodeQueue: ShadowClientVideoDecodeQueue?
    private var shadowClientNVDepacketizer = ShadowClientMoonlightNVRTPDepacketizer()
    private var hasLoggedDecodedFrameMetadata = false
    private var videoStatsWindowStartUptime: TimeInterval = 0
    private var videoStatsFrameCount = 0
    private var videoStatsByteCount = 0
    private var lastVideoStatPublishUptime: TimeInterval = 0
    private var videoDecodeQueueDropCount = 0
    private var firstVideoDecodeQueueDropUptime: TimeInterval = 0
    private var lastVideoDecodeQueueRecoveryUptime: TimeInterval = 0
    private var activeVideoConfiguration: ShadowClientRemoteSessionVideoConfiguration?
    private var depacketizerCorruptionCount = 0
    private var firstDepacketizerCorruptionUptime: TimeInterval = 0
    private var lastDepacketizerRecoveryUptime: TimeInterval = 0
    private var depacketizerRecoveryAttemptCount = 0
    private var firstDepacketizerRecoveryAttemptUptime: TimeInterval = 0
    private var decoderFailureCount = 0
    private var firstDecoderFailureUptime: TimeInterval = 0
    private var lastDecoderRecoveryUptime: TimeInterval = 0
    private var decoderRecoveryAttemptCount = 0
    private var firstDecoderRecoveryAttemptUptime: TimeInterval = 0
    private var decoderOutputStallRecoveryCount = 0
    private var firstDecoderOutputStallRecoveryUptime: TimeInterval = 0
    private var lastDecoderOutputStallRecoveryUptime: TimeInterval = 0
    private var decoderOutputStallCandidateCount = 0
    private var firstDecoderOutputStallCandidateUptime: TimeInterval = 0
    private var lastDecodeSubmitUptime: TimeInterval = 0
    private var lastDecodedFrameOutputUptime: TimeInterval = 0
    private let decodedFrameCallbackSignal = ShadowClientRealtimeUptimeSignal()
    private var hasRenderedFirstFrame = false
    private var hasPublishedRenderingState = false
    private var frameAssemblyLogCount = 0
    private var lastRenderedFramePublishUptime: TimeInterval = 0
    private var videoReceiveQueueDropCount = 0
    private var firstVideoReceiveQueueDropUptime: TimeInterval = 0
    private var lastVideoReceiveQueueRecoveryUptime: TimeInterval = 0
    private var lastVideoQueuePressureSignalUptime: TimeInterval = 0
    private var lastVideoDecodeQueueConsumerTrimUptime: TimeInterval = 0
    private var lastVideoRecoveryRequestUptime: TimeInterval = 0
    private var pendingVideoRecoveryRequest = false
    private var videoRenderSubmitDropCount = 0
    private var lastObservedDecodeQueueBacklog = 0
    private var awaitingAV1SyncFrame = false
    private var av1SyncGateDroppedFrameCount = 0
    private var lastAV1DecodeSubmissionContext: AV1DecodeSubmissionContext?
    private var videoReceiveQueueCapacity = ShadowClientRealtimeSessionDefaults.videoReceiveQueueCapacity
    private var videoDecodeQueueCapacity = ShadowClientRealtimeSessionDefaults.videoDecodeQueueCapacity
    private var videoDecodeQueueConsumerMaxBufferedUnits = ShadowClientRealtimeSessionDefaults.videoDecodeQueueConsumerMaxBufferedUnits
    private var videoDecodeQueueProducerSheddingHighWatermark = ShadowClientRealtimeSessionDefaults.videoDecodeQueueProducerSheddingHighWatermark
    private var videoDecodeQueueProducerTrimToRecentUnits = ShadowClientRealtimeSessionDefaults.videoDecodeQueueProducerTrimToRecentUnits
    private var videoDepacketizerDecodeQueueShedHighWatermark = ShadowClientRealtimeSessionDefaults.videoDepacketizerDecodeQueueShedHighWatermark
    private var videoQueuePressurePolicy = ShadowClientVideoQueuePressurePolicy.conservative
    private var videoReceiveQueuePressureSignalInterval = ShadowClientRealtimeSessionDefaults.videoReceiveQueuePressureSignalInterval
    private var videoReceiveQueuePressureTrimInterval = ShadowClientRealtimeSessionDefaults.videoReceiveQueuePressureTrimInterval
    private var videoReceiveQueuePressureTrimToRecentPackets = ShadowClientRealtimeSessionDefaults.videoReceiveQueuePressureTrimToRecentPackets
    private var videoReceiveQueueDropRecoveryThreshold = ShadowClientRealtimeSessionDefaults.videoReceiveQueueDropRecoveryThreshold
    private var videoReceiveQueueIngressSheddingMaximumBurstPackets = ShadowClientRealtimeSessionDefaults.videoReceiveQueueIngressSheddingMaximumBurstPackets
    private var videoDepacketizerDecodeQueueProbeIntervalPackets = ShadowClientRealtimeSessionDefaults.videoDepacketizerDecodeQueueProbeIntervalPackets

    public init(
        surfaceContext: ShadowClientRealtimeSessionSurfaceContext = .init(),
        decoder: ShadowClientVideoToolboxDecoder = .init(),
        connectTimeout: Duration = ShadowClientRealtimeSessionDefaults.defaultConnectTimeout
    ) {
        self.surfaceContext = surfaceContext
        self.decoder = decoder
        self.connectTimeout = connectTimeout
    }

    deinit {
        receiveTask?.cancel()
        depacketizeTask?.cancel()
        decodeTask?.cancel()
        stallMonitorTask?.cancel()

        let packetQueue = videoPacketQueue
        let decodeQueue = videoDecodeQueue
        let rtspClient = rtspClient
        let decoder = self.decoder
        Task.detached(priority: .utility) {
            await packetQueue?.close()
            await decodeQueue?.close()
            if let rtspClient {
                await rtspClient.stop()
            }
            await decoder.reset()
        }
    }

    public func connect(
        sessionURL: String,
        host _: String,
        appTitle _: String,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration
    ) async throws {
        try await disconnect()
        let resolvedVideoConfiguration = resolveRuntimeVideoConfiguration(videoConfiguration)
        activeVideoConfiguration = resolvedVideoConfiguration
        let sessionSurfaceContext = self.surfaceContext
        await decoder.setPreferredOutputDimensions(
            width: resolvedVideoConfiguration.width,
            height: resolvedVideoConfiguration.height,
            fps: resolvedVideoConfiguration.fps
        )
        await decoder.configureAV1Fallback(
            hdrEnabled: resolvedVideoConfiguration.enableHDR,
            yuv444Enabled: resolvedVideoConfiguration.enableYUV444
        )
        hasLoggedDecodedFrameMetadata = false
        videoStatsWindowStartUptime = 0
        videoStatsFrameCount = 0
        videoStatsByteCount = 0
        lastVideoStatPublishUptime = 0
        videoDecodeQueueDropCount = 0
        firstVideoDecodeQueueDropUptime = 0
        lastVideoDecodeQueueRecoveryUptime = 0
        depacketizerCorruptionCount = 0
        firstDepacketizerCorruptionUptime = 0
        lastDepacketizerRecoveryUptime = 0
        depacketizerRecoveryAttemptCount = 0
        firstDepacketizerRecoveryAttemptUptime = 0
        decoderFailureCount = 0
        firstDecoderFailureUptime = 0
        lastDecoderRecoveryUptime = 0
        decoderRecoveryAttemptCount = 0
        firstDecoderRecoveryAttemptUptime = 0
        decoderOutputStallRecoveryCount = 0
        firstDecoderOutputStallRecoveryUptime = 0
        lastDecoderOutputStallRecoveryUptime = 0
        decoderOutputStallCandidateCount = 0
        firstDecoderOutputStallCandidateUptime = 0
        lastDecodeSubmitUptime = 0
        lastDecodedFrameOutputUptime = 0
        decodedFrameCallbackSignal.reset()
        hasRenderedFirstFrame = false
        hasPublishedRenderingState = false
        frameAssemblyLogCount = 0
        lastRenderedFramePublishUptime = 0
        videoReceiveQueueDropCount = 0
        firstVideoReceiveQueueDropUptime = 0
        lastVideoReceiveQueueRecoveryUptime = 0
        lastVideoQueuePressureSignalUptime = 0
        lastVideoDecodeQueueConsumerTrimUptime = 0
        lastVideoRecoveryRequestUptime = 0
        pendingVideoRecoveryRequest = false
        videoRenderSubmitDropCount = 0
        lastObservedDecodeQueueBacklog = 0
        awaitingAV1SyncFrame = false
        av1SyncGateDroppedFrameCount = 0
        lastAV1DecodeSubmissionContext = nil
        configureQueuePressureProfile(for: resolvedVideoConfiguration)

        await MainActor.run {
            sessionSurfaceContext.reset()
            sessionSurfaceContext.updatePreferredRenderFPS(resolvedVideoConfiguration.fps)
            sessionSurfaceContext.updateActiveDynamicRangeMode(
                resolvedVideoConfiguration.enableHDR ? .hdr : .sdr
            )
            sessionSurfaceContext.transition(to: .connecting)
        }

        let trimmed = sessionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let _ = url.host else {
            throw ShadowClientRealtimeSessionRuntimeError.invalidSessionURL
        }

        let client = ShadowClientRTSPInterleavedClient(
            timeout: connectTimeout,
            onControlRoundTripSample: { [sessionSurfaceContext] roundTripMs in
                await MainActor.run {
                    sessionSurfaceContext.updateControlRoundTripMs(
                        Int(roundTripMs.rounded())
                    )
                }
            },
            onAudioOutputStateChanged: { [sessionSurfaceContext] audioState in
                await MainActor.run {
                    sessionSurfaceContext.updateAudioOutputState(audioState)
                }
            }
        )
        let track = try await client.start(
            url: url,
            videoConfiguration: resolvedVideoConfiguration,
            remoteInputKey: resolvedVideoConfiguration.remoteInputKey,
            remoteInputKeyID: resolvedVideoConfiguration.remoteInputKeyID
        )

        let depacketizerTailStrategy = Self.depacketizerTailTruncationStrategy(for: track.codec)
        shadowClientNVDepacketizer.configureTailTruncationStrategy(depacketizerTailStrategy)
        shadowClientNVDepacketizer.configureFrameHeaderProfile(
            appVersion: resolvedVideoConfiguration.serverAppVersion
        )
        videoQueuePressurePolicy = .fromTailTruncationStrategy(depacketizerTailStrategy)
        shadowClientNVDepacketizer.reset()
        awaitingAV1SyncFrame = track.codec == .av1
        av1SyncGateDroppedFrameCount = 0
        lastAV1DecodeSubmissionContext = nil
        await MainActor.run {
            surfaceContext.updateActiveVideoCodec(track.codec)
        }
        await transitionSurfaceState(.waitingForFirstFrame)

        rtspClient = client
        let packetQueue = ShadowClientVideoPacketQueue(
            capacity: videoReceiveQueueCapacity,
            pressureSignalInterval: videoReceiveQueuePressureSignalInterval,
            maxIngressSheddingBurstPackets: videoReceiveQueueIngressSheddingMaximumBurstPackets
        )
        videoPacketQueue = packetQueue
        let decodeQueue = ShadowClientVideoDecodeQueue(
            capacity: videoDecodeQueueCapacity
        )
        videoDecodeQueue = decodeQueue

        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop(
                client: client,
                codec: track.codec,
                payloadType: track.rtpPayloadType,
                videoPayloadCandidates: Set(track.candidateRTPPayloadTypes),
                packetQueue: packetQueue
            )
        }
        depacketizeTask = Task { [weak self] in
            await self?.runDepacketizeLoop(
                codec: track.codec,
                parameterSets: track.parameterSets,
                packetQueue: packetQueue
            )
        }
        decodeTask = Task { [weak self] in
            await self?.runDecodeLoop()
        }
        stallMonitorTask = Task { [weak self] in
            await self?.runDecoderOutputStallMonitor(codec: track.codec)
        }

        try await waitForInitialRenderState(timeout: connectTimeout)
    }

    public func disconnect() async throws {
        receiveTask?.cancel()
        receiveTask = nil
        depacketizeTask?.cancel()
        depacketizeTask = nil
        decodeTask?.cancel()
        decodeTask = nil
        stallMonitorTask?.cancel()
        stallMonitorTask = nil
        await closeVideoPacketQueue()
        await closeVideoDecodeQueue()

        if let rtspClient {
            await rtspClient.stop()
        }
        rtspClient = nil

        await decoder.resetForRecovery()
        videoQueuePressurePolicy = .conservative
        activeVideoConfiguration = nil
        hasLoggedDecodedFrameMetadata = false
        videoStatsWindowStartUptime = 0
        videoStatsFrameCount = 0
        videoStatsByteCount = 0
        lastVideoStatPublishUptime = 0
        videoDecodeQueueDropCount = 0
        firstVideoDecodeQueueDropUptime = 0
        lastVideoDecodeQueueRecoveryUptime = 0
        depacketizerCorruptionCount = 0
        firstDepacketizerCorruptionUptime = 0
        lastDepacketizerRecoveryUptime = 0
        depacketizerRecoveryAttemptCount = 0
        firstDepacketizerRecoveryAttemptUptime = 0
        decoderFailureCount = 0
        firstDecoderFailureUptime = 0
        lastDecoderRecoveryUptime = 0
        decoderRecoveryAttemptCount = 0
        firstDecoderRecoveryAttemptUptime = 0
        decoderOutputStallRecoveryCount = 0
        firstDecoderOutputStallRecoveryUptime = 0
        lastDecoderOutputStallRecoveryUptime = 0
        decoderOutputStallCandidateCount = 0
        firstDecoderOutputStallCandidateUptime = 0
        lastDecodeSubmitUptime = 0
        lastDecodedFrameOutputUptime = 0
        decodedFrameCallbackSignal.reset()
        hasRenderedFirstFrame = false
        hasPublishedRenderingState = false
        frameAssemblyLogCount = 0
        lastRenderedFramePublishUptime = 0
        videoReceiveQueueDropCount = 0
        firstVideoReceiveQueueDropUptime = 0
        lastVideoReceiveQueueRecoveryUptime = 0
        lastVideoQueuePressureSignalUptime = 0
        lastVideoDecodeQueueConsumerTrimUptime = 0
        lastVideoRecoveryRequestUptime = 0
        pendingVideoRecoveryRequest = false
        videoRenderSubmitDropCount = 0
        lastObservedDecodeQueueBacklog = 0
        awaitingAV1SyncFrame = false
        av1SyncGateDroppedFrameCount = 0
        lastAV1DecodeSubmissionContext = nil
        resetQueuePressureProfile()
        await MainActor.run {
            surfaceContext.reset()
        }
    }

    public func sendInput(_ event: ShadowClientRemoteInputEvent) async throws {
        guard let rtspClient else {
            return
        }
        try await rtspClient.sendInput(event)
    }

    private func runReceiveLoop(
        client: ShadowClientRTSPInterleavedClient,
        codec: ShadowClientVideoCodec,
        payloadType: Int,
        videoPayloadCandidates: Set<Int>,
        packetQueue: ShadowClientVideoPacketQueue
    ) async {
        let runtimeLogger = logger
        do {
            try await client.receiveInterleavedVideoPackets(
                payloadType: payloadType,
                videoPayloadCandidates: videoPayloadCandidates
            ) { payload, marker in
                let enqueueResult = await packetQueue.enqueue(
                    .init(payload: payload, marker: marker)
                )
                if let droppedCountForLog = enqueueResult.droppedCountForLog {
                    runtimeLogger.notice(
                        "Video receive queue dropped oldest packet due to sustained ingress pressure (count=\(droppedCountForLog, privacy: .public))"
                    )
                }
                if let droppedIncomingCountForLog = enqueueResult.droppedIncomingCountForLog {
                    runtimeLogger.notice(
                        "Video receive queue ingress shedding active for codec \(String(describing: codec), privacy: .public) (dropped-packets=\(droppedIncomingCountForLog, privacy: .public))"
                    )
                }
                if let droppedCountForPressureSignal = enqueueResult.droppedCountForPressureSignal {
                    Task { [weak self] in
                        await self?.handleVideoReceiveQueueBackpressure(
                            codec: codec,
                            droppedCount: droppedCountForPressureSignal
                        )
                    }
                }
            }
        } catch {
            if Task.isCancelled {
                return
            }
            logger.error("Realtime stream task failed: \(error.localizedDescription, privacy: .public)")
            let nextState = Self.renderState(forStreamError: error)
            await transitionSurfaceState(nextState)
        }
        stallMonitorTask?.cancel()
        stallMonitorTask = nil
        await closeVideoPacketQueue()
    }

    private func runDepacketizeLoop(
        codec: ShadowClientVideoCodec,
        parameterSets: [Data],
        packetQueue: ShadowClientVideoPacketQueue
    ) async {
        var packetsSinceDecodeQueueProbe = 0
        var droppingPacketsUntilFrameStart = false

        while !Task.isCancelled {
            guard let packet = await packetQueue.next() else {
                break
            }

            if droppingPacketsUntilFrameStart {
                if !Self.isLikelyVideoFrameStart(payload: packet.payload) {
                    continue
                }
                droppingPacketsUntilFrameStart = false
            }

            packetsSinceDecodeQueueProbe += 1
            if videoQueuePressurePolicy.allowsDepacketizerPacketShedding,
               packetsSinceDecodeQueueProbe >=
                videoDepacketizerDecodeQueueProbeIntervalPackets
            {
                packetsSinceDecodeQueueProbe = 0
                let bufferedDecodeUnits = await videoDecodeQueue?.bufferedUnitCount() ?? 0
                if Self.shouldShedDepacketizerWork(
                    allowsPacketLevelShedding: videoQueuePressurePolicy.allowsDepacketizerPacketShedding,
                    bufferedDecodeUnits: bufferedDecodeUnits,
                    highWatermark: videoDepacketizerDecodeQueueShedHighWatermark
                ) {
                    await handleVideoDecodeQueueBackpressure(
                        codec: codec,
                        droppedCount: 1,
                        source: "depacketize-shed"
                    )
                    resetDepacketizerStateForBoundaryRealignment(codec: codec)
                    if !Self.isLikelyVideoFrameStart(payload: packet.payload) {
                        droppingPacketsUntilFrameStart = true
                    }
                    continue
                }
            }

            do {
                try await consumeRTPPayload(
                    codec: codec,
                    payload: packet.payload,
                    marker: packet.marker,
                    initialParameterSets: parameterSets
                )
            } catch {
                if Task.isCancelled {
                    return
                }
                logger.error("Realtime depacketizer task failed: \(error.localizedDescription, privacy: .public)")
                let nextState = Self.renderState(forStreamError: error)
                await transitionSurfaceState(nextState)
                receiveTask?.cancel()
                stallMonitorTask?.cancel()
                stallMonitorTask = nil
                await closeVideoDecodeQueue()
                return
            }
        }

        await closeVideoDecodeQueue()
    }

    private func runDecodeLoop() async {
        while !Task.isCancelled {
            let dequeueResult = await dequeueVideoAccessUnit()
            guard let accessUnit = dequeueResult.accessUnit else {
                return
            }
            if dequeueResult.droppedCount > 0 {
                await decoder.reportQueueSaturationSignal()
                await handleVideoDecodeQueueBackpressure(
                    codec: accessUnit.codec,
                    droppedCount: dequeueResult.droppedCount,
                    source: "consumer-trim"
                )
            }

            do {
                lastObservedDecodeQueueBacklog = dequeueResult.remainingBufferedCount
                if accessUnit.codec == .av1 {
                    lastAV1DecodeSubmissionContext = .init(
                        accessUnitBytes: accessUnit.data.count,
                        decodeQueueBacklog: dequeueResult.remainingBufferedCount,
                        depacketizerMetadata: accessUnit.depacketizerMetadata
                    )
                } else {
                    lastAV1DecodeSubmissionContext = nil
                }
                try await decodeFrame(
                    accessUnit: accessUnit.data,
                    codec: accessUnit.codec,
                    parameterSets: accessUnit.parameterSets,
                    remainingDecodeQueueBacklog: dequeueResult.remainingBufferedCount
                )
                lastDecodeSubmitUptime = ProcessInfo.processInfo.systemUptime
                if Self.shouldClearDecoderFailureHistoryOnSuccessfulDecode(
                    now: lastDecodeSubmitUptime,
                    firstFailureUptime: firstDecoderFailureUptime,
                    windowSeconds: ShadowClientRealtimeSessionDefaults.decoderFailureWindowSeconds
                ) {
                    decoderFailureCount = 0
                    firstDecoderFailureUptime = 0
                }
                depacketizerRecoveryAttemptCount = 0
                firstDepacketizerRecoveryAttemptUptime = 0
            } catch {
                logger.error("\(String(describing: accessUnit.codec), privacy: .public) decode failed: \(error.localizedDescription, privacy: .public)")
                if accessUnit.codec == .av1 {
                    logAV1DecodeFailureContext(error: error)
                }
                if await handleDecoderFailure(codec: accessUnit.codec, error: error) {
                    continue
                }
                await failStreamingSession(
                    message: Self.runtimeRecoveryExhaustedMessage(
                        codec: accessUnit.codec,
                        reason: "decoder recovery exhausted"
                    )
                )
                return
            }
        }
    }

    private func dequeueVideoAccessUnit() async -> (
        accessUnit: VideoAccessUnit?,
        droppedCount: Int,
        remainingBufferedCount: Int
    ) {
        guard let videoDecodeQueue else {
            return (nil, 0, 0)
        }
        let now = ProcessInfo.processInfo.systemUptime
        let maxBufferedUnits = effectiveVideoDecodeQueueConsumerMaxBufferedUnits(now: now)
        let allowConsumerTrim = videoQueuePressurePolicy.allowsDecodeQueueConsumerTrim
        let result = await videoDecodeQueue.nextWithBackpressureTrim(
            maxBufferedUnits: maxBufferedUnits,
            allowTrim: allowConsumerTrim
        )
        return (result.unit, result.droppedCount, result.remainingBufferedCount)
    }

    private func closeVideoPacketQueue() async {
        if let videoPacketQueue {
            await videoPacketQueue.close()
        }
        self.videoPacketQueue = nil
    }

    private func closeVideoDecodeQueue() async {
        if let videoDecodeQueue {
            await videoDecodeQueue.close()
        }
        self.videoDecodeQueue = nil
    }

    private func flushVideoPipelineForRecovery(codec: ShadowClientVideoCodec) async {
        if let videoPacketQueue {
            await videoPacketQueue.removeAll()
        }
        if let videoDecodeQueue {
            await videoDecodeQueue.removeAll()
        }
        shadowClientNVDepacketizer.reset()
        if codec == .av1 {
            awaitingAV1SyncFrame = true
            av1SyncGateDroppedFrameCount = 0
            lastAV1DecodeSubmissionContext = nil
        }
    }

    private func failStreamingSession(message: String) async {
        logger.error("\(message, privacy: .public)")
        receiveTask?.cancel()
        depacketizeTask?.cancel()
        depacketizeTask = nil
        stallMonitorTask?.cancel()
        stallMonitorTask = nil
        awaitingAV1SyncFrame = false
        av1SyncGateDroppedFrameCount = 0
        lastAV1DecodeSubmissionContext = nil
        await transitionSurfaceState(.failed(message))
        await closeVideoPacketQueue()
        await closeVideoDecodeQueue()
    }

    private func consumeRTPPayload(
        codec: ShadowClientVideoCodec,
        payload: Data,
        marker: Bool,
        initialParameterSets: [Data]
    ) async throws {
        _ = marker
        switch shadowClientNVDepacketizer.ingestWithStatus(payload: payload, marker: marker) {
        case .noFrame:
            return
        case .droppedCorruptFrame:
            if await handleDepacketizerCorruption(codec: codec) {
                throw ShadowClientRealtimeSessionRuntimeError.transportFailure(
                    Self.runtimeRecoveryExhaustedMessage(
                        codec: codec,
                        reason: "depacketizer recovery exhausted"
                    )
                )
            }
            return
        case let .frame(frame):
            let frameMetadata = shadowClientNVDepacketizer.consumeLastCompletedFrameMetadata()
            frameAssemblyLogCount &+= 1
            if frameAssemblyLogCount == 1 ||
                frameAssemblyLogCount.isMultiple(of: ShadowClientRealtimeSessionDefaults.videoFrameAssemblyLogInterval)
            {
                logger.notice("ShadowClient NV frame assembled for codec \(String(describing: codec), privacy: .public): \(frame.count, privacy: .public) bytes")
            }
            depacketizerCorruptionCount = 0
            firstDepacketizerCorruptionUptime = 0

            updateRuntimeVideoStats(frameBytes: frame.count)
            if codec == .av1,
               !(await shouldAdmitAV1FrameToDecoderQueue(frameMetadata: frameMetadata))
            {
                return
            }
            if codec == .av1,
               !Self.isLikelyValidAV1AccessUnit(frame)
            {
                // AV1 low-latency streams can contain non-canonical OBU packaging.
                // Avoid pre-decoder drops here and let VideoToolbox decide decode validity.
                logger.notice("Forwarding non-canonical AV1 access unit to decoder without pre-drop")
            }
            if let videoDecodeQueue {
                let producerSheddingHighWatermark = max(
                    1,
                    min(
                        videoDecodeQueueCapacity - 1,
                        videoDecodeQueueProducerSheddingHighWatermark
                    )
                )
                let bufferedUnitCount = await videoDecodeQueue.bufferedUnitCount()
                if videoQueuePressurePolicy.allowsDecodeQueueProducerTrim,
                   bufferedUnitCount >= producerSheddingHighWatermark
                {
                    let producerTrimTarget = max(
                        1,
                        min(
                            producerSheddingHighWatermark,
                            videoDecodeQueueProducerTrimToRecentUnits
                        )
                    )
                    let producerTrimmedCount = await videoDecodeQueue.trimToMostRecent(
                        maxBufferedUnits: producerTrimTarget
                    )
                    if producerTrimmedCount > 0 {
                        await handleVideoDecodeQueueBackpressure(
                            codec: codec,
                            droppedCount: producerTrimmedCount,
                            source: "producer-trim"
                        )
                    }
                }

                let droppedOldest = await videoDecodeQueue.enqueue(
                    .init(
                        codec: codec,
                        parameterSets: initialParameterSets,
                        data: frame,
                        depacketizerMetadata: frameMetadata
                    )
                )
                if droppedOldest {
                    await handleVideoDecodeQueueBackpressure(
                        codec: codec,
                        source: "enqueue-overflow"
                    )
                }
            }
        }
    }

    private func shouldAdmitAV1FrameToDecoderQueue(
        frameMetadata: ShadowClientAV1RTPDepacketizer.AssembledFrameMetadata?
    ) async -> Bool {
        guard awaitingAV1SyncFrame else {
            return true
        }

        let frameType = frameMetadata?.frameType
        if Self.isAV1SyncFrameType(frameType) {
            let droppedBeforeSync = av1SyncGateDroppedFrameCount
            awaitingAV1SyncFrame = false
            av1SyncGateDroppedFrameCount = 0
            let frameIndexDescription = Self.optionalUInt32Description(frameMetadata?.frameIndex)
            let frameTypeDescription = Self.optionalUInt8Description(frameType)
            logger.notice(
                "AV1 sync gate acquired IDR frame index=\(frameIndexDescription, privacy: .public) type=\(frameTypeDescription, privacy: .public) dropped-before-sync=\(droppedBeforeSync, privacy: .public)"
            )
            return true
        }

        av1SyncGateDroppedFrameCount += 1
        if av1SyncGateDroppedFrameCount == 1 ||
            av1SyncGateDroppedFrameCount.isMultiple(of: 60)
        {
            let frameIndexDescription = Self.optionalUInt32Description(frameMetadata?.frameIndex)
            let frameTypeDescription = Self.optionalUInt8Description(frameType)
            logger.notice(
                "AV1 sync gate dropping non-sync frame index=\(frameIndexDescription, privacy: .public) type=\(frameTypeDescription, privacy: .public) dropped=\(self.av1SyncGateDroppedFrameCount, privacy: .public)"
            )
        }
        _ = await requestVideoRecoveryFrame(
            for: .av1,
            reason: "av1-sync-gate",
            minimumInterval: 0.35
        )
        return false
    }

    private func logAV1DecodeFailureContext(error: any Error) {
        guard let context = lastAV1DecodeSubmissionContext else {
            return
        }

        let status = Self.decodeFailureStatus(from: error)
        let metadata = context.depacketizerMetadata
        let statusDescription = Self.optionalOSStatusDescription(status)
        let frameIndexDescription = Self.optionalUInt32Description(metadata?.frameIndex)
        let streamPacketDescription = Self.optionalUInt32Description(metadata?.firstStreamPacketIndex)
        let frameTypeDescription = Self.optionalUInt8Description(metadata?.frameType)
        let headerTypeDescription = Self.optionalUInt8Description(metadata?.frameHeaderType)
        let headerSizeDescription = Self.optionalIntDescription(metadata?.frameHeaderSize)
        let lastPayloadLengthDescription = Self.optionalUInt16Description(metadata?.lastPacketPayloadLength)
        logger.error(
            "AV1 decode failure context status=\(statusDescription, privacy: .public) frame-bytes=\(context.accessUnitBytes, privacy: .public) decode-backlog=\(context.decodeQueueBacklog, privacy: .public) frame-index=\(frameIndexDescription, privacy: .public) stream-packet=\(streamPacketDescription, privacy: .public) frame-type=\(frameTypeDescription, privacy: .public) header-type=\(headerTypeDescription, privacy: .public) header-size=\(headerSizeDescription, privacy: .public) last-payload-len=\(lastPayloadLengthDescription, privacy: .public)"
        )
    }

    private func handleVideoDecodeQueueBackpressure(
        codec: ShadowClientVideoCodec,
        droppedCount: Int = 1,
        source: String = "enqueue-overflow"
    ) async {
        guard droppedCount > 0 else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if firstVideoDecodeQueueDropUptime == 0 ||
            now - firstVideoDecodeQueueDropUptime > ShadowClientRealtimeSessionDefaults.videoDecodeQueueDropWindowSeconds
        {
            firstVideoDecodeQueueDropUptime = now
            videoDecodeQueueDropCount = 0
        }
        lastVideoQueuePressureSignalUptime = now
        if source == "consumer-trim" {
            lastVideoDecodeQueueConsumerTrimUptime = now
        }
        let previousDecodeQueueDropCount = videoDecodeQueueDropCount
        videoDecodeQueueDropCount += droppedCount

        if Self.didCounterCrossIntervalBoundary(
            previous: previousDecodeQueueDropCount,
            current: videoDecodeQueueDropCount,
            interval: ShadowClientRealtimeSessionDefaults.videoDecodeQueueBackpressureLogInterval
        ) {
            // Queue pressure is a throughput signal, not a decoder-instability signal.
            // Keep VT feed aggressive under backlog and reserve instability for real decode faults/stalls.
            await decoder.reportQueueSaturationSignal()
            logger.notice(
                "Video decode queue backpressure detected for codec \(String(describing: codec), privacy: .public) (source=\(source, privacy: .public), dropped-oldest=\(self.videoDecodeQueueDropCount, privacy: .public))"
            )
        }

        if source == "producer-trim" || source == "producer-shed" || source == "consumer-trim" {
            return
        }

        guard Self.shouldTriggerDecodeQueueRecovery(source: source) else {
            return
        }
        guard Self.shouldEscalateQueuePressureToRecovery(
            now: now,
            lastDecodedFrameOutputUptime: effectiveLastDecodedFrameOutputUptime(),
            minimumStallSeconds: ShadowClientRealtimeSessionDefaults.videoQueuePressureRecoveryMinimumOutputStallSeconds
        ) else {
            return
        }
        let decodeQueueRecoveryThreshold = max(
            ShadowClientRealtimeSessionDefaults.videoDecodeQueueDropRecoveryThreshold,
            videoDecodeQueueConsumerMaxBufferedUnits * 3
        )
        guard videoDecodeQueueDropCount >= decodeQueueRecoveryThreshold else {
            return
        }
        guard now - lastVideoDecodeQueueRecoveryUptime >= ShadowClientRealtimeSessionDefaults.videoDecodeQueueRecoveryCooldownSeconds else {
            return
        }

        lastVideoDecodeQueueRecoveryUptime = now
        videoDecodeQueueDropCount = 0
        firstVideoDecodeQueueDropUptime = 0
        logger.error(
            "Video decode queue remained saturated for codec \(String(describing: codec), privacy: .public); requesting recovery frame to resynchronize"
        )
        await flushVideoPipelineForRecovery(codec: codec)
        await requestVideoRecoveryFrame(
            for: codec,
            reason: "decode-queue-saturation"
        )
    }

    private func handleVideoReceiveQueueBackpressure(
        codec: ShadowClientVideoCodec,
        droppedCount: Int = 1
    ) async {
        guard droppedCount > 0 else {
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        if firstVideoReceiveQueueDropUptime == 0 ||
            now - firstVideoReceiveQueueDropUptime > ShadowClientRealtimeSessionDefaults.videoReceiveQueueDropWindowSeconds
        {
            firstVideoReceiveQueueDropUptime = now
            videoReceiveQueueDropCount = 0
        }
        lastVideoQueuePressureSignalUptime = now
        let previousDropCount = videoReceiveQueueDropCount
        videoReceiveQueueDropCount += droppedCount
        if videoReceiveQueueDropCount == droppedCount ||
            Self.didCounterCrossIntervalBoundary(
                previous: previousDropCount,
                current: videoReceiveQueueDropCount,
                interval: videoReceiveQueuePressureSignalInterval
            )
        {
            await decoder.reportQueueSaturationSignal()
        }

        if Self.didCounterCrossIntervalBoundary(
            previous: previousDropCount,
            current: videoReceiveQueueDropCount,
            interval: videoReceiveQueuePressureTrimInterval
        ),
           let videoPacketQueue
        {
            let trimmedCount = await videoPacketQueue.trimToMostRecent(
                maxBufferedPackets: videoReceiveQueuePressureTrimToRecentPackets
            )
            if trimmedCount > 0 {
                // Trimming can drop packet heads in the middle of an access unit.
                // Reset depacketizer state so next frame assembly restarts on a clean boundary.
                resetDepacketizerStateForBoundaryRealignment(codec: codec)
                logger.notice(
                    "Video receive queue pressure trim dropped \(trimmedCount, privacy: .public) stale packets for codec \(String(describing: codec), privacy: .public)"
                )
            }
        }

        guard Self.shouldEscalateQueuePressureToRecovery(
            now: now,
            lastDecodedFrameOutputUptime: effectiveLastDecodedFrameOutputUptime(),
            minimumStallSeconds: ShadowClientRealtimeSessionDefaults.videoQueuePressureRecoveryMinimumOutputStallSeconds
        ) else {
            return
        }
        let receiveQueueRecoveryThreshold = max(
            videoReceiveQueueDropRecoveryThreshold,
            videoReceiveQueuePressureTrimToRecentPackets * 2
        )
        guard videoReceiveQueueDropCount >= receiveQueueRecoveryThreshold else {
            return
        }
        guard now - lastVideoReceiveQueueRecoveryUptime >= ShadowClientRealtimeSessionDefaults.videoReceiveQueueRecoveryCooldownSeconds else {
            return
        }

        lastVideoReceiveQueueRecoveryUptime = now
        videoReceiveQueueDropCount = 0
        firstVideoReceiveQueueDropUptime = 0
        logger.error(
            "Video receive queue remained saturated for codec \(String(describing: codec), privacy: .public); fast-forwarding pipeline and requesting recovery frame"
        )
        await flushVideoPipelineForRecovery(codec: codec)
        await requestVideoRecoveryFrame(
            for: codec,
            reason: "receive-queue-saturation"
        )
    }

    private func resetDepacketizerStateForBoundaryRealignment(codec: ShadowClientVideoCodec) {
        shadowClientNVDepacketizer.reset()
        if codec == .av1 {
            awaitingAV1SyncFrame = true
            av1SyncGateDroppedFrameCount = 0
            lastAV1DecodeSubmissionContext = nil
        }
    }

    private func isVideoPipelineUnderIngressPressure(now: TimeInterval) -> Bool {
        if Self.isRecentQueuePressureSignal(
            now: now,
            lastSignalUptime: lastVideoQueuePressureSignalUptime,
            windowSeconds: ShadowClientRealtimeSessionDefaults.videoQueuePressureRecentSignalWindowSeconds
        ) {
            return true
        }
        let receiveQueueUnderPressure = firstVideoReceiveQueueDropUptime > 0 &&
            videoReceiveQueueDropCount > 0 &&
            now - firstVideoReceiveQueueDropUptime <=
            ShadowClientRealtimeSessionDefaults.videoReceiveQueueDropWindowSeconds
        if receiveQueueUnderPressure {
            return true
        }

        let decodeQueueUnderPressure = firstVideoDecodeQueueDropUptime > 0 &&
            videoDecodeQueueDropCount > 0 &&
            now - firstVideoDecodeQueueDropUptime <=
            ShadowClientRealtimeSessionDefaults.videoDecodeQueueDropWindowSeconds
        return decodeQueueUnderPressure
    }

    private func handleDepacketizerCorruption(codec: ShadowClientVideoCodec) async -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if firstDepacketizerCorruptionUptime == 0 ||
            now - firstDepacketizerCorruptionUptime > ShadowClientRealtimeSessionDefaults.depacketizerCorruptionWindowSeconds
        {
            firstDepacketizerCorruptionUptime = now
            depacketizerCorruptionCount = 0
        }
        depacketizerCorruptionCount += 1

        guard depacketizerCorruptionCount >= ShadowClientRealtimeSessionDefaults.depacketizerCorruptionThreshold else {
            return false
        }

        let pipelineUnderIngressPressure = isVideoPipelineUnderIngressPressure(now: now)
        let depacketizerRecoveryMinimumStallSeconds = pipelineUnderIngressPressure
            ? max(
                ShadowClientRealtimeSessionDefaults.videoQueuePressureRecoveryMinimumOutputStallSeconds,
                ShadowClientRealtimeSessionDefaults.videoQueuePressureRecoveryMinimumOutputStallSeconds * 2.0
            )
            : ShadowClientRealtimeSessionDefaults.videoQueuePressureRecoveryMinimumOutputStallSeconds
        guard Self.shouldEscalateQueuePressureToRecovery(
            now: now,
            lastDecodedFrameOutputUptime: effectiveLastDecodedFrameOutputUptime(),
            minimumStallSeconds: depacketizerRecoveryMinimumStallSeconds
        ) else {
            return false
        }
        guard now - lastDepacketizerRecoveryUptime >= ShadowClientRealtimeSessionDefaults.depacketizerRecoveryCooldownSeconds else {
            return false
        }

        lastDepacketizerRecoveryUptime = now
        depacketizerCorruptionCount = 0
        firstDepacketizerCorruptionUptime = 0
        if firstDepacketizerRecoveryAttemptUptime == 0 ||
            now - firstDepacketizerRecoveryAttemptUptime >
            ShadowClientRealtimeSessionDefaults.depacketizerRecoveryAttemptWindowSeconds
        {
            firstDepacketizerRecoveryAttemptUptime = now
            depacketizerRecoveryAttemptCount = 0
        }
        depacketizerRecoveryAttemptCount += 1
        if depacketizerRecoveryAttemptCount >=
            ShadowClientRealtimeSessionDefaults.depacketizerMaxRecoveryAttempts
        {
            logger.error(
                "Video depacketizer recovery attempts exceeded threshold for codec \(String(describing: codec), privacy: .public); aborting runtime recovery"
            )
            return true
        }
        logger.error("Video depacketizer detected sustained stream discontinuity for codec \(String(describing: codec), privacy: .public); requesting recovery frame")
        await flushVideoPipelineForRecovery(codec: codec)
        await requestVideoRecoveryFrame(
            for: codec,
            reason: "depacketizer-discontinuity"
        )
        if !hasRenderedFirstFrame {
            await transitionSurfaceState(.waitingForFirstFrame)
        }
        return false
    }

    private func handleDecoderFailure(
        codec: ShadowClientVideoCodec,
        error: any Error
    ) async -> Bool {
        if Self.shouldAbortDecoderRecovery(forDecoderError: error) {
            logger.error(
                "Video decoder reported fatal failure for codec \(String(describing: codec), privacy: .public); aborting runtime recovery"
            )
            return false
        }

        let now = ProcessInfo.processInfo.systemUptime
        if firstDecoderFailureUptime == 0 ||
            now - firstDecoderFailureUptime > ShadowClientRealtimeSessionDefaults.decoderFailureWindowSeconds
        {
            firstDecoderFailureUptime = now
            decoderFailureCount = 0
        }
        decoderFailureCount += 1

        if hasRenderedFirstFrame, decoderFailureCount == 1 {
            logger.notice(
                "Video decoder dropped one frame for codec \(String(describing: codec), privacy: .public); requesting recovery frame before hard reset"
            )
            _ = await requestVideoRecoveryFrame(
                for: codec,
                reason: "decoder-single-frame-drop",
                minimumInterval: 0.35
            )
            return true
        }

        guard now - lastDecoderRecoveryUptime >= ShadowClientRealtimeSessionDefaults.decoderRecoveryCooldownSeconds else {
            return true
        }

        lastDecoderRecoveryUptime = now
        decoderFailureCount = 0
        firstDecoderFailureUptime = 0
        hasLoggedDecodedFrameMetadata = false
        await decoder.reportDecoderInstabilitySignal()

        if firstDecoderRecoveryAttemptUptime == 0 ||
            now - firstDecoderRecoveryAttemptUptime > ShadowClientRealtimeSessionDefaults.decoderRecoveryAttemptWindowSeconds
        {
            firstDecoderRecoveryAttemptUptime = now
            decoderRecoveryAttemptCount = 0
        }
        decoderRecoveryAttemptCount += 1
        if decoderRecoveryAttemptCount >= ShadowClientRealtimeSessionDefaults.decoderMaxRecoveryAttempts
        {
            logger.error(
                "Video decoder recovery attempts exceeded threshold for codec \(String(describing: codec), privacy: .public); aborting runtime recovery"
            )
            return false
        }

        logger.error(
            "Video decoder entered recovery for codec \(String(describing: codec), privacy: .public); resetting decoder and requesting recovery frame"
        )
        await flushVideoPipelineForRecovery(codec: codec)
        await decoder.reset()
        if let configuration = activeVideoConfiguration {
            await decoder.setPreferredOutputDimensions(
                width: configuration.width,
                height: configuration.height,
                fps: configuration.fps
            )
            await decoder.configureAV1Fallback(
                hdrEnabled: configuration.enableHDR,
                yuv444Enabled: configuration.enableYUV444
            )
        }
        await requestVideoRecoveryFrame(
            for: codec,
            reason: "decoder-recovery"
        )
        if !hasRenderedFirstFrame {
            await transitionSurfaceState(.waitingForFirstFrame)
        }
        return true
    }

    private func runDecoderOutputStallMonitor(codec: ShadowClientVideoCodec) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(250))
            if Task.isCancelled {
                return
            }

            if let pendingDecodeFailure = await decoder.consumePendingDecodeFailure() {
                logger.error(
                    "\(String(describing: codec), privacy: .public) decode failed: \(pendingDecodeFailure.localizedDescription, privacy: .public)"
                )
                if codec == .av1 {
                    logAV1DecodeFailureContext(error: pendingDecodeFailure)
                }
                if await handleDecoderFailure(codec: codec, error: pendingDecodeFailure) {
                    continue
                }
                await failStreamingSession(
                    message: Self.runtimeRecoveryExhaustedMessage(
                        codec: codec,
                        reason: "decoder recovery exhausted"
                    )
                )
                return
            }

            let now = ProcessInfo.processInfo.systemUptime
            let isPipelineUnderIngressPressure =
                isVideoPipelineUnderIngressPressure(now: now) || pendingVideoRecoveryRequest
            let effectiveLastDecodedFrameOutputUptime = effectiveLastDecodedFrameOutputUptime()
            let hasRecentConsumerTrimPressure = lastVideoDecodeQueueConsumerTrimUptime > 0 &&
                now - lastVideoDecodeQueueConsumerTrimUptime <=
                ShadowClientRealtimeSessionDefaults.decoderOutputStallConsumerTrimPressureWindowSeconds
            let effectiveActiveDecodeWindowSeconds =
                Self.effectiveDecoderOutputStallActiveDecodeWindowSeconds(
                    baseWindow:
                    ShadowClientRealtimeSessionDefaults.decoderOutputStallActiveDecodeWindowSeconds,
                    isPipelineUnderIngressPressure: isPipelineUnderIngressPressure,
                    hasRecentConsumerTrimPressure: hasRecentConsumerTrimPressure
                )
            let effectiveStallThresholdSeconds =
                Self.effectiveDecoderOutputStallThresholdSeconds(
                    baseThreshold:
                    ShadowClientRealtimeSessionDefaults.decoderOutputStallThresholdSeconds,
                    isPipelineUnderIngressPressure: isPipelineUnderIngressPressure,
                    hasRecentConsumerTrimPressure: hasRecentConsumerTrimPressure
                )
            let requiredStallCandidateCount =
                Self.effectiveDecoderOutputStallCandidateThreshold(
                    isPipelineUnderIngressPressure: isPipelineUnderIngressPressure,
                    hasRecentConsumerTrimPressure: hasRecentConsumerTrimPressure
                )
            let shouldRecover = Self.shouldTriggerDecoderOutputStallRecovery(
                hasRenderedFirstFrame: hasRenderedFirstFrame,
                now: now,
                lastDecodeSubmitUptime: lastDecodeSubmitUptime,
                lastDecodedFrameOutputUptime: effectiveLastDecodedFrameOutputUptime,
                activeDecodeWindowSeconds: effectiveActiveDecodeWindowSeconds,
                stallThresholdSeconds: effectiveStallThresholdSeconds
            )
            guard shouldRecover else {
                resetDecoderOutputStallCandidates()
                continue
            }

            guard registerDecoderOutputStallCandidate(
                now: now,
                requiredCandidateCount: requiredStallCandidateCount
            ) else {
                continue
            }

            let underPressureSignal = isPipelineUnderIngressPressure || hasRecentConsumerTrimPressure
            if Self.shouldSuppressDecoderOutputStallRecovery(
                now: now,
                lastDecodedFrameOutputUptime: effectiveLastDecodedFrameOutputUptime,
                underPressureSignal: underPressureSignal
            ) {
                continue
            }

            if await handleDecoderOutputStall(
                codec: codec,
                now: now,
                isPipelineUnderIngressPressure: isPipelineUnderIngressPressure,
                hasRecentConsumerTrimPressure: hasRecentConsumerTrimPressure
            ) {
                continue
            }
            await failStreamingSession(
                message: Self.runtimeRecoveryExhaustedMessage(
                    codec: codec,
                    reason: "decoder output stalled"
                )
            )
            return
        }
    }

    private func registerDecoderOutputStallCandidate(
        now: TimeInterval,
        requiredCandidateCount: Int
    ) -> Bool {
        let candidateWindow = max(
            0.5,
            ShadowClientRealtimeSessionDefaults.decoderOutputStallCandidateWindowSeconds
        )
        if firstDecoderOutputStallCandidateUptime == 0 ||
            now - firstDecoderOutputStallCandidateUptime > candidateWindow
        {
            firstDecoderOutputStallCandidateUptime = now
            decoderOutputStallCandidateCount = 0
        }
        decoderOutputStallCandidateCount += 1
        return decoderOutputStallCandidateCount >= max(1, requiredCandidateCount)
    }

    private func resetDecoderOutputStallCandidates() {
        decoderOutputStallCandidateCount = 0
        firstDecoderOutputStallCandidateUptime = 0
    }

    private func handleDecoderOutputStall(
        codec: ShadowClientVideoCodec,
        now: TimeInterval,
        isPipelineUnderIngressPressure: Bool,
        hasRecentConsumerTrimPressure: Bool
    ) async -> Bool {
        guard now - lastDecoderOutputStallRecoveryUptime >=
            ShadowClientRealtimeSessionDefaults.decoderOutputStallRecoveryCooldownSeconds
        else {
            return true
        }
        resetDecoderOutputStallCandidates()

        if firstDecoderOutputStallRecoveryUptime == 0 ||
            now - firstDecoderOutputStallRecoveryUptime >
            ShadowClientRealtimeSessionDefaults.decoderOutputStallRecoveryWindowSeconds
        {
            firstDecoderOutputStallRecoveryUptime = now
            decoderOutputStallRecoveryCount = 0
        }
        decoderOutputStallRecoveryCount += 1
        let underPressureSignal = isPipelineUnderIngressPressure || hasRecentConsumerTrimPressure
        if Self.shouldAbortDecoderOutputStallRecovery(
            recoveryAttemptCount: decoderOutputStallRecoveryCount,
            maxRecoveryAttempts: ShadowClientRealtimeSessionDefaults.decoderMaxOutputStallRecoveries
        ) {
            logger.error(
                "Video decoder output stall recoveries exceeded threshold for codec \(String(describing: codec), privacy: .public); aborting runtime recovery"
            )
            return false
        }
        lastDecoderOutputStallRecoveryUptime = now
        if hasRecentConsumerTrimPressure {
            await decoder.reportDecoderInstabilitySignal()
        } else if isPipelineUnderIngressPressure {
            await decoder.reportQueueSaturationSignal()
        } else {
            await decoder.reportDecoderInstabilitySignal()
        }
        let softRecoveryAttemptLimit =
            ShadowClientRealtimeSessionDefaults.decoderOutputStallPressureSoftRecoveryAttempts +
            (hasRecentConsumerTrimPressure
                ? ShadowClientRealtimeSessionDefaults.decoderOutputStallConsumerTrimSoftRecoveryBonusAttempts
                : 0)

        if Self.shouldUseSoftDecoderOutputStallRecovery(
            underPressureSignal: underPressureSignal,
            recoveryAttemptCount: decoderOutputStallRecoveryCount,
            softRecoveryAttemptLimit: softRecoveryAttemptLimit
        ) {
            logger.notice(
                "Video decoder output stalled for codec \(String(describing: codec), privacy: .public) under queue pressure; requesting recovery frame without decoder reset"
            )
            _ = await requestVideoRecoveryFrame(
                for: codec,
                reason: "decoder-output-stall-pressure"
            )
            lastDecodeSubmitUptime = now
            return true
        }

        if underPressureSignal {
            let hardResetPressureGraceAttempts = max(
                0,
                ShadowClientRealtimeSessionDefaults.decoderOutputStallPressureHardResetGraceAttempts
            )
            let maximumSoftPressureAttempts = softRecoveryAttemptLimit + hardResetPressureGraceAttempts
            if decoderOutputStallRecoveryCount <= maximumSoftPressureAttempts {
                logger.notice(
                    "Video decoder output stalled for codec \(String(describing: codec), privacy: .public) while queue pressure signal is active; extending soft recovery window and skipping decoder reset"
                )
                _ = await requestVideoRecoveryFrame(
                    for: codec,
                    reason: "decoder-output-stall-pressure-extended"
                )
                lastDecodeSubmitUptime = now
                return true
            }
            logger.error(
                "Video decoder output stalled for codec \(String(describing: codec), privacy: .public) while queue pressure persisted; forcing decoder hard reset path"
            )
        }

        logger.error(
            "Video decoder output stalled for codec \(String(describing: codec), privacy: .public); resetting decoder and requesting recovery frame"
        )
        resetVideoQueuePressureTracking()
        await flushVideoPipelineForRecovery(codec: codec)
        await decoder.resetForRecovery()
        if let configuration = activeVideoConfiguration {
            await decoder.setPreferredOutputDimensions(
                width: configuration.width,
                height: configuration.height,
                fps: configuration.fps
            )
            await decoder.configureAV1Fallback(
                hdrEnabled: configuration.enableHDR,
                yuv444Enabled: configuration.enableYUV444
            )
        }
        await requestVideoRecoveryFrame(
            for: codec,
            reason: "decoder-output-stall"
        )
        lastDecodeSubmitUptime = now
        lastDecodedFrameOutputUptime = now
        if !hasRenderedFirstFrame {
            await transitionSurfaceState(.waitingForFirstFrame)
        }
        return true
    }

    private func decodeFrame(
        accessUnit: Data,
        codec: ShadowClientVideoCodec,
        parameterSets: [Data],
        remainingDecodeQueueBacklog: Int
    ) async throws {
        let runtime = self
        let decodedFrameCallbackSignal = self.decodedFrameCallbackSignal
        try await decoder.decode(
            accessUnit: accessUnit,
            codec: codec,
            parameterSets: parameterSets,
            backlogHint: remainingDecodeQueueBacklog
        ) { pixelBuffer in
            decodedFrameCallbackSignal.recordNow()
            let sendableFrame = ShadowClientSendablePixelBuffer(value: pixelBuffer)
            await runtime.handleDecodedFrameOutput(
                codec: codec,
                pixelBuffer: sendableFrame.value
            )
        }
    }

    private func handleDecodedFrameOutput(
        codec: ShadowClientVideoCodec,
        pixelBuffer: CVPixelBuffer
    ) async {
        let now = ProcessInfo.processInfo.systemUptime
        if codec == .av1 {
            awaitingAV1SyncFrame = false
            av1SyncGateDroppedFrameCount = 0
            lastAV1DecodeSubmissionContext = nil
        }
        recordDecodedFrameOutputUptime()
        if shouldDropDecodedFrameForRenderPacing(now: now) {
            return
        }
        logDecodedFrameMetadataIfNeeded(
            codec: codec,
            pixelBuffer: pixelBuffer
        )
        surfaceContext.frameStore.update(pixelBuffer: pixelBuffer)
        lastRenderedFramePublishUptime = now
        if !hasPublishedRenderingState {
            hasPublishedRenderingState = true
            let sessionSurfaceContext = self.surfaceContext
            await MainActor.run {
                sessionSurfaceContext.transition(to: .rendering)
            }
        }
    }

    private func shouldDropDecodedFrameForRenderPacing(now: TimeInterval) -> Bool {
        guard let configuration = activeVideoConfiguration else {
            return false
        }
        guard Self.shouldDropRenderSubmitForSessionFPS(
            now: now,
            lastRenderedFramePublishUptime: lastRenderedFramePublishUptime,
            sessionFPS: configuration.fps,
            pacingToleranceRatio: ShadowClientRealtimeSessionDefaults.videoRenderSubmitPacingToleranceRatio
        ) else {
            return false
        }
        let renderPacingBacklogThreshold = max(
            2,
            videoDecodeQueueConsumerMaxBufferedUnits / 2
        )
        guard lastObservedDecodeQueueBacklog >= renderPacingBacklogThreshold else {
            return false
        }
        guard isVideoPipelineUnderIngressPressure(now: now) else {
            return false
        }
        guard !pendingVideoRecoveryRequest else {
            return false
        }

        let previousRenderSubmitDropCount = videoRenderSubmitDropCount
        videoRenderSubmitDropCount += 1
        if Self.didCounterCrossIntervalBoundary(
            previous: previousRenderSubmitDropCount,
            current: videoRenderSubmitDropCount,
            interval: ShadowClientRealtimeSessionDefaults.videoRenderSubmitDropSummaryInterval
        ) {
            logger.notice(
                "Video render submit pacing dropped decoded frame to match session FPS (count=\(self.videoRenderSubmitDropCount, privacy: .public))"
            )
        }
        return true
    }

    private func transitionSurfaceState(
        _ state: ShadowClientRealtimeSessionSurfaceContext.RenderState
    ) async {
        if state != .rendering {
            hasPublishedRenderingState = false
            lastRenderedFramePublishUptime = 0
        }
        let sessionSurfaceContext = self.surfaceContext
        await MainActor.run {
            sessionSurfaceContext.transition(to: state)
        }
    }

    private func resolveRuntimeVideoConfiguration(
        _ configuration: ShadowClientRemoteSessionVideoConfiguration
    ) -> ShadowClientRemoteSessionVideoConfiguration {
        let resolvedCodecPreference = videoCodecSupport.resolvePreferredCodec(
            configuration.preferredCodec,
            enableHDR: configuration.enableHDR,
            enableYUV444: configuration.enableYUV444
        )
        return .init(
            width: configuration.width,
            height: configuration.height,
            fps: configuration.fps,
            bitrateKbps: configuration.bitrateKbps,
            preferredCodec: resolvedCodecPreference,
            enableHDR: configuration.enableHDR,
            enableSurroundAudio: configuration.enableSurroundAudio,
            enableYUV444: configuration.enableYUV444,
            remoteInputKey: configuration.remoteInputKey,
            remoteInputKeyID: configuration.remoteInputKeyID
        )
    }

    private func configureQueuePressureProfile(
        for configuration: ShadowClientRemoteSessionVideoConfiguration
    ) {
        let profile = Self.queuePressureProfile(for: configuration)
        videoReceiveQueueCapacity = profile.receiveQueueCapacity
        videoReceiveQueuePressureSignalInterval = profile.receiveQueuePressureSignalInterval
        videoReceiveQueuePressureTrimInterval = profile.receiveQueuePressureTrimInterval
        videoReceiveQueuePressureTrimToRecentPackets = profile.receiveQueuePressureTrimToRecentPackets
        videoReceiveQueueDropRecoveryThreshold = profile.receiveQueueDropRecoveryThreshold
        videoReceiveQueueIngressSheddingMaximumBurstPackets = profile.receiveQueueIngressSheddingMaximumBurstPackets
        videoDecodeQueueCapacity = profile.decodeQueueCapacity
        videoDecodeQueueConsumerMaxBufferedUnits = profile.decodeQueueConsumerMaxBufferedUnits
        videoDecodeQueueProducerSheddingHighWatermark = profile.decodeQueueProducerSheddingHighWatermark
        videoDecodeQueueProducerTrimToRecentUnits = profile.decodeQueueProducerTrimToRecentUnits
        videoDepacketizerDecodeQueueProbeIntervalPackets = profile.depacketizerDecodeQueueProbeIntervalPackets
        videoDepacketizerDecodeQueueShedHighWatermark = profile.depacketizerDecodeQueueShedHighWatermark
        logger.notice(
            "Video queue profile configured receive-cap=\(profile.receiveQueueCapacity, privacy: .public) decode-cap=\(profile.decodeQueueCapacity, privacy: .public) trim-packets=\(profile.receiveQueuePressureTrimToRecentPackets, privacy: .public) decode-consumer-max=\(profile.decodeQueueConsumerMaxBufferedUnits, privacy: .public) ingress-burst-cap=\(profile.receiveQueueIngressSheddingMaximumBurstPackets, privacy: .public) depacketize-probe=\(profile.depacketizerDecodeQueueProbeIntervalPackets, privacy: .public)"
        )
    }

    private func resetQueuePressureProfile() {
        videoReceiveQueueCapacity = ShadowClientRealtimeSessionDefaults.videoReceiveQueueCapacity
        videoReceiveQueuePressureSignalInterval = ShadowClientRealtimeSessionDefaults.videoReceiveQueuePressureSignalInterval
        videoReceiveQueuePressureTrimInterval = ShadowClientRealtimeSessionDefaults.videoReceiveQueuePressureTrimInterval
        videoReceiveQueuePressureTrimToRecentPackets = ShadowClientRealtimeSessionDefaults.videoReceiveQueuePressureTrimToRecentPackets
        videoReceiveQueueDropRecoveryThreshold = ShadowClientRealtimeSessionDefaults.videoReceiveQueueDropRecoveryThreshold
        videoReceiveQueueIngressSheddingMaximumBurstPackets = ShadowClientRealtimeSessionDefaults.videoReceiveQueueIngressSheddingMaximumBurstPackets
        videoDecodeQueueCapacity = ShadowClientRealtimeSessionDefaults.videoDecodeQueueCapacity
        videoDecodeQueueConsumerMaxBufferedUnits = ShadowClientRealtimeSessionDefaults.videoDecodeQueueConsumerMaxBufferedUnits
        videoDecodeQueueProducerSheddingHighWatermark = ShadowClientRealtimeSessionDefaults.videoDecodeQueueProducerSheddingHighWatermark
        videoDecodeQueueProducerTrimToRecentUnits = ShadowClientRealtimeSessionDefaults.videoDecodeQueueProducerTrimToRecentUnits
        videoDepacketizerDecodeQueueProbeIntervalPackets = ShadowClientRealtimeSessionDefaults.videoDepacketizerDecodeQueueProbeIntervalPackets
        videoDepacketizerDecodeQueueShedHighWatermark = ShadowClientRealtimeSessionDefaults.videoDepacketizerDecodeQueueShedHighWatermark
    }

    private func effectiveVideoDecodeQueueConsumerMaxBufferedUnits(now: TimeInterval) -> Int {
        let base = min(
            max(1, videoDecodeQueueConsumerMaxBufferedUnits),
            max(1, videoDecodeQueueCapacity - 1)
        )
        guard Self.isRecentQueuePressureSignal(
            now: now,
            lastSignalUptime: lastVideoQueuePressureSignalUptime,
            windowSeconds: ShadowClientRealtimeSessionDefaults.videoQueuePressureRecentSignalWindowSeconds
        ) || pendingVideoRecoveryRequest else {
            return base
        }

        let pressureExpanded = Int(
            (Double(videoDecodeQueueCapacity) *
                ShadowClientRealtimeSessionDefaults.videoDecodeQueueConsumerPressureExpansionRatio)
                .rounded(.up)
        )
        return min(
            max(1, videoDecodeQueueCapacity - 1),
            max(base, pressureExpanded)
        )
    }

    private func updateRuntimeVideoStats(frameBytes: Int) {
        let now = ProcessInfo.processInfo.systemUptime
        if videoStatsWindowStartUptime == 0 {
            videoStatsWindowStartUptime = now
        }
        videoStatsFrameCount += 1
        videoStatsByteCount += max(0, frameBytes)

        if now - lastVideoStatPublishUptime < 0.2 {
            return
        }
        lastVideoStatPublishUptime = now

        let windowDuration = max(now - videoStatsWindowStartUptime, 0.001)
        let bitrateKbps = Int((Double(videoStatsByteCount) * 8.0 / 1_000.0) / windowDuration)
        let fps = Double(videoStatsFrameCount) / windowDuration
        videoStatsWindowStartUptime = now
        videoStatsFrameCount = 0
        videoStatsByteCount = 0
        let sessionSurfaceContext = self.surfaceContext
        Task { @MainActor in
            sessionSurfaceContext.updateRuntimeVideoStats(
                fps: fps,
                bitrateKbps: bitrateKbps
            )
        }
    }

    private func waitForInitialRenderState(timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if Task.isCancelled {
                throw CancellationError()
            }

            let state = await MainActor.run {
                surfaceContext.renderState
            }

            switch state {
            case .rendering:
                return
            case let .disconnected(message):
                throw ShadowClientRealtimeSessionRuntimeError.transportFailure(message)
            case let .failed(message):
                throw ShadowClientRealtimeSessionRuntimeError.transportFailure(message)
            case .idle, .connecting, .waitingForFirstFrame:
                break
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        throw ShadowClientRealtimeSessionRuntimeError.transportFailure(
            "Timed out waiting for first frame."
        )
    }

    private func logDecodedFrameMetadataIfNeeded(
        codec: ShadowClientVideoCodec,
        pixelBuffer: CVPixelBuffer
    ) {
        hasRenderedFirstFrame = true
        guard !hasLoggedDecodedFrameMetadata else {
            return
        }
        hasLoggedDecodedFrameMetadata = true

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let transfer = attachmentStringValue(
            forKey: kCVImageBufferTransferFunctionKey,
            pixelBuffer: pixelBuffer
        ) ?? "nil"
        let primaries = attachmentStringValue(
            forKey: kCVImageBufferColorPrimariesKey,
            pixelBuffer: pixelBuffer
        ) ?? "nil"
        let matrix = attachmentStringValue(
            forKey: kCVImageBufferYCbCrMatrixKey,
            pixelBuffer: pixelBuffer
        ) ?? "nil"

        logger.notice(
            "Decoded first frame metadata codec=\(String(describing: codec), privacy: .public) pixel-format=0x\(String(pixelFormat, radix: 16), privacy: .public) primaries=\(primaries, privacy: .public) transfer=\(transfer, privacy: .public) matrix=\(matrix, privacy: .public)"
        )

        let resolvedDynamicRangeMode = Self.dynamicRangeMode(fromTransferFunction: transfer)
        let sessionSurfaceContext = self.surfaceContext
        Task { @MainActor in
            sessionSurfaceContext.updateActiveDynamicRangeMode(resolvedDynamicRangeMode)
        }
    }

    private func recordDecodedFrameOutputUptime() {
        lastDecodedFrameOutputUptime = ProcessInfo.processInfo.systemUptime
        decoderOutputStallCandidateCount = 0
        firstDecoderOutputStallCandidateUptime = 0
        resetVideoQueuePressureTracking()
        pendingVideoRecoveryRequest = false
    }

    private func effectiveLastDecodedFrameOutputUptime() -> TimeInterval {
        max(lastDecodedFrameOutputUptime, decodedFrameCallbackSignal.current())
    }

    private func resetVideoQueuePressureTracking() {
        videoReceiveQueueDropCount = 0
        firstVideoReceiveQueueDropUptime = 0
        videoDecodeQueueDropCount = 0
        firstVideoDecodeQueueDropUptime = 0
        lastVideoQueuePressureSignalUptime = 0
        lastVideoDecodeQueueConsumerTrimUptime = 0
    }

    @discardableResult
    private func requestVideoRecoveryFrame(
        for codec: ShadowClientVideoCodec,
        reason: String,
        minimumInterval: TimeInterval = ShadowClientRealtimeSessionDefaults.videoRecoveryFrameRequestCooldownSeconds
    ) async -> Bool {
        if codec == .av1 {
            awaitingAV1SyncFrame = true
        }
        return await requestVideoRecoveryFrame(
            reason: reason,
            minimumInterval: minimumInterval
        )
    }

    @discardableResult
    private func requestVideoRecoveryFrame(
        reason: String,
        minimumInterval: TimeInterval = ShadowClientRealtimeSessionDefaults.videoRecoveryFrameRequestCooldownSeconds
    ) async -> Bool {
        guard let rtspClient else {
            return false
        }

        let now = ProcessInfo.processInfo.systemUptime
        let isPipelineUnderIngressPressure = isVideoPipelineUnderIngressPressure(now: now)
        guard Self.shouldAllowVideoRecoveryFrameRequest(
            now: now,
            lastRequestUptime: lastVideoRecoveryRequestUptime,
            isRequestPending: pendingVideoRecoveryRequest,
            minimumInterval: minimumInterval,
            pendingTimeout: ShadowClientRealtimeSessionDefaults.videoRecoveryFramePendingTimeoutSeconds,
            isPipelineUnderIngressPressure: isPipelineUnderIngressPressure,
            pressureMinimumInterval: ShadowClientRealtimeSessionDefaults.videoRecoveryFrameRequestUnderPressureCooldownSeconds
        ) else {
            return false
        }

        lastVideoRecoveryRequestUptime = now
        pendingVideoRecoveryRequest = true
        logger.notice(
            "Video recovery frame requested (reason=\(reason, privacy: .public))"
        )
        await rtspClient.requestVideoRecoveryFrame()
        return true
    }

    private func attachmentStringValue(
        forKey key: CFString,
        pixelBuffer: CVPixelBuffer
    ) -> String? {
        guard let attachment = CVBufferCopyAttachment(pixelBuffer, key, nil) else {
            return nil
        }
        if let value = attachment as? String {
            return value
        }
        if CFGetTypeID(attachment) == CFStringGetTypeID() {
            return attachment as? String
        }
        return nil
    }

    private static func depacketizerTailTruncationStrategy(
        for codec: ShadowClientVideoCodec
    ) -> ShadowClientMoonlightNVRTPDepacketizer.TailTruncationStrategy {
        switch codec {
        case .h264, .h265:
            // H264/H265 tolerate trailing zero padding and Sunshine doesn't guarantee valid lastPayloadLength.
            return .passthroughForAnnexBCodecs
        case .av1:
            return .trimUsingLastPacketLength
        }
    }

    static func shouldAbortDecoderOutputStallRecovery(
        recoveryAttemptCount: Int,
        maxRecoveryAttempts: Int = ShadowClientRealtimeSessionDefaults.decoderMaxOutputStallRecoveries
    ) -> Bool {
        recoveryAttemptCount >= max(1, maxRecoveryAttempts)
    }

    static func shouldAbortDecoderRecovery(forDecoderError error: any Error) -> Bool {
        if let decoderError = error as? ShadowClientVideoToolboxDecoderError {
            switch decoderError {
            case .missingParameterSets, .missingFrameDimensions, .cannotCreateSampleBuffer:
                return false
            case .missingAV1CodecConfiguration,
                 .unsupportedCodec,
                 .cannotCreateFormatDescription,
                 .cannotCreateDecoder:
                return true
            case .decodeFailed:
                // Treat runtime decode failures as recoverable and let the bounded
                // recovery budget decide abort timing. This avoids immediate
                // fatal teardown on transient VT statuses during active playback.
                return false
            }
        }

        let normalized = error.localizedDescription.lowercased()
        if normalized.isEmpty {
            return false
        }
        let fatalSignatures = [
            "could not create hardware decoder session",
            "could not create video format description",
            "decoder codec is not supported",
        ]
        return fatalSignatures.contains(where: normalized.contains)
    }

    static func isRecoverableDecodeFailureStatus(_ status: OSStatus) -> Bool {
        // -12909 is commonly reported for transient malformed/partial frame submissions.
        let recoverableStatuses: Set<OSStatus> = [-12909]
        return recoverableStatuses.contains(status)
    }

    static func decodeFailureStatus(from error: any Error) -> OSStatus? {
        guard let decoderError = error as? ShadowClientVideoToolboxDecoderError else {
            return nil
        }
        if case let .decodeFailed(status) = decoderError {
            return status
        }
        return nil
    }

    private static func runtimeRecoveryExhaustedMessage(
        codec: ShadowClientVideoCodec,
        reason: String
    ) -> String {
        "\(String(describing: codec).uppercased()) decode failed (\(reason)). Runtime recovery exhausted; retry with fallback codec."
    }

    static func isAV1SyncFrameType(_ frameType: UInt8?) -> Bool {
        frameType == 2
    }

    private static func optionalOSStatusDescription(_ status: OSStatus?) -> String {
        guard let status else {
            return "unknown"
        }
        return String(status)
    }

    private static func optionalUInt32Description(_ value: UInt32?) -> String {
        guard let value else {
            return "unknown"
        }
        return String(value)
    }

    private static func optionalUInt16Description(_ value: UInt16?) -> String {
        guard let value else {
            return "unknown"
        }
        return String(value)
    }

    private static func optionalUInt8Description(_ value: UInt8?) -> String {
        guard let value else {
            return "unknown"
        }
        return String(value)
    }

    private static func optionalIntDescription(_ value: Int?) -> String {
        guard let value else {
            return "unknown"
        }
        return String(value)
    }

    static func shouldClearDecoderFailureHistoryOnSuccessfulDecode(
        now: TimeInterval,
        firstFailureUptime: TimeInterval,
        windowSeconds: TimeInterval
    ) -> Bool {
        guard firstFailureUptime > 0 else {
            return false
        }
        return now - firstFailureUptime > windowSeconds
    }

    private static func dynamicRangeMode(
        fromTransferFunction transferFunction: String
    ) -> ShadowClientRealtimeSessionSurfaceContext.DynamicRangeMode {
        let normalized = transferFunction.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if normalized.contains("2084") || normalized.contains("PQ") || normalized.contains("HLG") {
            return .hdr
        }
        if normalized.isEmpty || normalized == "NIL" {
            return .unknown
        }
        return .sdr
    }

    static func shouldTriggerDecoderOutputStallRecovery(
        hasRenderedFirstFrame: Bool,
        now: TimeInterval,
        lastDecodeSubmitUptime: TimeInterval,
        lastDecodedFrameOutputUptime: TimeInterval,
        activeDecodeWindowSeconds: TimeInterval =
            ShadowClientRealtimeSessionDefaults.decoderOutputStallActiveDecodeWindowSeconds,
        stallThresholdSeconds: TimeInterval =
            ShadowClientRealtimeSessionDefaults.decoderOutputStallThresholdSeconds
    ) -> Bool {
        guard hasRenderedFirstFrame else {
            return false
        }
        guard lastDecodeSubmitUptime > 0, lastDecodedFrameOutputUptime > 0 else {
            return false
        }

        let secondsSinceDecodeSubmit = now - lastDecodeSubmitUptime
        let secondsSinceDecodedFrameOutput = now - lastDecodedFrameOutputUptime
        guard secondsSinceDecodeSubmit <= max(0, activeDecodeWindowSeconds)
        else {
            return false
        }
        return secondsSinceDecodedFrameOutput >= max(0, stallThresholdSeconds)
    }

    static func effectiveDecoderOutputStallThresholdSeconds(
        baseThreshold: TimeInterval = ShadowClientRealtimeSessionDefaults.decoderOutputStallThresholdSeconds,
        isPipelineUnderIngressPressure: Bool,
        hasRecentConsumerTrimPressure: Bool
    ) -> TimeInterval {
        var threshold = max(0, baseThreshold)
        if isPipelineUnderIngressPressure {
            threshold *= max(
                1.0,
                ShadowClientRealtimeSessionDefaults.decoderOutputStallThresholdUnderPressureMultiplier
            )
        }
        if hasRecentConsumerTrimPressure {
            threshold *= max(
                1.0,
                ShadowClientRealtimeSessionDefaults.decoderOutputStallThresholdConsumerTrimMultiplier
            )
        }
        return threshold
    }

    static func effectiveDecoderOutputStallActiveDecodeWindowSeconds(
        baseWindow: TimeInterval = ShadowClientRealtimeSessionDefaults.decoderOutputStallActiveDecodeWindowSeconds,
        isPipelineUnderIngressPressure: Bool,
        hasRecentConsumerTrimPressure: Bool
    ) -> TimeInterval {
        var window = max(0, baseWindow)
        if isPipelineUnderIngressPressure {
            window *= max(
                1.0,
                ShadowClientRealtimeSessionDefaults.decoderOutputStallActiveDecodeWindowUnderPressureMultiplier
            )
        }
        if hasRecentConsumerTrimPressure {
            window *= max(
                1.0,
                ShadowClientRealtimeSessionDefaults.decoderOutputStallActiveDecodeWindowConsumerTrimMultiplier
            )
        }
        return window
    }

    static func effectiveDecoderOutputStallCandidateThreshold(
        isPipelineUnderIngressPressure: Bool,
        hasRecentConsumerTrimPressure: Bool
    ) -> Int {
        if hasRecentConsumerTrimPressure {
            return max(
                1,
                ShadowClientRealtimeSessionDefaults.decoderOutputStallCandidateThresholdConsumerTrim
            )
        }
        if isPipelineUnderIngressPressure {
            return max(
                1,
                ShadowClientRealtimeSessionDefaults.decoderOutputStallCandidateThresholdUnderPressure
            )
        }
        return max(
            1,
            ShadowClientRealtimeSessionDefaults.decoderOutputStallCandidateThreshold
        )
    }

    static func shouldSuppressDecoderOutputStallRecovery(
        now: TimeInterval,
        lastDecodedFrameOutputUptime: TimeInterval,
        underPressureSignal: Bool
    ) -> Bool {
        guard underPressureSignal else {
            return false
        }
        guard lastDecodedFrameOutputUptime > 0 else {
            return true
        }
        let elapsedSinceFrameOutput = now - lastDecodedFrameOutputUptime
        let suppressionCeiling = max(
            ShadowClientRealtimeSessionDefaults.decoderOutputStallSuppressionGraceSeconds,
            ShadowClientRealtimeSessionDefaults.decoderOutputStallSuppressionMaximumSecondsUnderPressure
        )
        return elapsedSinceFrameOutput < suppressionCeiling
    }

    static func shouldSuppressDecoderOutputStallRecovery(
        now: TimeInterval,
        lastDecodedFrameOutputUptime: TimeInterval,
        isPipelineUnderIngressPressure: Bool
    ) -> Bool {
        shouldSuppressDecoderOutputStallRecovery(
            now: now,
            lastDecodedFrameOutputUptime: lastDecodedFrameOutputUptime,
            underPressureSignal: isPipelineUnderIngressPressure
        )
    }

    static func isRecentQueuePressureSignal(
        now: TimeInterval,
        lastSignalUptime: TimeInterval,
        windowSeconds: TimeInterval
    ) -> Bool {
        guard lastSignalUptime > 0 else {
            return false
        }
        return now - lastSignalUptime <= max(0, windowSeconds)
    }

    static func shouldUseSoftDecoderOutputStallRecovery(
        underPressureSignal: Bool,
        recoveryAttemptCount: Int,
        softRecoveryAttemptLimit: Int
    ) -> Bool {
        guard underPressureSignal else {
            return false
        }
        guard recoveryAttemptCount > 0 else {
            return false
        }
        return recoveryAttemptCount <= max(0, softRecoveryAttemptLimit)
    }

    static func shouldUseSoftDecoderOutputStallRecovery(
        isPipelineUnderIngressPressure: Bool,
        recoveryAttemptCount: Int,
        softRecoveryAttemptLimit: Int
    ) -> Bool {
        shouldUseSoftDecoderOutputStallRecovery(
            underPressureSignal: isPipelineUnderIngressPressure,
            recoveryAttemptCount: recoveryAttemptCount,
            softRecoveryAttemptLimit: softRecoveryAttemptLimit
        )
    }

    static func didCounterCrossIntervalBoundary(
        previous: Int,
        current: Int,
        interval: Int
    ) -> Bool {
        guard interval > 0, current > previous else {
            return false
        }
        let previousBucket = previous / interval
        let currentBucket = current / interval
        return currentBucket > previousBucket
    }

    static func shouldAllowVideoRecoveryFrameRequest(
        now: TimeInterval,
        lastRequestUptime: TimeInterval,
        isRequestPending: Bool,
        minimumInterval: TimeInterval,
        pendingTimeout: TimeInterval,
        isPipelineUnderIngressPressure: Bool,
        pressureMinimumInterval: TimeInterval
    ) -> Bool {
        let elapsed = now - lastRequestUptime
        if isRequestPending && elapsed < max(0, pendingTimeout) {
            return false
        }
        if isPipelineUnderIngressPressure &&
            elapsed < max(max(0, minimumInterval), max(0, pressureMinimumInterval))
        {
            return false
        }
        return elapsed >= max(0, minimumInterval)
    }

    static func shouldDropRenderSubmitForSessionFPS(
        now: TimeInterval,
        lastRenderedFramePublishUptime: TimeInterval,
        sessionFPS: Int,
        pacingToleranceRatio: Double
    ) -> Bool {
        guard lastRenderedFramePublishUptime > 0 else {
            return false
        }
        let normalizedFPS = max(1, sessionFPS)
        let normalizedToleranceRatio = min(1.0, max(0.1, pacingToleranceRatio))
        let minimumInterval = (1.0 / Double(normalizedFPS)) * normalizedToleranceRatio
        return now - lastRenderedFramePublishUptime < minimumInterval
    }

    static func isTransientInputSendError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if (nsError.domain == "Network.NWError" && nsError.code == 89) ||
            (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
        {
            return true
        }

        if let networkError = error as? NWError {
            if case let .posix(code) = networkError {
                switch code {
                case .ECANCELED, .ENOTCONN:
                    return true
                default:
                    break
                }
            }
        }

        let normalized = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.contains("operation canceled") ||
            normalized.contains("operation cancelled") ||
            normalized.contains("nwerror error 89")
        {
            return true
        }
        return false
    }

    static func shouldResetInputControlChannelAfterSendError(_ error: Error) -> Bool {
        if isTransientInputSendError(error) {
            return false
        }

        if let controlError = error as? ShadowClientSunshineControlChannelError {
            switch controlError {
            case .connectionClosed,
                 .connectionTimedOut,
                 .commandAcknowledgeTimedOut:
                return true
            case .handshakeTimedOut,
                 .verifyConnectNotReceived,
                 .invalidEncryptedControlKey,
                 .encryptedControlEncodingFailed:
                return false
            }
        }

        if let networkError = error as? NWError {
            if case let .posix(code) = networkError {
                switch code {
                case .ECONNRESET, .EPIPE:
                    return true
                default:
                    break
                }
            }
        }

        let normalized = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.contains("connection closed") ||
            normalized.contains("connection reset by peer") ||
            normalized.contains("broken pipe")
        {
            return true
        }
        return false
    }

    static func isLikelyValidAV1AccessUnit(_ accessUnit: Data) -> Bool {
        guard !accessUnit.isEmpty else {
            return false
        }

        var index = 0
        while index < accessUnit.count {
            let obuHeader = accessUnit[index]
            // forbidden bit and reserved bit should both be unset
            if (obuHeader & 0x80) != 0 || (obuHeader & 0x01) != 0 {
                return false
            }

            let hasExtension = (obuHeader & 0x04) != 0
            let hasSizeField = (obuHeader & 0x02) != 0
            guard hasSizeField else {
                return false
            }

            index += 1
            if hasExtension {
                guard index < accessUnit.count else {
                    return false
                }
                index += 1
            }

            guard let leb = decodeLEB128(in: accessUnit, from: index) else {
                return false
            }
            index = leb.nextIndex
            guard leb.value >= 0, index + leb.value <= accessUnit.count else {
                return false
            }
            index += leb.value
        }

        return true
    }

    static func shouldShedDepacketizerWork(
        allowsPacketLevelShedding: Bool,
        bufferedDecodeUnits: Int,
        highWatermark: Int = ShadowClientRealtimeSessionDefaults.videoDepacketizerDecodeQueueShedHighWatermark
    ) -> Bool {
        guard allowsPacketLevelShedding else {
            return false
        }
        return bufferedDecodeUnits >= max(1, highWatermark)
    }

    static func shouldShedDepacketizerWork(
        codec: ShadowClientVideoCodec,
        bufferedDecodeUnits: Int,
        highWatermark: Int = ShadowClientRealtimeSessionDefaults.videoDepacketizerDecodeQueueShedHighWatermark
    ) -> Bool {
        let tailStrategy = depacketizerTailTruncationStrategy(for: codec)
        let policy = ShadowClientVideoQueuePressurePolicy.fromTailTruncationStrategy(tailStrategy)
        return shouldShedDepacketizerWork(
            allowsPacketLevelShedding: policy.allowsDepacketizerPacketShedding,
            bufferedDecodeUnits: bufferedDecodeUnits,
            highWatermark: highWatermark
        )
    }

    static func shouldTriggerDecodeQueueRecovery(source: String) -> Bool {
        switch source {
        case "producer-shed", "producer-trim":
            return false
        default:
            return true
        }
    }

    static func shouldEscalateQueuePressureToRecovery(
        now: TimeInterval,
        lastDecodedFrameOutputUptime: TimeInterval,
        minimumStallSeconds: TimeInterval
    ) -> Bool {
        guard lastDecodedFrameOutputUptime > 0 else {
            return true
        }
        return (now - lastDecodedFrameOutputUptime) >= max(0, minimumStallSeconds)
    }

    static func shouldAdoptVideoPayloadType(
        observedPayloadType: Int,
        currentPayloadType: Int,
        audioPayloadType: Int?,
        videoPayloadCandidates: Set<Int>
    ) -> Bool {
        guard observedPayloadType != currentPayloadType else {
            return false
        }
        guard observedPayloadType != ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType else {
            return false
        }
        if let audioPayloadType,
           observedPayloadType == audioPayloadType
        {
            return false
        }
        guard (96 ... 127).contains(observedPayloadType) else {
            return false
        }
        return videoPayloadCandidates.contains(observedPayloadType)
    }

    static func queuePressureProfile(
        for configuration: ShadowClientRemoteSessionVideoConfiguration
    ) -> VideoQueuePressureProfile {
        let normalizedFPS = max(ShadowClientStreamingLaunchBounds.minimumFPS, configuration.fps)
        let normalizedWidth = max(ShadowClientStreamingLaunchBounds.minimumWidth, configuration.width)
        let normalizedHeight = max(ShadowClientStreamingLaunchBounds.minimumHeight, configuration.height)
        let normalizedBitrateKbps = max(
            ShadowClientStreamingLaunchBounds.minimumBitrateKbps,
            configuration.bitrateKbps
        )

        let payloadBytes = max(
            1,
            max(256, ShadowClientRealtimeSessionDefaults.videoEstimatedPacketPayloadBytes)
        )
        let estimatedPacketsPerSecond = max(
            1,
            Int(
                (
                    (Double(normalizedBitrateKbps) * 1_000.0 / 8.0) /
                        Double(payloadBytes)
                ).rounded(.up)
            )
        )
        let bitratePacketsPerFrame = max(
            1,
            Int((Double(estimatedPacketsPerSecond) / Double(normalizedFPS)).rounded(.up))
        )
        let modeledBytesPerFrame =
            (Double(normalizedWidth) * Double(normalizedHeight) *
                ShadowClientRealtimeSessionDefaults.videoReceiveQueueModelBitsPerPixel) / 8.0
        let modeledPacketsPerFrame = max(
            ShadowClientRealtimeSessionDefaults.videoReceiveQueueMinimumPacketsPerFrameEstimate,
            Int((modeledBytesPerFrame / Double(payloadBytes)).rounded(.up))
        )
        let bitratePacketCapFromModel = max(
            modeledPacketsPerFrame,
            Int(
                (
                    Double(modeledPacketsPerFrame) *
                        max(
                            1.0,
                            ShadowClientRealtimeSessionDefaults.videoReceiveQueueBitratePacketsPerFrameCapRatio
                        )
                ).rounded(.up)
            )
        )
        let effectivePacketsPerFrame = min(
            ShadowClientRealtimeSessionDefaults.videoReceiveQueueMaximumPacketsPerFrameEstimate,
            max(
                ShadowClientRealtimeSessionDefaults.videoReceiveQueueMinimumPacketsPerFrameEstimate,
                min(bitratePacketsPerFrame, bitratePacketCapFromModel)
            )
        )
        let complexityScale = min(
            2.4,
            max(
                1.0,
                sqrt(
                    Double(effectivePacketsPerFrame) /
                        Double(
                            max(
                                1,
                                ShadowClientRealtimeSessionDefaults.videoReceiveQueueMinimumPacketsPerFrameEstimate * 2
                            )
                        )
                )
            )
        )
        let fpsScale = max(
            0.5,
            Double(normalizedFPS) / Double(max(1, ShadowClientStreamingLaunchBounds.defaultFPS))
        )
        let complexityWindowBoost = Int(((complexityScale - 1.0) * 1.0).rounded(.up))
        let targetFrameWindow = Int(
            (
                Double(ShadowClientRealtimeSessionDefaults.videoReceiveQueueTargetFrameWindow) *
                    pow(fpsScale, 0.25)
            ).rounded(.toNearestOrAwayFromZero)
        ) + max(0, complexityWindowBoost)
        let boundedTargetFrameWindow = min(
            ShadowClientRealtimeSessionDefaults.videoReceiveQueueMaximumFrameWindow,
            max(
                ShadowClientRealtimeSessionDefaults.videoReceiveQueueMinimumFrameWindow,
                targetFrameWindow
            )
        )
        let targetWindowSeconds = min(
            ShadowClientRealtimeSessionDefaults.videoReceiveQueueTargetWindowSeconds,
            max(
                ShadowClientRealtimeSessionDefaults.videoReceiveQueueMinimumTargetWindowSeconds,
                Double(boundedTargetFrameWindow) / Double(max(1, normalizedFPS))
            )
        )
        let receiveQueueCapacityByTimeWindow = Int(
            (Double(estimatedPacketsPerSecond) * targetWindowSeconds).rounded(.up)
        )
        let receiveQueueCapacityByFrameWindow = effectivePacketsPerFrame * boundedTargetFrameWindow

        let receiveQueueCapacity = min(
            ShadowClientRealtimeSessionDefaults.videoReceiveQueueMaximumCapacity,
            max(
                ShadowClientRealtimeSessionDefaults.videoReceiveQueueCapacity,
                min(receiveQueueCapacityByTimeWindow, receiveQueueCapacityByFrameWindow)
            )
        )

        let receiveQueuePressureTrimToRecentPackets = min(
            max(1, receiveQueueCapacity - 1),
            max(
                ShadowClientRealtimeSessionDefaults.videoReceiveQueuePressureTrimToRecentPackets,
                effectivePacketsPerFrame * ShadowClientRealtimeSessionDefaults.videoReceiveQueueTrimFrameWindow
            )
        )
        let receiveQueuePressureSignalInterval = max(
            ShadowClientRealtimeSessionDefaults.videoReceiveQueuePressureSignalInterval,
            max(8, receiveQueuePressureTrimToRecentPackets / 2)
        )
        let receiveQueuePressureTrimInterval = max(
            ShadowClientRealtimeSessionDefaults.videoReceiveQueuePressureTrimInterval,
            receiveQueuePressureTrimToRecentPackets
        )
        let receiveQueueDropRecoveryThreshold = max(
            ShadowClientRealtimeSessionDefaults.videoReceiveQueueDropRecoveryThreshold,
            receiveQueuePressureTrimToRecentPackets *
                ShadowClientRealtimeSessionDefaults.videoReceiveQueueRecoveryFrameWindow
        )
        let receiveQueueIngressSheddingMaximumBurstPackets = min(
            receiveQueueCapacity,
            max(
                ShadowClientRealtimeSessionDefaults.videoReceiveQueueIngressSheddingMaximumBurstPackets,
                receiveQueuePressureTrimToRecentPackets
            )
        )

        let fpsScaledDecodeCapacity = max(
            ShadowClientRealtimeSessionDefaults.videoDecodeQueueCapacity,
            Int((Double(normalizedFPS) / 4.0 * pow(complexityScale, 0.95)).rounded(.up))
        )
        let decodeQueueCapacity = min(
            ShadowClientRealtimeSessionDefaults.videoDecodeQueueMaximumCapacity,
            max(ShadowClientRealtimeSessionDefaults.videoDecodeQueueCapacity, fpsScaledDecodeCapacity)
        )
        let decodeQueueConsumerMaxBufferedUnits = min(
            max(1, decodeQueueCapacity - 1),
            max(
                ShadowClientRealtimeSessionDefaults.videoDecodeQueueConsumerMaxBufferedUnits,
                Int(
                    (
                        Double(decodeQueueCapacity) *
                            ShadowClientRealtimeSessionDefaults.videoDecodeQueueConsumerTargetRatio
                    ).rounded(.up)
                )
            )
        )
        let decodeQueueProducerSheddingHighWatermark = min(
            max(1, decodeQueueCapacity - 1),
            max(
                ShadowClientRealtimeSessionDefaults.videoDecodeQueueProducerSheddingHighWatermark,
                decodeQueueConsumerMaxBufferedUnits + max(2, decodeQueueCapacity / 8)
            )
        )
        let decodeQueueProducerTrimToRecentUnits = min(
            decodeQueueProducerSheddingHighWatermark,
            max(
                decodeQueueConsumerMaxBufferedUnits,
                max(
                    ShadowClientRealtimeSessionDefaults.videoDecodeQueueProducerTrimToRecentUnits,
                    decodeQueueProducerSheddingHighWatermark -
                        max(2, decodeQueueProducerSheddingHighWatermark / 4)
                )
            )
        )
        let depacketizerDecodeQueueShedHighWatermark = min(
            max(1, decodeQueueCapacity - 1),
            max(
                ShadowClientRealtimeSessionDefaults.videoDepacketizerDecodeQueueShedHighWatermark,
                decodeQueueConsumerMaxBufferedUnits
            )
        )
        let depacketizerDecodeQueueProbeIntervalPackets = max(
            1,
            min(
                ShadowClientRealtimeSessionDefaults.videoDepacketizerDecodeQueueProbeIntervalPackets,
                max(1, bitratePacketsPerFrame / 2)
            )
        )

        return .init(
            receiveQueueCapacity: receiveQueueCapacity,
            receiveQueuePressureSignalInterval: receiveQueuePressureSignalInterval,
            receiveQueuePressureTrimInterval: receiveQueuePressureTrimInterval,
            receiveQueuePressureTrimToRecentPackets: receiveQueuePressureTrimToRecentPackets,
            receiveQueueDropRecoveryThreshold: receiveQueueDropRecoveryThreshold,
            receiveQueueIngressSheddingMaximumBurstPackets: receiveQueueIngressSheddingMaximumBurstPackets,
            decodeQueueCapacity: decodeQueueCapacity,
            decodeQueueConsumerMaxBufferedUnits: decodeQueueConsumerMaxBufferedUnits,
            decodeQueueProducerSheddingHighWatermark: decodeQueueProducerSheddingHighWatermark,
            decodeQueueProducerTrimToRecentUnits: decodeQueueProducerTrimToRecentUnits,
            depacketizerDecodeQueueProbeIntervalPackets: depacketizerDecodeQueueProbeIntervalPackets,
            depacketizerDecodeQueueShedHighWatermark: depacketizerDecodeQueueShedHighWatermark
        )
    }

    static func isLikelyVideoFrameBoundary(
        marker: Bool,
        payload: Data
    ) -> Bool {
        if marker {
            return true
        }
        // NV video packet header carries EOF/FEC metadata at fixed offsets.
        guard payload.count >= 12 else {
            return false
        }

        let flags = payload[payload.startIndex + 8]
        guard (flags & 0x02) != 0 else {
            return false
        }
        let multiFecBlocks = payload[payload.startIndex + 11]
        let fecCurrentBlockNumber = (multiFecBlocks >> 4) & 0x03
        let fecLastBlockNumber = (multiFecBlocks >> 6) & 0x03
        return fecCurrentBlockNumber == fecLastBlockNumber
    }

    static func isLikelyVideoFrameStart(payload: Data) -> Bool {
        // NV packet header encodes SOF/FEC block metadata at fixed offsets.
        guard payload.count >= 12 else {
            return false
        }

        let flags = payload[payload.startIndex + 8]
        let hasSOF = (flags & 0x01) != 0
        guard hasSOF else {
            return false
        }

        let multiFecBlocks = payload[payload.startIndex + 11]
        let fecCurrentBlockNumber = (multiFecBlocks >> 4) & 0x03
        return fecCurrentBlockNumber == 0
    }

    private static func decodeLEB128(
        in data: Data,
        from startIndex: Int
    ) -> (value: Int, nextIndex: Int)? {
        guard startIndex < data.count else {
            return nil
        }

        var value = 0
        var shift = 0
        var index = startIndex

        while index < data.count, shift <= 56 {
            let byte = Int(data[index])
            value |= (byte & 0x7F) << shift
            index += 1
            if (byte & 0x80) == 0 {
                return (value, index)
            }
            shift += 7
        }

        return nil
    }

    private static func renderState(forStreamError error: Error) -> ShadowClientRealtimeSessionSurfaceContext.RenderState {
        let normalizedMessage = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = normalizedMessage.isEmpty ? "RTSP transport connection closed." : normalizedMessage

        if isConnectionTerminationError(error, message: fallback) {
            return .disconnected(fallback)
        }

        return .failed(fallback)
    }

    private static func isConnectionTerminationError(_ error: Error, message: String) -> Bool {
        if let rtspError = error as? ShadowClientRTSPInterleavedClientError {
            switch rtspError {
            case .connectionClosed, .connectionFailed:
                return true
            case .invalidURL, .requestFailed, .invalidResponse:
                break
            }
        }

        let normalized = message.lowercased()
        let terminationSignatures = [
            "connection reset by peer",
            "connection closed",
            "connection timed out",
            "no message available on stream",
            "broken pipe",
            "network is down",
            "no route to host",
            "not connected",
            "network connection was lost",
            "software caused connection abort",
            "transport connection closed",
        ]
        return terminationSignatures.contains(where: normalized.contains)
    }
}

private struct ShadowClientSendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

private enum ShadowClientRTSPInterleavedClientError: Error, Equatable {
    case invalidURL
    case connectionFailed
    case requestFailed(String)
    case invalidResponse
    case connectionClosed
}

extension ShadowClientRTSPInterleavedClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "RTSP endpoint URL is invalid."
        case .connectionFailed:
            return "RTSP transport connection timed out."
        case let .requestFailed(message):
            return message
        case .invalidResponse:
            return "RTSP server returned an invalid response."
        case .connectionClosed:
            return "RTSP transport connection closed."
        }
    }
}

private struct ShadowClientRTSPResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

struct ShadowClientRTPPacket {
    let isRTP: Bool
    let channel: Int
    let sequenceNumber: UInt16
    let marker: Bool
    let payloadType: Int
    let payload: Data
}

struct ShadowClientRTPPacketPayloadParseResult: Equatable, Sendable {
    let sequenceNumber: UInt16
    let marker: Bool
    let payloadType: Int
    let payload: Data
}

enum ShadowClientRTPPacketPayloadParserError: Error, Equatable {
    case invalidPacket
}

enum ShadowClientRTPPacketPayloadParser {
    static func parse(
        _ payload: Data
    ) throws -> ShadowClientRTPPacketPayloadParseResult {
        // Data slices may carry non-zero startIndex. Normalize once to keep direct
        // integer indexing stable across parser/depacketizer boundaries.
        let packetBytes = payload.startIndex == 0 ? payload : Data(payload)

        guard packetBytes.count >= ShadowClientRTSPProtocolProfile.rtpMinimumHeaderLength else {
            throw ShadowClientRTPPacketPayloadParserError.invalidPacket
        }

        let version = packetBytes[0] >> ShadowClientRTSPProtocolProfile.rtpVersionShift
        guard version == ShadowClientRTSPProtocolProfile.rtpVersion else {
            throw ShadowClientRTPPacketPayloadParserError.invalidPacket
        }

        let hasPadding = (packetBytes[0] & ShadowClientRTSPProtocolProfile.rtpPaddingMask) != 0
        let hasExtension = (packetBytes[0] & ShadowClientRTSPProtocolProfile.rtpExtensionMask) != 0
        let csrcCount = Int(packetBytes[0] & ShadowClientRTSPProtocolProfile.rtpCSRCCountMask)
        let marker = (packetBytes[1] & ShadowClientRTSPProtocolProfile.rtpMarkerMask) != 0
        let payloadType = Int(packetBytes[1] & ShadowClientRTSPProtocolProfile.rtpPayloadTypeMask)
        let sequenceNumber = (UInt16(packetBytes[2]) << 8) | UInt16(packetBytes[3])

        var headerLength = ShadowClientRTSPProtocolProfile.rtpMinimumHeaderLength + csrcCount * 4
        guard packetBytes.count >= headerLength else {
            throw ShadowClientRTPPacketPayloadParserError.invalidPacket
        }

        if hasExtension {
            // Moonlight/Sunshine RTP video packets carry a fixed 4-byte extension preamble
            // before NV packet data. The extension length field is not used in the same way
            // as generic RFC3550 streams, so we intentionally skip only these 4 bytes.
            headerLength += 4
            guard packetBytes.count >= headerLength else {
                throw ShadowClientRTPPacketPayloadParserError.invalidPacket
            }
        }

        var endIndex = packetBytes.count
        if hasPadding, let padding = packetBytes.last {
            endIndex = max(headerLength, packetBytes.count - Int(padding))
        }
        guard endIndex > headerLength else {
            throw ShadowClientRTPPacketPayloadParserError.invalidPacket
        }

        return ShadowClientRTPPacketPayloadParseResult(
            sequenceNumber: sequenceNumber,
            marker: marker,
            payloadType: payloadType,
            payload: Data(packetBytes[headerLength..<endIndex])
        )
    }
}

struct ShadowClientRTPVideoReorderBuffer: Sendable {
    private let targetDepth: Int
    private let maximumDepth: Int
    private var expectedSequence: UInt16?
    private var packetsBySequence: [UInt16: ShadowClientRTPPacket] = [:]

    init(targetDepth: Int = 4, maximumDepth: Int = 96) {
        self.targetDepth = max(2, targetDepth)
        self.maximumDepth = max(self.targetDepth, maximumDepth)
    }

    mutating func reset() {
        expectedSequence = nil
        packetsBySequence.removeAll(keepingCapacity: false)
    }

    mutating func enqueue(_ packet: ShadowClientRTPPacket) -> [ShadowClientRTPPacket] {
        guard packetsBySequence[packet.sequenceNumber] == nil else {
            return []
        }

        packetsBySequence[packet.sequenceNumber] = packet
        if expectedSequence == nil {
            expectedSequence = packet.sequenceNumber
        }

        var readyPackets = drainContiguousPackets()
        if readyPackets.isEmpty, packetsBySequence.count >= targetDepth {
            advanceExpectedSequenceToNearestPacket()
            readyPackets = drainContiguousPackets()
        }

        trimOverflow()
        return readyPackets
    }

    private mutating func drainContiguousPackets() -> [ShadowClientRTPPacket] {
        var readyPackets: [ShadowClientRTPPacket] = []
        while let expectedSequence,
              let packet = packetsBySequence.removeValue(forKey: expectedSequence)
        {
            readyPackets.append(packet)
            self.expectedSequence = expectedSequence &+ 1
        }
        return readyPackets
    }

    private mutating func advanceExpectedSequenceToNearestPacket() {
        guard let expectedSequence,
              !packetsBySequence.isEmpty
        else {
            return
        }

        var nearestSequence: UInt16?
        var nearestDistance = UInt16.max
        for sequence in packetsBySequence.keys {
            let distance = sequenceDistance(from: expectedSequence, to: sequence)
            if nearestSequence == nil || distance < nearestDistance {
                nearestSequence = sequence
                nearestDistance = distance
            }
        }
        self.expectedSequence = nearestSequence
    }

    private mutating func trimOverflow() {
        guard packetsBySequence.count > maximumDepth,
              let expectedSequence
        else {
            return
        }

        var overflow = packetsBySequence.count - maximumDepth
        while overflow > 0 {
            var farthestSequence: UInt16?
            var farthestDistance: UInt16 = 0
            for sequence in packetsBySequence.keys {
                let distance = sequenceDistance(from: expectedSequence, to: sequence)
                if farthestSequence == nil || distance > farthestDistance {
                    farthestSequence = sequence
                    farthestDistance = distance
                }
            }
            guard let farthestSequence else {
                break
            }
            packetsBySequence.removeValue(forKey: farthestSequence)
            overflow -= 1
        }
    }

    private func sequenceDistance(from start: UInt16, to end: UInt16) -> UInt16 {
        end &- start
    }
}

private actor ShadowClientRTSPInterleavedClient {
    private let timeout: Duration
    private let onControlRoundTripSample: (@Sendable (Double) async -> Void)?
    private let onAudioOutputStateChanged: (@Sendable (ShadowClientRealtimeAudioOutputState) async -> Void)?
    private let defaultClientPortBase: UInt16 = ShadowClientRTSPProtocolProfile.clientPortBase
    private let queue = DispatchQueue(label: "com.skyline23.shadowclient.rtsp.connection")
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "RTSP")
    private var connection: NWConnection?
    private var readBuffer = Data()
    private var cseq = 1
    private var sessionHeader: String?
    private var remoteHost: NWEndpoint.Host?
    private var localHost: NWEndpoint.Host?
    private var audioServerPort: NWEndpoint.Port?
    private var videoServerPort: NWEndpoint.Port?
    private var controlServerPort: NWEndpoint.Port?
    private var audioPingPayload: Data?
    private var videoPingPayload: Data?
    private var audioTrackDescriptor: ShadowClientRTSPAudioTrackDescriptor?
    private var prePlayVideoUDPSocket: ShadowClientUDPDatagramSocket?
    private var prePlayVideoPingWarmupTask: Task<Void, Never>?
    private var controlConnectData: UInt32?
    private var controlChannelRuntime: ShadowClientSunshineControlChannelRuntime?
    private var controlChannelMode: ShadowClientSunshineControlChannelMode = .plaintext
    private var hasStartedControlChannelBootstrap = false
    private var useSessionIdentifierV1 = false
    private var remoteInputKey: Data?
    private var remoteInputKeyID: UInt32?
    private var audioEncryptionConfiguration: ShadowClientRealtimeAudioEncryptionConfiguration?
    private var negotiatedClientPortBase: UInt16 = ShadowClientRTSPProtocolProfile.clientPortBase
    private var loggedInputSendKinds = Set<String>()
    private var loggedInputDropKinds = Set<String>()

    init(
        timeout: Duration,
        onControlRoundTripSample: (@Sendable (Double) async -> Void)? = nil,
        onAudioOutputStateChanged: (@Sendable (ShadowClientRealtimeAudioOutputState) async -> Void)? = nil
    ) {
        self.timeout = timeout
        self.onControlRoundTripSample = onControlRoundTripSample
        self.onAudioOutputStateChanged = onAudioOutputStateChanged
    }

    func start(
        url: URL,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration,
        remoteInputKey: Data?,
        remoteInputKeyID: UInt32?
    ) async throws -> ShadowClientRTSPVideoTrackDescriptor {
        self.remoteInputKey = remoteInputKey
        self.remoteInputKeyID = remoteInputKeyID
        hasStartedControlChannelBootstrap = false
        loggedInputSendKinds.removeAll(keepingCapacity: true)
        loggedInputDropKinds.removeAll(keepingCapacity: true)
        audioTrackDescriptor = nil
        let normalizedURL = normalizeRTSPURL(url)
        guard let host = normalizedURL.host else {
            throw ShadowClientRTSPInterleavedClientError.invalidURL
        }
        remoteHost = .init(host)
        let portValue = normalizedURL.port ?? ShadowClientRTSPProtocolProfile.defaultPort
        guard let port = NWEndpoint.Port(rawValue: UInt16(portValue)) else {
            throw ShadowClientRTSPInterleavedClientError.invalidURL
        }

        let connection = NWConnection(
            host: .init(host),
            port: port,
            using: .tcp
        )
        self.connection = connection
        try await waitForReady(connection)
        if let resolvedHost = resolvedRemoteHost(from: connection) {
            remoteHost = resolvedHost
            logger.notice("RTSP resolved remote endpoint host \(String(describing: resolvedHost), privacy: .public)")
        }
        if let resolvedHost = resolvedLocalHost(from: connection) {
            localHost = resolvedHost
            logger.notice("RTSP resolved local endpoint host \(String(describing: resolvedHost), privacy: .public)")
        }
        logger.notice("RTSP connected to \(host, privacy: .public):\(portValue, privacy: .public)")
        logger.notice("RTSP session URL \(normalizedURL.absoluteString, privacy: .public)")

        do {
            _ = try await sendRequest(
                method: ShadowClientRTSPRequestDefaults.optionsMethod,
                url: normalizedURL.absoluteString,
                headers: [
                    ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
                ]
            )
        } catch {
            logger.notice(
                "RTSP OPTIONS retry on fresh TCP connection after failure: \(error.localizedDescription, privacy: .public)"
            )
            try await reconnect(host: host, port: port)
            do {
                _ = try await sendRequest(
                    method: ShadowClientRTSPRequestDefaults.optionsMethod,
                    url: normalizedURL.absoluteString,
                    headers: [
                        ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
                    ]
                )
            } catch {
                throw ShadowClientRTSPInterleavedClientError.requestFailed(
                    "RTSP OPTIONS failed: \(error.localizedDescription)"
                )
            }
        }

        let describe: ShadowClientRTSPResponse
        do {
            describe = try await sendDescribeRequest(
                url: normalizedURL.absoluteString,
                headers: [
                    ShadowClientRTSPRequestDefaults.headerAccept: ShadowClientRTSPRequestDefaults.acceptSDP,
                    ShadowClientRTSPRequestDefaults.headerIfModifiedSince: ShadowClientRTSPRequestDefaults.ifModifiedSinceEpoch,
                    ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
                ]
            )
        } catch {
            logger.notice(
                "RTSP DESCRIBE retry on fresh TCP connection after failure: \(error.localizedDescription, privacy: .public)"
            )
            // Some GameStream/Sunshine stacks close the RTSP socket after OPTIONS.
            // Retry DESCRIBE on a fresh socket before failing the handshake.
            try await reconnect(host: host, port: port)
            do {
                describe = try await sendDescribeRequest(
                    url: normalizedURL.absoluteString,
                    headers: [
                        ShadowClientRTSPRequestDefaults.headerAccept: ShadowClientRTSPRequestDefaults.acceptSDP,
                        ShadowClientRTSPRequestDefaults.headerIfModifiedSince: ShadowClientRTSPRequestDefaults.ifModifiedSinceEpoch,
                        ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
                    ]
                )
            } catch {
                throw ShadowClientRTSPInterleavedClientError.requestFailed(
                    "RTSP DESCRIBE failed: \(error.localizedDescription)"
                )
            }
        }
        let sdp = String(data: describe.body, encoding: .utf8) ?? ""
        logger.notice("RTSP DESCRIBE parsed body bytes \(describe.body.count, privacy: .public), characters \(sdp.count, privacy: .public)")

        // Keep one RTSP socket for the SETUP/ANNOUNCE/PLAY sequence, like Moonlight.
        // Sunshine can acknowledge PLAY on a new socket but still keep UDP routing tied
        // to the transport state negotiated on the original connection.
        try await reconnect(host: host, port: port)
        let contentBase =
            describe.headers[ShadowClientRTSPRequestDefaults.responseHeaderContentBase] ??
            describe.headers[ShadowClientRTSPRequestDefaults.responseHeaderContentLocation]
        let parsedTrack: ShadowClientRTSPVideoTrackDescriptor
        if sdp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parsedTrack = fallbackVideoTrackDescriptor(
                sessionURL: normalizedURL.absoluteString,
                describeSDP: nil,
                videoConfiguration: videoConfiguration
            )
            logger.notice("RTSP DESCRIBE returned empty SDP; using fallback video track \(parsedTrack.controlURL, privacy: .public)")
        } else {
            do {
                parsedTrack = try ShadowClientRTSPSessionDescriptionParser.parseVideoTrack(
                    sdp: sdp,
                    contentBase: contentBase,
                    fallbackSessionURL: normalizedURL.absoluteString
                )
            } catch {
                parsedTrack = fallbackVideoTrackDescriptor(
                    sessionURL: normalizedURL.absoluteString,
                    describeSDP: sdp,
                    videoConfiguration: videoConfiguration
                )
                logger.notice("RTSP track parse failed (\(error.localizedDescription, privacy: .public)); using fallback video track \(parsedTrack.controlURL, privacy: .public)")
            }
        }
        let announceCodec = preferredAnnounceCodec(
            preferredCodec: videoConfiguration.preferredCodec,
            describedCodec: parsedTrack.codec
        )
        if announceCodec != parsedTrack.codec {
            logger.notice(
                "RTSP overriding described codec \(String(describing: parsedTrack.codec), privacy: .public) with preferred codec \(String(describing: announceCodec), privacy: .public)"
            )
        }
        let track = ShadowClientRTSPVideoTrackDescriptor(
            codec: announceCodec,
            rtpPayloadType: parsedTrack.rtpPayloadType,
            candidateRTPPayloadTypes: parsedTrack.candidateRTPPayloadTypes,
            controlURL: parsedTrack.controlURL,
            parameterSets: announceCodec == parsedTrack.codec ? parsedTrack.parameterSets : []
        )

        negotiatedClientPortBase = ShadowClientRTSPClientPortAllocator.selectClientPortBase(
            preferred: defaultClientPortBase,
            localHost: localHost
        )
        if negotiatedClientPortBase != defaultClientPortBase {
            logger.notice(
                "RTSP selected alternate client port base \(self.negotiatedClientPortBase, privacy: .public) (preferred \(self.defaultClientPortBase, privacy: .public))"
            )
        }
        let setupTransportHeader = ShadowClientRTSPProtocolProfile.setupTransportHeader(
            clientPortBase: negotiatedClientPortBase
        )
        let setupURLCandidates = videoControlURLCandidates(
            primary: track.controlURL,
            sessionURL: normalizedURL.absoluteString
        )
        let preferredOpusChannelCount =
            ShadowClientRealtimeAudioSessionRuntime.preferredOpusChannelCountForNegotiation(
                surroundRequested: videoConfiguration.enableSurroundAudio
            )
        if videoConfiguration.enableSurroundAudio, preferredOpusChannelCount <= 2 {
            logger.notice(
                "RTSP audio negotiation downgraded to stereo because no runtime multichannel Opus decoder is available"
            )
        }
        var parsedAudioTrack = ShadowClientRTSPSessionDescriptionParser.parseAudioTrack(
            sdp: sdp,
            contentBase: contentBase,
            fallbackSessionURL: normalizedURL.absoluteString,
            preferredOpusChannelCount: preferredOpusChannelCount
        )
        if let negotiatedAudioTrack = parsedAudioTrack,
           !ShadowClientRealtimeAudioSessionRuntime.canDecode(track: negotiatedAudioTrack)
        {
            logger.notice(
                "RTSP selected audio track is not decodable at runtime (codec=\(negotiatedAudioTrack.codec.label, privacy: .public), channels=\(negotiatedAudioTrack.channelCount, privacy: .public)); retrying with stereo-preferred negotiation"
            )
            let stereoPreferredTrack = ShadowClientRTSPSessionDescriptionParser.parseAudioTrack(
                sdp: sdp,
                contentBase: contentBase,
                fallbackSessionURL: normalizedURL.absoluteString,
                preferredOpusChannelCount: 2
            )
            if let stereoPreferredTrack,
               ShadowClientRealtimeAudioSessionRuntime.canDecode(track: stereoPreferredTrack)
            {
                parsedAudioTrack = stereoPreferredTrack
            } else {
                parsedAudioTrack = nil
                logger.error(
                    "RTSP could not resolve a decodable audio track from SDP; continuing without negotiated audio track"
                )
            }
        }
        if let parsedAudioTrack {
            audioTrackDescriptor = parsedAudioTrack
            logger.notice(
                "RTSP audio track parsed codec=\(parsedAudioTrack.codec.label, privacy: .public) payloadType=\(parsedAudioTrack.rtpPayloadType, privacy: .public) sampleRate=\(parsedAudioTrack.sampleRate, privacy: .public) channels=\(parsedAudioTrack.channelCount, privacy: .public)"
            )
        }
        let audioControls = (try? ShadowClientRTSPSessionDescriptionParser.parseAudioControlURLs(
            sdp: sdp,
            contentBase: contentBase,
            fallbackSessionURL: normalizedURL.absoluteString
        )) ?? []
        let prioritizedAudioControls = {
            if let parsedControlURL = parsedAudioTrack?.controlURL {
                return [parsedControlURL] + audioControls
            }
            return audioControls
        }()
        let audioSetupCandidates = audioControlURLCandidates(
            controlsFromSDP: prioritizedAudioControls,
            sessionURL: normalizedURL.absoluteString
        )
        if !audioSetupCandidates.isEmpty {
            for controlURL in audioSetupCandidates {
                var headers: [String: String] = [
                    ShadowClientRTSPRequestDefaults.headerTransport: setupTransportHeader,
                    ShadowClientRTSPRequestDefaults.headerIfModifiedSince: ShadowClientRTSPRequestDefaults.ifModifiedSinceEpoch,
                    ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
                ]
                if let sessionHeader {
                    headers[ShadowClientRTSPRequestDefaults.headerSession] = sessionHeader
                }

                do {
                    let response = try await sendRequestWithReconnectRetry(
                        method: ShadowClientRTSPRequestDefaults.setupMethod,
                        url: controlURL,
                        headers: headers,
                        host: host,
                        port: port
                    )
                    if sessionHeader == nil,
                       let session = response.headers[ShadowClientRTSPRequestDefaults.responseHeaderSession]
                    {
                        sessionHeader = session.split(separator: ";").first.map(String.init)
                    }
                    if let transport = response.headers[ShadowClientRTSPRequestDefaults.responseHeaderTransport],
                       let parsedPort = ShadowClientRTSPTransportHeaderParser.parseServerPort(from: transport)
                    {
                        audioServerPort = NWEndpoint.Port(rawValue: parsedPort)
                        logger.notice("RTSP negotiated UDP audio server port \(parsedPort, privacy: .public)")
                    }
                    audioPingPayload = ShadowClientRTSPTransportHeaderParser.parseSunshinePingPayload(
                        from: response.headers[ShadowClientRTSPRequestDefaults.responseHeaderPingPayload]
                    )
                    if let audioPingPayload,
                       let token = String(data: audioPingPayload, encoding: .utf8)
                    {
                        logger.notice("RTSP audio ping payload token \(token, privacy: .public)")
                    } else {
                        logger.notice("RTSP audio ping payload token unavailable; legacy ping fallback only")
                    }
                    logger.notice("RTSP audio SETUP ok for \(controlURL, privacy: .public)")
                    break
                } catch {
                    logger.error("RTSP audio SETUP failed for \(controlURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        let controlHost = remoteHost ?? .init(host)

        var setup: ShadowClientRTSPResponse?
        var selectedSetupURL: String?
        var setupError: Error?
        for setupURL in setupURLCandidates {
            do {
                var headers: [String: String] = [
                    ShadowClientRTSPRequestDefaults.headerTransport: setupTransportHeader,
                    ShadowClientRTSPRequestDefaults.headerIfModifiedSince: ShadowClientRTSPRequestDefaults.ifModifiedSinceEpoch,
                    ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
                ]
                if let sessionHeader {
                    headers[ShadowClientRTSPRequestDefaults.headerSession] = sessionHeader
                }
                let response = try await sendRequestWithReconnectRetry(
                    method: ShadowClientRTSPRequestDefaults.setupMethod,
                    url: setupURL,
                    headers: headers,
                    host: host,
                    port: port
                )
                setup = response
                selectedSetupURL = setupURL
                break
            } catch {
                setupError = error
                logger.error("RTSP video SETUP failed for \(setupURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        guard let setup else {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP video SETUP failed: \(setupError?.localizedDescription ?? "unknown")"
            )
        }
        if let session = setup.headers[ShadowClientRTSPRequestDefaults.responseHeaderSession] {
            sessionHeader = session.split(separator: ";").first.map(String.init)
        }
        if let transport = setup.headers[ShadowClientRTSPRequestDefaults.responseHeaderTransport],
           let parsedPort = ShadowClientRTSPTransportHeaderParser.parseServerPort(from: transport)
        {
            videoServerPort = NWEndpoint.Port(rawValue: parsedPort)
            logger.notice("RTSP negotiated UDP video server port \(parsedPort, privacy: .public)")
        } else {
            videoServerPort = nil
        }
        videoPingPayload = ShadowClientRTSPTransportHeaderParser.parseSunshinePingPayload(
            from: setup.headers[ShadowClientRTSPRequestDefaults.responseHeaderPingPayload]
        )
        if let videoPingPayload,
           let token = String(data: videoPingPayload, encoding: .utf8)
        {
            logger.notice("RTSP video ping payload token \(token, privacy: .public)")
        } else {
            logger.notice("RTSP video ping payload token unavailable; legacy ping fallback only")
        }
        logger.notice("RTSP video SETUP ok for payload type \(track.rtpPayloadType, privacy: .public) via \(selectedSetupURL ?? track.controlURL, privacy: .public)")
        prepareVideoPingBeforePlay(host: controlHost)

        var parsedControlConnectData: UInt32?
        var parsedControlServerPort: NWEndpoint.Port?
        let controlSetupCandidates = controlStreamURLCandidates(
            sessionURL: normalizedURL.absoluteString
        )
        for controlURL in controlSetupCandidates {
            var headers: [String: String] = [
                ShadowClientRTSPRequestDefaults.headerTransport: setupTransportHeader,
                ShadowClientRTSPRequestDefaults.headerIfModifiedSince: ShadowClientRTSPRequestDefaults.ifModifiedSinceEpoch,
                ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
            ]
            if let sessionHeader {
                headers[ShadowClientRTSPRequestDefaults.headerSession] = sessionHeader
            }

            do {
                let response = try await sendRequestWithReconnectRetry(
                    method: ShadowClientRTSPRequestDefaults.setupMethod,
                    url: controlURL,
                    headers: headers,
                    host: host,
                    port: port
                )
                if let transport = response.headers[ShadowClientRTSPRequestDefaults.responseHeaderTransport],
                   let parsedPort = ShadowClientRTSPTransportHeaderParser.parseServerPort(from: transport)
                {
                    parsedControlServerPort = NWEndpoint.Port(rawValue: parsedPort)
                    logger.notice("RTSP negotiated UDP control server port \(parsedPort, privacy: .public)")
                }
                if let parsed = ShadowClientRTSPTransportHeaderParser.parseSunshineControlConnectData(
                    from: response.headers[ShadowClientRTSPRequestDefaults.responseHeaderConnectData]
                ) {
                    parsedControlConnectData = parsed
                    logger.notice("RTSP control connect data \(parsed, privacy: .public)")
                }
                logger.notice("RTSP control SETUP ok for \(controlURL, privacy: .public)")
                break
            } catch {
                logger.error("RTSP control SETUP failed for \(controlURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        controlConnectData = parsedControlConnectData
        controlServerPort = parsedControlServerPort

        let handshakeNegotiation = ShadowClientSunshineHandshakeNegotiation(
            audioPingPayload: audioPingPayload,
            videoPingPayload: videoPingPayload,
            controlConnectData: parsedControlConnectData,
            encryptionRequestedFlags: parseSunshineEncryptionRequestedFlags(from: sdp),
            prefersSessionIdentifierV1: ShadowClientSunshineSessionDefaults.prefersSessionIdentifierV1,
            supportsEncryptedControlChannelV2: ShadowClientSunshineSessionDefaults.supportsEncryptedControlChannelV2 && remoteInputKey != nil,
            supportsEncryptedAudioTransport: remoteInputKey != nil && remoteInputKeyID != nil
        )
        useSessionIdentifierV1 = handshakeNegotiation.supportsSessionIdentifierV1
        if handshakeNegotiation.controlChannelEncryptionEnabled, let remoteInputKey
        {
            controlChannelMode = .encryptedV2(key: remoteInputKey)
        } else {
            controlChannelMode = .plaintext
        }
        let controlModeLabel: String
        switch controlChannelMode {
        case .plaintext:
            controlModeLabel = "plaintext"
        case .encryptedV2:
            controlModeLabel = "encrypted-v2"
        }
        if handshakeNegotiation.audioEncryptionEnabled,
           let remoteInputKey,
           let remoteInputKeyID
        {
            audioEncryptionConfiguration = .init(
                key: remoteInputKey,
                keyID: remoteInputKeyID
            )
        } else {
            audioEncryptionConfiguration = nil
        }
        let audioEncryptionLabel = handshakeNegotiation.audioEncryptionEnabled ? "encrypted" : "plaintext"
        logger.notice(
            "RTSP negotiation session-id-v1=\(handshakeNegotiation.supportsSessionIdentifierV1, privacy: .public) ml-flags=\(handshakeNegotiation.moonlightFeatureFlags, privacy: .public) encryption-enabled=\(handshakeNegotiation.encryptionEnabledFlags, privacy: .public) control-mode=\(controlModeLabel, privacy: .public) audio-mode=\(audioEncryptionLabel, privacy: .public)"
        )

        let announcePayload = ShadowClientRTSPAnnouncePayloadBuilder.build(
            hostAddress: host,
            videoConfiguration: videoConfiguration,
            codec: track.codec,
            videoPort: videoServerPort?.rawValue ?? ShadowClientRealtimeSessionDefaults.fallbackVideoPort,
            moonlightFeatureFlags: handshakeNegotiation.moonlightFeatureFlags,
            encryptionEnabledFlags: handshakeNegotiation.encryptionEnabledFlags
        )
        let announceTargets = announceURLCandidates(sessionURL: normalizedURL.absoluteString)
        var announceHeaders: [String: String] = [
            ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
            ShadowClientRTSPRequestDefaults.headerContentType: ShadowClientRTSPRequestDefaults.acceptSDP,
            ShadowClientRTSPRequestDefaults.headerContentLength: "\(announcePayload.count)",
        ]
        if let sessionHeader {
            announceHeaders[ShadowClientRTSPRequestDefaults.headerSession] = sessionHeader
        }

        var announceSucceeded = false
        for announceTarget in announceTargets {
            do {
                _ = try await sendRequestWithReconnectRetry(
                    method: ShadowClientRTSPRequestDefaults.announceMethod,
                    url: announceTarget,
                    headers: announceHeaders,
                    body: announcePayload,
                    host: host,
                    port: port
                )
                logger.notice("RTSP ANNOUNCE ok for \(announceTarget, privacy: .public)")
                announceSucceeded = true
                break
            } catch {
                logger.error("RTSP ANNOUNCE failed for \(announceTarget, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if !announceSucceeded {
            logger.error("RTSP ANNOUNCE did not succeed on any target; continuing to PLAY for compatibility")
        }

        let playHeaders: [String: String] = [
            ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
        ]
        let resolvedPlayHeaders: [String: String]
        if let sessionHeader {
            var headers = playHeaders
            headers["Session"] = sessionHeader
            resolvedPlayHeaders = headers
        } else {
            resolvedPlayHeaders = playHeaders
        }

        let playTargets = playURLCandidates(sessionURL: normalizedURL.absoluteString)
        var playSucceeded = false
        var lastPlayError: Error?
        for playTarget in playTargets {
            do {
                _ = try await sendRequestWithReconnectRetry(
                    method: ShadowClientRTSPRequestDefaults.playMethod,
                    url: playTarget,
                    headers: resolvedPlayHeaders,
                    host: host,
                    port: port
                )
                logger.notice("RTSP PLAY ok for \(playTarget, privacy: .public)")
                playSucceeded = true
                break
            } catch {
                lastPlayError = error
                logger.error("RTSP PLAY failed for \(playTarget, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        guard playSucceeded else {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP PLAY failed: \(lastPlayError?.localizedDescription ?? "unknown")"
            )
        }

        var didStartSunshineControl = false
        if controlServerPort != nil {
            await ensureSunshineControlChannelStarted(fallbackHost: remoteHost ?? .init(host))
            didStartSunshineControl = hasStartedControlChannelBootstrap
            if didStartSunshineControl {
                logger.debug("RTSP control path negotiated; Sunshine control bootstrap ready")
            } else {
                logger.debug("RTSP control path negotiated; Sunshine bootstrap unavailable, trying legacy first-frame compatibility probe")
            }
        }
        if !didStartSunshineControl {
            await attemptLegacyFirstFrameBootstrap(host: remoteHost ?? .init(host))
        }
        return track
    }

    private func preferredAnnounceCodec(
        preferredCodec: ShadowClientVideoCodecPreference,
        describedCodec: ShadowClientVideoCodec
    ) -> ShadowClientVideoCodec {
        switch preferredCodec {
        case .auto:
            return describedCodec
        case .av1:
            return .av1
        case .h265:
            return .h265
        case .h264:
            return .h264
        }
    }

    private func reconnect(
        host: String,
        port: NWEndpoint.Port
    ) async throws {
        connection?.cancel()
        connection = nil
        readBuffer.removeAll(keepingCapacity: false)

        let nextConnection = NWConnection(
            host: .init(host),
            port: port,
            using: .tcp
        )
        connection = nextConnection
        try await waitForReady(nextConnection)
        if let resolvedHost = resolvedRemoteHost(from: nextConnection) {
            remoteHost = resolvedHost
        } else {
            remoteHost = .init(host)
        }
        localHost = resolvedLocalHost(from: nextConnection)
    }

    private func normalizeRTSPURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        if components.path.isEmpty {
            components.path = "/"
        }
        return components.url ?? url
    }

    private func fallbackVideoTrackDescriptor(
        sessionURL: String,
        describeSDP: String?,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration
    ) -> ShadowClientRTSPVideoTrackDescriptor {
        let codec: ShadowClientVideoCodec
        switch videoConfiguration.preferredCodec {
        case .av1:
            codec = .av1
        case .h265:
            codec = .h265
        case .h264:
            codec = .h264
        case .auto:
            codec = inferFallbackCodec(fromDescribeSDP: describeSDP)
        }

        let controlURL = videoControlURLCandidates(
            primary: sessionURL,
            sessionURL: sessionURL
        ).first ?? sessionURL

        let payloadType = inferFallbackPayloadType(
            fromDescribeSDP: describeSDP,
            codec: codec
        )

        return ShadowClientRTSPVideoTrackDescriptor(
            codec: codec,
            rtpPayloadType: payloadType,
            candidateRTPPayloadTypes: [payloadType],
            controlURL: controlURL,
            parameterSets: []
        )
    }

    private func inferFallbackCodec(fromDescribeSDP sdp: String?) -> ShadowClientVideoCodec {
        guard let sdp else {
            return .h264
        }

        if sdp.localizedCaseInsensitiveContains(ShadowClientRTSPProtocolProfile.av1ClockRateMarker) {
            return .av1
        }
        if sdp.localizedCaseInsensitiveContains(ShadowClientRTSPProtocolProfile.h265ClockRateMarker) ||
            sdp.localizedCaseInsensitiveContains(ShadowClientRTSPProtocolProfile.hevcClockRateMarker) ||
            sdp.contains(ShadowClientRTSPProtocolProfile.hevcParameterSetMarker)
        {
            return .h265
        }
        return .h264
    }

    private func inferFallbackPayloadType(
        fromDescribeSDP sdp: String?,
        codec: ShadowClientVideoCodec
    ) -> Int {
        guard let sdp else {
            return ShadowClientRTSPProtocolProfile.fallbackVideoPayloadType
        }

        return ShadowClientRTSPSessionDescriptionParser.inferFallbackVideoPayloadType(
            sdp: sdp,
            preferredCodec: codec
        ) ?? ShadowClientRTSPProtocolProfile.fallbackVideoPayloadType
    }

    private func videoControlURLCandidates(
        primary: String,
        sessionURL: String
    ) -> [String] {
        var candidates: [String] = []

        func add(_ value: String?) {
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else {
                return
            }
            candidates.append(trimmed)
        }

        add(primary)
        ShadowClientRTSPProtocolProfile.videoControlPaths.forEach(add)

        if let parsedSessionURL = URL(string: sessionURL) {
            let normalizedBaseURL = normalizeRTSPURL(parsedSessionURL)
            var components = URLComponents(url: normalizedBaseURL, resolvingAgainstBaseURL: false)
            for path in ShadowClientRTSPProtocolProfile.videoControlPaths.map(ShadowClientRTSPProtocolProfile.absolutePath) {
                components?.path = path
                add(components?.url?.absoluteString)
            }
        }

        return candidates
    }

    private func audioControlURLCandidates(
        controlsFromSDP: [String],
        sessionURL: String
    ) -> [String] {
        var candidates: [String] = []

        func add(_ value: String?) {
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else {
                return
            }
            candidates.append(trimmed)
        }

        controlsFromSDP.forEach(add)
        ShadowClientRTSPProtocolProfile.audioControlPaths.forEach(add)

        if let parsedSessionURL = URL(string: sessionURL) {
            let normalizedBaseURL = normalizeRTSPURL(parsedSessionURL)
            var components = URLComponents(url: normalizedBaseURL, resolvingAgainstBaseURL: false)
            for path in ShadowClientRTSPProtocolProfile.audioControlPaths.map(ShadowClientRTSPProtocolProfile.absolutePath) {
                components?.path = path
                add(components?.url?.absoluteString)
            }
        }

        return candidates
    }

    private func controlStreamURLCandidates(sessionURL: String) -> [String] {
        var candidates: [String] = []

        func add(_ value: String?) {
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else {
                return
            }
            candidates.append(trimmed)
        }

        ShadowClientRTSPProtocolProfile.controlStreamPaths.forEach(add)

        if let parsedSessionURL = URL(string: sessionURL) {
            let normalizedBaseURL = normalizeRTSPURL(parsedSessionURL)
            var components = URLComponents(url: normalizedBaseURL, resolvingAgainstBaseURL: false)
            for path in ShadowClientRTSPProtocolProfile.controlStreamPaths.map(ShadowClientRTSPProtocolProfile.absolutePath) {
                components?.path = path
                add(components?.url?.absoluteString)
            }
        }

        return candidates
    }

    private func announceURLCandidates(sessionURL: String) -> [String] {
        var candidates: [String] = []

        func add(_ value: String?) {
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else {
                return
            }
            candidates.append(trimmed)
        }

        ShadowClientRTSPProtocolProfile.announcePaths.forEach(add)

        if let parsedSessionURL = URL(string: sessionURL) {
            let normalizedBaseURL = normalizeRTSPURL(parsedSessionURL)
            var components = URLComponents(url: normalizedBaseURL, resolvingAgainstBaseURL: false)
            for path in ShadowClientRTSPProtocolProfile.announcePaths.map(ShadowClientRTSPProtocolProfile.absolutePath) {
                components?.path = path
                add(components?.url?.absoluteString)
            }
        }

        return candidates
    }

    private func playURLCandidates(sessionURL: String) -> [String] {
        var candidates: [String] = []

        func add(_ value: String?) {
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else {
                return
            }
            candidates.append(trimmed)
        }

        ShadowClientRTSPProtocolProfile.playPaths.forEach(add)
        add(sessionURL)
        return candidates
    }

    private func parseSunshineEncryptionRequestedFlags(from sdp: String) -> UInt32 {
        let lines = sdp
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            let lower = line.lowercased()
            guard let range = lower.range(
                of: ShadowClientSunshineHandshakeProfile.encryptionRequestedAttributePrefix
            ) else {
                continue
            }

            let rawValue = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = UInt32(rawValue) {
                return parsed
            }
        }

        return ShadowClientSunshineHandshakeProfile.encryptionDisabled
    }

    private func ensureSunshineControlChannelStarted(
        fallbackHost: NWEndpoint.Host
    ) async {
        guard !hasStartedControlChannelBootstrap else {
            return
        }
        let started = await startSunshineControlChannelIfNeeded(
            host: String(describing: fallbackHost)
        )
        hasStartedControlChannelBootstrap = started
    }

    private func startSunshineControlChannelIfNeeded(host: String) async -> Bool {
        guard let controlServerPort else {
            logger.notice("RTSP control bootstrap skipped (no negotiated control server port)")
            return true
        }

        if controlChannelRuntime != nil {
            return true
        }

        let controlHost = remoteHost ?? .init(host)
        let runtime = ShadowClientSunshineControlChannelRuntime(
            onRoundTripSample: onControlRoundTripSample
        )

        do {
            try await runtime.start(
                host: controlHost,
                port: controlServerPort,
                connectData: controlConnectData,
                mode: controlChannelMode
            )
            controlChannelRuntime = runtime
            return true
        } catch {
            logger.error("RTSP control bootstrap failed: \(error.localizedDescription, privacy: .public)")
            await runtime.stop()
            return false
        }
    }

    func stop() async {
        if let controlChannelRuntime {
            await controlChannelRuntime.stop()
        }
        controlChannelRuntime = nil
        hasStartedControlChannelBootstrap = false
        cancelPrePlayPingWarmupTasks()

        connection?.cancel()
        connection = nil
        readBuffer.removeAll(keepingCapacity: false)
        remoteHost = nil
        localHost = nil
        audioServerPort = nil
        videoServerPort = nil
        controlServerPort = nil
        audioPingPayload = nil
        videoPingPayload = nil
        audioTrackDescriptor = nil
        prePlayVideoUDPSocket?.close()
        prePlayVideoUDPSocket = nil
        controlConnectData = nil
        controlChannelMode = .plaintext
        useSessionIdentifierV1 = false
        remoteInputKey = nil
        remoteInputKeyID = nil
        audioEncryptionConfiguration = nil
        negotiatedClientPortBase = defaultClientPortBase
        loggedInputSendKinds.removeAll(keepingCapacity: false)
        loggedInputDropKinds.removeAll(keepingCapacity: false)
    }

    func sendInput(_ event: ShadowClientRemoteInputEvent) async throws {
        await ensureSunshineControlChannelStarted(
            fallbackHost: remoteHost ?? .init("127.0.0.1")
        )

        guard let controlChannelRuntime else {
            return
        }
        guard let packet = ShadowClientSunshineInputPacketCodec.encode(event) else {
            let kind = inputEventKind(event)
            if loggedInputDropKinds.insert(kind).inserted {
                logger.notice("Sunshine input dropped during encode for event \(kind, privacy: .public)")
            }
            return
        }

        let kind = inputEventKind(event)
        if loggedInputSendKinds.insert(kind).inserted {
            logger.notice(
                "Sunshine input send enabled for event \(kind, privacy: .public) channel=\(packet.channelID, privacy: .public) bytes=\(packet.payload.count, privacy: .public)"
            )
        }

        do {
            try await controlChannelRuntime.sendInputPacket(
                packet.payload,
                channelID: packet.channelID
            )
        } catch {
            if ShadowClientRealtimeRTSPSessionRuntime.isTransientInputSendError(error) {
                return
            }
            if ShadowClientRealtimeRTSPSessionRuntime.shouldResetInputControlChannelAfterSendError(error) {
                logger.notice(
                    "Sunshine input channel reset after send failure: \(error.localizedDescription, privacy: .public)"
                )
                await controlChannelRuntime.stop()
                self.controlChannelRuntime = nil
                hasStartedControlChannelBootstrap = false
                return
            }
            throw error
        }
    }

    func requestVideoRecoveryFrame() async {
        await ensureSunshineControlChannelStarted(
            fallbackHost: remoteHost ?? .init("127.0.0.1")
        )
        guard let controlChannelRuntime else {
            return
        }
        await controlChannelRuntime.requestVideoRecoveryFrame()
    }

    private func inputEventKind(_ event: ShadowClientRemoteInputEvent) -> String {
        switch event {
        case .keyDown:
            return "keyDown"
        case .keyUp:
            return "keyUp"
        case .pointerMoved:
            return "pointerMoved"
        case .pointerButton:
            return "pointerButton"
        case .scroll:
            return "scroll"
        case .gamepadState:
            return "gamepadState"
        case .gamepadArrival:
            return "gamepadArrival"
        }
    }

    func receiveInterleavedVideoPackets(
        payloadType: Int,
        videoPayloadCandidates: Set<Int>,
        onVideoPacket: @escaping @Sendable (Data, Bool) async throws -> Void
    ) async throws {
        let audioTrack = audioTrackDescriptor
        if let remoteHost, let videoServerPort {
            try await receiveUDPVideoPackets(
                host: remoteHost,
                port: videoServerPort,
                payloadType: payloadType,
                videoPayloadCandidates: videoPayloadCandidates,
                audioTrack: audioTrack,
                onVideoPacket: onVideoPacket
            )
            return
        }

        var effectivePayloadType = payloadType
        var hasReceivedVideoPayload = false
        var packetCount = 0
        var reorderBuffer = ShadowClientRTPVideoReorderBuffer()
        var ignoredPayloadTypeMismatches: Set<Int> = []

        while !Task.isCancelled {
            if let packet = try parseInterleavedPacketIfAvailable() {
                guard packet.isRTP, packet.channel == 0 else {
                    continue
                }

                packetCount += 1
                if packetCount == 1 {
                    await ensureSunshineControlChannelStarted(
                        fallbackHost: remoteHost ?? .init("127.0.0.1")
                    )
                    logger.notice(
                        "First RTP video packet received: payloadType=\(packet.payloadType, privacy: .public), marker=\(packet.marker, privacy: .public), payloadBytes=\(packet.payload.count, privacy: .public)"
                    )
                }

                if packet.payloadType == effectivePayloadType {
                    hasReceivedVideoPayload = true
                    let orderedPackets = reorderBuffer.enqueue(packet)
                    for orderedPacket in orderedPackets {
                        try await onVideoPacket(
                            orderedPacket.payload,
                            orderedPacket.marker
                        )
                    }
                    continue
                }

                if !hasReceivedVideoPayload,
                   ShadowClientRealtimeRTSPSessionRuntime.shouldAdoptVideoPayloadType(
                       observedPayloadType: packet.payloadType,
                       currentPayloadType: effectivePayloadType,
                       audioPayloadType: audioTrack?.rtpPayloadType,
                       videoPayloadCandidates: videoPayloadCandidates
                   )
                {
                    logger.notice(
                        "RTSP payload type mismatch; adopting stream payload type \(packet.payloadType, privacy: .public) (expected \(effectivePayloadType, privacy: .public))"
                    )
                    effectivePayloadType = packet.payloadType
                    reorderBuffer.reset()
                    hasReceivedVideoPayload = true
                    let orderedPackets = reorderBuffer.enqueue(packet)
                    for orderedPacket in orderedPackets {
                        try await onVideoPacket(
                            orderedPacket.payload,
                            orderedPacket.marker
                        )
                    }
                } else if !hasReceivedVideoPayload,
                          ignoredPayloadTypeMismatches.insert(packet.payloadType).inserted
                {
                    logger.notice(
                        "RTSP payload type mismatch ignored for non-video candidate payload type \(packet.payloadType, privacy: .public)"
                    )
                }
                continue
            }

            let chunk = try await receiveBytes()
            guard !chunk.isEmpty else {
                throw ShadowClientRTSPInterleavedClientError.connectionClosed
            }
            readBuffer.append(chunk)
        }
    }

    private func receiveUDPVideoPackets(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        payloadType: Int,
        videoPayloadCandidates: Set<Int>,
        audioTrack: ShadowClientRTSPAudioTrackDescriptor?,
        onVideoPacket: @escaping @Sendable (Data, Bool) async throws -> Void
    ) async throws {
        cancelPrePlayPingWarmupTasks()

        let localHost = self.localHost
        let udpSocket: ShadowClientUDPDatagramSocket
        if let prePlaySocket = prePlayVideoUDPSocket {
            udpSocket = prePlaySocket
            prePlayVideoUDPSocket = nil
            logger.notice("RTSP UDP video socket reused from pre-PLAY bootstrap")
        } else {
            udpSocket = try makeVideoUDPSocket(
                host: host,
                port: port,
                localHost: localHost
            )
        }
        logger.notice("RTSP video receive switched to UDP \(String(describing: host), privacy: .public):\(port.rawValue, privacy: .public)")

        let pingPayload = videoPingPayload
        let rtspLogger = logger
        let audioPingPayload = self.audioPingPayload
        let audioEncryptionConfiguration = self.audioEncryptionConfiguration
        let audioRuntime = ShadowClientRealtimeAudioSessionRuntime(
            stateDidChange: onAudioOutputStateChanged
        )

        do {
            let initialVideoPings = ShadowClientSunshinePingPacketCodec.makePingPackets(
                sequence: 1,
                negotiatedPayload: pingPayload
            )
            for initialVideoPing in initialVideoPings {
                try udpSocket.send(initialVideoPing)
            }
            rtspLogger.notice("RTSP UDP video initial ping sent (variants=\(initialVideoPings.count, privacy: .public), bytes=\(initialVideoPings.first?.count ?? 0, privacy: .public))")
        } catch {
            rtspLogger.error("RTSP UDP video initial ping failed: \(error.localizedDescription, privacy: .public)")
        }

        if let audioServerPort {
            do {
                try await audioRuntime.start(
                    remoteHost: host,
                    remotePort: audioServerPort,
                    localHost: localHost,
                    preferredLocalPort: negotiatedClientPortBase &+ 1,
                    track: audioTrack,
                    pingPayload: audioPingPayload,
                    encryption: audioEncryptionConfiguration
                )
                rtspLogger.notice("RTSP UDP audio receive switched to \(String(describing: host), privacy: .public):\(audioServerPort.rawValue, privacy: .public)")
            } catch {
                rtspLogger.error("RTSP UDP audio runtime setup failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        let sendableVideoSocket = udpSocket

        let pingTask = Task {
            var sequence: UInt32 = 1
            var loggedPingCount = 0
            var loggedPingError = false
            while !Task.isCancelled {
                sequence &+= 1
                do {
                    let pingPackets = ShadowClientSunshinePingPacketCodec.makePingPackets(
                        sequence: sequence,
                        negotiatedPayload: pingPayload
                    )
                    for pingPacket in pingPackets {
                        try sendableVideoSocket.send(pingPacket)
                    }
                    if loggedPingCount < 3 {
                        rtspLogger.notice("RTSP UDP video ping sent (sequence=\(sequence, privacy: .public), variants=\(pingPackets.count, privacy: .public), bytes=\(pingPackets.first?.count ?? 0, privacy: .public))")
                        loggedPingCount += 1
                    }
                } catch {
                    if !loggedPingError {
                        rtspLogger.error("RTSP UDP video ping send failed: \(error.localizedDescription, privacy: .public)")
                        loggedPingError = true
                    }
                }
                try? await Task.sleep(for: ShadowClientRealtimeSessionDefaults.pingInterval)
            }
        }

        defer {
            pingTask.cancel()
            audioRuntime.stop()
            udpSocket.close()
        }

        var effectivePayloadType = payloadType
        var hasReceivedVideoPayload = false
        var packetCount = 0
        var parseFailureCount = 0
        var datagramCount = 0
        var reorderBuffer = ShadowClientRTPVideoReorderBuffer()
        var ignoredPayloadTypeMismatches: Set<Int> = []
        let receiveStart = ContinuousClock.now

        while !Task.isCancelled {
            guard let datagram = try udpSocket.receive(
                maximumLength: ShadowClientRealtimeSessionDefaults.maximumTransportReadLength
            ) else {
                if datagramCount == 0,
                   receiveStart.duration(to: ContinuousClock.now) >= ShadowClientRealtimeSessionDefaults.initialVideoDatagramTimeout
                {
                    throw ShadowClientRTSPInterleavedClientError.requestFailed(
                        "RTSP UDP video timeout: no video datagram received"
                    )
                }
                continue
            }
            guard !datagram.isEmpty else {
                continue
            }

            datagramCount += 1
            if datagramCount == 1 {
                logger.notice(
                    "First UDP video datagram received: bytes=\(datagram.count, privacy: .public), preview=\(Self.hexPreview(datagram), privacy: .public)"
                )
            }

            let packet: ShadowClientRTPPacket
            do {
                packet = try parseRTPPacket(datagram, channel: 0)
            } catch {
                parseFailureCount += 1
                if parseFailureCount <= ShadowClientRealtimeSessionDefaults.udpParseFailureLogLimit {
                    logger.error(
                        "RTSP UDP datagram ignored (RTP parse failed #\(parseFailureCount, privacy: .public)): \(error.localizedDescription, privacy: .public), bytes=\(datagram.count, privacy: .public), preview=\(Self.hexPreview(datagram), privacy: .public)"
                    )
                }
                continue
            }

            packetCount += 1
            if packetCount == 1 {
                await ensureSunshineControlChannelStarted(fallbackHost: host)
                logger.notice(
                    "First RTP video packet received: payloadType=\(packet.payloadType, privacy: .public), marker=\(packet.marker, privacy: .public), payloadBytes=\(packet.payload.count, privacy: .public)"
                )
            }

            if packet.payloadType == effectivePayloadType {
                hasReceivedVideoPayload = true
                let orderedPackets = reorderBuffer.enqueue(packet)
                for orderedPacket in orderedPackets {
                    try await onVideoPacket(
                        orderedPacket.payload,
                        orderedPacket.marker
                    )
                }
                continue
            }

            if !hasReceivedVideoPayload,
               ShadowClientRealtimeRTSPSessionRuntime.shouldAdoptVideoPayloadType(
                   observedPayloadType: packet.payloadType,
                   currentPayloadType: effectivePayloadType,
                   audioPayloadType: audioTrack?.rtpPayloadType,
                   videoPayloadCandidates: videoPayloadCandidates
               )
            {
                logger.notice(
                    "RTSP payload type mismatch; adopting stream payload type \(packet.payloadType, privacy: .public) (expected \(effectivePayloadType, privacy: .public))"
                )
                effectivePayloadType = packet.payloadType
                reorderBuffer.reset()
                hasReceivedVideoPayload = true
                let orderedPackets = reorderBuffer.enqueue(packet)
                for orderedPacket in orderedPackets {
                    try await onVideoPacket(
                        orderedPacket.payload,
                        orderedPacket.marker
                    )
                }
            } else if !hasReceivedVideoPayload,
                      ignoredPayloadTypeMismatches.insert(packet.payloadType).inserted
            {
                logger.notice(
                    "RTSP payload type mismatch ignored for non-video candidate payload type \(packet.payloadType, privacy: .public)"
                )
            }
        }
    }

    private static func hexPreview(_ bytes: Data, limit: Int = 24) -> String {
        let prefix = bytes.prefix(limit)
            .map { String(format: "%02X", $0) }
            .joined()
        return bytes.count > limit ? prefix + "..." : prefix
    }

    private func makeVideoUDPSocket(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        localHost: NWEndpoint.Host?
    ) throws -> ShadowClientUDPDatagramSocket {
        let preferredLocalPort = negotiatedVideoPingPort()
        do {
            let socket = try ShadowClientUDPDatagramSocket(
                localHost: localHost,
                localPort: preferredLocalPort,
                remoteHost: host,
                remotePort: port.rawValue
            )
            logger.notice(
                "RTSP UDP video socket bound \(socket.localEndpointDescription(), privacy: .public) (preferred-client-port \(preferredLocalPort, privacy: .public))"
            )
            return socket
        } catch {
            logger.error(
                "RTSP UDP video bind on preferred client port \(preferredLocalPort, privacy: .public) failed: \(error.localizedDescription, privacy: .public); retrying with ephemeral port"
            )
            let socket = try ShadowClientUDPDatagramSocket(
                localHost: localHost,
                localPort: nil,
                remoteHost: host,
                remotePort: port.rawValue
            )
            logger.notice("RTSP UDP video socket bound \(socket.localEndpointDescription(), privacy: .public) (ephemeral-fallback)")
            return socket
        }
    }

    private func negotiatedVideoPingPort() -> UInt16 {
        negotiatedClientPortBase
    }

    private func prepareVideoPingBeforePlay(host: NWEndpoint.Host) {
        guard prePlayVideoUDPSocket == nil,
              let videoServerPort
        else {
            return
        }

        do {
            let socket = try makeVideoUDPSocket(
                host: host,
                port: videoServerPort,
                localHost: localHost
            )
            prePlayVideoUDPSocket = socket

            let prePlayPings = ShadowClientSunshinePingPacketCodec.makePingPackets(
                sequence: 1,
                negotiatedPayload: videoPingPayload
            )
            for packet in prePlayPings {
                try socket.send(packet)
            }
            logger.notice(
                "RTSP UDP video pre-PLAY ping sent (variants=\(prePlayPings.count, privacy: .public), bytes=\(prePlayPings.first?.count ?? 0, privacy: .public))"
            )
            prePlayVideoPingWarmupTask?.cancel()
            let payload = videoPingPayload
            prePlayVideoPingWarmupTask = Task { [logger] in
                var sequence: UInt32 = 1
                var loggedSendCount = 0
                while !Task.isCancelled {
                    sequence &+= 1
                    let pingPackets = ShadowClientSunshinePingPacketCodec.makePingPackets(
                        sequence: sequence,
                        negotiatedPayload: payload
                    )
                    for packet in pingPackets {
                        try? socket.send(packet)
                    }
                    if loggedSendCount < 2 {
                        logger.debug("RTSP UDP video pre-PLAY warmup ping sent (sequence=\(sequence, privacy: .public), variants=\(pingPackets.count, privacy: .public))")
                        loggedSendCount += 1
                    }
                    try? await Task.sleep(for: ShadowClientRealtimeSessionDefaults.pingInterval)
                }
            }
        } catch {
            prePlayVideoPingWarmupTask?.cancel()
            prePlayVideoPingWarmupTask = nil
            prePlayVideoUDPSocket?.close()
            prePlayVideoUDPSocket = nil
            logger.error("RTSP UDP video pre-PLAY ping setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func cancelPrePlayPingWarmupTasks() {
        prePlayVideoPingWarmupTask?.cancel()
        prePlayVideoPingWarmupTask = nil
    }

    private func attemptLegacyFirstFrameBootstrap(host: NWEndpoint.Host) async {
        guard let port = NWEndpoint.Port(
            rawValue: ShadowClientRTSPProtocolProfile.legacyFirstFrameBootstrapPort
        ) else {
            return
        }

        let bootstrapConnection = NWConnection(host: host, port: port, using: .tcp)
        do {
            try await waitForReady(
                bootstrapConnection,
                timeout: .milliseconds(700)
            )
            logger.notice("RTSP legacy first-frame bootstrap connected on \(port.rawValue, privacy: .public)")
        } catch {
            logger.debug("RTSP legacy first-frame bootstrap skipped: \(error.localizedDescription, privacy: .public)")
        }
        bootstrapConnection.cancel()
    }

    private func sendRequest(
        method: String,
        url: String,
        headers: [String: String],
        body: Data = Data()
    ) async throws -> ShadowClientRTSPResponse {
        guard let connection else {
            throw ShadowClientRTSPInterleavedClientError.connectionFailed
        }

        let requestPayload = buildRequestPayload(
            method: method,
            url: url,
            headers: headers,
            body: body
        )
        try await send(bytes: requestPayload, over: connection)

        let response = try await readResponse()
        logResponse(method: method, response: response)
        guard (200...299).contains(response.statusCode) else {
            let bodyText = String(data: response.body, encoding: .utf8) ?? ""
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP \(method) failed (\(response.statusCode)): \(bodyText)"
            )
        }
        return response
    }

    private func sendRequestWithReconnectRetry(
        method: String,
        url: String,
        headers: [String: String],
        body: Data = Data(),
        host: String,
        port: NWEndpoint.Port
    ) async throws -> ShadowClientRTSPResponse {
        do {
            return try await sendRequest(
                method: method,
                url: url,
                headers: headers,
                body: body
            )
        } catch {
            guard shouldRetryAfterReconnect(error) else {
                throw error
            }

            logger.notice(
                "RTSP \(method, privacy: .public) retrying after reconnect due to transport error: \(error.localizedDescription, privacy: .public)"
            )
            try await reconnect(host: host, port: port)
            return try await sendRequest(
                method: method,
                url: url,
                headers: headers,
                body: body
            )
        }
    }

    private func shouldRetryAfterReconnect(_ error: Error) -> Bool {
        if let rtspError = error as? ShadowClientRTSPInterleavedClientError {
            switch rtspError {
            case .requestFailed:
                return false
            case .invalidURL:
                return false
            case .connectionFailed, .invalidResponse, .connectionClosed:
                return true
            }
        }

        return true
    }

    private func sendDescribeRequest(
        url: String,
        headers: [String: String]
    ) async throws -> ShadowClientRTSPResponse {
        guard let connection else {
            throw ShadowClientRTSPInterleavedClientError.connectionFailed
        }

        let requestPayload = buildRequestPayload(
            method: ShadowClientRTSPRequestDefaults.describeMethod,
            url: url,
            headers: headers
        )
        try await send(bytes: requestPayload, over: connection)

        let rawResponse = try await readResponseUntilConnectionClose()
        let response = try parseRTSPResponseFromRawData(rawResponse)
        logResponse(method: ShadowClientRTSPRequestDefaults.describeMethod, response: response)

        guard (200...299).contains(response.statusCode) else {
            let bodyText = String(data: response.body, encoding: .utf8) ?? ""
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP DESCRIBE failed (\(response.statusCode)): \(bodyText)"
            )
        }

        return response
    }

    private func readResponseUntilConnectionClose() async throws -> Data {
        var response = Data()

        while true {
            do {
                let chunk = try await receiveBytes()
                if chunk.isEmpty {
                    break
                }
                response.append(chunk)
            } catch {
                if response.isEmpty {
                    throw error
                }

                logger.notice(
                    "RTSP read terminated after partial response (\(error.localizedDescription, privacy: .public)); proceeding with buffered bytes \(response.count, privacy: .public)"
                )
                break
            }
        }

        guard !response.isEmpty else {
            throw ShadowClientRTSPInterleavedClientError.connectionClosed
        }
        return response
    }

    private func parseRTSPResponseFromRawData(_ rawData: Data) throws -> ShadowClientRTSPResponse {
        let headerTerminatorCRLF = ShadowClientRTSPProtocolProfile.headerTerminatorCRLF
        let headerTerminatorLF = ShadowClientRTSPProtocolProfile.headerTerminatorLF
        let headerRange: Range<Int>
        let bodyStart: Int

        if let range = rawData.range(of: headerTerminatorCRLF) {
            headerRange = range
            bodyStart = range.upperBound
        } else if let range = rawData.range(of: headerTerminatorLF) {
            headerRange = range
            bodyStart = range.upperBound
        } else {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
        }

        let headerData = rawData[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
        }

        let lines = headerText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let statusLine = lines.first,
              statusLine.hasPrefix(ShadowClientRTSPRequestDefaults.protocolVersion),
              let statusCode = Int(statusLine.split(separator: " ").dropFirst().first ?? "")
        else {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let body: Data
        if let contentLength = Int(
            headers[ShadowClientRTSPRequestDefaults.responseHeaderContentLength] ?? ""
        ), contentLength >= 0 {
            let end = min(rawData.count, bodyStart + contentLength)
            body = Data(rawData[bodyStart..<end])
        } else {
            body = bodyStart <= rawData.count ? Data(rawData[bodyStart...]) : Data()
        }

        return ShadowClientRTSPResponse(
            statusCode: statusCode,
            headers: headers,
            body: body
        )
    }

    private func buildRequestPayload(
        method: String,
        url: String,
        headers: [String: String],
        body: Data = Data()
    ) -> Data {
        var lines: [String] = []
        lines.append("\(method) \(url) \(ShadowClientRTSPRequestDefaults.protocolVersion)")
        lines.append("CSeq: \(cseq)")
        cseq += 1
        lines.append(
            "\(ShadowClientRTSPRequestDefaults.headerClientVersion): \(ShadowClientRTSPRequestDefaults.clientVersionHeaderValue)"
        )
        if let hostHeader = ShadowClientRTSPProtocolProfile.hostHeaderValue(forRTSPURLString: url) {
            lines.append("\(ShadowClientRTSPRequestDefaults.headerHost): \(hostHeader)")
        }
        for key in headers.keys.sorted() {
            if let value = headers[key] {
                lines.append("\(key): \(value)")
            }
        }
        lines.append("")
        lines.append("")
        var payload = Data(lines.joined(separator: "\r\n").utf8)
        if !body.isEmpty {
            payload.append(body)
        }
        return payload
    }

    private func readResponse() async throws -> ShadowClientRTSPResponse {
        while true {
            if let response = parseRTSPResponseIfAvailable() {
                return response
            }

            do {
                let chunk = try await receiveBytes()
                guard !chunk.isEmpty else {
                    throw ShadowClientRTSPInterleavedClientError.connectionClosed
                }
                readBuffer.append(chunk)
            } catch {
                if let response = parseRTSPResponseIfAvailable() {
                    logger.notice(
                        "RTSP response completed after transport read error (\(error.localizedDescription, privacy: .public)); using buffered bytes"
                    )
                    return response
                }
                throw error
            }
        }
    }

    private func parseRTSPResponseIfAvailable() -> ShadowClientRTSPResponse? {
        let headerTerminatorCRLF = ShadowClientRTSPProtocolProfile.headerTerminatorCRLF
        let headerTerminatorLF = ShadowClientRTSPProtocolProfile.headerTerminatorLF
        let headerRange: Range<Int>
        let bodyStart: Int
        if let range = readBuffer.range(of: headerTerminatorCRLF) {
            headerRange = range
            bodyStart = range.upperBound
        } else if let range = readBuffer.range(of: headerTerminatorLF) {
            headerRange = range
            bodyStart = range.upperBound
        } else {
            return nil
        }
        let headerData = readBuffer[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        let lines = headerText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let statusLine = lines.first,
              statusLine.hasPrefix(ShadowClientRTSPRequestDefaults.protocolVersion),
              let statusCode = Int(statusLine.split(separator: " ").dropFirst().first ?? "")
        else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        if let contentLength = Int(
            headers[ShadowClientRTSPRequestDefaults.responseHeaderContentLength] ?? ""
        ) {
            let bodyEnd = bodyStart + contentLength
            guard readBuffer.count >= bodyEnd else {
                return nil
            }

            let body = Data(readBuffer[bodyStart..<bodyEnd])
            readBuffer.removeSubrange(0..<bodyEnd)
            return ShadowClientRTSPResponse(
                statusCode: statusCode,
                headers: headers,
                body: body
            )
        }

        let contentType = headers[ShadowClientRTSPRequestDefaults.responseHeaderContentType]?.lowercased() ?? ""
        if contentType.contains(ShadowClientRTSPRequestDefaults.acceptSDP) {
            guard readBuffer.count > bodyStart else {
                return nil
            }

            let body = Data(readBuffer[bodyStart...])
            readBuffer.removeAll(keepingCapacity: false)
            return ShadowClientRTSPResponse(
                statusCode: statusCode,
                headers: headers,
                body: body
            )
        }

        readBuffer.removeSubrange(0..<bodyStart)
        return ShadowClientRTSPResponse(
            statusCode: statusCode,
            headers: headers,
            body: Data()
        )
    }

    private func logResponse(method: String, response: ShadowClientRTSPResponse) {
        let sortedHeaders = response.headers
            .map { key, value in "\(key)=\(value)" }
            .sorted()
            .joined(separator: "; ")

        logger.notice(
            "RTSP \(method, privacy: .public) <- status \(response.statusCode, privacy: .public), body \(response.body.count, privacy: .public) bytes, headers [\(sortedHeaders, privacy: .public)]"
        )

        guard method == ShadowClientRTSPRequestDefaults.describeMethod,
              !response.body.isEmpty,
              let preview = String(
                  data: response.body.prefix(ShadowClientRealtimeSessionDefaults.describeResponsePreviewByteCount),
                  encoding: .utf8
              )
        else {
            return
        }

        logger.notice("RTSP DESCRIBE body preview: \(preview, privacy: .public)")
    }

    private func parseInterleavedPacketIfAvailable() throws -> ShadowClientRTPPacket? {
        guard let first = readBuffer.first else {
            return nil
        }

        if first != ShadowClientRTSPProtocolProfile.interleavedFrameMagicByte {
            return nil
        }

        guard readBuffer.count >= ShadowClientRTSPProtocolProfile.interleavedHeaderLength else {
            return nil
        }

        let frameLength = Int(readBuffer[2]) << 8 | Int(readBuffer[3])
        let packetEnd = ShadowClientRTSPProtocolProfile.interleavedHeaderLength + frameLength
        guard readBuffer.count >= packetEnd else {
            return nil
        }

        let channel = Int(readBuffer[1])
        let payload = readBuffer[ShadowClientRTSPProtocolProfile.interleavedHeaderLength..<packetEnd]
        readBuffer.removeSubrange(0..<packetEnd)

        // Odd interleaved channels carry RTCP/control packets.
        // Skip them before RTP parsing to keep decode state clean.
        if channel % 2 == ShadowClientRTSPProtocolProfile.rtcpChannelParityRemainder {
            return ShadowClientRTPPacket(
                isRTP: false,
                channel: channel,
                sequenceNumber: 0,
                marker: false,
                payloadType: -1,
                payload: Data()
            )
        }

        return try parseRTPPacket(payload, channel: channel)
    }

    private func parseRTPPacket(
        _ payload: Data,
        channel: Int
    ) throws -> ShadowClientRTPPacket {
        let parsed: ShadowClientRTPPacketPayloadParseResult
        do {
            parsed = try ShadowClientRTPPacketPayloadParser.parse(payload)
        } catch {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
        }

        return ShadowClientRTPPacket(
            isRTP: true,
            channel: channel,
            sequenceNumber: parsed.sequenceNumber,
            marker: parsed.marker,
            payloadType: parsed.payloadType,
            payload: parsed.payload
        )
    }

    private func waitForReady(_ connection: NWConnection) async throws {
        try await waitForReady(connection, timeout: timeout)
    }

    private func waitForReady(
        _ connection: NWConnection,
        timeout: Duration
    ) async throws {
        final class ReadyWaitGate: @unchecked Sendable {
            private let lock = NSLock()
            private let connection: NWConnection
            private var continuation: CheckedContinuation<Void, Error>?
            private var timeoutTask: Task<Void, Never>?

            init(connection: NWConnection) {
                self.connection = connection
            }

            func install(
                continuation: CheckedContinuation<Void, Error>,
                timeout: Duration,
                timeoutError: @autoclosure @escaping () -> Error
            ) {
                lock.lock()
                self.continuation = continuation
                lock.unlock()
                timeoutTask = Task {
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    self.finish(.failure(timeoutError()))
                    self.connection.cancel()
                }
            }

            func finish(_ result: Result<Void, Error>) {
                lock.lock()
                guard let continuation else {
                    lock.unlock()
                    return
                }
                self.continuation = nil
                let timeoutTask = self.timeoutTask
                self.timeoutTask = nil
                lock.unlock()

                connection.stateUpdateHandler = nil
                timeoutTask?.cancel()
                continuation.resume(with: result)
            }

            func cancel() {
                finish(.failure(CancellationError()))
                connection.cancel()
            }
        }

        let gate = ReadyWaitGate(connection: connection)
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                gate.install(
                    continuation: continuation,
                    timeout: timeout,
                    timeoutError: ShadowClientRTSPInterleavedClientError.connectionFailed
                )
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        gate.finish(.success(()))
                    case let .failed(error):
                        gate.finish(.failure(error))
                    case .cancelled:
                        gate.finish(.failure(ShadowClientRTSPInterleavedClientError.connectionClosed))
                    default:
                        break
                    }
                }
                connection.start(queue: self.queue)
            }
        } onCancel: {
            gate.cancel()
        }
    }

    private func resolvedRemoteHost(from connection: NWConnection) -> NWEndpoint.Host? {
        if case let .hostPort(host, _) = connection.currentPath?.remoteEndpoint {
            return host
        }

        if case let .hostPort(host, _) = connection.endpoint {
            return host
        }

        return nil
    }

    private func resolvedLocalHost(from connection: NWConnection) -> NWEndpoint.Host? {
        if case let .hostPort(host, _) = connection.currentPath?.localEndpoint {
            return host
        }
        return nil
    }

    private func send(bytes: Data, over connection: NWConnection) async throws {
        try await Self.send(bytes: bytes, over: connection)
    }

    private static func send(bytes: Data, over connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: bytes, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private func receiveBytes() async throws -> Data {
        guard let connection else {
            throw ShadowClientRTSPInterleavedClientError.connectionClosed
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(
                minimumIncompleteLength: ShadowClientRealtimeSessionDefaults.minimumTransportReadLength,
                maximumLength: ShadowClientRealtimeSessionDefaults.maximumTransportReadLength
            ) { content, _, isComplete, error in
                // Sunshine can close/reset a RTSP TCP socket right after writing a valid
                // response chunk. In that case Network.framework may deliver `content`
                // together with a terminal error. Keep the bytes and let response parsing
                // decide whether the message is complete.
                if let content, !content.isEmpty {
                    continuation.resume(returning: content)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if isComplete {
                    continuation.resume(returning: Data())
                    return
                }

                continuation.resume(returning: content ?? Data())
            }
        }
    }

}

private enum ShadowClientUDPDatagramSocketError: Error {
    case unsupportedAddress(String)
    case socketFailure(String)
}

private final class ShadowClientUDPDatagramSocket: @unchecked Sendable {
    private let descriptor: Int32
    private var remoteAddress: sockaddr_in
    private let addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
    private let closeLock = NSLock()
    private var isClosed = false
    private var receiveBuffer: [UInt8] = Array(
        repeating: 0,
        count: ShadowClientRealtimeSessionDefaults.maximumTransportReadLength
    )

    init(
        localHost: NWEndpoint.Host?,
        localPort: UInt16?,
        remoteHost: NWEndpoint.Host,
        remotePort: UInt16
    ) throws {
        guard let remoteAddress = Self.makeIPv4Address(from: remoteHost, port: remotePort) else {
            throw ShadowClientUDPDatagramSocketError.unsupportedAddress(
                "Unsupported remote UDP endpoint: \(String(describing: remoteHost)):\(remotePort)"
            )
        }
        self.remoteAddress = remoteAddress

        descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else {
            throw ShadowClientUDPDatagramSocketError.socketFailure(
                "socket() failed: \(String(cString: strerror(errno)))"
            )
        }

        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 250_000)
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        )
        var receiveBufferSize: Int32 = 4 * 1_024 * 1_024
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVBUF,
            &receiveBufferSize,
            socklen_t(MemoryLayout<Int32>.size)
        )
        var sendBufferSize: Int32 = 1 * 1_024 * 1_024
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_SNDBUF,
            &sendBufferSize,
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

        var localAddress = Self.makeLocalIPv4Address(from: localHost, port: localPort)
        let bindStatus = withUnsafePointer(to: &localAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(descriptor, sockaddrPointer, addressLength)
            }
        }
        if bindStatus != 0 {
            let message = "bind() failed: \(String(cString: strerror(errno)))"
            Darwin.close(descriptor)
            throw ShadowClientUDPDatagramSocketError.socketFailure(message)
        }
    }

    deinit {
        close()
    }

    func send(_ datagram: Data) throws {
        var remoteAddress = remoteAddress
        let sentBytes = datagram.withUnsafeBytes { bytes in
            withUnsafePointer(to: &remoteAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(
                        descriptor,
                        bytes.baseAddress,
                        datagram.count,
                        0,
                        sockaddrPointer,
                        addressLength
                    )
                }
            }
        }

        if sentBytes < 0 {
            throw ShadowClientUDPDatagramSocketError.socketFailure(
                "sendto() failed: \(String(cString: strerror(errno)))"
            )
        }
    }

    func receive(maximumLength: Int) throws -> Data? {
        if receiveBuffer.count < maximumLength {
            receiveBuffer = Array(repeating: 0, count: maximumLength)
        }
        var sourceAddress = sockaddr_storage()
        var sourceLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let receivedBytes = receiveBuffer.withUnsafeMutableBytes { bytes in
            withUnsafeMutablePointer(to: &sourceAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    recvfrom(
                        descriptor,
                        bytes.baseAddress,
                        min(maximumLength, bytes.count),
                        0,
                        sockaddrPointer,
                        &sourceLength
                    )
                }
            }
        }

        if receivedBytes < 0 {
            let errorCode = errno
            if errorCode == EAGAIN || errorCode == EWOULDBLOCK || errorCode == EINTR {
                return nil
            }
            if errorCode == EBADF, isSocketMarkedClosed() {
                return nil
            }
            throw ShadowClientUDPDatagramSocketError.socketFailure(
                "recvfrom() failed (\(errorCode)): \(String(cString: strerror(errorCode)))"
            )
        }

        guard receivedBytes > 0 else {
            return nil
        }
        return receiveBuffer.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return Data()
            }
            return Data(bytes: baseAddress, count: receivedBytes)
        }
    }

    func localEndpointDescription() -> String {
        var address = sockaddr_storage()
        var addressLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let status = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(descriptor, sockaddrPointer, &addressLength)
            }
        }
        guard status == 0 else {
            return "ephemeral:unknown"
        }

        guard address.ss_family == sa_family_t(AF_INET) else {
            return "ephemeral:unknown"
        }

        return withUnsafePointer(to: &address) { pointer -> String in
            pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sockaddrInPointer in
                var ipv4 = sockaddrInPointer.pointee.sin_addr
                let port = CFSwapInt16BigToHost(sockaddrInPointer.pointee.sin_port)
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                let converted = inet_ntop(
                    AF_INET,
                    &ipv4,
                    &buffer,
                    socklen_t(INET_ADDRSTRLEN)
                )
                guard converted != nil else {
                    return "0.0.0.0:\(port)"
                }
                return "\(String(cString: buffer)):\(port)"
            }
        }
    }

    func close() {
        closeLock.lock()
        let shouldClose = !isClosed
        if shouldClose {
            isClosed = true
        }
        closeLock.unlock()

        if shouldClose {
            Darwin.close(descriptor)
        }
    }

    private func isSocketMarkedClosed() -> Bool {
        closeLock.lock()
        let closed = isClosed
        closeLock.unlock()
        return closed
    }

    private static func makeLocalIPv4Address(
        from host: NWEndpoint.Host?,
        port: UInt16?
    ) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = CFSwapInt16HostToBig(port ?? 0)
        if let host, let parsed = parseIPv4Host(host) {
            address.sin_addr = parsed
        } else {
            address.sin_addr = in_addr(s_addr: CFSwapInt32HostToBig(INADDR_ANY))
        }
        return address
    }

    private static func makeIPv4Address(
        from host: NWEndpoint.Host,
        port: UInt16
    ) -> sockaddr_in? {
        guard let parsed = parseIPv4Host(host) else {
            return nil
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = CFSwapInt16HostToBig(port)
        address.sin_addr = parsed
        return address
    }

    private static func parseIPv4Host(_ host: NWEndpoint.Host) -> in_addr? {
        let hostString = String(describing: host).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostString.isEmpty else {
            return nil
        }

        var parsed = in_addr()
        let result = hostString.withCString { cString in
            inet_pton(AF_INET, cString, &parsed)
        }
        guard result == 1 else {
            return nil
        }
        return parsed
    }
}

struct ShadowClientH265RTPDepacketizer: Sendable {
    private var currentNALUnits: [Data] = []
    private var fragmentedNALBuffer: Data?

    mutating func reset() {
        currentNALUnits = []
        fragmentedNALBuffer = nil
    }

    mutating func ingest(payload: Data, marker: Bool) -> Data? {
        guard payload.count >= 3 else {
            return marker ? flushIfNeeded() : nil
        }

        let nalType = (payload[0] >> 1) & 0x3F
        if nalType == 49 {
            ingestFragmentationUnit(payload)
        } else if nalType == 48 {
            // RFC7798 AP packet: split embedded NAL units by 16-bit length prefix.
            ingestAggregationPacket(payload)
        } else {
            fragmentedNALBuffer = nil
            currentNALUnits.append(payload)
        }

        if marker {
            return flushIfNeeded()
        }
        return nil
    }

    private mutating func ingestFragmentationUnit(_ payload: Data) {
        guard payload.count >= 3 else {
            return
        }

        let fuHeader = payload[2]
        let start = (fuHeader & 0x80) != 0
        let end = (fuHeader & 0x40) != 0
        let nalType = fuHeader & 0x3F
        let reconstructedFirstByte = (payload[0] & 0x81) | (nalType << 1)
        let reconstructedSecondByte = payload[1]
        let fuPayload = payload.dropFirst(3)

        if start {
            var nal = Data([reconstructedFirstByte, reconstructedSecondByte])
            nal.append(contentsOf: fuPayload)
            fragmentedNALBuffer = nal
            if end, let fragmentedNALBuffer {
                currentNALUnits.append(fragmentedNALBuffer)
                self.fragmentedNALBuffer = nil
            }
            return
        }

        guard var buffer = fragmentedNALBuffer else {
            return
        }
        buffer.append(contentsOf: fuPayload)
        fragmentedNALBuffer = buffer

        if end {
            currentNALUnits.append(buffer)
            fragmentedNALBuffer = nil
        }
    }

    private mutating func ingestAggregationPacket(_ payload: Data) {
        guard payload.count > 2 else {
            return
        }

        fragmentedNALBuffer = nil
        var cursor = 2
        while cursor + 2 <= payload.count {
            let nalLength = (Int(payload[cursor]) << 8) | Int(payload[cursor + 1])
            cursor += 2

            guard nalLength > 0 else {
                continue
            }
            guard cursor + nalLength <= payload.count else {
                return
            }

            currentNALUnits.append(
                Data(payload[cursor ..< (cursor + nalLength)])
            )
            cursor += nalLength
        }
    }

    private mutating func flushIfNeeded() -> Data? {
        guard !currentNALUnits.isEmpty else {
            return nil
        }

        var annexB = Data()
        for nal in currentNALUnits {
            annexB.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            annexB.append(nal)
        }
        currentNALUnits = []
        return annexB
    }
}
