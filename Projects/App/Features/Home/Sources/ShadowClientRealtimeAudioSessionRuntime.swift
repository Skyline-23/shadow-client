@preconcurrency import AVFoundation
import CommonCrypto
import Foundation
import Network
import os
#if os(macOS)
import CoreAudio
#endif

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
    private var output: (any ShadowClientRealtimeAudioOutput)?
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
        let prefersSpatialHeadphoneRendering =
            await ShadowClientRealtimeAudioOutputCapability.prefersSpatialHeadphoneRendering(
                channels: resolvedTrack.channelCount
            )
        let queuePressureProfile = Self.audioQueuePressureProfile(
            sampleRate: resolvedTrack.sampleRate,
            channels: resolvedTrack.channelCount,
            packetDurationMs: packetDurationMs,
            prefersSpatialHeadphoneRendering: prefersSpatialHeadphoneRendering
        )
        var decoderImplementationName = "unknown"
        var realtimePendingDurationCapMs = ShadowClientMoonlightProtocolPolicy.Audio
            .outputRealtimePendingDurationCapMs

        do {
            let resolvedDecoder = try await ShadowClientRealtimeAudioDecoderFactory.make(
                for: resolvedTrack
            )
            // Match Moonlight's LBQ pressure policy: skip enqueue above 30ms pending duration.
            realtimePendingDurationCapMs = Self.audioRealtimePendingDurationCapMs(
                packetDurationMs: packetDurationMs,
                maximumQueuedBuffers: queuePressureProfile.maximumQueuedBuffers,
                prefersSpatialHeadphoneRendering: prefersSpatialHeadphoneRendering
            )
            // Keep renderer backpressure aligned with Moonlight SDL behavior (~10 queued frames).
            let rendererPendingDurationCapMs = max(
                realtimePendingDurationCapMs,
                Double(packetDurationMs * (prefersSpatialHeadphoneRendering ? 16 : 10))
            )
            decoderImplementationName = ShadowClientRealtimeAudioDecoderFactory.debugName(
                for: resolvedDecoder
            )
            decoder = resolvedDecoder
            output = try ShadowClientRealtimeAudioOutputFactory.make(
                format: resolvedDecoder.outputFormat,
                maximumQueuedBufferCount: queuePressureProfile.maximumQueuedBuffers,
                nominalFramesPerBuffer: AVAudioFrameCount(max(1, nominalPacketFrameCount)),
                maximumPendingDurationMs: rendererPendingDurationCapMs,
                prefersSpatialHeadphoneRendering: prefersSpatialHeadphoneRendering
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
                capacity: max(
                    ShadowClientMoonlightProtocolPolicy.Audio.packetQueueBound,
                    queuePressureProfile.maximumQueuedBuffers
                )
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
        output audioOutput: any ShadowClientRealtimeAudioOutput
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
            var lastDecodeCooldownActivationUptime: TimeInterval = 0
            var lossConcealmentEventCount = 0
            var rsFECRecoveryCount = 0
            let audioDecodeCooldown = ShadowClientRealtimeSessionDefaults.audioOutputQueueDecodeCooldown
            let audioDecodeCooldownSeconds: TimeInterval = {
                let components = ShadowClientRealtimeSessionDefaults.audioOutputQueueDecodeCooldown.components
                return TimeInterval(components.seconds) +
                    (TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
            }()
            let outputSlotBackoff: Duration = .milliseconds(2)
            let decodeCooldownActivationMinimumIntervalSeconds: TimeInterval = 0.25

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
                guard now >= decodeCooldownUntilUptime else {
                    return
                }
                guard now - lastDecodeCooldownActivationUptime >=
                    decodeCooldownActivationMinimumIntervalSeconds
                else {
                    return
                }
                decodeCooldownUntilUptime = max(
                    decodeCooldownUntilUptime,
                    now + audioDecodeCooldownSeconds
                )
                lastDecodeCooldownActivationUptime = now
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

            let enqueueDecodedBuffer: (AVAudioPCMBuffer, String, Bool) async -> Void = { pcmBuffer, source, shouldDropDueToPendingPressure in
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

                if await audioOutput.enqueue(pcmBuffer: pcmBuffer) {
                    logFirstDecodedBufferIfNeeded(pcmBuffer.frameLength, source)
                    return
                }
                registerOutputQueuePressureDrop(1, "drop-output-enqueue-failed")
            }

            while !Task.isCancelled {
                let nowUptime = ProcessInfo.processInfo.systemUptime
                let isDecodeCooldownActive = nowUptime < decodeCooldownUntilUptime
                let availableOutputSlots = await audioOutput.availableEnqueueSlots()
                let drainLimit = Self.audioReadyPacketDrainLimit(
                    isDecodeCooldownActive: isDecodeCooldownActive,
                    availableOutputSlots: availableOutputSlots,
                    maximumDrainBatch: 4
                ) ?? 0
                if drainLimit == 0 {
                    if isDecodeCooldownActive {
                        try? await Task.sleep(for: audioDecodeCooldown)
                    } else if Self.shouldHoldDecodeWhenReadyPacketsEmpty(
                        isDecodeCooldownActive: isDecodeCooldownActive,
                        availableOutputSlots: availableOutputSlots
                    ) {
                        try? await Task.sleep(for: outputSlotBackoff)
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
                    let shouldDropDueToPendingPressure = !audioOutput.usesSystemManagedBuffering && Self
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
                    let availableOutputSlotsForPacket = await audioOutput.availableEnqueueSlots()
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
                                    await enqueueDecodedBuffer(
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
                                await enqueueDecodedBuffer(
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
                            await enqueueDecodedBuffer(
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
        output audioOutput: any ShadowClientRealtimeAudioOutput,
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
        output audioOutput: any ShadowClientRealtimeAudioOutput,
        state finalState: ShadowClientRealtimeAudioOutputState
    ) {
        if let currentOutput = output,
           ObjectIdentifier(currentOutput) == ObjectIdentifier(audioOutput)
        {
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
                let pingPackets = ShadowClientHostPingPacketCodec.makePingPackets(
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
        let initialPackets = ShadowClientHostPingPacketCodec.makePingPackets(
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
            private var continuation: CheckedContinuation<Void, Error>?
            private var timeoutTask: Task<Void, Never>?

            func install(
                continuation: CheckedContinuation<Void, Error>,
                timeout: Duration,
                timeoutError: @escaping @Sendable () -> Error,
                onTimeout: @escaping @Sendable () -> Void
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
                    if self.finish(.failure(timeoutError())) {
                        onTimeout()
                    }
                }
            }

            func finish(_ result: Result<Void, Error>) -> Bool {
                lock.lock()
                guard let continuation else {
                    lock.unlock()
                    return false
                }
                self.continuation = nil
                let timeoutTask = self.timeoutTask
                self.timeoutTask = nil
                lock.unlock()
                timeoutTask?.cancel()
                continuation.resume(with: result)
                return true
            }
        }

        let gate = ReadyWaitGate()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                gate.install(
                    continuation: continuation,
                    timeout: timeout,
                    timeoutError: {
                        NSError(
                            domain: "ShadowClientRealtimeAudioSessionRuntime",
                            code: 1,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Audio UDP connection timed out.",
                            ]
                        )
                    },
                    onTimeout: {
                        connection.stateUpdateHandler = nil
                        connection.cancel()
                    }
                )
                connection.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if gate.finish(.success(())) {
                            connection.stateUpdateHandler = nil
                        }
                    case let .failed(error):
                        if gate.finish(.failure(error)) {
                            connection.stateUpdateHandler = nil
                        }
                    case .cancelled:
                        if gate.finish(.failure(CancellationError())) {
                            connection.stateUpdateHandler = nil
                        }
                    default:
                        break
                    }
                }
                connection.start(queue: connectionQueue)
            }
        } onCancel: {
            if gate.finish(.failure(CancellationError())) {
                connection.stateUpdateHandler = nil
                connection.cancel()
            }
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
        // Moonlight/Apollo-host often interleave PT127 FEC shards in RTP sequence space.
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
        ),
        prefersSpatialHeadphoneRendering: Bool = false
    ) -> AudioQueuePressureProfile {
        _ = sampleRate
        let normalizedPacketDurationMs = max(1, packetDurationMs)
        let maximumQueuedBuffers: Int
        if prefersSpatialHeadphoneRendering || channels > 2 {
            maximumQueuedBuffers = ShadowClientMoonlightProtocolPolicy.Audio.packetQueueBound * 2
        } else {
            maximumQueuedBuffers = ShadowClientMoonlightProtocolPolicy.Audio.packetQueueBound
        }
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
        maximumQueuedBuffers _: Int,
        prefersSpatialHeadphoneRendering: Bool = false
    ) -> Double {
        prefersSpatialHeadphoneRendering
            ? max(
                ShadowClientMoonlightProtocolPolicy.Audio.outputRealtimePendingDurationCapMs * 8,
                240
            )
            : ShadowClientMoonlightProtocolPolicy.Audio.outputRealtimePendingDurationCapMs
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
    ) async -> Int {
        guard surroundRequested else {
            return 2
        }

        let negotiatedMaximumOutputChannels: Int
        if let maximumOutputChannels {
            negotiatedMaximumOutputChannels = maximumOutputChannels
        } else {
            negotiatedMaximumOutputChannels = await ShadowClientRealtimeAudioOutputCapability.maximumOutputChannels()
        }
        let resolvedMaximumOutputChannels = max(1, negotiatedMaximumOutputChannels)
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
        guard await ShadowClientRealtimeAudioDecoderFactory.canDecode(track: surroundTrack) else {
            return 2
        }
        return negotiatedSurroundChannels
    }

    public static func canDecode(track: ShadowClientRTSPAudioTrackDescriptor) async -> Bool {
        await ShadowClientRealtimeAudioDecoderFactory.canDecode(track: track)
    }
}

private enum ShadowClientRealtimeAudioOutputCapability {
    static func supportsHeadTrackedRoute() -> Bool {
        #if os(iOS)
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            guard output.isSpatialAudioEnabled else {
                return false
            }
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
                return true
            default:
                return false
            }
        }
        #else
        false
        #endif
    }

    static func prefersSpatialHeadphoneRendering(channels: Int) async -> Bool {
        guard channels > 2 else {
            return false
        }
        #if os(iOS) || os(tvOS)
        return await MainActor.run {
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
            return outputs.contains { output in
                output.isSpatialAudioEnabled
            }
        }
        #elseif os(macOS)
        return false
        #else
        return false
        #endif
    }

    static func maximumOutputChannels() async -> Int {
        #if os(iOS) || os(tvOS)
        return await MainActor.run {
            let session = AVAudioSession.sharedInstance()
            let headphoneSpatialRoute = session.currentRoute.outputs.contains { output in
                output.isSpatialAudioEnabled
            }
            if headphoneSpatialRoute {
                return 8
            }
            let routeMaximumChannels = Int(session.maximumOutputNumberOfChannels)
            let currentRouteChannels = Int(session.outputNumberOfChannels)
            return max(2, routeMaximumChannels, currentRouteChannels)
        }
        #else
        if let outputChannels = macDefaultOutputChannelCount(), outputChannels > 0 {
            return max(2, outputChannels)
        }

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
        #endif
    }

    #if os(macOS)
    private static func macDefaultOutputChannelCount() -> Int? {
        var defaultDeviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propertySize,
            &defaultDeviceID
        )
        guard deviceStatus == noErr, defaultDeviceID != 0 else {
            return nil
        }

        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )

        var configurationSize: UInt32 = 0
        let sizeStatus = AudioObjectGetPropertyDataSize(
            defaultDeviceID,
            &address,
            0,
            nil,
            &configurationSize
        )
        guard sizeStatus == noErr, configurationSize >= UInt32(MemoryLayout<AudioBufferList>.size) else {
            return nil
        }

        let rawBuffer = UnsafeMutableRawPointer.allocate(
            byteCount: Int(configurationSize),
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawBuffer.deallocate() }
        let bufferListPointer = rawBuffer.bindMemory(
            to: AudioBufferList.self,
            capacity: 1
        )

        let configurationStatus = AudioObjectGetPropertyData(
            defaultDeviceID,
            &address,
            0,
            nil,
            &configurationSize,
            bufferListPointer
        )
        guard configurationStatus == noErr else {
            return nil
        }

        let bufferList = UnsafeMutableAudioBufferListPointer(bufferListPointer)
        let channelCount = bufferList.reduce(0) { partial, buffer in
            partial + Int(buffer.mNumberChannels)
        }
        return channelCount > 0 ? channelCount : nil
    }
    #endif
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

protocol ShadowClientRealtimeAudioOutput: AnyObject, Sendable {
    func enqueue(pcmBuffer: AVAudioPCMBuffer) async -> Bool
    func hasEnqueueCapacity() async -> Bool
    func pendingDurationMs() async -> Double
    func availableEnqueueSlots() async -> Int
    func stop()
    func recoverPlaybackUnderPressure() -> Bool
    var usesSystemManagedBuffering: Bool { get }
    var debugFormatDescription: String { get }
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
    private static let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "RealtimeAudioDecoderFactory"
    )

    static func canDecode(track: ShadowClientRTSPAudioTrackDescriptor) async -> Bool {
        do {
            _ = try await make(for: track)
            return true
        } catch {
            logger.notice(
                "Audio decoder unavailable codec=\(track.codec.label, privacy: .public) sampleRate=\(track.sampleRate, privacy: .public) channels=\(track.channelCount, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
            )
            return false
        }
    }

    static func make(
        for track: ShadowClientRTSPAudioTrackDescriptor
    ) async throws -> any ShadowClientRealtimeAudioPacketDecoding {
        let customDecoderAttempt = await makeCustomDecoderAttempt(for: track)
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
    ) async -> (decoder: (any ShadowClientRealtimeCustomAudioDecoder)?, error: Error?) {
        do {
            let decoder = try await ShadowClientRealtimeCustomAudioDecoderRegistry.makeDecoder(
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

private enum ShadowClientRealtimeAudioOutputFactory {
    static func make(
        format: AVAudioFormat,
        maximumQueuedBufferCount: Int,
        nominalFramesPerBuffer: AVAudioFrameCount,
        maximumPendingDurationMs: Double,
        prefersSpatialHeadphoneRendering: Bool
    ) throws -> any ShadowClientRealtimeAudioOutput {
        #if os(iOS) || os(tvOS) || os(macOS)
        return try ShadowClientRealtimeSampleBufferAudioOutput(
            format: format,
            maximumQueuedBufferCount: maximumQueuedBufferCount,
            nominalFramesPerBuffer: nominalFramesPerBuffer,
            maximumPendingDurationMs: maximumPendingDurationMs,
            prefersSpatialHeadphoneRendering: prefersSpatialHeadphoneRendering
        )
        #endif
    }
}

#if os(iOS) || os(tvOS) || os(macOS)
// Safety invariant: sample-buffer rendering state is confined to `rendererQueue`,
// while backpressure accounting is actor-isolated in `BudgetState`.
private final class ShadowClientRealtimeSampleBufferAudioOutput: @unchecked Sendable, ShadowClientRealtimeAudioOutput {
    private static let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "RealtimeSampleBufferAudio"
    )
    private static let startupLeadTime = CMTime(value: 1, timescale: 20)
    private static let minimumStartupPreroll = CMTime(value: 30, timescale: 1000)

    private actor BudgetState {
        private let sampleRate: Double
        private let nominalFramesPerBuffer: Double
        private let maximumQueuedFrameEstimate: Double
        private var queuedFrameEstimate: Double = 0
        private var lastObservedTime: CMTime?

        init(
            sampleRate: Double,
            nominalFramesPerBuffer: Double,
            maximumQueuedFrameEstimate: Double
        ) {
            self.sampleRate = sampleRate
            self.nominalFramesPerBuffer = nominalFramesPerBuffer
            self.maximumQueuedFrameEstimate = maximumQueuedFrameEstimate
        }

        func reserve(
            incomingFrameCount: Double,
            currentTime: CMTime
        ) -> Bool {
            advance(to: currentTime)
            guard queuedFrameEstimate + incomingFrameCount <= maximumQueuedFrameEstimate else {
                return false
            }
            queuedFrameEstimate += incomingFrameCount
            return true
        }

        func rollback(incomingFrameCount: Double) {
            queuedFrameEstimate = max(0, queuedFrameEstimate - incomingFrameCount)
        }

        func pendingDurationMs(currentTime: CMTime) -> Double {
            advance(to: currentTime)
            guard sampleRate > 0 else {
                return 0
            }
            return (queuedFrameEstimate / sampleRate) * 1_000.0
        }

        func availableEnqueueSlots(currentTime: CMTime) -> Int {
            advance(to: currentTime)
            let remainingFrames = max(0, maximumQueuedFrameEstimate - queuedFrameEstimate)
            return max(0, Int((remainingFrames / nominalFramesPerBuffer).rounded(.down)))
        }

        func hasCapacity(currentTime: CMTime) -> Bool {
            advance(to: currentTime)
            return queuedFrameEstimate < maximumQueuedFrameEstimate
        }

        func reset(currentTime: CMTime?) {
            queuedFrameEstimate = 0
            lastObservedTime = currentTime
        }

        private func advance(to currentTime: CMTime) {
            guard currentTime.isValid, currentTime.isNumeric else {
                lastObservedTime = nil
                return
            }
            guard let lastObservedTime,
                  lastObservedTime.isValid,
                  lastObservedTime.isNumeric
            else {
                self.lastObservedTime = currentTime
                return
            }
            let delta = CMTimeGetSeconds(currentTime) - CMTimeGetSeconds(lastObservedTime)
            guard delta > 0 else {
                self.lastObservedTime = currentTime
                return
            }
            queuedFrameEstimate = max(0, queuedFrameEstimate - (delta * sampleRate))
            self.lastObservedTime = currentTime
        }
    }

    private struct PendingSampleBuffer {
        let sampleBuffer: CMSampleBuffer
    }

    private let inputFormat: AVAudioFormat
    private let renderFormat: AVAudioFormat
    private let rendererQueue = DispatchQueue(
        label: "com.skyline23.shadow-client.audio-sample-buffer-renderer",
        qos: .userInitiated
    )
    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let formatDescription: CMAudioFormatDescription
    private let budgetState: BudgetState
    private var pendingSampleBuffers: [PendingSampleBuffer] = []
    private var nextPresentationTime: CMTime = .zero
    private var hasStartedTimeline = false
    private var isTerminated = false
    private var hasLoggedFirstQueuedSample = false
    private var hasLoggedFirstRendererEnqueue = false
    private var flushTask: Task<Void, Never>?
    private var outputConfigurationTask: Task<Void, Never>?

    init(
        format: AVAudioFormat,
        maximumQueuedBufferCount: Int,
        nominalFramesPerBuffer: AVAudioFrameCount,
        maximumPendingDurationMs: Double,
        prefersSpatialHeadphoneRendering _: Bool
    ) throws {
        inputFormat = format
        renderFormat = try Self.makeRendererFormat(from: format)
        let nominalFrames = max(1, Double(nominalFramesPerBuffer))
        let boundedMaximumPendingDurationMs = max(1, maximumPendingDurationMs)
        let maximumPendingFramesFromDuration = max(
            nominalFrames,
            (renderFormat.sampleRate * boundedMaximumPendingDurationMs / 1_000.0).rounded(.up)
        )
        let maximumPendingFramesFromCount = nominalFrames * Double(max(1, maximumQueuedBufferCount))
        let maximumQueuedFrameEstimate = min(
            maximumPendingFramesFromCount,
            max(nominalFrames, maximumPendingFramesFromDuration)
        )
        budgetState = BudgetState(
            sampleRate: renderFormat.sampleRate,
            nominalFramesPerBuffer: nominalFrames,
            maximumQueuedFrameEstimate: maximumQueuedFrameEstimate
        )
        formatDescription = try Self.makeFormatDescription(for: renderFormat)

        renderer.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
        synchronizer.addRenderer(renderer)
        synchronizer.delaysRateChangeUntilHasSufficientMediaData = false
        synchronizer.rate = 0

        rendererQueue.sync {
            startFeedingLocked()
        }
        startRendererNotificationMonitoring()
        Self.logger.notice(
            "Sample buffer audio backend configured routes=[\(Self.currentRouteSummary(), privacy: .public)] spatial-formats=\(String(describing: self.renderer.allowedAudioSpatializationFormats), privacy: .public)"
        )
    }

    deinit {
        stop()
    }

    func enqueue(pcmBuffer: AVAudioPCMBuffer) async -> Bool {
        let frameCount = max(1, Double(pcmBuffer.frameLength))
        let currentTime = rendererQueue.sync { currentSynchronizerTimeLocked() }
        guard await budgetState.reserve(
            incomingFrameCount: frameCount,
            currentTime: currentTime
        ) else {
            return false
        }

        let queued = rendererQueue.sync {
            guard !isTerminated else {
                return false
            }
            guard let sampleBuffer = makeSampleBuffer(
                from: pcmBuffer,
                formatDescription: formatDescription,
                presentationTimeStamp: nextPresentationTime
            ) else {
                Self.logger.error(
                    "Sample buffer audio enqueue failed to create CMSampleBuffer frames=\(pcmBuffer.frameLength, privacy: .public)"
                )
                return false
            }

            if !hasLoggedFirstQueuedSample {
                hasLoggedFirstQueuedSample = true
                Self.logger.notice(
                    "Sample buffer audio queued first sample pts=\(CMTimeGetSeconds(self.nextPresentationTime), privacy: .public)s frames=\(pcmBuffer.frameLength, privacy: .public) renderer-ready=\(self.renderer.isReadyForMoreMediaData, privacy: .public)"
                )
            }
            pendingSampleBuffers.append(PendingSampleBuffer(sampleBuffer: sampleBuffer))
            nextPresentationTime = CMTimeAdd(
                nextPresentationTime,
                CMTime(
                    value: CMTimeValue(pcmBuffer.frameLength),
                    timescale: CMTimeScale(max(1, Int32(renderFormat.sampleRate.rounded())))
                )
            )
            startFeedingLocked()
            drainPendingSampleBuffersLocked()
            startTimelineIfNeededLocked()
            return true
        }

        if !queued {
            await budgetState.rollback(incomingFrameCount: frameCount)
        }
        return queued
    }

    func hasEnqueueCapacity() async -> Bool {
        let currentTime = rendererQueue.sync { currentSynchronizerTimeLocked() }
        return await budgetState.hasCapacity(currentTime: currentTime)
    }

    func pendingDurationMs() async -> Double {
        let currentTime = rendererQueue.sync { currentSynchronizerTimeLocked() }
        return await budgetState.pendingDurationMs(currentTime: currentTime)
    }

    func availableEnqueueSlots() async -> Int {
        let currentTime = rendererQueue.sync { currentSynchronizerTimeLocked() }
        return await budgetState.availableEnqueueSlots(currentTime: currentTime)
    }

    func stop() {
        flushTask?.cancel()
        outputConfigurationTask?.cancel()
        flushTask = nil
        outputConfigurationTask = nil

        rendererQueue.sync {
            guard !isTerminated else {
                return
            }
            isTerminated = true
            renderer.stopRequestingMediaData()
            renderer.flush()
            pendingSampleBuffers.removeAll(keepingCapacity: true)
            synchronizer.rate = 0
        }

        let budgetState = self.budgetState
        Task {
            await budgetState.reset(currentTime: nil)
        }
    }

    func recoverPlaybackUnderPressure() -> Bool {
        rendererQueue.sync {
            guard !isTerminated else {
                return false
            }
            renderer.stopRequestingMediaData()
            renderer.flush()
            pendingSampleBuffers.removeAll(keepingCapacity: true)
            nextPresentationTime = currentSynchronizerTimeLocked()
            hasStartedTimeline = synchronizer.rate != 0
            startFeedingLocked()
            let budgetState = self.budgetState
            let currentTime = nextPresentationTime
            Task {
                await budgetState.reset(currentTime: currentTime)
            }
            return true
        }
    }

    var debugFormatDescription: String {
        let interleaving = renderFormat.isInterleaved ? "interleaved" : "planar"
        return "AVSampleBufferAudioRenderer/\(String(describing: renderFormat.commonFormat))/\(renderFormat.channelCount)ch/\(Int(renderFormat.sampleRate))Hz/\(interleaving)"
    }

    var usesSystemManagedBuffering: Bool {
        true
    }

    private func startRendererNotificationMonitoring() {
        flushTask = Task { [weak self] in
            guard let self else {
                return
            }
            for await notification in NotificationCenter.default.notifications(
                named: .AVSampleBufferAudioRendererWasFlushedAutomatically,
                object: renderer
            ) {
                guard !Task.isCancelled else {
                    return
                }
                let flushTimeValue = notification.userInfo?[AVSampleBufferAudioRendererFlushTimeKey] as? NSValue
                let flushTime = flushTimeValue?.timeValue ?? .invalid
                rendererQueue.async { [weak self] in
                    self?.handleAutomaticFlushLocked(flushTime: flushTime)
                }
            }
        }

        outputConfigurationTask = Task { [weak self] in
            guard let self else {
                return
            }
            for await _ in NotificationCenter.default.notifications(
                named: .AVSampleBufferAudioRendererOutputConfigurationDidChange,
                object: renderer
            ) {
                guard !Task.isCancelled else {
                    return
                }
                rendererQueue.async { [weak self] in
                    self?.handleOutputConfigurationChangeLocked()
                }
            }
        }
    }

    private func handleAutomaticFlushLocked(flushTime: CMTime) {
        guard !isTerminated else {
            return
        }
        renderer.stopRequestingMediaData()
        renderer.flush()
        pendingSampleBuffers.removeAll(keepingCapacity: true)
        let resetTime = flushTime.isValid && flushTime.isNumeric ? flushTime : currentSynchronizerTimeLocked()
        nextPresentationTime = resetTime
        hasStartedTimeline = synchronizer.rate != 0
        startFeedingLocked()
        let budgetState = self.budgetState
        Task {
            await budgetState.reset(currentTime: resetTime)
        }
        Self.logger.notice(
            "Sample buffer audio renderer auto-flushed; resetting at \(CMTimeGetSeconds(resetTime), privacy: .public)s routes=[\(Self.currentRouteSummary(), privacy: .public)]"
        )
    }

    private func handleOutputConfigurationChangeLocked() {
        guard !isTerminated else {
            return
        }
        renderer.stopRequestingMediaData()
        renderer.flush()
        pendingSampleBuffers.removeAll(keepingCapacity: true)
        let currentTime = currentSynchronizerTimeLocked()
        nextPresentationTime = currentTime
        hasStartedTimeline = synchronizer.rate != 0
        startFeedingLocked()
        let budgetState = self.budgetState
        Task {
            await budgetState.reset(currentTime: currentTime)
        }
        Self.logger.notice(
            "Sample buffer audio output configuration changed; resetting renderer routes=[\(Self.currentRouteSummary(), privacy: .public)]"
        )
    }

    private func startFeedingLocked() {
        renderer.requestMediaDataWhenReady(on: rendererQueue) { [weak self] in
            self?.drainPendingSampleBuffersLocked()
        }
    }

    private func drainPendingSampleBuffersLocked() {
        guard !isTerminated else {
            renderer.stopRequestingMediaData()
            return
        }
        while renderer.isReadyForMoreMediaData,
              !pendingSampleBuffers.isEmpty
        {
            let pendingSampleBuffer = pendingSampleBuffers.removeFirst()
            renderer.enqueue(pendingSampleBuffer.sampleBuffer)
            if !hasLoggedFirstRendererEnqueue {
                hasLoggedFirstRendererEnqueue = true
                Self.logger.notice(
                    "Sample buffer audio renderer accepted first sample status=\(String(describing: self.renderer.status), privacy: .public) rate=\(self.synchronizer.rate, privacy: .public) pending=\(self.pendingSampleBuffers.count, privacy: .public)"
                )
            }
            startTimelineIfNeededLocked()
        }
    }

    private func startTimelineIfNeededLocked() {
        let currentTime = currentSynchronizerTimeLocked()
        let queuedDuration = CMTimeSubtract(nextPresentationTime, currentTime)
        let hasMinimumPreroll = queuedDuration.isValid &&
            queuedDuration.isNumeric &&
            CMTimeCompare(queuedDuration, Self.minimumStartupPreroll) >= 0
        guard renderer.hasSufficientMediaDataForReliablePlaybackStart || hasMinimumPreroll else {
            return
        }
        guard !hasStartedTimeline else {
            if synchronizer.rate == 0 {
                synchronizer.setRate(1, time: currentTime)
            }
            return
        }
        let hostTime = CMClockGetTime(CMClockGetHostTimeClock())
        synchronizer.setRate(
            1,
            time: currentTime,
            atHostTime: CMTimeAdd(hostTime, Self.startupLeadTime)
        )
        Self.logger.notice(
            "Sample buffer audio timeline started rate=\(self.synchronizer.rate, privacy: .public) time=\(CMTimeGetSeconds(currentTime), privacy: .public)s pending=\(self.pendingSampleBuffers.count, privacy: .public) renderer-preroll=\(self.renderer.hasSufficientMediaDataForReliablePlaybackStart, privacy: .public) queued-preroll-ms=\(CMTimeGetSeconds(queuedDuration) * 1000, privacy: .public)"
        )
        hasStartedTimeline = true
    }

    private func currentSynchronizerTimeLocked() -> CMTime {
        let currentTime = synchronizer.currentTime()
        if currentTime.isValid, currentTime.isNumeric {
            return currentTime
        }
        return nextPresentationTime
    }

    private static func makeFormatDescription(
        for format: AVAudioFormat
    ) throws -> CMAudioFormatDescription {
        let streamDescription = format.streamDescription
        var asbd = streamDescription.pointee
        var formatDescription: CMAudioFormatDescription?
        let channelLayout = format.channelLayout
        let layoutSize = channelLayout.map { audioChannelLayoutSize(for: $0) } ?? 0
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: layoutSize,
            layout: channelLayout?.layout,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let formatDescription else {
            throw NSError(
                domain: "ShadowClientRealtimeSampleBufferAudioOutput",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format description (\(status))."]
            )
        }
        return formatDescription
    }

    private static func makeRendererFormat(
        from format: AVAudioFormat
    ) throws -> AVAudioFormat {
        let channelLayoutData = format.channelLayout.map {
            Data(
                bytes: $0.layout,
                count: audioChannelLayoutSize(for: $0)
            )
        } ?? Self.channelLayoutData(for: Int(format.channelCount))

        guard let channelLayoutData else {
            Self.logger.error(
                "Sample buffer renderer format missing channel layout inputChannels=\(format.channelCount, privacy: .public) sampleRate=\(Int(format.sampleRate), privacy: .public)"
            )
            throw NSError(
                domain: "ShadowClientRealtimeSampleBufferAudioOutput",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing channel layout for renderer format."]
            )
        }

        guard let rendererFormat = AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVChannelLayoutKey: channelLayoutData,
        ]) else {
            throw NSError(
                domain: "ShadowClientRealtimeSampleBufferAudioOutput",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create renderer LPCM format."]
            )
        }

        return rendererFormat
    }

    private func makeSampleBuffer(
        from pcmBuffer: AVAudioPCMBuffer,
        formatDescription: CMAudioFormatDescription,
        presentationTimeStamp: CMTime
    ) -> CMSampleBuffer? {
        guard let renderBuffer = makeRenderPCMBuffer(pcmBuffer) else {
            return nil
        }
        guard let dataBuffer = Self.makeAudioDataBlockBuffer(from: renderBuffer) else {
            return nil
        }
        var sampleBuffer: CMSampleBuffer?
        let createStatus = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: dataBuffer,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(renderBuffer.frameLength),
            presentationTimeStamp: presentationTimeStamp,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let sampleBuffer else {
            return nil
        }
        return sampleBuffer
    }

    private func makeRenderPCMBuffer(_ pcmBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if pcmBuffer.format == renderFormat {
            return pcmBuffer
        }

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: renderFormat,
            frameCapacity: pcmBuffer.frameLength
        ) else {
            return nil
        }
        convertedBuffer.frameLength = pcmBuffer.frameLength

        let frameCount = Int(pcmBuffer.frameLength)
        let channelCount = Int(min(pcmBuffer.format.channelCount, renderFormat.channelCount))
        guard frameCount > 0, channelCount > 0 else {
            return nil
        }

        let outputList = UnsafeMutableAudioBufferListPointer(convertedBuffer.mutableAudioBufferList)
        guard let outputBaseAddress = outputList.first?.mData?.assumingMemoryBound(to: Int16.self)
        else {
            return nil
        }

        switch pcmBuffer.format.commonFormat {
        case .pcmFormatFloat32:
            guard let inputChannels = pcmBuffer.floatChannelData else {
                return nil
            }
            for frame in 0 ..< frameCount {
                for channel in 0 ..< channelCount {
                    let sample = inputChannels[channel][frame]
                    let clamped = max(-1.0, min(1.0, sample))
                    outputBaseAddress[(frame * channelCount) + channel] = Int16(clamped * Float(Int16.max))
                }
            }
        case .pcmFormatInt16:
            if pcmBuffer.format.isInterleaved {
                guard let inputBaseAddress = pcmBuffer.audioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Int16.self) else {
                    return nil
                }
                memcpy(outputBaseAddress, inputBaseAddress, frameCount * channelCount * MemoryLayout<Int16>.size)
            } else {
                guard let inputChannels = pcmBuffer.int16ChannelData else {
                    return nil
                }
                for frame in 0 ..< frameCount {
                    for channel in 0 ..< channelCount {
                        outputBaseAddress[(frame * channelCount) + channel] = inputChannels[channel][frame]
                    }
                }
            }
        default:
            return nil
        }

        return convertedBuffer
    }

    private static func makeAudioDataBlockBuffer(
        from pcmBuffer: AVAudioPCMBuffer
    ) -> CMBlockBuffer? {
        let audioBuffer = pcmBuffer.audioBufferList.pointee.mBuffers
        guard let sourceBytes = audioBuffer.mData,
              audioBuffer.mDataByteSize > 0
        else {
            return nil
        }

        var blockBuffer: CMBlockBuffer?
        let createStatus = CMBlockBufferCreateEmpty(
            allocator: kCFAllocatorDefault,
            capacity: 0,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard createStatus == kCMBlockBufferNoErr, let blockBuffer else {
            return nil
        }

        let byteCount = Int(audioBuffer.mDataByteSize)
        let appendStatus = CMBlockBufferAppendMemoryBlock(
            blockBuffer,
            memoryBlock: nil,
            length: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0
        )
        guard appendStatus == kCMBlockBufferNoErr else {
            return nil
        }

        let replaceStatus = CMBlockBufferReplaceDataBytes(
            with: sourceBytes,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: byteCount
        )
        guard replaceStatus == kCMBlockBufferNoErr else {
            return nil
        }

        return blockBuffer
    }

    private static func audioChannelLayoutSize(for channelLayout: AVAudioChannelLayout) -> Int {
        let descriptionCount = max(0, Int(channelLayout.layout.pointee.mNumberChannelDescriptions) - 1)
        return MemoryLayout<AudioChannelLayout>.size +
            (descriptionCount * MemoryLayout<AudioChannelDescription>.size)
    }

    private static func channelLayoutData(for channels: Int) -> Data? {
        let layoutTag: AudioChannelLayoutTag = switch channels {
        case 1:
            kAudioChannelLayoutTag_Mono
        case 2:
            kAudioChannelLayoutTag_Stereo
        case 6:
            kAudioChannelLayoutTag_MPEG_5_1_D
        case 8:
            kAudioChannelLayoutTag_MPEG_7_1_C
        default:
            kAudioChannelLayoutTag_DiscreteInOrder | AudioChannelLayoutTag(channels)
        }

        guard let channelLayout = AVAudioChannelLayout(layoutTag: layoutTag) else {
            return nil
        }

        return Data(
            bytes: channelLayout.layout,
            count: MemoryLayout<AudioChannelLayout>.size
        )
    }

    private static func currentRouteSummary() -> String {
        #if os(iOS) || os(tvOS)
        AVAudioSession.sharedInstance().currentRoute.outputs
            .map { output in
                "\(output.portType.rawValue){name=\(output.portName),channels=\(output.channels?.count ?? 0),spatial=\(output.isSpatialAudioEnabled)}"
            }
            .joined(separator: ",")
        #else
        let engine = AVAudioEngine()
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        return "default-output{channels=\(outputFormat.channelCount),sampleRate=\(Int(outputFormat.sampleRate))}"
        #endif
    }
}
#endif

// Safety invariant: mutable audio engine graph state is confined to `engineQueue`,
// while queued-buffer accounting is actor-isolated in `QueuedBufferState`.
private final class ShadowClientRealtimeAudioEngineOutput: @unchecked Sendable, ShadowClientRealtimeAudioOutput {
    private static let minimumQueuedBufferCount = 4
    private static let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "RealtimeAudioEngine"
    )

    private actor QueuedBufferState {
        private let maximumQueuedBufferCount: Int
        private let nominalFramesPerBuffer: Double
        private let maximumQueuedFrameEstimate: Double
        private let sampleRate: Double
        private var queuedBufferCount = 0
        private var queuedFrameEstimate: Double = 0

        init(
            maximumQueuedBufferCount: Int,
            nominalFramesPerBuffer: Double,
            maximumQueuedFrameEstimate: Double,
            sampleRate: Double
        ) {
            self.maximumQueuedBufferCount = maximumQueuedBufferCount
            self.nominalFramesPerBuffer = nominalFramesPerBuffer
            self.maximumQueuedFrameEstimate = maximumQueuedFrameEstimate
            self.sampleRate = sampleRate
        }

        func reserve(
            incomingFrameCount: Double
        ) -> Bool {
            guard queuedFrameEstimate + incomingFrameCount <= maximumQueuedFrameEstimate else {
                return false
            }
            queuedBufferCount += 1
            queuedFrameEstimate += incomingFrameCount
            return true
        }

        func hasCapacity() -> Bool {
            return queuedFrameEstimate < maximumQueuedFrameEstimate
        }

        func pendingDurationMs() -> Double {
            guard sampleRate > 0 else {
                return 0
            }
            return (queuedFrameEstimate / sampleRate) * 1_000.0
        }

        func availableEnqueueSlots() -> Int {
            let remainingFrames = max(0, maximumQueuedFrameEstimate - queuedFrameEstimate)
            return max(
                0,
                min(
                    maximumQueuedBufferCount,
                    Int((remainingFrames / nominalFramesPerBuffer).rounded(.down))
                )
            )
        }

        func reset() {
            queuedBufferCount = 0
            queuedFrameEstimate = 0
        }

        func didConsume(consumedFrameCount: Double) {
            queuedBufferCount = max(0, queuedBufferCount - 1)
            queuedFrameEstimate = max(0, queuedFrameEstimate - consumedFrameCount)
        }
    }

    private let engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private let environmentNode: AVAudioEnvironmentNode?
    private let engineQueue = DispatchQueue(
        label: "com.skyline23.shadow-client.audio-engine-output",
        qos: .userInitiated
    )
    private let format: AVAudioFormat
    private let prefersSpatialHeadphoneRendering: Bool
    private let maximumQueuedBufferCount: Int
    private let nominalFramesPerBuffer: Double
    private let maximumQueuedFrameEstimate: Double
    private let queuedBufferState: QueuedBufferState
    private var isStarted = false
    private var isTerminated = false
    private var isGraphConfigured = false
    private var routeChangeTask: Task<Void, Never>?

    init(
        format: AVAudioFormat,
        maximumQueuedBufferCount: Int = minimumQueuedBufferCount,
        nominalFramesPerBuffer: AVAudioFrameCount,
        maximumPendingDurationMs: Double,
        prefersSpatialHeadphoneRendering: Bool = false
    ) throws {
        self.format = format
        self.prefersSpatialHeadphoneRendering = prefersSpatialHeadphoneRendering
        self.environmentNode = Self.makeEnvironmentNodeIfNeeded(format: format)
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
        self.queuedBufferState = QueuedBufferState(
            maximumQueuedBufferCount: self.maximumQueuedBufferCount,
            nominalFramesPerBuffer: self.nominalFramesPerBuffer,
            maximumQueuedFrameEstimate: self.maximumQueuedFrameEstimate,
            sampleRate: format.sampleRate
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
            startHeadTrackingLocked()
            startRouteChangeMonitoringLocked()
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

    func enqueue(pcmBuffer: AVAudioPCMBuffer) async -> Bool {
        let incomingFrameCount = max(1, Double(pcmBuffer.frameLength))
        guard await queuedBufferState.reserve(
            incomingFrameCount: incomingFrameCount
        ) else {
            return false
        }

        let enqueued = engineQueue.sync {
            guard !isTerminated else {
                return false
            }

            guard ensurePlaybackReadyLocked() else {
                return false
            }

            player.scheduleBuffer(
                pcmBuffer,
                completionCallbackType: .dataConsumed
            ) { [queuedBufferState, incomingFrameCount] _ in
                Task {
                    await queuedBufferState.didConsume(consumedFrameCount: incomingFrameCount)
                }
            }
            return true
        }
        if !enqueued {
            await queuedBufferState.didConsume(consumedFrameCount: incomingFrameCount)
        }
        return enqueued
    }

    func hasEnqueueCapacity() async -> Bool {
        await queuedBufferState.hasCapacity()
    }

    func pendingDurationMs() async -> Double {
        await queuedBufferState.pendingDurationMs()
    }

    func availableEnqueueSlots() async -> Int {
        await queuedBufferState.availableEnqueueSlots()
    }

    func stop() {
        engineQueue.sync {
            if isTerminated {
                return
            }
            isTerminated = true
            stopHeadTrackingLocked()
            let currentPlayer = player
            currentPlayer.stop()
            if currentPlayer.engine === engine {
                engine.disconnectNodeOutput(currentPlayer)
                engine.detach(currentPlayer)
            }
            if let environmentNode,
               environmentNode.engine === engine
            {
                engine.disconnectNodeOutput(environmentNode)
                engine.detach(environmentNode)
            }
            engine.stop()
            engine.reset()
            isGraphConfigured = false
            isStarted = false
        }
        routeChangeTask?.cancel()
        routeChangeTask = nil

        let queuedBufferState = self.queuedBufferState
        Task {
            await queuedBufferState.reset()
        }
    }

    func recoverPlaybackUnderPressure() -> Bool {
        engineQueue.sync {
            guard !isTerminated else {
                return false
            }
            guard rebuildGraphAndStartLocked() else {
                return false
            }
            let queuedBufferState = self.queuedBufferState
            Task {
                await queuedBufferState.reset()
            }
            return true
        }
    }

    var debugFormatDescription: String {
        let interleaving = format.isInterleaved ? "interleaved" : "planar"
        return "\(String(describing: format.commonFormat))/\(format.channelCount)ch/\(Int(format.sampleRate))Hz/\(interleaving)"
    }

    var usesSystemManagedBuffering: Bool {
        false
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
        if let environmentNode {
            if environmentNode.engine == nil {
                engine.attach(environmentNode)
            }
            guard environmentNode.engine === engine else {
                return false
            }
            engine.disconnectNodeOutput(environmentNode)
            engine.connect(
                player,
                to: environmentNode,
                format: format
            )
            engine.connect(
                environmentNode,
                to: engine.mainMixerNode,
                format: nil
            )
        } else {
            engine.connect(
                player,
                to: engine.mainMixerNode,
                format: format
            )
        }
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
        if let environmentNode {
            engine.connect(
                newPlayer,
                to: environmentNode,
                format: format
            )
            newPlayer.sourceMode = .ambienceBed
            newPlayer.renderingAlgorithm = .auto
            newPlayer.position = AVAudioMake3DPoint(0, 0, 0)
        } else {
            engine.connect(
                newPlayer,
                to: engine.mainMixerNode,
                format: format
            )
        }
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
        startHeadTrackingLocked()
        startRouteChangeMonitoringLocked()
        return startPlayerLocked()
    }

    private func startHeadTrackingLocked() {
        guard let environmentNode else {
            Self.logger.notice("Spatial audio disabled: environment node not created for current route/format")
            return
        }
        #if os(iOS)
        if #available(iOS 18.0, *) {
            let headTrackingSupported = ShadowClientRealtimeAudioOutputCapability
                .supportsHeadTrackedRoute()
            environmentNode.isListenerHeadTrackingEnabled = headTrackingSupported
            Self.logger.notice(
                "Spatial audio head tracking route-output-type=\(environmentNode.outputType.rawValue, privacy: .public) route-supports-head-tracking=\(headTrackingSupported, privacy: .public) active=\(environmentNode.isListenerHeadTrackingEnabled, privacy: .public) rendering-algorithms=\(String(describing: environmentNode.applicableRenderingAlgorithms), privacy: .public)"
            )
        }
        #elseif os(macOS)
        if #available(macOS 15.0, *) {
            environmentNode.isListenerHeadTrackingEnabled = true
            Self.logger.notice(
                "Spatial audio head tracking requested route-output-type=\(environmentNode.outputType.rawValue, privacy: .public) active=\(environmentNode.isListenerHeadTrackingEnabled, privacy: .public) rendering-algorithms=\(String(describing: environmentNode.applicableRenderingAlgorithms), privacy: .public)"
            )
        }
        #elseif os(tvOS)
        if #available(tvOS 18.0, *) {
            environmentNode.isListenerHeadTrackingEnabled = true
            Self.logger.notice(
                "Spatial audio head tracking requested route-output-type=\(environmentNode.outputType.rawValue, privacy: .public) active=\(environmentNode.isListenerHeadTrackingEnabled, privacy: .public) rendering-algorithms=\(String(describing: environmentNode.applicableRenderingAlgorithms), privacy: .public)"
            )
        }
        #endif
    }

    private func stopHeadTrackingLocked() {
        guard let environmentNode else {
            return
        }
        #if os(iOS)
        if #available(iOS 18.0, *) {
            environmentNode.isListenerHeadTrackingEnabled = false
        }
        #elseif os(macOS)
        if #available(macOS 15.0, *) {
            environmentNode.isListenerHeadTrackingEnabled = false
        }
        #elseif os(tvOS)
        if #available(tvOS 18.0, *) {
            environmentNode.isListenerHeadTrackingEnabled = false
        }
        #endif
    }

    private func startRouteChangeMonitoringLocked() {
        guard routeChangeTask == nil else {
            return
        }
        #if os(iOS) || os(tvOS)
        routeChangeTask = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: AVAudioSession.routeChangeNotification
            ) {
                guard let self else {
                    return
                }
                self.engineQueue.async { [weak self] in
                    self?.refreshSpatialAudioRouteLocked()
                }
            }
        }
        #endif
    }

    private func refreshSpatialAudioRouteLocked() {
        guard let environmentNode else {
            return
        }
        environmentNode.outputType = Self.preferredEnvironmentOutputType()
        startHeadTrackingLocked()
        Self.logger.notice(
            "Spatial audio route refreshed output-type=\(environmentNode.outputType.rawValue, privacy: .public) routes=[\(Self.currentRouteSummary(), privacy: .public)]"
        )
    }

    private static func makeEnvironmentNodeIfNeeded(format: AVAudioFormat) -> AVAudioEnvironmentNode? {
        guard supportsSpatialAudio(for: format) else {
            return nil
        }

        let environmentNode = AVAudioEnvironmentNode()
        environmentNode.outputType = preferredEnvironmentOutputType()
        environmentNode.listenerPosition = AVAudioMake3DPoint(0, 0, 0)
        environmentNode.listenerAngularOrientation = AVAudioMake3DAngularOrientation(0, 0, 0)
        environmentNode.reverbParameters.enable = false
        return environmentNode
    }

    private static func supportsSpatialAudio(for format: AVAudioFormat) -> Bool {
        guard format.channelCount > 2 else {
            return false
        }

        #if os(iOS)
        return AVAudioSession.sharedInstance().currentRoute.outputs.contains { $0.isSpatialAudioEnabled }
        #elseif os(tvOS)
        guard format.channelCount > 2 else {
            return false
        }
        return true
        #elseif os(macOS)
        return true
        #else
        return false
        #endif
    }

    private static func preferredEnvironmentOutputType() -> AVAudioEnvironmentOutputType {
        #if os(iOS)
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let headphonesActive = outputs.contains { output in
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
                return true
            default:
                return false
            }
        }
        if headphonesActive {
            return .headphones
        }
        let builtInSpeakerActive = outputs.contains { output in
            switch output.portType {
            case .builtInSpeaker, .builtInReceiver:
                return true
            default:
                return false
            }
        }
        return builtInSpeakerActive ? .builtInSpeakers : .auto
        #elseif os(tvOS)
        return .builtInSpeakers
        #else
        return .auto
        #endif
    }

    static func currentRouteSummary() -> String {
        #if os(iOS) || os(tvOS)
        AVAudioSession.sharedInstance().currentRoute.outputs
            .map { output in
                "\(output.portType.rawValue){name=\(output.portName),channels=\(output.channels?.count ?? 0),spatial=\(output.isSpatialAudioEnabled)}"
            }
            .joined(separator: ",")
        #else
        let engine = AVAudioEngine()
        let outputFormat = engine.outputNode.inputFormat(forBus: 0)
        return "default-output{channels=\(outputFormat.channelCount),sampleRate=\(Int(outputFormat.sampleRate))}"
        #endif
    }

    #if os(iOS)
    private static func supportsHeadTrackedRoute() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            guard output.isSpatialAudioEnabled else {
                return false
            }
            switch output.portType {
            case .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
                return true
            default:
                return false
            }
        }
    }
    #endif
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
