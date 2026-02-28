import AVFoundation
import CommonCrypto
import Foundation
import Network
import os

public enum ShadowClientRealtimeAudioOutputState: Equatable, Sendable {
    case idle
    case starting
    case playing(codec: ShadowClientAudioCodec, sampleRate: Int, channels: Int)
    case deviceUnavailable(String)
    case decoderFailed(String)
    case disconnected(String)
}

public struct ShadowClientRealtimeAudioEncryptionConfiguration: Equatable, Sendable {
    public let key: Data
    public let keyID: UInt32

    public init(
        key: Data,
        keyID: UInt32
    ) {
        self.key = key
        self.keyID = keyID
    }
}

public final class ShadowClientRealtimeAudioSessionRuntime: @unchecked Sendable {
    fileprivate struct RTPPacket: Sendable {
        let sequenceNumber: UInt16
        let timestamp: UInt32
        let ssrc: UInt32
        let payloadType: Int
        let payload: Data
    }

    fileprivate struct QueuedPrimaryAudioPacket: Sendable {
        let packet: RTPPacket
        let observedMoonlightFECShardsSincePreviousPrimary: Int
    }

    fileprivate struct AudioQueuePressureProfile: Sendable {
        let pressureSignalInterval: Int
        let pressureTrimInterval: Int
        let pressureTrimToRecentPackets: Int
        let decodeSheddingLowWatermarkSlots: Int
        let maximumQueuedBuffers: Int
    }

    private let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "RealtimeAudio"
    )
    private let stateDidChange: (@Sendable (ShadowClientRealtimeAudioOutputState) async -> Void)?
    private let connectionQueue = DispatchQueue(
        label: "com.skyline23.shadowclient.realtime-audio.connection"
    )
    private var connection: NWConnection?
    private var receiveTask: Task<Void, Never>?
    private var decodeTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var packetQueue: ShadowClientRealtimeAudioPacketQueue?
    private var decoder: (any ShadowClientRealtimeAudioPacketDecoding)?
    private var payloadDecryptor: ShadowClientRealtimeAudioPayloadDecryptor?
    private var output: ShadowClientRealtimeAudioEngineOutput?
    private var jitterBuffer = ShadowClientRealtimeAudioRTPJitterBuffer(
        targetDepth: ShadowClientRealtimeSessionDefaults.audioJitterBufferTargetDepth,
        maximumDepth: ShadowClientRealtimeSessionDefaults.audioJitterBufferMaximumDepth,
        outOfOrderWait: ShadowClientRealtimeSessionDefaults.audioJitterBufferOutOfOrderWaitSeconds
    )
    private var state: ShadowClientRealtimeAudioOutputState = .idle

    public init(
        stateDidChange: (@Sendable (ShadowClientRealtimeAudioOutputState) async -> Void)? = nil
    ) {
        self.stateDidChange = stateDidChange
    }

    deinit {
        stop(emitIdleState: false)
    }

    public func start(
        remoteHost: NWEndpoint.Host,
        remotePort: NWEndpoint.Port,
        localHost: NWEndpoint.Host?,
        preferredLocalPort: UInt16?,
        track: ShadowClientRTSPAudioTrackDescriptor?,
        pingPayload: Data?,
        encryption: ShadowClientRealtimeAudioEncryptionConfiguration? = nil
    ) async throws {
        stop()
        updateState(.starting)

        let resolvedTrack = track ?? ShadowClientRTSPAudioTrackDescriptor(
            codec: .opus,
            rtpPayloadType: 97,
            sampleRate: 48_000,
            channelCount: 2,
            controlURL: nil,
            formatParameters: [:]
        )
        let packetDurationMs = ShadowClientMoonlightProtocolPolicy.Audio.packetDurationMs(
            from: ShadowClientRTSPAnnounceProfile.aqosPacketDuration
        )
        let minimumPacketSamples = max(1, resolvedTrack.sampleRate / 200)
        let maximumPacketSamples = max(minimumPacketSamples, minimumPacketSamples * 48)
        let nominalPacketFrameCount = Self.moonlightPLCSamplesPerChannel(
            sampleRate: resolvedTrack.sampleRate,
            packetDurationMs: packetDurationMs,
            minimumPacketSamples: minimumPacketSamples,
            maximumPacketSamples: maximumPacketSamples
        )
        var decoderImplementationName = "unknown"
        var realtimePendingDurationCapMs = ShadowClientMoonlightProtocolPolicy.Audio
            .outputRealtimePendingDurationCapMs

        do {
            let resolvedDecoder = try ShadowClientRealtimeAudioDecoderFactory.make(
                for: resolvedTrack
            )
            let queuePressureProfile = Self.audioQueuePressureProfile(
                sampleRate: resolvedTrack.sampleRate,
                channels: resolvedTrack.channelCount,
                packetDurationMs: packetDurationMs
            )
            // Match Moonlight's LBQ pressure policy: skip enqueue above 30ms pending duration.
            realtimePendingDurationCapMs = Self.audioRealtimePendingDurationCapMs(
                packetDurationMs: packetDurationMs,
                maximumQueuedBuffers: queuePressureProfile.maximumQueuedBuffers
            )
            // Keep renderer backpressure aligned with Moonlight SDL behavior (~10 queued frames).
            let rendererPendingDurationCapMs = max(
                realtimePendingDurationCapMs,
                Double(packetDurationMs * 10)
            )
            decoderImplementationName = ShadowClientRealtimeAudioDecoderFactory.debugName(
                for: resolvedDecoder
            )
            decoder = resolvedDecoder
            output = try ShadowClientRealtimeAudioEngineOutput(
                format: resolvedDecoder.outputFormat,
                maximumQueuedBufferCount: queuePressureProfile.maximumQueuedBuffers,
                nominalFramesPerBuffer: AVAudioFrameCount(max(1, nominalPacketFrameCount)),
                maximumPendingDurationMs: rendererPendingDurationCapMs
            )
            logger.notice(
                "Audio output pressure mode=shadow-lbq-pending-duration(moonlight-compatible) cap-ms=\(realtimePendingDurationCapMs, privacy: .public) renderer-cap-ms=\(rendererPendingDurationCapMs, privacy: .public) queued-buffers=\(queuePressureProfile.maximumQueuedBuffers, privacy: .public) nominal-frames=\(nominalPacketFrameCount, privacy: .public)"
            )
            if let encryption {
                payloadDecryptor = try ShadowClientRealtimeAudioPayloadDecryptor(
                    configuration: encryption
                )
            } else {
                payloadDecryptor = nil
            }
        } catch {
            let message = "Audio output initialization failed: \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
            updateState(.deviceUnavailable(message))
            throw error
        }

        do {
            let udpConnection = try await makeUDPConnection(
                remoteHost: remoteHost,
                remotePort: remotePort,
                localHost: localHost,
                preferredLocalPort: preferredLocalPort
            )
            connection = udpConnection
            jitterBuffer.reset(preferredPayloadType: resolvedTrack.rtpPayloadType)
            let packetQueue = ShadowClientRealtimeAudioPacketQueue(
                capacity: ShadowClientMoonlightProtocolPolicy.Audio.packetQueueBound
            )
            self.packetQueue = packetQueue
            let moonlightRSFECQueue = ShadowClientRealtimeAudioMoonlightRSFECQueue()

            try await sendInitialPing(
                over: udpConnection,
                pingPayload: pingPayload
            )
            startPingLoop(
                over: udpConnection,
                pingPayload: pingPayload
            )
            guard let activeDecoder = decoder,
                  let activeOutput = output
            else {
                let message = "Audio runtime dependencies were released before receive loop start."
                logger.error("\(message, privacy: .public)")
                updateState(.disconnected(message))
                throw NSError(
                    domain: "ShadowClientRealtimeAudioSessionRuntime",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message]
                )
            }
            startDecodeLoop(
                over: udpConnection,
                packetQueue: packetQueue,
                moonlightRSFECQueue: moonlightRSFECQueue,
                sampleRate: resolvedTrack.sampleRate,
                packetDurationMs: packetDurationMs,
                realtimePendingDurationCapMs: realtimePendingDurationCapMs,
                decoder: activeDecoder,
                payloadDecryptor: payloadDecryptor,
                output: activeOutput
            )
            startReceiveLoop(
                over: udpConnection,
                preferredPayloadType: resolvedTrack.rtpPayloadType,
                sampleRate: resolvedTrack.sampleRate,
                channels: resolvedTrack.channelCount,
                packetDurationMs: packetDurationMs,
                output: activeOutput,
                packetQueue: packetQueue,
                moonlightRSFECQueue: moonlightRSFECQueue
            )
            updateState(
                .playing(
                    codec: resolvedTrack.codec,
                    sampleRate: resolvedTrack.sampleRate,
                    channels: resolvedTrack.channelCount
                )
            )
            let encryptionLabel = payloadDecryptor == nil ? "disabled" : "enabled"
            logger.notice(
                "Audio runtime started codec=\(resolvedTrack.codec.label, privacy: .public) payloadType=\(resolvedTrack.rtpPayloadType, privacy: .public) sampleRate=\(resolvedTrack.sampleRate, privacy: .public) channels=\(resolvedTrack.channelCount, privacy: .public) encryption=\(encryptionLabel, privacy: .public) decoder=\(decoderImplementationName, privacy: .public) output=\(activeOutput.debugFormatDescription, privacy: .public)"
            )
        } catch {
            let message = "Audio transport failed to start: \(error.localizedDescription)"
            logger.error("\(message, privacy: .public)")
            updateState(.disconnected(message))
            throw error
        }
    }

    public func stop() {
        stop(emitIdleState: true)
    }

    private func stop(emitIdleState: Bool) {
        receiveTask?.cancel()
        receiveTask = nil

        decodeTask?.cancel()
        decodeTask = nil

        pingTask?.cancel()
        pingTask = nil

        connection?.cancel()
        connection = nil

        let packetQueueToShutdown = packetQueue
        packetQueue = nil
        if let packetQueueToShutdown {
            Task {
                _ = await packetQueueToShutdown.shutdown()
            }
        }

        let outputToStop = output
        output = nil
        outputToStop?.stop()

        decoder = nil
        payloadDecryptor = nil
        jitterBuffer.reset(preferredPayloadType: nil)
        if emitIdleState {
            updateState(.idle)
        }
    }

    private func startDecodeLoop(
        over connection: NWConnection,
        packetQueue: ShadowClientRealtimeAudioPacketQueue,
        moonlightRSFECQueue: ShadowClientRealtimeAudioMoonlightRSFECQueue,
        sampleRate: Int,
        packetDurationMs: Int,
        realtimePendingDurationCapMs: Double,
        decoder: any ShadowClientRealtimeAudioPacketDecoding,
        payloadDecryptor: ShadowClientRealtimeAudioPayloadDecryptor?,
        output audioOutput: ShadowClientRealtimeAudioEngineOutput
    ) {
        decodeTask = Task.detached(priority: .high) { [weak self] in
            guard let self else {
                return
            }

            let queuePressureProfile = Self.audioQueuePressureProfile(
                sampleRate: sampleRate,
                channels: decoder.channels,
                packetDurationMs: packetDurationMs
            )
            let decodeFailureAbortThreshold = max(
                1,
                ShadowClientRealtimeSessionDefaults.audioDecodeFailureAbortThreshold
            )
            let decodeFailureLogInterval = max(
                1,
                ShadowClientRealtimeSessionDefaults.audioDecodeFailureLogInterval
            )
            let minimumPacketSamples = max(1, sampleRate / 200)
            let maximumPacketSamples = max(minimumPacketSamples, minimumPacketSamples * 48)
            let moonlightPLCSamplesPerChannel = Self.moonlightPLCSamplesPerChannel(
                sampleRate: sampleRate,
                packetDurationMs: packetDurationMs,
                minimumPacketSamples: minimumPacketSamples,
                maximumPacketSamples: maximumPacketSamples
            )

            var hasLoggedFirstDecodedBuffer = false
            var lastDecodedSequenceNumber: UInt16?
            var consecutiveDroppedOutputBuffers = 0
            var consecutiveDecryptFailures = 0
            var consecutiveDecodeFailures = 0
            var outputQueuePressureDropCount = 0
            var firstOutputQueuePressureDropUptime: TimeInterval = 0
            var decodeCooldownUntilUptime: TimeInterval = 0
            var lossConcealmentEventCount = 0
            var rsFECRecoveryCount = 0
            let audioDecodeCooldown = ShadowClientRealtimeSessionDefaults.audioOutputQueueDecodeCooldown
            let audioDecodeCooldownSeconds: TimeInterval = {
                let components = ShadowClientRealtimeSessionDefaults.audioOutputQueueDecodeCooldown.components
                return TimeInterval(components.seconds) +
                    (TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
            }()

            let registerOutputQueuePressureDrop: (Int, String) -> Void = { droppedCount, reason in
                guard droppedCount > 0 else {
                    return
                }
                let now = ProcessInfo.processInfo.systemUptime
                if firstOutputQueuePressureDropUptime == 0 ||
                    now - firstOutputQueuePressureDropUptime >
                    ShadowClientRealtimeSessionDefaults.audioOutputQueueDropWindowSeconds
                {
                    firstOutputQueuePressureDropUptime = now
                    outputQueuePressureDropCount = 0
                }

                let previousDropCount = outputQueuePressureDropCount
                outputQueuePressureDropCount += droppedCount
                if outputQueuePressureDropCount == droppedCount ||
                    Self.didCounterCrossIntervalBoundary(
                        previous: previousDropCount,
                        current: outputQueuePressureDropCount,
                        interval: max(
                            queuePressureProfile.pressureSignalInterval,
                            ShadowClientMoonlightProtocolPolicy.Audio.packetQueueBound
                        )
                    )
                {
                    self.logger.error(
                        "Audio output queue pressure detected (\(reason, privacy: .public), dropped=\(outputQueuePressureDropCount, privacy: .public))"
                    )
                }
            }
            let maybeActivateDecodeCooldownAfterPressureBurst: () -> Void = {
                let now = ProcessInfo.processInfo.systemUptime
                guard Self.shouldActivateAudioDecodeCooldown(
                    now: now,
                    firstOutputQueuePressureDropUptime: firstOutputQueuePressureDropUptime,
                    outputQueuePressureDropCount: outputQueuePressureDropCount,
                    dropWindowSeconds: ShadowClientRealtimeSessionDefaults.audioOutputQueueDropWindowSeconds,
                    burstThreshold: ShadowClientRealtimeSessionDefaults.audioOutputQueueSaturationBurstThreshold
                ) else {
                    return
                }
                decodeCooldownUntilUptime = max(
                    decodeCooldownUntilUptime,
                    now + audioDecodeCooldownSeconds
                )
                outputQueuePressureDropCount = 0
                firstOutputQueuePressureDropUptime = 0
                self.logger.notice(
                    "Audio output saturation burst detected; pausing decode for \(Int((audioDecodeCooldownSeconds * 1_000).rounded()), privacy: .public)ms"
                )
            }

            let logFirstDecodedBufferIfNeeded: (AVAudioFrameCount, String) -> Void = { frameLength, source in
                guard !hasLoggedFirstDecodedBuffer else {
                    return
                }
                hasLoggedFirstDecodedBuffer = true
                self.logger.notice(
                    "First decoded audio buffer enqueued: source=\(source, privacy: .public), frames=\(frameLength, privacy: .public)"
                )
            }

            let enqueueDecodedBuffer: (AVAudioPCMBuffer, String, Bool) -> Void = { pcmBuffer, source, shouldDropDueToPendingPressure in
                if shouldDropDueToPendingPressure {
                    registerOutputQueuePressureDrop(1, "drop-shadow-lbq-pending-audio-duration")
                    return
                }

                if decoder.requiresPlaybackSafetyGuard,
                   !ShadowClientRealtimeAudioPCMBufferGuard.isSafeForPlayback(pcmBuffer)
                {
                    consecutiveDroppedOutputBuffers += 1
                    if consecutiveDroppedOutputBuffers == 1 ||
                        consecutiveDroppedOutputBuffers.isMultiple(of: 25)
                    {
                        self.logger.error(
                            "Sanitizing suspicious decoded audio buffer (count=\(consecutiveDroppedOutputBuffers, privacy: .public), format=\(String(describing: pcmBuffer.format.commonFormat), privacy: .public), channels=\(pcmBuffer.format.channelCount, privacy: .public), frames=\(pcmBuffer.frameLength, privacy: .public))"
                        )
                    }
                    ShadowClientRealtimeAudioPCMBufferGuard.replaceWithSilence(pcmBuffer)
                } else {
                    consecutiveDroppedOutputBuffers = 0
                }

                if audioOutput.enqueue(pcmBuffer: pcmBuffer) {
                    logFirstDecodedBufferIfNeeded(pcmBuffer.frameLength, source)
                    return
                }
                registerOutputQueuePressureDrop(1, "drop-output-enqueue-failed")
            }

            while !Task.isCancelled {
                let nowUptime = ProcessInfo.processInfo.systemUptime
                let isDecodeCooldownActive = nowUptime < decodeCooldownUntilUptime
                let availableOutputSlots = audioOutput.availableEnqueueSlots
                let drainLimit = Self.audioReadyPacketDrainLimit(
                    isDecodeCooldownActive: isDecodeCooldownActive,
                    availableOutputSlots: availableOutputSlots,
                    maximumDrainBatch: 4
                ) ?? 0
                if drainLimit == 0 {
                    if isDecodeCooldownActive || Self.shouldHoldDecodeWhenReadyPacketsEmpty(
                        isDecodeCooldownActive: isDecodeCooldownActive,
                        availableOutputSlots: availableOutputSlots
                    ) {
                        try? await Task.sleep(for: audioDecodeCooldown)
                    }
                    continue
                }

                guard let batchResult = await packetQueue.nextBatch(maxCount: drainLimit) else {
                    return
                }
                let pendingPacketCountAfterFirstDequeue = max(
                    0,
                    batchResult.pendingPacketCountAfterDequeue + max(0, batchResult.packets.count - 1)
                )
                for (batchIndex, queuedPacket) in batchResult.packets.enumerated() {
                    if Task.isCancelled {
                        return
                    }
                    let packet = queuedPacket.packet
                    let pendingPacketCountAfterCurrentDequeue = max(
                        0,
                        pendingPacketCountAfterFirstDequeue - batchIndex
                    )
                    let pendingQueueDurationMs = Double(
                        pendingPacketCountAfterCurrentDequeue * max(1, packetDurationMs)
                    )
                    let shouldDropDueToPendingPressure = Self
                        .shouldRequeueReadyPacketsForPendingOutputPressure(
                            pendingOutputDurationMs: pendingQueueDurationMs,
                            realtimePendingDurationCapMs: realtimePendingDurationCapMs
                        )
                    if shouldDropDueToPendingPressure {
                        registerOutputQueuePressureDrop(1, "drop-shadow-lbq-pending-audio-duration")
                        maybeActivateDecodeCooldownAfterPressureBurst()
                        // Keep RTP continuity aligned with consumed queue order.
                        lastDecodedSequenceNumber = packet.sequenceNumber
                        continue
                    }
                    let availableOutputSlotsForPacket = audioOutput.availableEnqueueSlots
                    if Self.shouldRequeueReadyPacketsForUnavailableOutputSlots(
                        availableOutputSlots: availableOutputSlotsForPacket
                    ) {
                        registerOutputQueuePressureDrop(1, "drop-output-no-enqueue-slots")
                        maybeActivateDecodeCooldownAfterPressureBurst()
                        // Keep RTP continuity aligned with consumed queue order.
                        lastDecodedSequenceNumber = packet.sequenceNumber
                        continue
                    }

                    do {
                        let rawMissingPacketCount = Self.missingRTPPacketCount(
                            previousSequenceNumber: lastDecodedSequenceNumber,
                            currentSequenceNumber: packet.sequenceNumber
                        )
                        let missingPacketCount = Self.adjustMissingRTPPacketCountForObservedMoonlightFEC(
                            rawMissingPacketCount: rawMissingPacketCount,
                            observedMoonlightFECShardsSinceLastDecodedPacket: queuedPacket
                                .observedMoonlightFECShardsSincePreviousPrimary
                        )

                        let canAttemptMissingRecovery = Self
                            .shouldAttemptMissingPacketRecoveryOrConcealment(
                                missingPacketCount: missingPacketCount,
                                isFECIncompatible: await moonlightRSFECQueue.isFECIncompatible(),
                                remainingOutputSlots: max(0, availableOutputSlotsForPacket - 1),
                                decodeSheddingLowWatermarkSlots: queuePressureProfile
                                    .decodeSheddingLowWatermarkSlots,
                                deferredPacketCount: 0
                            )

                        var recoveredMissingPacketCount = 0
                        if canAttemptMissingRecovery,
                           let previousSequenceNumber = lastDecodedSequenceNumber,
                           missingPacketCount > 0
                        {
                            for missingOffset in 1 ... missingPacketCount {
                                let missingSequenceNumber = previousSequenceNumber &+ UInt16(missingOffset)
                                guard let recoveredPayload = await moonlightRSFECQueue.takeRecoveredPayload(
                                    sequenceNumber: missingSequenceNumber
                                ) else {
                                    continue
                                }

                                let recoveredDecodePayload: Data
                                if let payloadDecryptor {
                                    do {
                                        recoveredDecodePayload = try payloadDecryptor.decrypt(
                                            payload: recoveredPayload,
                                            sequenceNumber: missingSequenceNumber
                                        )
                                        consecutiveDecryptFailures = 0
                                    } catch {
                                        consecutiveDecryptFailures += 1
                                        if consecutiveDecryptFailures == 1 ||
                                            consecutiveDecryptFailures.isMultiple(of: 25)
                                        {
                                            self.logger.error(
                                                "Failed to decrypt RS-FEC recovered RTP audio payload (count=\(consecutiveDecryptFailures, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                                            )
                                        }
                                        continue
                                    }
                                } else {
                                    recoveredDecodePayload = recoveredPayload
                                }

                                if let recoveredPCMBuffer = try decoder.decode(
                                    payload: recoveredDecodePayload,
                                    decodeFEC: false
                                ) {
                                    enqueueDecodedBuffer(
                                        recoveredPCMBuffer,
                                        "rs-fec",
                                        false
                                    )
                                    recoveredMissingPacketCount += 1
                                }
                            }
                        }

                        if recoveredMissingPacketCount > 0 {
                            let previousRSFECRecoveryCount = rsFECRecoveryCount
                            rsFECRecoveryCount += recoveredMissingPacketCount
                            if rsFECRecoveryCount == recoveredMissingPacketCount ||
                                Self.didCounterCrossIntervalBoundary(
                                    previous: previousRSFECRecoveryCount,
                                    current: rsFECRecoveryCount,
                                    interval: 25
                                )
                            {
                                self.logger.notice(
                                    "Audio Moonlight RS-FEC recovered missing packets (count=\(rsFECRecoveryCount, privacy: .public))"
                                )
                            }
                        }

                        let pendingConcealmentPacketCount = max(
                            0,
                            missingPacketCount - recoveredMissingPacketCount
                        )
                        if canAttemptMissingRecovery, pendingConcealmentPacketCount > 0 {
                            for _ in 0 ..< pendingConcealmentPacketCount {
                                guard let silenceBuffer = Self.makeSilentPCMBuffer(
                                    format: decoder.outputFormat,
                                    frameCount: moonlightPLCSamplesPerChannel
                                ) else {
                                    registerOutputQueuePressureDrop(1, "alloc-loss-concealment-buffer")
                                    continue
                                }
                                let concealmentBuffer = (try? decoder.decodePacketLossConcealment(
                                    samplesPerChannel: moonlightPLCSamplesPerChannel
                                )) ?? silenceBuffer
                                enqueueDecodedBuffer(
                                    concealmentBuffer,
                                    "plc",
                                    false
                                )
                            }
                            let previousLossConcealmentEventCount = lossConcealmentEventCount
                            lossConcealmentEventCount += pendingConcealmentPacketCount
                            if lossConcealmentEventCount == pendingConcealmentPacketCount ||
                                Self.didCounterCrossIntervalBoundary(
                                    previous: previousLossConcealmentEventCount,
                                    current: lossConcealmentEventCount,
                                    interval: 25
                                )
                            {
                                self.logger.notice(
                                    "Audio packet loss concealment inserted buffers (count=\(lossConcealmentEventCount, privacy: .public), frameSamples=\(moonlightPLCSamplesPerChannel, privacy: .public))"
                                )
                            }
                        }

                        let decodePayload: Data
                        if let payloadDecryptor {
                            do {
                                decodePayload = try payloadDecryptor.decrypt(
                                    payload: packet.payload,
                                    sequenceNumber: packet.sequenceNumber
                                )
                                consecutiveDecryptFailures = 0
                            } catch {
                                consecutiveDecryptFailures += 1
                                if consecutiveDecryptFailures == 1 ||
                                    consecutiveDecryptFailures.isMultiple(of: 25)
                                {
                                    self.logger.error(
                                        "Failed to decrypt RTP audio payload (count=\(consecutiveDecryptFailures, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                                    )
                                }
                                // Keep RTP continuity aligned with consumed queue order.
                                lastDecodedSequenceNumber = packet.sequenceNumber
                                continue
                            }
                        } else {
                            decodePayload = packet.payload
                        }

                        if let pcmBuffer = try decoder.decode(
                            payload: decodePayload,
                            decodeFEC: false
                        ) {
                            enqueueDecodedBuffer(
                                pcmBuffer,
                                "primary",
                                false
                            )
                        }

                        consecutiveDecodeFailures = 0
                        lastDecodedSequenceNumber = packet.sequenceNumber
                    } catch {
                        consecutiveDecodeFailures += 1
                        if consecutiveDecodeFailures == 1 ||
                            consecutiveDecodeFailures.isMultiple(of: decodeFailureLogInterval)
                        {
                            self.logger.error(
                                "Audio decode failed (count=\(consecutiveDecodeFailures, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                            )
                        }
                        if consecutiveDecodeFailures >= decodeFailureAbortThreshold {
                            let message = "Audio decode repeatedly failed (\(consecutiveDecodeFailures))."
                            self.logger.error("\(message, privacy: .public)")
                            self.handleReceiveLoopTermination(
                                over: connection,
                                output: audioOutput,
                                state: .decoderFailed(message)
                            )
                            return
                        }
                        // Decode failures still consumed this RTP sequence.
                        lastDecodedSequenceNumber = packet.sequenceNumber
                    }
                }
            }
        }
    }

    private func startReceiveLoop(
        over connection: NWConnection,
        preferredPayloadType: Int,
        sampleRate _: Int,
        channels _: Int,
        packetDurationMs: Int,
        output audioOutput: ShadowClientRealtimeAudioEngineOutput,
        packetQueue: ShadowClientRealtimeAudioPacketQueue,
        moonlightRSFECQueue: ShadowClientRealtimeAudioMoonlightRSFECQueue
    ) {
        receiveTask = Task.detached(priority: .high) { [weak self] in
            guard let self else {
                return
            }

            var currentPayloadType = (96 ... 127).contains(preferredPayloadType) ?
                preferredPayloadType :
                ShadowClientRealtimeSessionDefaults.moonlightPrimaryAudioPayloadType
            var loggedPayloadNormalizationKeys = Set<String>()
            var loggedFECIncompatibility = false
            var loggedUnexpectedPayloadTypes = Set<Int>()
            var payloadTypeObservationCounts: [Int: Int] = [:]
            var observedMoonlightFECShardsSinceLastQueuedPrimary = 0
            var dropPacketsRemaining = Self.initialAudioResyncDropPacketCount(
                packetDurationMs: packetDurationMs
            )
            var datagramCount = 0
            var queueOverflowEventCount = 0
            let payloadTypeObservationThreshold = max(
                1,
                ShadowClientRealtimeSessionDefaults.audioPayloadTypeAdaptationObservationThreshold
            )

            while !Task.isCancelled {
                do {
                    guard let datagram = try await Self.receiveDatagram(over: connection),
                          !datagram.isEmpty
                    else {
                        continue
                    }
                    datagramCount += 1
                    if datagramCount == 1 {
                        logger.notice(
                            "First UDP audio datagram received: bytes=\(datagram.count, privacy: .public)"
                        )
                    }

                    guard let parsedPacket = Self.parseRTPPacket(datagram) else {
                        continue
                    }
                    let normalizedPayload = ShadowClientRealtimeAudioRTPPayloadNormalizer.normalize(
                        payloadType: parsedPacket.payloadType,
                        payload: parsedPacket.payload,
                        preferredPayloadType: currentPayloadType,
                        wrapperPayloadType: ShadowClientMoonlightProtocolPolicy.Audio
                            .fecWrapperPayloadType
                    )
                    if let normalizationKey = normalizedPayload.normalizationKey,
                       loggedPayloadNormalizationKeys.insert(normalizationKey).inserted,
                       let normalizationMessage = normalizedPayload.normalizationMessage
                    {
                        logger.notice("\(normalizationMessage, privacy: .public)")
                    }
                    let packet = RTPPacket(
                        sequenceNumber: parsedPacket.sequenceNumber,
                        timestamp: parsedPacket.timestamp,
                        ssrc: parsedPacket.ssrc,
                        payloadType: normalizedPayload.payloadType,
                        payload: normalizedPayload.payload
                    )
                    await moonlightRSFECQueue.ingest(
                        packetSequenceNumber: packet.sequenceNumber,
                        packetTimestamp: packet.timestamp,
                        packetSSRC: packet.ssrc,
                        payloadType: packet.payloadType,
                        payload: packet.payload,
                        expectedPrimaryPayloadType: currentPayloadType,
                        wrapperPayloadType: ShadowClientMoonlightProtocolPolicy.Audio
                            .fecWrapperPayloadType
                    )
                    let isFECIncompatible = await moonlightRSFECQueue.isFECIncompatible()
                    if isFECIncompatible, !loggedFECIncompatibility {
                        loggedFECIncompatibility = true
                        logger.notice(
                            "Audio Moonlight RS-FEC marked incompatible; switching to primary-payload passthrough mode"
                        )
                    }
                    if normalizedPayload.isMoonlightAudioFECPayload {
                        observedMoonlightFECShardsSinceLastQueuedPrimary += 1
                    }
                    if !Self.shouldProcessPayloadMismatch(for: normalizedPayload) {
                        continue
                    }

                    if packet.payloadType != currentPayloadType {
                        if let adaptedPayloadType = Self.payloadTypePreference(
                            observed: packet.payloadType,
                            current: currentPayloadType,
                            hasLockedPayloadType: false
                        ) {
                            let observations = (payloadTypeObservationCounts[adaptedPayloadType] ?? 0) + 1
                            payloadTypeObservationCounts[adaptedPayloadType] = observations
                            if observations == 1 || observations == payloadTypeObservationThreshold {
                                logger.notice(
                                    "Audio RTP payload mismatch observed candidate \(adaptedPayloadType, privacy: .public) (expected=\(currentPayloadType, privacy: .public), observations=\(observations, privacy: .public)/\(payloadTypeObservationThreshold, privacy: .public))"
                                )
                            }
                            guard observations >= payloadTypeObservationThreshold else {
                                continue
                            }
                            currentPayloadType = adaptedPayloadType
                            payloadTypeObservationCounts.removeAll(keepingCapacity: true)
                            loggedUnexpectedPayloadTypes.removeAll(keepingCapacity: true)
                            observedMoonlightFECShardsSinceLastQueuedPrimary = 0
                            jitterBuffer.reset(preferredPayloadType: currentPayloadType)
                            logger.notice(
                                "Audio RTP payload mismatch; adopting stream payload type \(currentPayloadType, privacy: .public)"
                            )
                        } else if loggedUnexpectedPayloadTypes.insert(packet.payloadType).inserted {
                            logger.notice(
                                "Audio RTP payload mismatch ignored (expected=\(currentPayloadType, privacy: .public), observed=\(packet.payloadType, privacy: .public))"
                            )
                        }
                        continue
                    }

                    let readyPackets = jitterBuffer.enqueue(
                        packet,
                        preferredPayloadType: currentPayloadType,
                        nowUptime: ProcessInfo.processInfo.systemUptime,
                        maximumReadyPackets: nil
                    )
                    let jitterOverflowDropCount = jitterBuffer.consumeOverflowDropCount()
                    if jitterOverflowDropCount > 0 {
                        logger.notice(
                            "Audio jitter queue dropped stale packets (count=\(jitterOverflowDropCount, privacy: .public))"
                        )
                    }
                    if dropPacketsRemaining > 0 {
                        dropPacketsRemaining -= 1
                        if dropPacketsRemaining == 0 {
                            logger.notice("Audio startup resync drop window completed")
                        }
                        continue
                    }
                    if readyPackets.isEmpty {
                        continue
                    }

                    for readyPacket in readyPackets {
                        let queuedPacket = QueuedPrimaryAudioPacket(
                            packet: readyPacket,
                            observedMoonlightFECShardsSincePreviousPrimary:
                            observedMoonlightFECShardsSinceLastQueuedPrimary
                        )
                        observedMoonlightFECShardsSinceLastQueuedPrimary = 0
                        let offerResult = await packetQueue.offer(queuedPacket)
                        if offerResult.flushedCount > 0 {
                            queueOverflowEventCount += 1
                            if queueOverflowEventCount == 1 || queueOverflowEventCount.isMultiple(of: 10) {
                                logger.error(
                                    "Audio packet queue overflow; flushed queued packets (events=\(queueOverflowEventCount, privacy: .public), dropped=\(offerResult.flushedCount, privacy: .public))"
                                )
                            }
                        }
                    }
                } catch {
                    if Task.isCancelled {
                        return
                    }
                    let message = "Audio RTP receive failed: \(error.localizedDescription)"
                    logger.error("\(message, privacy: .public)")
                    handleReceiveLoopTermination(
                        over: connection,
                        output: audioOutput,
                        state: .disconnected(message)
                    )
                    return
                }
            }
        }
    }

    private func handleReceiveLoopTermination(
        over connection: NWConnection,
        output audioOutput: ShadowClientRealtimeAudioEngineOutput,
        state finalState: ShadowClientRealtimeAudioOutputState
    ) {
        if output === audioOutput {
            output = nil
        }
        audioOutput.stop()

        guard self.connection === connection else {
            return
        }

        receiveTask = nil
        decodeTask?.cancel()
        decodeTask = nil
        pingTask?.cancel()
        pingTask = nil
        let packetQueueToShutdown = packetQueue
        packetQueue = nil
        if let packetQueueToShutdown {
            Task {
                _ = await packetQueueToShutdown.shutdown()
            }
        }
        connection.cancel()
        self.connection = nil
        decoder = nil
        payloadDecryptor = nil
        jitterBuffer.reset(preferredPayloadType: nil)
        updateState(finalState)
    }

    private func startPingLoop(
        over connection: NWConnection,
        pingPayload: Data?
    ) {
        pingTask = Task.detached {
            var sequence: UInt32 = 1
            while !Task.isCancelled {
                sequence &+= 1
                let pingPackets = ShadowClientSunshinePingPacketCodec.makePingPackets(
                    sequence: sequence,
                    negotiatedPayload: pingPayload
                )
                for pingPacket in pingPackets {
                    try? await Self.send(
                        bytes: pingPacket,
                        over: connection
                    )
                }
                try? await Task.sleep(
                    for: ShadowClientRealtimeSessionDefaults.pingInterval
                )
            }
        }
    }

    private func sendInitialPing(
        over connection: NWConnection,
        pingPayload: Data?
    ) async throws {
        let initialPackets = ShadowClientSunshinePingPacketCodec.makePingPackets(
            sequence: 1,
            negotiatedPayload: pingPayload
        )
        for packet in initialPackets {
            try await Self.send(bytes: packet, over: connection)
        }
    }

    private func makeUDPConnection(
        remoteHost: NWEndpoint.Host,
        remotePort: NWEndpoint.Port,
        localHost: NWEndpoint.Host?,
        preferredLocalPort: UInt16?
    ) async throws -> NWConnection {
        func makeParameters(localPort: UInt16?) -> NWParameters {
            let parameters = NWParameters.udp
            if let localHost {
                let endpointPort: NWEndpoint.Port
                if let localPort, let resolvedPort = NWEndpoint.Port(rawValue: localPort) {
                    endpointPort = resolvedPort
                } else {
                    endpointPort = .any
                }
                parameters.requiredLocalEndpoint = .hostPort(
                    host: localHost,
                    port: endpointPort
                )
            }
            return parameters
        }

        let primaryConnection = NWConnection(
            host: remoteHost,
            port: remotePort,
            using: makeParameters(localPort: preferredLocalPort)
        )
        do {
            try await waitForReady(
                primaryConnection,
                timeout: .seconds(2)
            )
            logLocalEndpoint(
                primaryConnection,
                messagePrefix: "Audio UDP socket ready"
            )
            return primaryConnection
        } catch {
            primaryConnection.cancel()
            guard preferredLocalPort != nil else {
                throw error
            }

            let fallbackConnection = NWConnection(
                host: remoteHost,
                port: remotePort,
                using: makeParameters(localPort: nil)
            )
            try await waitForReady(
                fallbackConnection,
                timeout: .seconds(2)
            )
            logLocalEndpoint(
                fallbackConnection,
                messagePrefix: "Audio UDP socket ready (ephemeral fallback)"
            )
            return fallbackConnection
        }
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
                    timeoutError: NSError(
                        domain: "ShadowClientRealtimeAudioSessionRuntime",
                        code: 1,
                        userInfo: [
                            NSLocalizedDescriptionKey: "Audio UDP connection timed out.",
                        ]
                    )
                )
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        gate.finish(.success(()))
                    case let .failed(error):
                        gate.finish(.failure(error))
                    case .cancelled:
                        gate.finish(.failure(CancellationError()))
                    default:
                        break
                    }
                }
                connection.start(queue: connectionQueue)
            }
        } onCancel: {
            gate.cancel()
        }
    }

    private func logLocalEndpoint(
        _ connection: NWConnection,
        messagePrefix: String
    ) {
        guard case let .hostPort(host, port) = connection.currentPath?.localEndpoint else {
            logger.notice("\(messagePrefix, privacy: .public)")
            return
        }
        logger.notice(
            "\(messagePrefix, privacy: .public) \(String(describing: host), privacy: .public):\(port.rawValue, privacy: .public)"
        )
    }

    private func updateState(_ nextState: ShadowClientRealtimeAudioOutputState) {
        guard state != nextState else {
            return
        }
        state = nextState
        guard let stateDidChange else {
            return
        }
        Task {
            await stateDidChange(nextState)
        }
    }

    private static func receiveDatagram(
        over connection: NWConnection
    ) async throws -> Data? {
        try await withCheckedThrowingContinuation { continuation in
            connection.receiveMessage { payload, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: payload)
            }
        }
    }

    private static func send(
        bytes: Data,
        over connection: NWConnection
    ) async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: bytes, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            })
        }
    }

    private static func parseRTPPacket(_ datagram: Data) -> RTPPacket? {
        guard datagram.count >= 12 else {
            return nil
        }

        let version = datagram[0] >> 6
        guard version == 2 else {
            return nil
        }

        let hasPadding = (datagram[0] & 0x20) != 0
        let hasExtension = (datagram[0] & 0x10) != 0
        let csrcCount = Int(datagram[0] & 0x0F)
        let payloadType = Int(
            datagram[1] & ShadowClientMoonlightProtocolPolicy.Audio.payloadTypeMask
        )
        let sequenceNumber = (UInt16(datagram[2]) << 8) | UInt16(datagram[3])
        let timestamp = (UInt32(datagram[4]) << 24) |
            (UInt32(datagram[5]) << 16) |
            (UInt32(datagram[6]) << 8) |
            UInt32(datagram[7])
        let ssrc = (UInt32(datagram[8]) << 24) |
            (UInt32(datagram[9]) << 16) |
            (UInt32(datagram[10]) << 8) |
            UInt32(datagram[11])

        var headerLength = 12 + (csrcCount * 4)
        guard datagram.count >= headerLength else {
            return nil
        }

        if hasExtension {
            guard datagram.count >= headerLength + 4 else {
                return nil
            }
            let extensionWordCount = (Int(datagram[headerLength + 2]) << 8) |
                Int(datagram[headerLength + 3])
            headerLength += 4 + (extensionWordCount * 4)
            guard datagram.count >= headerLength else {
                return nil
            }
        }

        var endIndex = datagram.count
        if hasPadding, let paddingCount = datagram.last {
            endIndex = max(headerLength, datagram.count - Int(paddingCount))
        }
        guard endIndex > headerLength else {
            return nil
        }

        return RTPPacket(
            sequenceNumber: sequenceNumber,
            timestamp: timestamp,
            ssrc: ssrc,
            payloadType: payloadType,
            payload: datagram[headerLength..<endIndex]
        )
    }

    private static func didCounterCrossIntervalBoundary(
        previous: Int,
        current: Int,
        interval: Int
    ) -> Bool {
        guard interval > 0 else {
            return false
        }
        let previousBoundary = previous / interval
        let currentBoundary = current / interval
        return currentBoundary > previousBoundary
    }

    internal static func initialAudioResyncDropPacketCount(packetDurationMs: Int) -> Int {
        ShadowClientMoonlightProtocolPolicy.Audio.initialResyncDropPacketCount(
            packetDurationMs: packetDurationMs
        )
    }

    private static func missingRTPPacketCount(
        previousSequenceNumber: UInt16?,
        currentSequenceNumber: UInt16
    ) -> Int {
        guard let previousSequenceNumber else {
            return 0
        }
        let sequenceDelta = Int(
            sequenceDistanceForward(
                from: previousSequenceNumber,
                to: currentSequenceNumber
            )
        )
        guard sequenceDelta > 1, sequenceDelta < 1024 else {
            return 0
        }
        return sequenceDelta - 1
    }

    internal static func adjustMissingRTPPacketCountForObservedMoonlightFEC(
        rawMissingPacketCount: Int,
        observedMoonlightFECShardsSinceLastDecodedPacket: Int
    ) -> Int {
        let normalizedMissingCount = max(0, rawMissingPacketCount)
        let normalizedObservedFECShardCount = max(0, observedMoonlightFECShardsSinceLastDecodedPacket)
        guard normalizedMissingCount > 0, normalizedObservedFECShardCount > 0 else {
            return normalizedMissingCount
        }
        // Moonlight/Sunshine often interleave PT127 FEC shards in RTP sequence space.
        // Exclude observed FEC-only gaps from primary audio loss accounting.
        let estimatedFECGapCount = min(normalizedMissingCount, normalizedObservedFECShardCount)
        return max(0, normalizedMissingCount - estimatedFECGapCount)
    }

    internal static func estimatedAudioSamplesPerPacket(
        sampleRate: Int,
        previousSequenceNumber: UInt16,
        currentSequenceNumber: UInt16,
        previousTimestamp: UInt32,
        currentTimestamp: UInt32,
        minimumPacketSamples: Int,
        maximumPacketSamples: Int
    ) -> Int? {
        let sequenceDelta = Int(
            sequenceDistanceForward(
                from: previousSequenceNumber,
                to: currentSequenceNumber
            )
        )
        guard sequenceDelta > 0, sequenceDelta < 64 else {
            return nil
        }
        let timestampDelta = Int(
            timestampDistanceForward(
                from: previousTimestamp,
                to: currentTimestamp
            )
        )
        guard timestampDelta > 0 else {
            return nil
        }
        let rawSamplesPerPacket = timestampDelta / sequenceDelta
        guard rawSamplesPerPacket > 0 else {
            return nil
        }
        let sampleStep = max(1, sampleRate / 200)
        guard rawSamplesPerPacket >= sampleStep else {
            return nil
        }
        let roundedSamples = ((rawSamplesPerPacket + (sampleStep / 2)) / sampleStep) * sampleStep
        let normalizedSamples = max(
            minimumPacketSamples,
            min(
                maximumPacketSamples,
                max(sampleStep, roundedSamples)
            )
        )
        return normalizedSamples
    }

    internal static func moonlightPLCSamplesPerChannel(
        sampleRate: Int,
        packetDurationMs: Int,
        minimumPacketSamples: Int,
        maximumPacketSamples: Int
    ) -> Int {
        ShadowClientMoonlightProtocolPolicy.Audio.plcSamplesPerChannel(
            sampleRate: sampleRate,
            packetDurationMs: packetDurationMs,
            minimumPacketSamples: minimumPacketSamples,
            maximumPacketSamples: maximumPacketSamples
        )
    }

    private static func sequenceDistanceForward(
        from: UInt16,
        to: UInt16
    ) -> UInt16 {
        to &- from
    }

    private static func timestampDistanceForward(
        from: UInt32,
        to: UInt32
    ) -> UInt32 {
        to &- from
    }

    private static func makeSilentPCMBuffer(
        format: AVAudioFormat,
        frameCount: Int
    ) -> AVAudioPCMBuffer? {
        guard frameCount > 0 else {
            return nil
        }
        let boundedFrameCount = AVAudioFrameCount(min(frameCount, Int(UInt16.max)))
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: boundedFrameCount
        ) else {
            return nil
        }
        buffer.frameLength = boundedFrameCount
        let byteCountFloat = Int(boundedFrameCount) * MemoryLayout<Float>.size
        let byteCountInt16 = Int(boundedFrameCount) * MemoryLayout<Int16>.size
        let channelCount = Int(format.channelCount)
        switch format.commonFormat {
        case .pcmFormatFloat32:
            if let channelData = buffer.floatChannelData {
                for channel in 0 ..< channelCount {
                    memset(channelData[channel], 0, byteCountFloat)
                }
            }
        case .pcmFormatInt16:
            if let channelData = buffer.int16ChannelData {
                for channel in 0 ..< channelCount {
                    memset(channelData[channel], 0, byteCountInt16)
                }
            }
        default:
            return nil
        }
        return buffer
    }

    internal static func extractRTPREDPrimaryPayload(
        from payload: Data
    ) -> (payloadType: Int, payload: Data)? {
        ShadowClientRealtimeAudioRTPPayloadNormalizer.extractRTPREDPrimaryPayload(from: payload)
    }

    internal static func payloadTypePreference(
        observed: Int,
        current: Int,
        hasLockedPayloadType: Bool
    ) -> Int? {
        guard observed != current else {
            return nil
        }
        guard !hasLockedPayloadType else {
            return nil
        }
        guard observed != ShadowClientMoonlightProtocolPolicy.Audio.fecWrapperPayloadType else {
            return nil
        }
        guard ShadowClientMoonlightProtocolPolicy.Audio.isValidDynamicPayloadType(observed) else {
            return nil
        }
        return observed
    }

    internal static func shouldProcessPayloadMismatch(
        for normalizedPayload: ShadowClientRealtimeAudioRTPPayloadNormalizer.Result
    ) -> Bool {
        guard !normalizedPayload.isMoonlightAudioFECPayload else {
            return false
        }
        guard normalizedPayload.payloadType != ShadowClientMoonlightProtocolPolicy.Audio
            .fecWrapperPayloadType
        else {
            // Treat wrapper/control-like payload types as non-adaptive traffic.
            // Valid RTP RED payloads are normalized to their primary payload type before this gate.
            return false
        }
        return true
    }

    internal static func audioReadyPacketDecodeWindow(
        readyPacketCount: Int,
        availableOutputSlots: Int,
        decodeSheddingLowWatermarkSlots: Int
    ) -> (
        decodeStartIndex: Int,
        decodeEndIndex: Int,
        deferredPacketCount: Int
    ) {
        guard readyPacketCount > 0 else {
            return (0, 0, 0)
        }
        guard availableOutputSlots > 0 else {
            return (0, 0, readyPacketCount)
        }

        _ = max(1, decodeSheddingLowWatermarkSlots)
        let decodeCount = min(readyPacketCount, availableOutputSlots)
        // Keep in-order continuity under pressure by decoding oldest ready packets
        // first and deferring newest overflow packets back into the jitter buffer.
        return (0, decodeCount, max(0, readyPacketCount - decodeCount))
    }

    internal static func audioReadyPacketDrainLimit(
        isDecodeCooldownActive: Bool,
        availableOutputSlots: Int,
        maximumDrainBatch: Int = 4
    ) -> Int? {
        if isDecodeCooldownActive {
            return 0
        }
        guard availableOutputSlots > 0 else {
            return 0
        }
        return min(max(1, maximumDrainBatch), availableOutputSlots)
    }

    internal static func shouldHoldDecodeWhenReadyPacketsEmpty(
        isDecodeCooldownActive: Bool,
        availableOutputSlots: Int
    ) -> Bool {
        guard !isDecodeCooldownActive else {
            return false
        }
        return availableOutputSlots <= 0
    }

    internal static func shouldRequeueReadyPacketsForPendingOutputPressure(
        pendingOutputDurationMs: Double,
        realtimePendingDurationCapMs: Double
    ) -> Bool {
        pendingOutputDurationMs > realtimePendingDurationCapMs
    }

    internal static func shouldRequeueReadyPacketsForUnavailableOutputSlots(
        availableOutputSlots: Int
    ) -> Bool {
        availableOutputSlots <= 0
    }

    internal static func shouldActivateAudioDecodeCooldown(
        now: TimeInterval,
        firstOutputQueuePressureDropUptime: TimeInterval,
        outputQueuePressureDropCount: Int,
        dropWindowSeconds: TimeInterval,
        burstThreshold: Int
    ) -> Bool {
        guard outputQueuePressureDropCount >= max(1, burstThreshold) else {
            return false
        }
        guard firstOutputQueuePressureDropUptime > 0 else {
            return false
        }
        return now - firstOutputQueuePressureDropUptime <= max(0, dropWindowSeconds)
    }

    internal static func dropPacketCountForWindow(
        windowSeconds: TimeInterval,
        packetDurationMs: Int
    ) -> Int {
        guard windowSeconds > 0 else {
            return 0
        }
        let normalizedPacketDurationMs = max(1, packetDurationMs)
        let windowMs = Int((windowSeconds * 1_000).rounded(.up))
        return max(1, windowMs / normalizedPacketDurationMs)
    }

    internal static func shouldAttemptMissingPacketRecoveryOrConcealment(
        missingPacketCount: Int,
        isFECIncompatible: Bool,
        remainingOutputSlots: Int,
        decodeSheddingLowWatermarkSlots: Int,
        deferredPacketCount: Int,
        minimumReservedOutputSlots: Int = 1
    ) -> Bool {
        guard !isFECIncompatible else {
            return false
        }
        guard missingPacketCount > 0 else {
            return false
        }
        guard deferredPacketCount == 0 else {
            return false
        }
        let lowWatermarkSlots = max(1, decodeSheddingLowWatermarkSlots)
        let reservedOutputSlots = max(0, minimumReservedOutputSlots)
        let requiredSlots = max(reservedOutputSlots, lowWatermarkSlots)
        return remainingOutputSlots > requiredSlots
    }

    internal static func maximumRecoveredAudioPacketsPerBurst(
        availableOutputSlots: Int,
        parityShardsPerFECBlock: Int = ShadowClientMoonlightProtocolPolicy.Audio.fecParityShardsPerBlock
    ) -> Int {
        guard parityShardsPerFECBlock == ShadowClientMoonlightProtocolPolicy.Audio
            .fecParityShardsPerBlock
        else {
            guard availableOutputSlots > 0 else {
                return 0
            }
            return min(availableOutputSlots, max(1, parityShardsPerFECBlock))
        }
        return ShadowClientMoonlightProtocolPolicy.Audio.recoveredPacketsPerBurstCap(
            availableOutputSlots: availableOutputSlots
        )
    }

    internal static func maximumConcealmentPacketsPerBurst(
        availableOutputSlots: Int,
        dataShardsPerFECBlock: Int = ShadowClientMoonlightProtocolPolicy.Audio.fecDataShardsPerBlock
    ) -> Int {
        guard dataShardsPerFECBlock == ShadowClientMoonlightProtocolPolicy.Audio
            .fecDataShardsPerBlock
        else {
            guard availableOutputSlots > 0 else {
                return 0
            }
            return min(availableOutputSlots, max(1, dataShardsPerFECBlock))
        }
        return ShadowClientMoonlightProtocolPolicy.Audio.concealmentPacketsPerBurstCap(
            availableOutputSlots: availableOutputSlots
        )
    }

    internal static func shouldSkipMissingAudioSequence(
        bufferedPacketCount: Int,
        targetDepth: Int,
        waitElapsed: TimeInterval?,
        requiredOutOfOrderWait: TimeInterval,
        isSevereOverflow: Bool
    ) -> Bool {
        guard bufferedPacketCount > 0 else {
            return false
        }
        if isSevereOverflow {
            return true
        }
        guard bufferedPacketCount >= max(1, targetDepth) else {
            return false
        }
        guard let waitElapsed else {
            return false
        }
        return waitElapsed >= max(0, requiredOutOfOrderWait)
    }

    private static func audioQueuePressureProfile(
        sampleRate: Int,
        channels: Int,
        packetDurationMs: Int = ShadowClientMoonlightProtocolPolicy.Audio.packetDurationMs(
            from: ShadowClientRTSPAnnounceProfile.aqosPacketDuration
        )
    ) -> AudioQueuePressureProfile {
        _ = sampleRate
        _ = channels
        let normalizedPacketDurationMs = max(1, packetDurationMs)
        let maximumQueuedBuffers = ShadowClientMoonlightProtocolPolicy.Audio.packetQueueBound
        let pressureSignalInterval = max(
            ShadowClientRealtimeSessionDefaults.audioOutputQueuePressureSignalInterval,
            ShadowClientMoonlightProtocolPolicy.Audio.packetQueueBound
        )
        let pressureTrimInterval = max(
            ShadowClientRealtimeSessionDefaults.audioOutputQueuePressureTrimInterval,
            ShadowClientMoonlightProtocolPolicy.Audio.packetQueueBound
        )
        let pressureTrimToRecentPackets = max(
            1,
            min(
                ShadowClientRealtimeSessionDefaults.audioOutputQueuePressureTrimToRecentPackets,
                max(1, maximumQueuedBuffers / 3)
            )
        )
        let decodeSheddingLowWatermarkSlots = 1
        _ = audioRealtimePendingDurationCapMs(
            packetDurationMs: normalizedPacketDurationMs,
            maximumQueuedBuffers: maximumQueuedBuffers
        )
        return .init(
            pressureSignalInterval: pressureSignalInterval,
            pressureTrimInterval: pressureTrimInterval,
            pressureTrimToRecentPackets: pressureTrimToRecentPackets,
            decodeSheddingLowWatermarkSlots: decodeSheddingLowWatermarkSlots,
            maximumQueuedBuffers: maximumQueuedBuffers
        )
    }

    internal static func audioRealtimePendingDurationCapMs(
        packetDurationMs _: Int,
        maximumQueuedBuffers _: Int
    ) -> Double {
        ShadowClientMoonlightProtocolPolicy.Audio.outputRealtimePendingDurationCapMs
    }

    internal static func recommendedMaximumQueuedAudioBuffers(
        sampleRate: Int,
        channels: Int,
        packetDurationMs: Int = ShadowClientMoonlightProtocolPolicy.Audio.packetDurationMs(
            from: ShadowClientRTSPAnnounceProfile.aqosPacketDuration
        )
    ) -> Int {
        audioQueuePressureProfile(
            sampleRate: sampleRate,
            channels: channels,
            packetDurationMs: packetDurationMs
        ).maximumQueuedBuffers
    }

    internal static func recommendedAudioPressureTrimToRecentPackets(
        sampleRate: Int,
        channels: Int,
        packetDurationMs: Int = ShadowClientMoonlightProtocolPolicy.Audio.packetDurationMs(
            from: ShadowClientRTSPAnnounceProfile.aqosPacketDuration
        )
    ) -> Int {
        audioQueuePressureProfile(
            sampleRate: sampleRate,
            channels: channels,
            packetDurationMs: packetDurationMs
        ).pressureTrimToRecentPackets
    }

    internal static func recommendedAudioRealtimePendingDurationCapMs(
        sampleRate: Int,
        channels: Int,
        packetDurationMs: Int = ShadowClientMoonlightProtocolPolicy.Audio.packetDurationMs(
            from: ShadowClientRTSPAnnounceProfile.aqosPacketDuration
        )
    ) -> Double {
        let profile = audioQueuePressureProfile(
            sampleRate: sampleRate,
            channels: channels,
            packetDurationMs: packetDurationMs
        )
        return audioRealtimePendingDurationCapMs(
            packetDurationMs: packetDurationMs,
            maximumQueuedBuffers: profile.maximumQueuedBuffers
        )
    }

    public static func preferredOpusChannelCountForNegotiation(
        surroundRequested: Bool,
        preferredSurroundChannelCount: Int = 6,
        sampleRate: Int = 48_000,
        maximumOutputChannels: Int? = nil
    ) -> Int {
        guard surroundRequested else {
            return 2
        }

        let resolvedMaximumOutputChannels = max(
            1,
            maximumOutputChannels ?? ShadowClientRealtimeAudioOutputCapability.maximumOutputChannels()
        )
        guard resolvedMaximumOutputChannels > 2 else {
            return 2
        }

        let requestedSurroundChannels = max(3, preferredSurroundChannelCount)
        let negotiatedSurroundChannels = min(
            requestedSurroundChannels,
            resolvedMaximumOutputChannels
        )
        guard negotiatedSurroundChannels > 2 else {
            return 2
        }
        let surroundTrack = ShadowClientRTSPAudioTrackDescriptor(
            codec: .opus,
            rtpPayloadType: 97,
            sampleRate: sampleRate,
            channelCount: negotiatedSurroundChannels,
            controlURL: nil,
            formatParameters: [:]
        )
        guard ShadowClientRealtimeAudioDecoderFactory.canDecode(track: surroundTrack) else {
            return 2
        }
        return negotiatedSurroundChannels
    }

    public static func canDecode(track: ShadowClientRTSPAudioTrackDescriptor) -> Bool {
        ShadowClientRealtimeAudioDecoderFactory.canDecode(track: track)
    }
}

private enum ShadowClientRealtimeAudioOutputCapability {
    static func maximumOutputChannels() -> Int {
        let engine = AVAudioEngine()
        let outputChannels = Int(engine.outputNode.inputFormat(forBus: 0).channelCount)
        if outputChannels > 0 {
            return outputChannels
        }

        let mixerChannels = Int(engine.mainMixerNode.outputFormat(forBus: 0).channelCount)
        if mixerChannels > 0 {
            return mixerChannels
        }
        return 2
    }
}

private struct ShadowClientRealtimeAudioRTPJitterBuffer: Sendable {
    private let targetDepth: Int
    private let maximumDepth: Int
    private let maximumDrainBatch: Int
    private let outOfOrderWait: TimeInterval
    private(set) var lockedPayloadType: Int?
    private var expectedSequence: UInt16?
    private var pendingGapSequence: UInt16?
    private var pendingGapStartUptime: TimeInterval?
    private var pendingOverflowDropCount = 0
    private var packetsBySequence: [UInt16: ShadowClientRealtimeAudioSessionRuntime.RTPPacket] = [:]

    init(
        targetDepth: Int,
        maximumDepth: Int,
        maximumDrainBatch: Int = 8,
        outOfOrderWait: TimeInterval = ShadowClientRealtimeSessionDefaults.audioJitterBufferOutOfOrderWaitSeconds
    ) {
        self.targetDepth = max(2, targetDepth)
        self.maximumDepth = max(self.targetDepth, maximumDepth)
        self.maximumDrainBatch = max(1, maximumDrainBatch)
        self.outOfOrderWait = max(0, outOfOrderWait)
    }

    mutating func reset(preferredPayloadType: Int?) {
        lockedPayloadType = preferredPayloadType
        expectedSequence = nil
        pendingGapSequence = nil
        pendingGapStartUptime = nil
        pendingOverflowDropCount = 0
        packetsBySequence.removeAll(keepingCapacity: false)
    }

    mutating func enqueue(
        _ packet: ShadowClientRealtimeAudioSessionRuntime.RTPPacket,
        preferredPayloadType: Int,
        nowUptime: TimeInterval,
        maximumReadyPackets: Int? = nil
    ) -> [ShadowClientRealtimeAudioSessionRuntime.RTPPacket] {
        if lockedPayloadType == nil {
            lockedPayloadType = preferredPayloadType
        }
        guard let lockedPayloadType, packet.payloadType == lockedPayloadType else {
            return []
        }

        packetsBySequence[packet.sequenceNumber] = packet
        if expectedSequence == nil {
            expectedSequence = packet.sequenceNumber
        }

        let readyPacketLimit = min(
            maximumDrainBatch,
            max(0, maximumReadyPackets ?? maximumDrainBatch)
        )
        var readyPackets: [ShadowClientRealtimeAudioSessionRuntime.RTPPacket] = []
        var skippedGapInCurrentDrain = false
        while readyPackets.count < readyPacketLimit, let expected = expectedSequence {
            if let nextPacket = packetsBySequence.removeValue(forKey: expected) {
                readyPackets.append(nextPacket)
                clearPendingGapWaitIfTracking(sequence: expected)
                expectedSequence = expected &+ 1
                continue
            }

            let severeOverflow = packetsBySequence.count >= maximumDepth
            let waitElapsed = pendingGapWaitElapsed(
                expectedSequence: expected,
                nowUptime: nowUptime
            )
            let shouldSkipMissingSequence =
                ShadowClientRealtimeAudioSessionRuntime.shouldSkipMissingAudioSequence(
                    bufferedPacketCount: packetsBySequence.count,
                    targetDepth: targetDepth,
                    waitElapsed: waitElapsed,
                    requiredOutOfOrderWait: outOfOrderWait,
                    isSevereOverflow: severeOverflow
                )
            guard shouldSkipMissingSequence,
                  nextAvailableSequence(after: expected) != nil
            else {
                markPendingGapWait(expectedSequence: expected, nowUptime: nowUptime)
                break
            }

            if skippedGapInCurrentDrain {
                markPendingGapWait(expectedSequence: expected, nowUptime: nowUptime)
                break
            }
            skippedGapInCurrentDrain = true
            clearPendingGapWaitState()
            expectedSequence = expected &+ 1
        }

        if packetsBySequence.count > maximumDepth {
            let overflowCount = packetsBySequence.count - maximumDepth
            removeOldestBufferedPackets(count: overflowCount)
            pendingOverflowDropCount += overflowCount
        }

        return readyPackets
    }

    mutating func trimToMostRecent(maxBufferedPackets: Int) -> Int {
        let normalizedLimit = max(1, maxBufferedPackets)
        guard packetsBySequence.count > normalizedLimit else {
            return 0
        }

        let overflowCount = packetsBySequence.count - normalizedLimit
        removeOldestBufferedPackets(count: overflowCount)
        return overflowCount
    }

    mutating func flush() -> Int {
        let droppedCount = packetsBySequence.count
        packetsBySequence.removeAll(keepingCapacity: true)
        expectedSequence = nil
        clearPendingGapWaitState()
        return droppedCount
    }

    mutating func reinsertReadyPacketsAtHead(
        _ packets: [ShadowClientRealtimeAudioSessionRuntime.RTPPacket]
    ) {
        guard !packets.isEmpty else {
            return
        }
        for packet in packets {
            packetsBySequence[packet.sequenceNumber] = packet
        }
        if let firstSequence = packets.first?.sequenceNumber {
            expectedSequence = firstSequence
            clearPendingGapWaitState()
        }
        if packetsBySequence.count > maximumDepth {
            let overflowCount = packetsBySequence.count - maximumDepth
            removeOldestBufferedPackets(count: overflowCount)
            pendingOverflowDropCount += overflowCount
        }
    }

    mutating func consumeOverflowDropCount() -> Int {
        let count = pendingOverflowDropCount
        pendingOverflowDropCount = 0
        return count
    }

    private mutating func removeOldestBufferedPackets(count: Int) {
        guard count > 0, !packetsBySequence.isEmpty else {
            return
        }

        let orderedSequences = orderedBufferedSequences()
        for sequence in orderedSequences.prefix(count) {
            packetsBySequence.removeValue(forKey: sequence)
        }

        guard !packetsBySequence.isEmpty else {
            expectedSequence = nil
            clearPendingGapWaitState()
            return
        }
        if let expected = expectedSequence,
           packetsBySequence[expected] != nil
        {
            synchronizePendingGapWaitState()
            return
        }
        if let expected = expectedSequence,
           let nextSequence = nextAvailableSequence(after: expected)
        {
            expectedSequence = nextSequence
            synchronizePendingGapWaitState()
            return
        }
        expectedSequence = packetsBySequence.keys.min()
        synchronizePendingGapWaitState()
    }

    private func orderedBufferedSequences() -> [UInt16] {
        guard let expected = expectedSequence else {
            return packetsBySequence.keys.sorted()
        }
        return packetsBySequence.keys.sorted { lhs, rhs in
            let lhsDistance = Self.sequenceDistanceForward(from: expected, to: lhs)
            let rhsDistance = Self.sequenceDistanceForward(from: expected, to: rhs)
            if lhsDistance == rhsDistance {
                return lhs < rhs
            }
            return lhsDistance < rhsDistance
        }
    }

    private func nextAvailableSequence(after expected: UInt16) -> UInt16? {
        guard !packetsBySequence.isEmpty else {
            return nil
        }
        return packetsBySequence.keys.min { lhs, rhs in
            let lhsDistance = Self.sequenceDistanceForward(from: expected, to: lhs)
            let rhsDistance = Self.sequenceDistanceForward(from: expected, to: rhs)
            if lhsDistance == rhsDistance {
                return lhs < rhs
            }
            return lhsDistance < rhsDistance
        }
    }

    private static func sequenceDistanceForward(
        from: UInt16,
        to: UInt16
    ) -> UInt16 {
        to &- from
    }

    private mutating func markPendingGapWait(
        expectedSequence: UInt16,
        nowUptime: TimeInterval
    ) {
        if pendingGapSequence != expectedSequence {
            pendingGapSequence = expectedSequence
            pendingGapStartUptime = nowUptime
        } else if pendingGapStartUptime == nil {
            pendingGapStartUptime = nowUptime
        }
    }

    private mutating func clearPendingGapWaitIfTracking(sequence: UInt16) {
        guard pendingGapSequence == sequence else {
            return
        }
        clearPendingGapWaitState()
    }

    private mutating func clearPendingGapWaitState() {
        pendingGapSequence = nil
        pendingGapStartUptime = nil
    }

    private mutating func synchronizePendingGapWaitState() {
        guard let expectedSequence, pendingGapSequence == expectedSequence else {
            clearPendingGapWaitState()
            return
        }
        if pendingGapStartUptime == nil {
            pendingGapStartUptime = ProcessInfo.processInfo.systemUptime
        }
    }

    private func pendingGapWaitElapsed(
        expectedSequence: UInt16,
        nowUptime: TimeInterval
    ) -> TimeInterval? {
        guard pendingGapSequence == expectedSequence,
              let pendingGapStartUptime
        else {
            return nil
        }
        return max(0, nowUptime - pendingGapStartUptime)
    }
}

private actor ShadowClientRealtimeAudioPacketQueue {
    struct OfferResult: Sendable {
        let flushedCount: Int
    }

    struct NextResult: Sendable {
        let packet: ShadowClientRealtimeAudioSessionRuntime.QueuedPrimaryAudioPacket
        let pendingPacketCountAfterDequeue: Int
    }

    struct BatchResult: Sendable {
        let packets: [ShadowClientRealtimeAudioSessionRuntime.QueuedPrimaryAudioPacket]
        let pendingPacketCountAfterDequeue: Int
    }

    private let capacity: Int
    private var packets: [ShadowClientRealtimeAudioSessionRuntime.QueuedPrimaryAudioPacket] = []
    private var packetReadIndex = 0
    private var waiters: [CheckedContinuation<ShadowClientRealtimeAudioSessionRuntime.QueuedPrimaryAudioPacket?, Never>] =
        []
    private var isShutdown = false

    init(capacity: Int) {
        self.capacity = max(1, capacity)
        packets.reserveCapacity(max(1, capacity))
    }

    func offer(
        _ packet: ShadowClientRealtimeAudioSessionRuntime.QueuedPrimaryAudioPacket
    ) -> OfferResult {
        guard !isShutdown else {
            return .init(flushedCount: 0)
        }

        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: packet)
            return .init(flushedCount: 0)
        }

        var flushedCount = 0
        if queuedPacketCount >= capacity {
            flushedCount = queuedPacketCount
            packets.removeAll(keepingCapacity: true)
            packetReadIndex = 0
        }
        packets.append(packet)
        return .init(flushedCount: flushedCount)
    }

    func next() async -> NextResult? {
        if let packet = popQueuedPacket() {
            return .init(
                packet: packet,
                pendingPacketCountAfterDequeue: queuedPacketCount
            )
        }
        if isShutdown {
            return nil
        }
        let packet = await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
        guard let packet else {
            return nil
        }
        return .init(
            packet: packet,
            pendingPacketCountAfterDequeue: queuedPacketCount
        )
    }

    func nextBatch(maxCount: Int) async -> BatchResult? {
        let normalizedMaxCount = max(1, maxCount)
        var dequeuedPackets: [ShadowClientRealtimeAudioSessionRuntime.QueuedPrimaryAudioPacket] = []
        dequeuedPackets.reserveCapacity(normalizedMaxCount)

        while dequeuedPackets.count < normalizedMaxCount,
              let packet = popQueuedPacket() {
            dequeuedPackets.append(packet)
        }

        if dequeuedPackets.isEmpty {
            if isShutdown {
                return nil
            }
            let packet = await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
            guard let packet else {
                return nil
            }
            dequeuedPackets.append(packet)
        }

        while dequeuedPackets.count < normalizedMaxCount,
              let packet = popQueuedPacket() {
            dequeuedPackets.append(packet)
        }

        return .init(
            packets: dequeuedPackets,
            pendingPacketCountAfterDequeue: queuedPacketCount
        )
    }

    func flush() -> Int {
        let droppedCount = queuedPacketCount
        packets.removeAll(keepingCapacity: true)
        packetReadIndex = 0
        return droppedCount
    }

    func pendingDurationMs(packetDurationMs: Int) -> Int {
        let normalizedPacketDurationMs = max(1, packetDurationMs)
        return queuedPacketCount * normalizedPacketDurationMs
    }

    func shutdown() -> Int {
        guard !isShutdown else {
            return 0
        }
        isShutdown = true
        let droppedCount = queuedPacketCount
        packets.removeAll(keepingCapacity: true)
        packetReadIndex = 0
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: nil)
        }
        return droppedCount
    }

    private var queuedPacketCount: Int {
        max(0, packets.count - packetReadIndex)
    }

    private func popQueuedPacket() -> ShadowClientRealtimeAudioSessionRuntime.QueuedPrimaryAudioPacket? {
        guard packetReadIndex < packets.count else {
            return nil
        }
        let packet = packets[packetReadIndex]
        packetReadIndex += 1
        compactStorageIfNeeded()
        return packet
    }

    private func compactStorageIfNeeded() {
        let consumedCount = packetReadIndex
        guard consumedCount > 0 else {
            return
        }
        if consumedCount >= packets.count {
            packets.removeAll(keepingCapacity: true)
            packetReadIndex = 0
            return
        }
        guard consumedCount >= 64, consumedCount * 2 >= packets.count else {
            return
        }
        packets.removeFirst(consumedCount)
        packetReadIndex = 0
    }
}

private protocol ShadowClientRealtimeAudioPacketDecoding {
    var codec: ShadowClientAudioCodec { get }
    var sampleRate: Int { get }
    var channels: Int { get }
    var outputFormat: AVAudioFormat { get }
    var requiresPlaybackSafetyGuard: Bool { get }
    func decode(payload: Data) throws -> AVAudioPCMBuffer?
    func decode(payload: Data, decodeFEC: Bool) throws -> AVAudioPCMBuffer?
    func decodePacketLossConcealment(samplesPerChannel: Int) throws -> AVAudioPCMBuffer?
}

private extension ShadowClientRealtimeAudioPacketDecoding {
    var requiresPlaybackSafetyGuard: Bool { true }

    func decode(payload: Data, decodeFEC _: Bool) throws -> AVAudioPCMBuffer? {
        try decode(payload: payload)
    }

    func decodePacketLossConcealment(samplesPerChannel _: Int) throws -> AVAudioPCMBuffer? {
        nil
    }
}

private enum ShadowClientRealtimeAudioDecoderFactory {
    static func canDecode(track: ShadowClientRTSPAudioTrackDescriptor) -> Bool {
        do {
            _ = try make(for: track)
            return true
        } catch {
            return false
        }
    }

    static func make(
        for track: ShadowClientRTSPAudioTrackDescriptor
    ) throws -> any ShadowClientRealtimeAudioPacketDecoding {
        let customDecoderAttempt = makeCustomDecoderAttempt(for: track)
        switch track.codec {
        case .opus:
            if let customDecoder = customDecoderAttempt.decoder {
                return ShadowClientRealtimeCustomDecoderAdapter(base: customDecoder)
            }
            if let customDecoderError = customDecoderAttempt.error {
                throw NSError(
                    domain: "ShadowClientRealtimeAudioDecoderFactory",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "External Opus decoder bootstrap failed (\(customDecoderError.localizedDescription)).",
                    ]
                )
            }
            throw NSError(
                domain: "ShadowClientRealtimeAudioDecoderFactory",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "External Opus decoder is required but unavailable.",
                ]
            )
        case .l16:
            if let customDecoder = customDecoderAttempt.decoder {
                return ShadowClientRealtimeCustomDecoderAdapter(base: customDecoder)
            }
            return ShadowClientRealtimeL16AudioDecoder(
                sampleRate: track.sampleRate,
                channels: track.channelCount
            )
        case .pcmu:
            if let customDecoder = customDecoderAttempt.decoder {
                return ShadowClientRealtimeCustomDecoderAdapter(base: customDecoder)
            }
            return ShadowClientRealtimeG711AudioDecoder(
                sampleRate: track.sampleRate,
                channels: track.channelCount,
                variant: .uLaw
            )
        case .pcma:
            if let customDecoder = customDecoderAttempt.decoder {
                return ShadowClientRealtimeCustomDecoderAdapter(base: customDecoder)
            }
            return ShadowClientRealtimeG711AudioDecoder(
                sampleRate: track.sampleRate,
                channels: track.channelCount,
                variant: .aLaw
            )
        case let .unknown(name):
            throw NSError(
                domain: "ShadowClientRealtimeAudioDecoderFactory",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Unsupported audio codec: \(name)",
                ]
            )
        }
    }

    private static func makeCustomDecoderAttempt(
        for track: ShadowClientRTSPAudioTrackDescriptor
    ) -> (decoder: (any ShadowClientRealtimeCustomAudioDecoder)?, error: Error?) {
        do {
            let decoder = try ShadowClientRealtimeCustomAudioDecoderRegistry.makeDecoder(
                for: track
            )
            return (decoder, nil)
        } catch {
            return (nil, error)
        }
    }

    static func debugName(
        for decoder: any ShadowClientRealtimeAudioPacketDecoding
    ) -> String {
        if let customAdapter = decoder as? ShadowClientRealtimeCustomDecoderAdapter {
            return String(describing: type(of: customAdapter.base))
        }
        return String(describing: type(of: decoder))
    }
}

private final class ShadowClientRealtimeCustomDecoderAdapter: ShadowClientRealtimeAudioPacketDecoding {
    let base: any ShadowClientRealtimeCustomAudioDecoder

    init(base: any ShadowClientRealtimeCustomAudioDecoder) {
        self.base = base
    }

    var codec: ShadowClientAudioCodec {
        base.codec
    }

    var sampleRate: Int {
        base.sampleRate
    }

    var channels: Int {
        base.channels
    }

    var outputFormat: AVAudioFormat {
        base.outputFormat
    }

    var requiresPlaybackSafetyGuard: Bool {
        base.requiresPlaybackSafetyGuard
    }

    func decode(payload: Data) throws -> AVAudioPCMBuffer? {
        try base.decode(payload: payload)
    }

    func decode(payload: Data, decodeFEC: Bool) throws -> AVAudioPCMBuffer? {
        try base.decode(payload: payload, decodeFEC: decodeFEC)
    }

    func decodePacketLossConcealment(samplesPerChannel: Int) throws -> AVAudioPCMBuffer? {
        try base.decodePacketLossConcealment(samplesPerChannel: samplesPerChannel)
    }
}

private enum ShadowClientRealtimeAudioFormatFactory {
    static func pcmFloatOutputFormat(
        sampleRate: Int,
        channels: Int
    ) -> AVAudioFormat? {
        if channels <= 2 {
            return AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: Double(sampleRate),
                channels: AVAudioChannelCount(channels),
                interleaved: false
            )
        }

        guard let channelLayoutData = channelLayoutData(for: channels) else {
            return nil
        }
        return AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true,
            AVChannelLayoutKey: channelLayoutData,
        ])
    }

    private static func channelLayoutData(for channels: Int) -> Data? {
        guard let channelLayout = AVAudioChannelLayout(
            layoutTag: channelLayoutTag(for: channels)
        ) else {
            return nil
        }
        return Data(
            bytes: channelLayout.layout,
            count: MemoryLayout<AudioChannelLayout>.size
        )
    }

    private static func channelLayoutTag(
        for channels: Int
    ) -> AudioChannelLayoutTag {
        switch channels {
        case 1:
            return kAudioChannelLayoutTag_Mono
        case 2:
            return kAudioChannelLayoutTag_Stereo
        case 6:
            return kAudioChannelLayoutTag_MPEG_5_1_D
        case 8:
            return kAudioChannelLayoutTag_MPEG_7_1_C
        default:
            return kAudioChannelLayoutTag_DiscreteInOrder | AudioChannelLayoutTag(channels)
        }
    }
}

private final class ShadowClientRealtimeL16AudioDecoder: ShadowClientRealtimeAudioPacketDecoding {
    let codec: ShadowClientAudioCodec = .l16
    let sampleRate: Int
    let channels: Int
    let outputFormat: AVAudioFormat

    init(sampleRate: Int, channels: Int) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: false
        )!
    }

    func decode(payload: Data) throws -> AVAudioPCMBuffer? {
        guard !payload.isEmpty else {
            return nil
        }
        let bytesPerFrame = channels * 2
        guard bytesPerFrame > 0 else {
            return nil
        }

        let frameCount = payload.count / bytesPerFrame
        guard frameCount > 0 else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ), let channelData = buffer.floatChannelData
        else {
            return nil
        }

        payload.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            for frame in 0..<frameCount {
                for channel in 0..<channels {
                    let index = (frame * channels + channel) * 2
                    let sample = Int16(
                        bitPattern: (UInt16(base[index]) << 8) | UInt16(base[index + 1])
                    )
                    channelData[channel][frame] = Float(sample) / Float(Int16.max)
                }
            }
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }
}

private final class ShadowClientRealtimeG711AudioDecoder: ShadowClientRealtimeAudioPacketDecoding {
    enum Variant {
        case uLaw
        case aLaw
    }

    let codec: ShadowClientAudioCodec
    let sampleRate: Int
    let channels: Int
    let outputFormat: AVAudioFormat
    private let variant: Variant

    init(sampleRate: Int, channels: Int, variant: Variant) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.variant = variant
        switch variant {
        case .uLaw:
            codec = .pcmu
        case .aLaw:
            codec = .pcma
        }
        self.outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: false
        )!
    }

    func decode(payload: Data) throws -> AVAudioPCMBuffer? {
        guard !payload.isEmpty else {
            return nil
        }
        guard channels > 0 else {
            return nil
        }

        let frameCount = payload.count / channels
        guard frameCount > 0 else {
            return nil
        }

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(frameCount)
        ), let channelData = buffer.floatChannelData
        else {
            return nil
        }

        payload.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            for frame in 0..<frameCount {
                for channel in 0..<channels {
                    let index = frame * channels + channel
                    let sample: Int16
                    switch variant {
                    case .uLaw:
                        sample = Self.decodeMuLaw(base[index])
                    case .aLaw:
                        sample = Self.decodeALaw(base[index])
                    }
                    channelData[channel][frame] = Float(sample) / Float(Int16.max)
                }
            }
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)
        return buffer
    }

    private static func decodeMuLaw(_ value: UInt8) -> Int16 {
        let inverted = ~value
        let sign = (inverted & 0x80) == 0 ? 1 : -1
        let exponent = (Int(inverted) >> 4) & 0x07
        let mantissa = Int(inverted & 0x0F)
        let magnitude = ((mantissa << 3) + 0x84) << exponent
        return Int16(sign * (magnitude - 0x84))
    }

    private static func decodeALaw(_ value: UInt8) -> Int16 {
        var decoded = Int(value ^ 0x55)
        let sign = (decoded & 0x80) == 0 ? 1 : -1
        decoded &= 0x7F

        let exponent = (decoded >> 4) & 0x07
        let mantissa = decoded & 0x0F
        var magnitude: Int
        if exponent == 0 {
            magnitude = (mantissa << 4) + 8
        } else {
            magnitude = ((mantissa << 4) + 0x108) << (exponent - 1)
        }

        return Int16(sign * magnitude)
    }
}

private final class ShadowClientRealtimeAudioEngineOutput {
    private static let minimumQueuedBufferCount = 4

    private let engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private let engineQueue = DispatchQueue(
        label: "com.skyline23.shadow-client.audio-engine-output",
        qos: .userInitiated
    )
    private let format: AVAudioFormat
    private let maximumQueuedBufferCount: Int
    private let nominalFramesPerBuffer: Double
    private let maximumQueuedFrameEstimate: Double
    private let queuedBufferLock = NSLock()
    private var queuedBufferCount = 0
    private var queuedFrameEstimate: Double = 0
    private var lastQueueEstimateUptime = ProcessInfo.processInfo.systemUptime
    private var isStarted = false
    private var isTerminated = false
    private var isGraphConfigured = false

    init(
        format: AVAudioFormat,
        maximumQueuedBufferCount: Int = minimumQueuedBufferCount,
        nominalFramesPerBuffer: AVAudioFrameCount,
        maximumPendingDurationMs: Double
    ) throws {
        self.format = format
        self.maximumQueuedBufferCount = max(
            Self.minimumQueuedBufferCount,
            maximumQueuedBufferCount
        )
        self.nominalFramesPerBuffer = max(1, Double(nominalFramesPerBuffer))
        let boundedMaximumPendingDurationMs = max(1, maximumPendingDurationMs)
        let maximumPendingFramesFromDuration = max(
            self.nominalFramesPerBuffer,
            (format.sampleRate * boundedMaximumPendingDurationMs / 1_000.0).rounded(.up)
        )
        let maximumPendingFramesFromCount = self.nominalFramesPerBuffer *
            Double(self.maximumQueuedBufferCount)
        self.maximumQueuedFrameEstimate = min(
            maximumPendingFramesFromCount,
            max(self.nominalFramesPerBuffer, maximumPendingFramesFromDuration)
        )
        var initializationState = 0
        engineQueue.sync {
            guard configureGraphLocked() else {
                initializationState = 1
                return
            }
            guard ensureEngineRunningLocked() else {
                initializationState = 2
                return
            }
            guard replacePlayerNodeLocked() else {
                initializationState = 1
                return
            }
            guard ensureEngineRunningLocked() else {
                initializationState = 2
                return
            }
            guard startPlayerLocked() else {
                initializationState = 3
                return
            }
        }
        if initializationState == 1 {
            throw NSError(
                domain: "ShadowClientRealtimeAudioEngineOutput",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Audio player node could not be attached to engine."]
            )
        }
        if initializationState == 2 {
            throw NSError(
                domain: "ShadowClientRealtimeAudioEngineOutput",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Audio engine could not start."]
            )
        }
        if initializationState == 3 {
            throw NSError(
                domain: "ShadowClientRealtimeAudioEngineOutput",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Audio player node is not attached to engine."]
            )
        }
    }

    func enqueue(pcmBuffer: AVAudioPCMBuffer) -> Bool {
        let incomingFrameCount = max(1, Double(pcmBuffer.frameLength))
        let nowUptime = ProcessInfo.processInfo.systemUptime
        queuedBufferLock.lock()
        refreshQueuedFrameEstimateLocked(nowUptime: nowUptime)
        guard queuedFrameEstimate + incomingFrameCount <= maximumQueuedFrameEstimate else {
            queuedBufferLock.unlock()
            return false
        }
        queuedBufferCount += 1
        queuedFrameEstimate += incomingFrameCount
        queuedBufferLock.unlock()

        return engineQueue.sync {
            guard !isTerminated else {
                didConsumeQueuedBuffer()
                return false
            }

            guard ensurePlaybackReadyLocked() else {
                didConsumeQueuedBuffer()
                return false
            }

            player.scheduleBuffer(
                pcmBuffer,
                completionCallbackType: .dataConsumed
            ) { [weak self] _ in
                self?.didConsumeQueuedBuffer()
            }
            return true
        }
    }

    var hasEnqueueCapacity: Bool {
        queuedBufferLock.lock()
        refreshQueuedFrameEstimateLocked(nowUptime: ProcessInfo.processInfo.systemUptime)
        let hasCapacity = queuedFrameEstimate < maximumQueuedFrameEstimate
        queuedBufferLock.unlock()
        return hasCapacity
    }

    var pendingDurationMs: Double {
        queuedBufferLock.lock()
        refreshQueuedFrameEstimateLocked(nowUptime: ProcessInfo.processInfo.systemUptime)
        let pendingFrames = queuedFrameEstimate
        queuedBufferLock.unlock()
        guard format.sampleRate > 0 else {
            return 0
        }
        return (pendingFrames / format.sampleRate) * 1_000.0
    }

    var availableEnqueueSlots: Int {
        queuedBufferLock.lock()
        refreshQueuedFrameEstimateLocked(nowUptime: ProcessInfo.processInfo.systemUptime)
        let remainingFrames = max(0, maximumQueuedFrameEstimate - queuedFrameEstimate)
        let available = max(
            0,
            min(
                maximumQueuedBufferCount,
                Int((remainingFrames / nominalFramesPerBuffer).rounded(.down))
            )
        )
        queuedBufferLock.unlock()
        return available
    }

    func stop() {
        engineQueue.sync {
            if isTerminated {
                return
            }
            isTerminated = true
            let currentPlayer = player
            currentPlayer.stop()
            if currentPlayer.engine === engine {
                engine.disconnectNodeOutput(currentPlayer)
                engine.detach(currentPlayer)
            }
            engine.stop()
            engine.reset()
            isGraphConfigured = false
            isStarted = false
        }

        queuedBufferLock.lock()
        queuedBufferCount = 0
        queuedFrameEstimate = 0
        lastQueueEstimateUptime = ProcessInfo.processInfo.systemUptime
        queuedBufferLock.unlock()
    }

    func recoverPlaybackUnderPressure() -> Bool {
        engineQueue.sync {
            guard !isTerminated else {
                return false
            }
            guard rebuildGraphAndStartLocked() else {
                return false
            }
            queuedBufferLock.lock()
            queuedBufferCount = 0
            queuedFrameEstimate = 0
            lastQueueEstimateUptime = ProcessInfo.processInfo.systemUptime
            queuedBufferLock.unlock()
            return true
        }
    }

    var debugFormatDescription: String {
        let interleaving = format.isInterleaved ? "interleaved" : "planar"
        return "\(String(describing: format.commonFormat))/\(format.channelCount)ch/\(Int(format.sampleRate))Hz/\(interleaving)"
    }

    private func didConsumeQueuedBuffer() {
        queuedBufferLock.lock()
        refreshQueuedFrameEstimateLocked(nowUptime: ProcessInfo.processInfo.systemUptime)
        queuedBufferCount = max(0, queuedBufferCount - 1)
        queuedBufferLock.unlock()
    }

    private func refreshQueuedFrameEstimateLocked(nowUptime: TimeInterval) {
        let elapsed = max(0, nowUptime - lastQueueEstimateUptime)
        guard elapsed > 0 else {
            return
        }
        let consumedFrames = elapsed * format.sampleRate
        if consumedFrames > 0 {
            queuedFrameEstimate = max(0, queuedFrameEstimate - consumedFrames)
        }
        lastQueueEstimateUptime = nowUptime
    }

    private func configureGraphLocked() -> Bool {
        if let attachedEngine = player.engine, attachedEngine !== engine {
            attachedEngine.detach(player)
            isGraphConfigured = false
        }

        if player.engine == nil {
            engine.attach(player)
        }
        guard player.engine === engine else {
            return false
        }

        engine.disconnectNodeOutput(player)
        engine.connect(
            player,
            to: engine.mainMixerNode,
            format: format
        )
        isGraphConfigured = true
        return true
    }

    private func ensureEngineRunningLocked() -> Bool {
        if engine.isRunning {
            return true
        }

        engine.prepare()
        try? engine.start()
        return engine.isRunning
    }

    private func startPlayerLocked() -> Bool {
        guard player.engine === engine else {
            return false
        }
        guard engine.attachedNodes.contains(player) else {
            return false
        }
        guard ensureEngineRunningLocked() else {
            return false
        }
        if !player.isPlaying {
            player.play()
        }
        isStarted = player.isPlaying
        return isStarted
    }

    private func replacePlayerNodeLocked() -> Bool {
        let previousPlayer = player
        previousPlayer.stop()
        if previousPlayer.engine === engine {
            engine.disconnectNodeOutput(previousPlayer)
            engine.detach(previousPlayer)
        }

        let newPlayer = AVAudioPlayerNode()
        engine.attach(newPlayer)
        engine.connect(
            newPlayer,
            to: engine.mainMixerNode,
            format: format
        )
        player = newPlayer
        isGraphConfigured = true
        isStarted = false
        return newPlayer.engine === engine
    }

    private func ensurePlaybackReadyLocked() -> Bool {
        if player.engine !== engine || !isGraphConfigured || !engine.attachedNodes.contains(player) {
            return rebuildGraphAndStartLocked()
        }

        guard ensureEngineRunningLocked() else {
            return false
        }

        if player.isPlaying {
            isStarted = true
            return true
        }

        if startPlayerLocked() {
            return true
        }

        // If direct restart fails, rebuild the graph before replaying to avoid
        // AVAudioPlayerNode assertions from detached/stale engine state.
        return rebuildGraphAndStartLocked()
    }

    private func rebuildGraphAndStartLocked() -> Bool {
        isStarted = false
        if !configureGraphLocked() {
            return false
        }
        if !replacePlayerNodeLocked() {
            return false
        }
        if !ensureEngineRunningLocked() {
            return false
        }
        return startPlayerLocked()
    }
}

private enum ShadowClientRealtimeAudioPayloadDecryptorError: Error {
    case invalidKeyLength(Int)
    case decryptFailed(Int)
}

private struct ShadowClientRealtimeAudioPayloadDecryptor: Sendable {
    private let key: Data
    private let keyID: UInt32

    init(configuration: ShadowClientRealtimeAudioEncryptionConfiguration) throws {
        guard configuration.key.count == kCCKeySizeAES128 else {
            throw ShadowClientRealtimeAudioPayloadDecryptorError.invalidKeyLength(
                configuration.key.count
            )
        }
        key = configuration.key
        keyID = configuration.keyID
    }

    func decrypt(
        payload: Data,
        sequenceNumber: UInt16
    ) throws -> Data {
        guard !payload.isEmpty else {
            return payload
        }

        let ivSeed = (keyID &+ UInt32(sequenceNumber)).bigEndian
        var iv = Data(repeating: 0, count: kCCBlockSizeAES128)
        withUnsafeBytes(of: ivSeed) { seed in
            iv.replaceSubrange(0 ..< seed.count, with: seed)
        }

        var output = Data(count: payload.count + kCCBlockSizeAES128)
        let outputCapacity = output.count
        var outputLength = 0
        let status = output.withUnsafeMutableBytes { outputBytes in
            payload.withUnsafeBytes { payloadBytes in
                iv.withUnsafeBytes { ivBytes in
                    key.withUnsafeBytes { keyBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            payloadBytes.baseAddress,
                            payload.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &outputLength
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw ShadowClientRealtimeAudioPayloadDecryptorError.decryptFailed(Int(status))
        }
        output.removeSubrange(outputLength ..< output.count)
        return output
    }
}
