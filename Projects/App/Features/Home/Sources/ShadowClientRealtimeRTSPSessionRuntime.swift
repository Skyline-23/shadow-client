import CoreVideo
import Darwin
import Foundation
import Network
import os
import ShadowClientFeatureSession

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

public actor ShadowClientRealtimeRTSPSessionRuntime {
    struct VideoTransportPacket: Sendable {
        let payload: Data
        let marker: Bool
    }

    struct VideoAccessUnit: Sendable {
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
    private let prepareAudioDecoders: (@Sendable () async -> Void)?
    private let audioSessionActivation: (@Sendable () async -> Void)?
    private let audioSessionDeactivation: (@Sendable () async -> Void)?
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
    private var av1RecoverableDecoderFailureCount = 0
    private var firstAV1RecoverableDecoderFailureUptime: TimeInterval = 0
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
    private var lastDecodedFrameCallbackUptime: TimeInterval = 0
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
    private var lastAV1ReferenceInvalidationRequestUptime: TimeInterval = 0
    private var pendingVideoRecoveryRequest = false
    private var videoRenderSubmitDropCount = 0
    private var lastObservedDecodeQueueBacklog = 0
    private var awaitingAV1SyncFrame = false
    private var av1SyncGateAllowsReferenceInvalidatedFrame = false
    private var av1SyncGateDroppedFrameCount = 0
    private var av1PendingRecoveryRequestAfterSuccessfulFrame = false
    private var lastObservedVideoFrameIndex: UInt32?
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
        connectTimeout: Duration = ShadowClientRealtimeSessionDefaults.defaultConnectTimeout,
        prepareAudioDecoders: (@Sendable () async -> Void)? = nil,
        audioSessionActivation: (@Sendable () async -> Void)? = nil,
        audioSessionDeactivation: (@Sendable () async -> Void)? = nil
    ) {
        self.surfaceContext = surfaceContext
        self.decoder = decoder
        self.connectTimeout = connectTimeout
        self.prepareAudioDecoders = prepareAudioDecoders
        self.audioSessionActivation = audioSessionActivation
        self.audioSessionDeactivation = audioSessionDeactivation
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
        host: String,
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
        av1RecoverableDecoderFailureCount = 0
        firstAV1RecoverableDecoderFailureUptime = 0
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
        lastDecodedFrameCallbackUptime = 0
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
        lastAV1ReferenceInvalidationRequestUptime = 0
        pendingVideoRecoveryRequest = false
        videoRenderSubmitDropCount = 0
        lastObservedDecodeQueueBacklog = 0
        awaitingAV1SyncFrame = false
        av1SyncGateAllowsReferenceInvalidatedFrame = false
        av1SyncGateDroppedFrameCount = 0
        av1PendingRecoveryRequestAfterSuccessfulFrame = false
        lastObservedVideoFrameIndex = nil
        lastAV1DecodeSubmissionContext = nil
        configureQueuePressureProfile(for: resolvedVideoConfiguration)

        await MainActor.run {
            sessionSurfaceContext.reset()
            sessionSurfaceContext.updatePreferredRenderFPS(resolvedVideoConfiguration.fps)
            sessionSurfaceContext.updateActiveDynamicRangeMode(
                resolvedVideoConfiguration.enableHDR ? .hdr : .sdr
            )
            sessionSurfaceContext.updateVideoPresentationSize(
                CGSize(
                    width: resolvedVideoConfiguration.width,
                    height: resolvedVideoConfiguration.height
                )
            )
            sessionSurfaceContext.transition(to: .connecting)
        }

        let trimmed = sessionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let _ = url.host else {
            throw ShadowClientRealtimeSessionRuntimeError.invalidSessionURL
        }

        if let prepareAudioDecoders {
            await prepareAudioDecoders()
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
            },
            onControllerFeedback: { [sessionSurfaceContext] feedbackEvent in
                sessionSurfaceContext.publishControllerFeedbackEvent(feedbackEvent)
            },
            onTermination: { [runtime = self] terminationEvent in
                await runtime.handleHostTerminationEvent(terminationEvent)
            },
            audioSessionActivation: audioSessionActivation,
            audioSessionDeactivation: audioSessionDeactivation
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
        av1SyncGateAllowsReferenceInvalidatedFrame = false
        av1SyncGateDroppedFrameCount = 0
        av1PendingRecoveryRequestAfterSuccessfulFrame = false
        lastObservedVideoFrameIndex = nil
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

        await decoder.reset()
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
        av1RecoverableDecoderFailureCount = 0
        firstAV1RecoverableDecoderFailureUptime = 0
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
        lastDecodedFrameCallbackUptime = 0
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
        lastAV1ReferenceInvalidationRequestUptime = 0
        pendingVideoRecoveryRequest = false
        videoRenderSubmitDropCount = 0
        lastObservedDecodeQueueBacklog = 0
        awaitingAV1SyncFrame = false
        av1SyncGateAllowsReferenceInvalidatedFrame = false
        av1SyncGateDroppedFrameCount = 0
        av1PendingRecoveryRequestAfterSuccessfulFrame = false
        lastObservedVideoFrameIndex = nil
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

    func sendInputKeepAlive() async throws {
        guard let rtspClient else {
            return
        }
        try await rtspClient.sendInputKeepAlive()
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
                await handleRuntimeRecoveryExhaustedNonFatal(
                    codec: accessUnit.codec,
                    reason: "decoder-recovery-exhausted"
                )
                try? await Task.sleep(for: .milliseconds(200))
                continue
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
            av1SyncGateAllowsReferenceInvalidatedFrame = false
            av1SyncGateDroppedFrameCount = 0
            av1PendingRecoveryRequestAfterSuccessfulFrame = false
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
        av1SyncGateAllowsReferenceInvalidatedFrame = false
        av1SyncGateDroppedFrameCount = 0
        av1PendingRecoveryRequestAfterSuccessfulFrame = false
        lastAV1DecodeSubmissionContext = nil
        await transitionSurfaceState(.failed(message))
        await closeVideoPacketQueue()
        await closeVideoDecodeQueue()
    }

    private func handleHostTerminationEvent(
        _ event: ShadowClientHostTerminationEvent
    ) async {
        logger.error("\(event.message, privacy: .public)")
        receiveTask?.cancel()
        depacketizeTask?.cancel()
        depacketizeTask = nil
        stallMonitorTask?.cancel()
        stallMonitorTask = nil
        awaitingAV1SyncFrame = false
        av1SyncGateAllowsReferenceInvalidatedFrame = false
        av1SyncGateDroppedFrameCount = 0
        av1PendingRecoveryRequestAfterSuccessfulFrame = false
        lastAV1DecodeSubmissionContext = nil
        await transitionSurfaceState(.disconnected(event.message))
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
        let ingestResult = shadowClientNVDepacketizer.ingestWithStatus(
            payload: payload,
            marker: marker
        )
        if let observedFrameIndex = shadowClientNVDepacketizer.lastObservedFrameIndex() {
            lastObservedVideoFrameIndex = observedFrameIndex
        }

        switch ingestResult {
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
            if let frameIndex = frameMetadata?.frameIndex {
                lastObservedVideoFrameIndex = frameIndex
            }
            if codec == .av1,
               ShadowClientMoonlightProtocolPolicy.AV1
               .shouldSendDeferredRecoveryRequestAfterSuccessfulFrame(
                   isPendingDeferredRequest: av1PendingRecoveryRequestAfterSuccessfulFrame
               )
            {
                _ = await requestAV1ReferenceFrameInvalidationOrRecovery(
                    reason: "depacketizer-discontinuity-post-success",
                    minimumInterval: 0.0
                )
            }

            updateRuntimeVideoStats(frameBytes: frame.count)
            if codec == .av1,
               !(await shouldAdmitAV1FrameToDecoderQueue(frameMetadata: frameMetadata))
            {
                return
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
        if Self.isAV1SyncFrameType(
            frameType,
            allowsReferenceInvalidatedFrame: av1SyncGateAllowsReferenceInvalidatedFrame
        ) {
            let droppedBeforeSync = av1SyncGateDroppedFrameCount
            awaitingAV1SyncFrame = false
            av1SyncGateAllowsReferenceInvalidatedFrame = false
            av1SyncGateDroppedFrameCount = 0
            let frameIndexDescription = Self.optionalUInt32Description(frameMetadata?.frameIndex)
            let frameTypeDescription = Self.optionalUInt8Description(frameType)
            logger.notice(
                "AV1 sync gate acquired sync frame index=\(frameIndexDescription, privacy: .public) type=\(frameTypeDescription, privacy: .public) dropped-before-sync=\(droppedBeforeSync, privacy: .public)"
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
        if codec == .av1, source == "enqueue-overflow" {
            guard now - lastVideoDecodeQueueRecoveryUptime >= 0.15 else {
                return
            }
            lastVideoDecodeQueueRecoveryUptime = now
            videoDecodeQueueDropCount = 0
            firstVideoDecodeQueueDropUptime = 0
            logger.error(
                "Video decode queue overflow for AV1; requesting immediate recovery frame"
            )
            await flushVideoPipelineForRecovery(codec: codec)
            await requestVideoRecoveryFrame(
                for: codec,
                reason: "decode-queue-saturation-immediate",
                minimumInterval: 0.0
            )
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
            av1SyncGateAllowsReferenceInvalidatedFrame = false
            av1SyncGateDroppedFrameCount = 0
            av1PendingRecoveryRequestAfterSuccessfulFrame = false
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
        if codec == .av1 {
            if firstDepacketizerRecoveryAttemptUptime == 0 ||
                now - firstDepacketizerRecoveryAttemptUptime >
                ShadowClientRealtimeSessionDefaults.av1DepacketizerRecoveryWindowSeconds
            {
                firstDepacketizerRecoveryAttemptUptime = now
                depacketizerRecoveryAttemptCount = 0
            }
            depacketizerRecoveryAttemptCount += 1
            if depacketizerRecoveryAttemptCount >= ShadowClientRealtimeSessionDefaults.av1MaxDepacketizerRecoveries {
                logger.error(
                    "Video depacketizer recovery attempts exceeded threshold for codec \(String(describing: codec), privacy: .public); aborting runtime recovery"
                )
                return true
            }
            depacketizerCorruptionCount = 0
            firstDepacketizerCorruptionUptime = 0
            lastDepacketizerRecoveryUptime = now
            let shouldDeferRecoveryRequest = ShadowClientMoonlightProtocolPolicy.AV1
                .shouldDeferRecoveryRequestAfterDiscontinuity()
            av1PendingRecoveryRequestAfterSuccessfulFrame = shouldDeferRecoveryRequest
            if shouldDeferRecoveryRequest {
                logger.error(
                    "Video depacketizer detected stream discontinuity for codec \(String(describing: codec), privacy: .public); deferring recovery request until next complete frame without immediate sync-gate transition"
                )
            } else {
                logger.error(
                    "Video depacketizer detected stream discontinuity for codec \(String(describing: codec), privacy: .public); immediately entering sync-gate and requesting recovery"
                )
                await flushVideoPipelineForRecovery(codec: codec)
                _ = await requestAV1ReferenceFrameInvalidationOrRecovery(
                    reason: "depacketizer-discontinuity-immediate",
                    minimumInterval: 0.0,
                    enterSyncGate: true
                )
            }
            if !hasRenderedFirstFrame {
                await transitionSurfaceState(.waitingForFirstFrame)
            }
            return false
        }

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
        let decodeFailureStatus = Self.decodeFailureStatus(from: error)
        let requiresImmediateDecoderReset = Self.requiresImmediateDecoderReset(
            codec: codec,
            decodeFailureStatus: decodeFailureStatus
        )
        if codec == .av1,
           let status = decodeFailureStatus,
           Self.isRecoverableDecodeFailureStatus(status)
        {
            if firstAV1RecoverableDecoderFailureUptime == 0 ||
                now - firstAV1RecoverableDecoderFailureUptime >
                ShadowClientRealtimeSessionDefaults.av1DecoderFastFallbackWindowSeconds
            {
                firstAV1RecoverableDecoderFailureUptime = now
                av1RecoverableDecoderFailureCount = 0
            }
            av1RecoverableDecoderFailureCount += 1
            if Self.shouldCountAV1RecoverableFailureForFastFallback(status),
               av1RecoverableDecoderFailureCount >=
                ShadowClientRealtimeSessionDefaults.av1DecoderFastFallbackFailureThreshold
            {
                logger.error(
                    "AV1 recoverable decoder failures exceeded fast-fallback threshold (count=\(self.av1RecoverableDecoderFailureCount, privacy: .public), window=\(ShadowClientRealtimeSessionDefaults.av1DecoderFastFallbackWindowSeconds, privacy: .public)s); aborting AV1 runtime recovery"
                )
                return false
            }
        }

        let shouldTreatFailureAsSoftFrameDrop = Self.shouldTreatDecoderFailureAsSoftFrameDrop(
            codec: codec,
            decodeFailureStatus: decodeFailureStatus
        )
        if shouldTreatFailureAsSoftFrameDrop {
            let lastDecodedOutputUptime = effectiveLastDecodedFrameOutputUptime()
            let hasRecoverableFailureBurst = Self.shouldRequestAV1SoftRecoveryFrameAfterRecoverableFailures(
                av1RecoverableDecoderFailureCount
            )
            let hasOutputStallEvidence = Self.shouldRequestAV1SoftRecoveryFrameAfterRecoverableFailures(
                recoverableFailureCount: av1RecoverableDecoderFailureCount,
                now: now,
                lastDecodedFrameOutputUptime: lastDecodedOutputUptime,
                minimumOutputStallSeconds: ShadowClientRealtimeSessionDefaults.videoQueuePressureRecoveryMinimumOutputStallSeconds
            )
            let shouldEnterSyncGateForSoftRecovery = Self.shouldEnterSyncGateForAV1SoftRecoveryRequest(
                recoverableFailureCount: av1RecoverableDecoderFailureCount,
                now: now,
                lastDecodedFrameOutputUptime: lastDecodedOutputUptime,
                minimumOutputStallSeconds: ShadowClientRealtimeSessionDefaults.videoQueuePressureRecoveryMinimumOutputStallSeconds
            )
            if hasRenderedFirstFrame, hasRecoverableFailureBurst {
                let shouldPerformLocalDecoderReset =
                    Self.shouldResetAV1DecoderAfterRecoverableFailureBurst(
                        recoverableFailureCount: av1RecoverableDecoderFailureCount,
                        now: now,
                        lastDecoderRecoveryUptime: lastDecoderRecoveryUptime,
                        recoveryCooldownSeconds: ShadowClientRealtimeSessionDefaults.decoderRecoveryCooldownSeconds
                    )
                if hasOutputStallEvidence {
                    logger.notice(
                        "AV1 decoder recoverable failure burst with output stall detected; requesting reference invalidation with sync-gate transition"
                    )
                } else {
                    logger.notice(
                        "AV1 decoder recoverable failure burst detected without output stall; forcing sync-gate transition to mask corrupted output"
                    )
                }
                if shouldPerformLocalDecoderReset {
                    logger.notice(
                        "AV1 decoder recoverable failure burst exceeded local-reset threshold; resetting decoder before recovery request"
                    )
                    lastDecoderRecoveryUptime = now
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
                    av1RecoverableDecoderFailureCount = 0
                    firstAV1RecoverableDecoderFailureUptime = 0
                }
                _ = await requestAV1ReferenceFrameInvalidationOrRecovery(
                    reason: "decoder-recoverable-soft",
                    minimumInterval: 1.0,
                    enterSyncGate: shouldEnterSyncGateForSoftRecovery
                )
            } else {
                logger.notice(
                    "AV1 decoder dropped recoverable frame without output stall; continuing without decoder reset"
                )
            }
            return true
        }

        if firstDecoderFailureUptime == 0 ||
            now - firstDecoderFailureUptime > ShadowClientRealtimeSessionDefaults.decoderFailureWindowSeconds
        {
            firstDecoderFailureUptime = now
            decoderFailureCount = 0
        }
        decoderFailureCount += 1

        if hasRenderedFirstFrame, decoderFailureCount == 1, !requiresImmediateDecoderReset {
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

        if !requiresImmediateDecoderReset {
            guard now - lastDecoderRecoveryUptime >= ShadowClientRealtimeSessionDefaults.decoderRecoveryCooldownSeconds else {
                return true
            }
        }

        lastDecoderRecoveryUptime = now
        decoderFailureCount = 0
        firstDecoderFailureUptime = 0
        if codec == .av1 {
            av1RecoverableDecoderFailureCount = 0
            firstAV1RecoverableDecoderFailureUptime = 0
        }
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
                await handleRuntimeRecoveryExhaustedNonFatal(
                    codec: codec,
                    reason: "decoder-recovery-exhausted-monitor"
                )
                try? await Task.sleep(for: .milliseconds(200))
                continue
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
            await handleRuntimeRecoveryExhaustedNonFatal(
                codec: codec,
                reason: "decoder-output-stall-exhausted"
            )
            try? await Task.sleep(for: .milliseconds(200))
            continue
        }
    }

    private func handleRuntimeRecoveryExhaustedNonFatal(
        codec: ShadowClientVideoCodec,
        reason: String
    ) async {
        if codec == .av1 || codec == .h265 {
            let codecLabel = codec == .av1 ? "AV1" : "HEVC"
            let fallbackLabel = codec == .av1 ? "fallback codec" : "H.264"
            let message =
                "\(codecLabel) runtime recovery exhausted (\(reason)). Runtime recovery exhausted; retry with \(fallbackLabel)."
            logger.error("\(message, privacy: .public)")
            await transitionSurfaceState(.failed(message))
            return
        }

        logger.error(
            "Runtime recovery exhausted for codec \(String(describing: codec), privacy: .public) (reason=\(reason, privacy: .public)); suppressing fatal escalation and keeping session alive"
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
            reason: reason,
            minimumInterval: 0.35
        )
        if !hasRenderedFirstFrame {
            await transitionSurfaceState(.waitingForFirstFrame)
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

        if Self.shouldKeepDecoderOutputStallRecoveryNonFatal(
            now: now,
            lastDecodeSubmitUptime: lastDecodeSubmitUptime
        ) {
            logger.notice(
                "Video decoder output stall detected without recent decode submissions for codec \(String(describing: codec), privacy: .public); keeping session alive and requesting recovery frame only"
            )
            lastDecoderOutputStallRecoveryUptime = now
            _ = await requestVideoRecoveryFrame(
                for: codec,
                reason: "decoder-output-stall-no-recent-ingress"
            )
            return true
        }

        if Self.shouldAbortDecoderOutputStallRecovery(
            recoveryAttemptCount: decoderOutputStallRecoveryCount,
            maxRecoveryAttempts: ShadowClientRealtimeSessionDefaults.decoderMaxOutputStallRecoveries
        ) {
            // Keep the session alive under prolonged no-output conditions.
            // Runtime should continue non-fatal recovery-frame requests instead
            // of escalating to a terminal stream failure.
            logger.error(
                "Video decoder output stall recoveries exceeded threshold for codec \(String(describing: codec), privacy: .public); suppressing fatal escalation and requesting recovery frame only"
            )
            lastDecoderOutputStallRecoveryUptime = now
            _ = await requestVideoRecoveryFrame(
                for: codec,
                reason: "decoder-output-stall-nonfatal"
            )
            return true
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
        try await decoder.decode(
            accessUnit: accessUnit,
            codec: codec,
            parameterSets: parameterSets,
            backlogHint: remainingDecodeQueueBacklog
        ) { pixelBuffer in
            await runtime.recordDecodedFrameCallbackUptime()
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
            av1SyncGateAllowsReferenceInvalidatedFrame = false
            av1SyncGateDroppedFrameCount = 0
            av1PendingRecoveryRequestAfterSuccessfulFrame = false
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
        await surfaceContext.frameStore.update(pixelBuffer: pixelBuffer)
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
        let resolvedConfiguration = Self.resolvedRuntimeVideoConfiguration(
            configuration,
            videoCodecSupport: videoCodecSupport
        )
        let resolvedCodecPreference = resolvedConfiguration.preferredCodec
        if resolvedCodecPreference != configuration.preferredCodec {
            logger.notice(
                "RTSP runtime codec auto-resolution requested=\(configuration.preferredCodec.rawValue, privacy: .public) resolved=\(resolvedCodecPreference.rawValue, privacy: .public) hdr=\(configuration.enableHDR, privacy: .public) yuv444=\(configuration.enableYUV444, privacy: .public) reason=local-decoder-capability"
            )
        }
        return resolvedConfiguration
    }

    public static func resolvedRuntimeVideoConfiguration(
        _ configuration: ShadowClientRemoteSessionVideoConfiguration,
        videoCodecSupport: ShadowClientVideoCodecSupport = .init()
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
            preferredSurroundChannelCount: configuration.preferredSurroundChannelCount,
            enableYUV444: configuration.enableYUV444,
            displayScalePercent: configuration.displayScalePercent,
            requestHiDPI: configuration.requestHiDPI,
            remoteInputKey: configuration.remoteInputKey,
            remoteInputKeyID: configuration.remoteInputKeyID,
            serverAppVersion: configuration.serverAppVersion
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
        videoStatsWindowStartUptime = now
        videoStatsFrameCount = 0
        videoStatsByteCount = 0
        let sessionSurfaceContext = self.surfaceContext
        Task { @MainActor in
            sessionSurfaceContext.updateRuntimeVideoBitrateKbps(bitrateKbps)
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
        lastDecodedFrameCallbackUptime = 0
        decoderOutputStallCandidateCount = 0
        firstDecoderOutputStallCandidateUptime = 0
        resetVideoQueuePressureTracking()
        pendingVideoRecoveryRequest = false
        // A successful decoded frame means pipeline recovery made forward progress.
        // Keep recovery escalation based on consecutive failures, not sparse
        // failures spread across otherwise healthy playback.
        depacketizerRecoveryAttemptCount = 0
        firstDepacketizerRecoveryAttemptUptime = 0
        decoderRecoveryAttemptCount = 0
        firstDecoderRecoveryAttemptUptime = 0
        decoderFailureCount = 0
        firstDecoderFailureUptime = 0
        av1RecoverableDecoderFailureCount = 0
        firstAV1RecoverableDecoderFailureUptime = 0
    }

    private func effectiveLastDecodedFrameOutputUptime() -> TimeInterval {
        max(lastDecodedFrameOutputUptime, lastDecodedFrameCallbackUptime)
    }

    private func recordDecodedFrameCallbackUptime() {
        lastDecodedFrameCallbackUptime = ProcessInfo.processInfo.systemUptime
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
    private func requestAV1ReferenceFrameInvalidationOrRecovery(
        reason: String,
        minimumInterval: TimeInterval = ShadowClientRealtimeSessionDefaults.videoRecoveryFrameRequestCooldownSeconds,
        enterSyncGate: Bool = false
    ) async -> Bool {
        let endFrameIndex =
            lastAV1DecodeSubmissionContext?.depacketizerMetadata?.frameIndex ??
            lastObservedVideoFrameIndex
        let now = ProcessInfo.processInfo.systemUptime

        if let endFrameIndex,
           now - lastAV1ReferenceInvalidationRequestUptime >= max(0, minimumInterval)
        {
            let range = Self.av1ReferenceInvalidationRange(endFrameIndex: endFrameIndex)
            lastAV1ReferenceInvalidationRequestUptime = now
            if enterSyncGate {
                awaitingAV1SyncFrame = true
                av1SyncGateAllowsReferenceInvalidatedFrame = false
                av1SyncGateDroppedFrameCount = 0
            }
            logger.notice(
                "AV1 reference frame invalidation requested (reason=\(reason, privacy: .public), range=\(range.start, privacy: .public)-\(range.end, privacy: .public))"
            )
            await rtspClient?.requestInvalidateReferenceFrames(
                startFrameIndex: range.start,
                endFrameIndex: range.end
            )
            return true
        }

        return await requestVideoRecoveryFrame(
            codec: .av1,
            reason: reason,
            minimumInterval: minimumInterval
        )
    }

    @discardableResult
    private func requestVideoRecoveryFrame(
        for codec: ShadowClientVideoCodec,
        reason: String,
        minimumInterval: TimeInterval = ShadowClientRealtimeSessionDefaults.videoRecoveryFrameRequestCooldownSeconds
    ) async -> Bool {
        if codec == .av1 {
            awaitingAV1SyncFrame = true
            av1SyncGateAllowsReferenceInvalidatedFrame = false
        }
        let didRequest = await requestVideoRecoveryFrame(
            codec: codec,
            reason: reason,
            minimumInterval: minimumInterval
        )
        if codec == .av1 {
            av1SyncGateAllowsReferenceInvalidatedFrame = false
            if didRequest {
                av1PendingRecoveryRequestAfterSuccessfulFrame = false
            }
        }
        return didRequest
    }

    @discardableResult
    private func requestVideoRecoveryFrame(
        codec: ShadowClientVideoCodec? = nil,
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
        await rtspClient.requestVideoRecoveryFrame(
            lastSeenFrameIndex: lastObservedVideoFrameIndex
        )
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
            // H264/H265 tolerate trailing zero padding and the Apollo host doesn't guarantee valid lastPayloadLength.
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
            case let .decodeFailed(status):
                return !isRecoverableDecodeFailureStatus(status)
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

    static func requiresImmediateDecoderReset(
        codec: ShadowClientVideoCodec,
        decodeFailureStatus: OSStatus?
    ) -> Bool {
        guard let decodeFailureStatus else {
            return false
        }
        // AV1 -12909 is often a transient decode miss under network burst loss.
        // Treat it as soft recovery first (request recovery frame) to avoid churn.
        if codec == .av1, decodeFailureStatus == -12909 {
            return false
        }
        return decodeFailureStatus == -12903
    }

    static func shouldTreatDecoderFailureAsSoftFrameDrop(
        codec: ShadowClientVideoCodec,
        decodeFailureStatus: OSStatus?
    ) -> Bool {
        codec == .av1 && decodeFailureStatus == -12909
    }

    static func shouldCountAV1RecoverableFailureForFastFallback(_ status: OSStatus) -> Bool {
        // Keep AV1 fast fallback tied to decoder-instability-class failures.
        // -12909 is treated as a soft frame drop and should not force codec relaunch.
        status == -12903
    }

    static func shouldResetAV1DecoderAfterRecoverableFailureBurst(
        recoverableFailureCount: Int,
        now: TimeInterval,
        lastDecoderRecoveryUptime: TimeInterval,
        recoveryCooldownSeconds: TimeInterval
    ) -> Bool {
        guard recoverableFailureCount >= 2 else {
            return false
        }
        return now - lastDecoderRecoveryUptime >= max(0, recoveryCooldownSeconds)
    }

    static func shouldRequestAV1SoftRecoveryFrameAfterRecoverableFailures(
        _ recoverableFailureCount: Int
    ) -> Bool {
        recoverableFailureCount >= 1
    }

    static func shouldRequestAV1SoftRecoveryFrameAfterRecoverableFailures(
        recoverableFailureCount: Int,
        now: TimeInterval,
        lastDecodedFrameOutputUptime: TimeInterval,
        minimumOutputStallSeconds: TimeInterval
    ) -> Bool {
        guard shouldRequestAV1SoftRecoveryFrameAfterRecoverableFailures(
            recoverableFailureCount
        ) else {
            return false
        }
        return shouldEscalateQueuePressureToRecovery(
            now: now,
            lastDecodedFrameOutputUptime: lastDecodedFrameOutputUptime,
            minimumStallSeconds: minimumOutputStallSeconds
        )
    }

    static func shouldEnterSyncGateForAV1SoftRecoveryRequest(
        recoverableFailureCount: Int,
        now: TimeInterval,
        lastDecodedFrameOutputUptime: TimeInterval,
        minimumOutputStallSeconds: TimeInterval
    ) -> Bool {
        // Visual corruption can still be severe even when VT keeps emitting output
        // (i.e. no output-stall signal). Enter sync gate on bursty recoverable
        // failures to suppress corrupted reference-chain output until next sync frame.
        let hasRecoverableFailureBurst = shouldRequestAV1SoftRecoveryFrameAfterRecoverableFailures(
            recoverableFailureCount
        )
        if hasRecoverableFailureBurst {
            return true
        }
        return shouldRequestAV1SoftRecoveryFrameAfterRecoverableFailures(
            recoverableFailureCount: recoverableFailureCount,
            now: now,
            lastDecodedFrameOutputUptime: lastDecodedFrameOutputUptime,
            minimumOutputStallSeconds: minimumOutputStallSeconds
        )
    }

    static func av1ReferenceInvalidationRange(
        endFrameIndex: UInt32,
        window: UInt32 = 0x20
    ) -> (start: UInt32, end: UInt32) {
        let normalizedWindow = max(1, window)
        let startFrameIndex = endFrameIndex > normalizedWindow
            ? (endFrameIndex - normalizedWindow)
            : 0
        return (startFrameIndex, endFrameIndex)
    }

    static func isRecoverableDecodeFailureStatus(_ status: OSStatus) -> Bool {
        // -12909 and -12903 are commonly observed as transient VT decode errors
        // during burst loss/recovery on realtime streams.
        let recoverableStatuses: Set<OSStatus> = [-12909, -12903]
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

    static func isAV1SyncFrameType(
        _ frameType: UInt8?,
        allowsReferenceInvalidatedFrame: Bool = false
    ) -> Bool {
        ShadowClientMoonlightProtocolPolicy.AV1.isSyncFrameType(
            frameType,
            allowsReferenceInvalidatedFrame: allowsReferenceInvalidatedFrame
        )
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

    static func shouldKeepDecoderOutputStallRecoveryNonFatal(
        now: TimeInterval,
        lastDecodeSubmitUptime: TimeInterval,
        recentIngressGraceSeconds: TimeInterval =
            ShadowClientRealtimeSessionDefaults.decoderOutputStallRecentIngressGraceSeconds
    ) -> Bool {
        guard lastDecodeSubmitUptime > 0 else {
            return true
        }
        return now - lastDecodeSubmitUptime > max(0, recentIngressGraceSeconds)
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

    static func shouldRequestVideoRecoveryAfterFECUnrecoverableBurst(
        now: TimeInterval,
        firstUnrecoverableUptime: TimeInterval,
        unrecoverableCount: Int,
        lastRequestUptime: TimeInterval,
        burstWindow: TimeInterval,
        burstThreshold: Int,
        minimumInterval: TimeInterval
    ) -> Bool {
        let normalizedBurstThreshold = max(1, burstThreshold)
        guard unrecoverableCount >= normalizedBurstThreshold else {
            return false
        }

        let normalizedBurstWindow = max(0, burstWindow)
        if firstUnrecoverableUptime > 0,
           now - firstUnrecoverableUptime > normalizedBurstWindow
        {
            return false
        }

        return now - lastRequestUptime >= max(0, minimumInterval)
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

    static func shouldTreatUDPVideoDatagramReceiveAsStalledAfterStartup(
        datagramCount: Int,
        secondsSinceLastDatagram: TimeInterval,
        inactivityTimeoutSeconds: TimeInterval =
            ShadowClientRealtimeSessionDefaults.postStartVideoDatagramInactivityTimeoutSeconds
    ) -> Bool {
        guard datagramCount > 0 else {
            return false
        }
        return secondsSinceLastDatagram >= max(0, inactivityTimeoutSeconds)
    }

    static func shouldRequestVideoRecoveryForUDPDatagramInactivity(
        now: TimeInterval,
        lastRecoveryRequestUptime: TimeInterval,
        lastInteractiveInputEventUptime: TimeInterval,
        secondsSinceLastDatagram: TimeInterval,
        inactivityTimeoutSeconds: TimeInterval =
            ShadowClientRealtimeSessionDefaults.postStartVideoDatagramInactivityTimeoutSeconds,
        recoveryRequestCooldownSeconds: TimeInterval =
            ShadowClientRealtimeSessionDefaults.videoRecoveryFrameRequestUnderPressureCooldownSeconds,
        recentInputWindowSeconds: TimeInterval =
            ShadowClientRealtimeSessionDefaults.postStartVideoDatagramRecoveryInputWindowSeconds
    ) -> Bool {
        guard secondsSinceLastDatagram >= max(0, inactivityTimeoutSeconds) else {
            return false
        }
        _ = lastInteractiveInputEventUptime
        _ = recentInputWindowSeconds
        return now - lastRecoveryRequestUptime >= max(0, recoveryRequestCooldownSeconds)
    }

    static func shouldTreatGamepadStateAsInteractiveForUDPDatagramRecovery(
        _ state: ShadowClientRemoteGamepadState
    ) -> Bool {
        state.buttonFlags != 0
    }

    static func shouldRecycleUDPVideoSocketAfterInactivity(
        datagramCount: Int,
        secondsSinceLastDatagram: TimeInterval,
        recycleThresholdSeconds: TimeInterval =
            ShadowClientRealtimeSessionDefaults.postStartVideoDatagramInactivitySocketRecycleThresholdSeconds
    ) -> Bool {
        guard datagramCount > 0 else {
            return false
        }
        return secondsSinceLastDatagram >= max(0, recycleThresholdSeconds)
    }

    static func shouldRecycleUDPVideoSocketForStartupInactivity(
        secondsSinceReceiveStart: TimeInterval,
        recycleThresholdSeconds: TimeInterval =
            ShadowClientRealtimeSessionDefaults.postStartVideoDatagramInactivitySocketRecycleThresholdSeconds
    ) -> Bool {
        return secondsSinceReceiveStart >= max(0, recycleThresholdSeconds)
    }

    static func shouldEscalateUDPVideoDatagramInactivityToFallback(
        now: TimeInterval,
        firstObservedStallUptime: TimeInterval,
        lastInteractiveInputUptime: TimeInterval,
        fallbackThresholdSeconds: TimeInterval =
            ShadowClientRealtimeSessionDefaults.postStartVideoDatagramInactivityFallbackThresholdSeconds
    ) -> Bool {
        // Moonlight-compatible behavior: once startup succeeds, post-start UDP
        // video inactivity is treated as a recoverable stall instead of a
        // terminal transport failure.
        _ = now
        _ = firstObservedStallUptime
        _ = lastInteractiveInputUptime
        _ = fallbackThresholdSeconds
        return false
    }

    static func shouldFallbackToInterleavedTransportAfterUDPReceiveError(
        _ error: Error
    ) -> Bool {
        let normalized = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.contains("udp video timeout: no video datagram received")
    }

    static func shouldRetryInSessionAfterUDPVideoReceiveError(
        _ error: Error
    ) -> Bool {
        if error is CancellationError {
            return false
        }
        let normalized = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.contains("udp video timeout: no video datagram received") ||
            normalized.contains("udp video timeout: no startup datagrams received")
        {
            // Moonlight-compatible policy: treat sustained UDP video inactivity as terminal
            // for this session attempt instead of looping in in-session recovery forever.
            return false
        }
        if normalized.contains("udp video receive recycle requested") {
            return true
        }
        if shouldFallbackToInterleavedTransportAfterUDPReceiveError(error) {
            return true
        }
        if isLikelyRTSPTransportTerminationError(error) {
            return true
        }
        // Runtime policy for Apollo-host UDP path: keep session alive and continue
        // in-session receive recovery for non-cancellation failures instead of
        // surfacing terminal transport errors to the launcher.
        return true
    }

    static func shouldResetControlChannelAfterTransientInputSendFailures(
        failureCount: Int,
        now: TimeInterval,
        firstFailureUptime: TimeInterval,
        burstWindowSeconds: TimeInterval =
            ShadowClientRealtimeSessionDefaults.transientInputSendFailureBurstWindowSeconds,
        burstThreshold: Int =
            ShadowClientRealtimeSessionDefaults.transientInputSendFailureBurstThreshold
    ) -> Bool {
        let normalizedBurstThreshold = max(1, burstThreshold)
        guard failureCount >= normalizedBurstThreshold else {
            return false
        }
        guard firstFailureUptime > 0 else {
            return false
        }
        return now - firstFailureUptime <= max(0, burstWindowSeconds)
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

    static func isLikelyRTSPTransportTerminationError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == "Network.NWError", nsError.code == 96 {
            return true
        }

        if let networkError = error as? NWError,
           case let .posix(code) = networkError
        {
            switch code {
            case .ECONNRESET, .EPIPE, .ENOTCONN, .ECONNABORTED:
                return true
            default:
                break
            }
        }

        let normalized = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.contains("no message available on stream") ||
            normalized.contains("transport connection closed") ||
            normalized.contains("connection closed") ||
            normalized.contains("connection reset by peer") ||
            normalized.contains("broken pipe") ||
            normalized.contains("nwerror error 96")
    }

    static func shouldResetInputControlChannelAfterSendError(_ error: Error) -> Bool {
        if isTransientInputSendError(error) {
            return false
        }
        if Self.isLikelyRTSPTransportTerminationError(error) {
            return true
        }

        if let controlError = error as? ShadowClientHostControlChannelError {
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
        videoPayloadCandidates _: Set<Int>
    ) -> Bool {
        guard observedPayloadType != currentPayloadType else {
            return false
        }
        guard observedPayloadType != ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType else {
            return false
        }
        guard observedPayloadType != audioPayloadType else {
            return false
        }
        guard (0 ... 127).contains(observedPayloadType) else {
            return false
        }

        // Before first-frame lock, accept video-socket RTP payload mismatches, but
        // never adopt the negotiated audio payload type on the video path.
        return true
    }

    static func videoPayloadTypeObservationThreshold(
        observedPayloadType: Int,
        videoPayloadCandidates: Set<Int>,
        baseThreshold: Int = ShadowClientRealtimeSessionDefaults.videoPayloadTypeAdaptationObservationThreshold
    ) -> Int {
        _ = observedPayloadType
        _ = videoPayloadCandidates
        _ = baseThreshold
        // Mirror Moonlight behavior on Apollo-host video sockets: switch to the
        // first valid non-audio/control payload type immediately so we don't
        // drop initial keyframe packets while probing mismatched PT values.
        return 1
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
        let hasSOF = (flags & 0x04) != 0
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
