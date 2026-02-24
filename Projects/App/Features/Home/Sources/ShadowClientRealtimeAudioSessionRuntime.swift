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
        let payloadType: Int
        let payload: Data
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
    private var pingTask: Task<Void, Never>?
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
        var decoderImplementationName = "unknown"

        do {
            let resolvedDecoder = try ShadowClientRealtimeAudioDecoderFactory.make(
                for: resolvedTrack
            )
            let queuePressureProfile = Self.audioQueuePressureProfile(
                sampleRate: resolvedTrack.sampleRate,
                channels: resolvedTrack.channelCount
            )
            decoderImplementationName = ShadowClientRealtimeAudioDecoderFactory.debugName(
                for: resolvedDecoder
            )
            decoder = resolvedDecoder
            output = try ShadowClientRealtimeAudioEngineOutput(
                format: resolvedDecoder.outputFormat,
                maximumQueuedBufferCount: queuePressureProfile.maximumQueuedBuffers
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
            startReceiveLoop(
                over: udpConnection,
                preferredPayloadType: resolvedTrack.rtpPayloadType,
                sampleRate: resolvedTrack.sampleRate,
                channels: resolvedTrack.channelCount,
                decoder: activeDecoder,
                payloadDecryptor: payloadDecryptor,
                output: activeOutput
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

        pingTask?.cancel()
        pingTask = nil

        connection?.cancel()
        connection = nil

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

    private func startReceiveLoop(
        over connection: NWConnection,
        preferredPayloadType: Int,
        sampleRate: Int,
        channels: Int,
        decoder: any ShadowClientRealtimeAudioPacketDecoding,
        payloadDecryptor: ShadowClientRealtimeAudioPayloadDecryptor?,
        output audioOutput: ShadowClientRealtimeAudioEngineOutput
    ) {
        receiveTask = Task { [weak self] in
            guard let self else {
                return
            }

            var currentPayloadType = preferredPayloadType
            var loggedUnexpectedPayloadTypes = Set<Int>()
            var loggedPayloadNormalizationKeys = Set<String>()
            var unexpectedPayloadTypeCounts: [Int: Int] = [:]
            var hasLockedPayloadType = false
            var pendingPayloadTypeCandidate: Int?
            var pendingPayloadTypeCandidateCount = 0
            var consecutivePayloadTypeMismatchCount = 0
            var payloadTypeMismatchPressure = 0
            var consecutiveDroppedOutputBuffers = 0
            var consecutiveDecryptFailures = 0
            var consecutiveDecodeFailures = 0
            var outputQueuePressureDropCount = 0
            var firstOutputQueuePressureDropUptime: TimeInterval = 0
            var consecutiveOutputQueueSaturationCount = 0
            var outputQueueDecodeCooldownActivationCount = 0
            var lastOutputRecoveryAttemptUptime: TimeInterval = 0
            var decodeCooldownDeadline: ContinuousClock.Instant?
            let queuePressureProfile = Self.audioQueuePressureProfile(
                sampleRate: sampleRate,
                channels: channels
            )
            let decodeSaturationBurstThreshold = max(
                1,
                ShadowClientRealtimeSessionDefaults.audioOutputQueueSaturationBurstThreshold
            )
            let decodeCooldown = ShadowClientRealtimeSessionDefaults.audioOutputQueueDecodeCooldown
            let outputRecoveryAttemptCooldownSeconds: TimeInterval = 0.35
            let payloadAdaptationObservationThreshold = max(
                1,
                ShadowClientRealtimeSessionDefaults.audioPayloadTypeAdaptationObservationThreshold
            )
            let decodeFailureAbortThreshold = max(
                1,
                ShadowClientRealtimeSessionDefaults.audioDecodeFailureAbortThreshold
            )
            let decodeFailureLogInterval = max(
                1,
                ShadowClientRealtimeSessionDefaults.audioDecodeFailureLogInterval
            )
            let clock = ContinuousClock()
            let minimumPacketSamples = max(1, sampleRate / 400)
            let maximumPacketSamples = max(minimumPacketSamples, minimumPacketSamples * 48)
            var lastDecodedSequenceNumber: UInt16?
            var lastDecodedTimestamp: UInt32?
            var estimatedSamplesPerPacket = max(minimumPacketSamples, sampleRate / 50)
            var lossConcealmentEventCount = 0
            var inBandFECRecoveryCount = 0
            var rsFECRecoveryCount = 0
            let moonlightRSFECQueue = ShadowClientRealtimeAudioMoonlightRSFECQueue()

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
                        interval: queuePressureProfile.pressureSignalInterval
                    )
                {
                    self.logger.error(
                        "Audio output queue pressure detected (\(reason, privacy: .public), dropped=\(outputQueuePressureDropCount, privacy: .public))"
                    )
                }

                if Self.didCounterCrossIntervalBoundary(
                    previous: previousDropCount,
                    current: outputQueuePressureDropCount,
                    interval: queuePressureProfile.pressureTrimInterval
                ) {
                    let trimmedCount = self.jitterBuffer.trimToMostRecent(
                        maxBufferedPackets: queuePressureProfile.pressureTrimToRecentPackets
                    )
                    if trimmedCount > 0 {
                        self.logger.notice(
                            "Audio jitter buffer pressure trim dropped \(trimmedCount, privacy: .public) stale packets"
                        )
                    }
                }
            }
            let activateDecodeCooldownUnderSaturation: (String) -> Void = { reason in
                guard decodeCooldownDeadline == nil else {
                    return
                }
                decodeCooldownDeadline = clock.now + decodeCooldown
                outputQueueDecodeCooldownActivationCount += 1
                let trimmedCount = self.jitterBuffer.trimToMostRecent(
                    maxBufferedPackets: queuePressureProfile.pressureTrimToRecentPackets
                )
                if outputQueueDecodeCooldownActivationCount == 1 ||
                    outputQueueDecodeCooldownActivationCount.isMultiple(of: 12)
                {
                    self.logger.notice(
                        "Audio decode cooldown activated due to \(reason, privacy: .public) (count=\(outputQueueDecodeCooldownActivationCount, privacy: .public), trimmed=\(trimmedCount, privacy: .public))"
                    )
                }
            }
            while !Task.isCancelled {
                do {
                    guard let datagram = try await Self.receiveDatagram(over: connection),
                          !datagram.isEmpty
                    else {
                        continue
                    }

                    guard let parsedPacket = Self.parseRTPPacket(datagram) else {
                        continue
                    }
                    let normalizedPayload = ShadowClientRealtimeAudioRTPPayloadNormalizer.normalize(
                        payloadType: parsedPacket.payloadType,
                        payload: parsedPacket.payload,
                        preferredPayloadType: currentPayloadType,
                        wrapperPayloadType: ShadowClientRealtimeSessionDefaults
                            .ignoredRTPControlPayloadType
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
                        payloadType: normalizedPayload.payloadType,
                        payload: normalizedPayload.payload
                    )
                    await moonlightRSFECQueue.ingest(
                        packetSequenceNumber: packet.sequenceNumber,
                        packetTimestamp: packet.timestamp,
                        payloadType: packet.payloadType,
                        payload: packet.payload,
                        expectedPrimaryPayloadType: currentPayloadType,
                        wrapperPayloadType: ShadowClientRealtimeSessionDefaults
                            .ignoredRTPControlPayloadType
                    )

                    if !Self.shouldProcessPayloadMismatch(for: normalizedPayload) {
                        continue
                    }

                    if packet.payloadType != currentPayloadType {
                        consecutivePayloadTypeMismatchCount += 1
                        payloadTypeMismatchPressure = min(
                            payloadAdaptationObservationThreshold * 4,
                            payloadTypeMismatchPressure + 1
                        )
                        let lockIsExpired = hasLockedPayloadType &&
                            (
                                consecutivePayloadTypeMismatchCount >= payloadAdaptationObservationThreshold ||
                                    payloadTypeMismatchPressure >= payloadAdaptationObservationThreshold
                            )
                        if lockIsExpired {
                            pendingPayloadTypeCandidate = nil
                            pendingPayloadTypeCandidateCount = 0
                            consecutivePayloadTypeMismatchCount = 0
                            payloadTypeMismatchPressure = 0
                            hasLockedPayloadType = false
                            if let nextPayloadType = Self.payloadTypePreference(
                                observed: packet.payloadType,
                                current: currentPayloadType,
                                hasLockedPayloadType: false
                            ) {
                                let previousPayloadType = currentPayloadType
                                currentPayloadType = nextPayloadType
                                jitterBuffer.reset(preferredPayloadType: currentPayloadType)
                                lastDecodedSequenceNumber = nil
                                lastDecodedTimestamp = nil
                                logger.notice(
                                    "Adapting RTP audio payload type from \(previousPayloadType, privacy: .public) to \(currentPayloadType, privacy: .public) after lock expiry due to sustained mismatch"
                                )
                            }
                            continue
                        }
                        let adaptationLockActive = hasLockedPayloadType && !lockIsExpired
                        if let nextPayloadType = Self.payloadTypePreference(
                            observed: packet.payloadType,
                            current: currentPayloadType,
                            hasLockedPayloadType: adaptationLockActive
                        ) {
                            if pendingPayloadTypeCandidate == nextPayloadType {
                                pendingPayloadTypeCandidateCount += 1
                            } else {
                                pendingPayloadTypeCandidate = nextPayloadType
                                pendingPayloadTypeCandidateCount = 1
                            }
                            if pendingPayloadTypeCandidateCount >= payloadAdaptationObservationThreshold {
                                let previousPayloadType = currentPayloadType
                                currentPayloadType = nextPayloadType
                                hasLockedPayloadType = false
                                pendingPayloadTypeCandidate = nil
                                pendingPayloadTypeCandidateCount = 0
                                consecutivePayloadTypeMismatchCount = 0
                                payloadTypeMismatchPressure = 0
                                jitterBuffer.reset(preferredPayloadType: currentPayloadType)
                                lastDecodedSequenceNumber = nil
                                lastDecodedTimestamp = nil
                                logger.notice(
                                    "Adapting RTP audio payload type from \(previousPayloadType, privacy: .public) to \(currentPayloadType, privacy: .public) after \(payloadAdaptationObservationThreshold, privacy: .public) consecutive candidate packets"
                                )
                            }
                        } else {
                            let previousUnexpectedCount = unexpectedPayloadTypeCounts[packet.payloadType, default: 0]
                            let currentUnexpectedCount = previousUnexpectedCount + 1
                            unexpectedPayloadTypeCounts[packet.payloadType] = currentUnexpectedCount
                            if loggedUnexpectedPayloadTypes.insert(packet.payloadType).inserted ||
                                Self.didCounterCrossIntervalBoundary(
                                    previous: previousUnexpectedCount,
                                    current: currentUnexpectedCount,
                                    interval: ShadowClientRealtimeSessionDefaults.audioUnexpectedPayloadTypeLogInterval
                                )
                            {
                                logger.notice(
                                    "Audio RTP payload mismatch summary: expected=\(currentPayloadType, privacy: .public), observed=\(packet.payloadType, privacy: .public), count=\(currentUnexpectedCount, privacy: .public)"
                                )
                            }
                        }
                        continue
                    }
                    hasLockedPayloadType = true
                    pendingPayloadTypeCandidate = nil
                    pendingPayloadTypeCandidateCount = 0
                    consecutivePayloadTypeMismatchCount = 0
                    payloadTypeMismatchPressure = max(0, payloadTypeMismatchPressure - 1)

                    @discardableResult
                    func handleOutputQueueSaturation(dropCount: Int) -> Bool {
                        consecutiveOutputQueueSaturationCount += 1
                        registerOutputQueuePressureDrop(max(1, dropCount), "skip-decode")
                        let now = ProcessInfo.processInfo.systemUptime
                        let canAttemptOutputRecovery =
                            lastOutputRecoveryAttemptUptime == 0 ||
                            now - lastOutputRecoveryAttemptUptime >=
                            outputRecoveryAttemptCooldownSeconds
                        if canAttemptOutputRecovery {
                            lastOutputRecoveryAttemptUptime = now
                            if audioOutput.recoverPlaybackUnderPressure() {
                                logger.notice(
                                    "Audio output playback recovered after queue saturation"
                                )
                                consecutiveOutputQueueSaturationCount = 0
                                decodeCooldownDeadline = nil
                                return true
                            }
                            if consecutiveOutputQueueSaturationCount == 1 ||
                                consecutiveOutputQueueSaturationCount.isMultiple(
                                    of: decodeSaturationBurstThreshold * 2
                                )
                            {
                                logger.notice(
                                    "Audio output recovery attempt failed while queue saturation persisted"
                                )
                            }
                            activateDecodeCooldownUnderSaturation("failed-recovery")
                        }
                        if consecutiveOutputQueueSaturationCount == decodeSaturationBurstThreshold ||
                            (
                                consecutiveOutputQueueSaturationCount > decodeSaturationBurstThreshold &&
                                    consecutiveOutputQueueSaturationCount.isMultiple(
                                        of: decodeSaturationBurstThreshold * 2
                                    )
                            )
                        {
                            if audioOutput.recoverPlaybackUnderPressure() {
                                logger.notice(
                                    "Audio output playback recovered after sustained queue saturation"
                                )
                                consecutiveOutputQueueSaturationCount = 0
                                lastOutputRecoveryAttemptUptime = now
                                decodeCooldownDeadline = nil
                                return true
                            }
                        }
                        if consecutiveOutputQueueSaturationCount >= decodeSaturationBurstThreshold {
                            consecutiveOutputQueueSaturationCount = 0
                            activateDecodeCooldownUnderSaturation("sustained-output-queue-saturation")
                        }
                        return false
                    }

                    let nowUptime = ProcessInfo.processInfo.systemUptime
                    let preDrainAvailableOutputSlots = audioOutput.availableEnqueueSlots
                    let isDecodeCooldownActive: Bool
                    if let cooldownDeadline = decodeCooldownDeadline {
                        isDecodeCooldownActive = clock.now < cooldownDeadline
                    } else {
                        isDecodeCooldownActive = false
                    }
                    let readyPacketDrainLimit = Self.audioReadyPacketDrainLimit(
                        isDecodeCooldownActive: isDecodeCooldownActive,
                        availableOutputSlots: preDrainAvailableOutputSlots
                    )
                    let readyPackets = jitterBuffer.enqueue(
                        packet,
                        preferredPayloadType: currentPayloadType,
                        nowUptime: nowUptime,
                        maximumReadyPackets: readyPacketDrainLimit
                    )
                    if readyPackets.isEmpty {
                        if isDecodeCooldownActive {
                            registerOutputQueuePressureDrop(1, "decode-cooldown-hold")
                            continue
                        }
                        if Self.shouldHoldDecodeWhenReadyPacketsEmpty(
                            isDecodeCooldownActive: isDecodeCooldownActive,
                            availableOutputSlots: preDrainAvailableOutputSlots
                        ) {
                            // Match Moonlight behavior: if output has no free slot right now,
                            // hold decode and keep buffered packets intact instead of escalating
                            // recovery as a synthetic drop.
                            continue
                        }
                        continue
                    }

                    if let cooldownDeadline = decodeCooldownDeadline {
                        if clock.now < cooldownDeadline {
                            registerOutputQueuePressureDrop(readyPackets.count, "decode-cooldown")
                            continue
                        }
                        decodeCooldownDeadline = nil
                    }
                    let availableOutputSlots = audioOutput.availableEnqueueSlots
                    if availableOutputSlots <= 0 {
                        if handleOutputQueueSaturation(dropCount: readyPackets.count) {
                            continue
                        }
                        continue
                    }
                    consecutiveOutputQueueSaturationCount = 0

                    var remainingOutputSlots = availableOutputSlots
                    let decodeSheddingLowWatermark = max(
                        1,
                        queuePressureProfile.decodeSheddingLowWatermarkSlots
                    )
                    let decodeWindow = Self.audioReadyPacketDecodeWindow(
                        readyPacketCount: readyPackets.count,
                        availableOutputSlots: availableOutputSlots,
                        decodeSheddingLowWatermarkSlots: decodeSheddingLowWatermark
                    )
                    if decodeWindow.droppedPacketCount > 0 {
                        registerOutputQueuePressureDrop(
                            decodeWindow.droppedPacketCount,
                            "producer-tail-shed"
                        )
                    }

                    for packetIndex in decodeWindow.decodeStartIndex ..< decodeWindow.decodeEndIndex {
                        let readyPacket = readyPackets[packetIndex]
                        do {
                            guard remainingOutputSlots > 0 else {
                                registerOutputQueuePressureDrop(1, "guard-no-slots")
                                continue
                            }
                            let missingPacketCount = Self.missingRTPPacketCount(
                                previousSequenceNumber: lastDecodedSequenceNumber,
                                currentSequenceNumber: readyPacket.sequenceNumber
                            )
                            if let previousSequenceNumber = lastDecodedSequenceNumber,
                               let previousTimestamp = lastDecodedTimestamp,
                               let refreshedEstimate = Self.estimatedAudioSamplesPerPacket(
                                   sampleRate: sampleRate,
                                   previousSequenceNumber: previousSequenceNumber,
                                   currentSequenceNumber: readyPacket.sequenceNumber,
                                   previousTimestamp: previousTimestamp,
                                   currentTimestamp: readyPacket.timestamp,
                                   minimumPacketSamples: minimumPacketSamples,
                                   maximumPacketSamples: maximumPacketSamples
                               )
                            {
                                estimatedSamplesPerPacket = refreshedEstimate
                            }
                            let decodePayload: Data
                            if let payloadDecryptor {
                                do {
                                    decodePayload = try payloadDecryptor.decrypt(
                                        payload: readyPacket.payload,
                                        sequenceNumber: readyPacket.sequenceNumber
                                    )
                                    consecutiveDecryptFailures = 0
                                } catch {
                                    consecutiveDecryptFailures += 1
                                    if consecutiveDecryptFailures == 1 ||
                                        consecutiveDecryptFailures.isMultiple(of: 25)
                                    {
                                        logger.error(
                                            "Failed to decrypt RTP audio payload (count=\(consecutiveDecryptFailures, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                                        )
                                    }
                                    if consecutiveDecryptFailures >= 150 {
                                        let message = "Audio payload decryption repeatedly failed."
                                        logger.error("\(message, privacy: .public)")
                                        handleReceiveLoopTermination(
                                            over: connection,
                                            output: audioOutput,
                                            state: .decoderFailed(message)
                                        )
                                        return
                                    }
                                    continue
                                }
                            } else {
                                decodePayload = readyPacket.payload
                            }
                            if missingPacketCount > 0 {
                                var recoveredMissingPacketCount = 0
                                let missingRecoveryBudget =
                                    Self.maximumRecoveredAudioPacketsPerBurst(
                                        availableOutputSlots: remainingOutputSlots
                                    )
                                let boundedMissingPacketCount = min(
                                    missingPacketCount,
                                    missingRecoveryBudget
                                )
                                if let previousSequenceNumber = lastDecodedSequenceNumber,
                                   boundedMissingPacketCount > 0,
                                   remainingOutputSlots > 0
                                {
                                    for missingOffset in 1 ... boundedMissingPacketCount {
                                        guard remainingOutputSlots > 0 else {
                                            registerOutputQueuePressureDrop(
                                                boundedMissingPacketCount - recoveredMissingPacketCount,
                                                "drop-rs-fec-recovery-buffer"
                                            )
                                            break
                                        }
                                        let missingSequenceNumber = previousSequenceNumber &+
                                            UInt16(missingOffset)
                                        guard let recoveredPayload = await moonlightRSFECQueue
                                            .takeRecoveredPayload(
                                                sequenceNumber: missingSequenceNumber
                                            )
                                        else {
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
                                                    logger.error(
                                                        "Failed to decrypt RS-FEC recovered RTP audio payload (count=\(consecutiveDecryptFailures, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                                                    )
                                                }
                                                continue
                                            }
                                        } else {
                                            recoveredDecodePayload = recoveredPayload
                                        }

                                        do {
                                            if let recoveredPCMBuffer = try decoder.decode(
                                                payload: recoveredDecodePayload,
                                                decodeFEC: false
                                            ) {
                                                if decoder.requiresPlaybackSafetyGuard {
                                                    guard ShadowClientRealtimeAudioPCMBufferGuard
                                                        .isSafeForPlayback(recoveredPCMBuffer)
                                                    else {
                                                        ShadowClientRealtimeAudioPCMBufferGuard
                                                            .replaceWithSilence(recoveredPCMBuffer)
                                                        if audioOutput.enqueue(
                                                            pcmBuffer: recoveredPCMBuffer
                                                        ) == false {
                                                            registerOutputQueuePressureDrop(
                                                                1,
                                                                "drop-rs-fec-sanitized-buffer"
                                                            )
                                                            continue
                                                        }
                                                        remainingOutputSlots = max(
                                                            0,
                                                            remainingOutputSlots - 1
                                                        )
                                                        recoveredMissingPacketCount += 1
                                                        continue
                                                    }
                                                }

                                                if audioOutput.enqueue(
                                                    pcmBuffer: recoveredPCMBuffer
                                                ) == false {
                                                    registerOutputQueuePressureDrop(
                                                        1,
                                                        "drop-rs-fec-recovery-buffer"
                                                    )
                                                    continue
                                                }
                                                remainingOutputSlots = max(
                                                    0,
                                                    remainingOutputSlots - 1
                                                )
                                                recoveredMissingPacketCount += 1
                                            }
                                        } catch {
                                            logger.error(
                                                "Audio RS-FEC recovered payload decode failed for sequence \(missingSequenceNumber, privacy: .public): \(error.localizedDescription, privacy: .public)"
                                            )
                                        }
                                    }
                                }
                                if missingPacketCount > boundedMissingPacketCount {
                                    registerOutputQueuePressureDrop(
                                        missingPacketCount - boundedMissingPacketCount,
                                        "drop-rs-fec-recovery-budget"
                                    )
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
                                        logger.notice(
                                            "Audio Moonlight RS-FEC recovered missing packets (count=\(rsFECRecoveryCount, privacy: .public))"
                                        )
                                    }
                                }

                                if recoveredMissingPacketCount == 0,
                                   missingPacketCount == 1,
                                   remainingOutputSlots > 0
                                {
                                    if let fecBuffer = try decoder.decode(
                                        payload: decodePayload,
                                        decodeFEC: true
                                    ) {
                                        if audioOutput.enqueue(pcmBuffer: fecBuffer) {
                                            remainingOutputSlots = max(0, remainingOutputSlots - 1)
                                            recoveredMissingPacketCount = 1
                                            inBandFECRecoveryCount += 1
                                            if inBandFECRecoveryCount == 1 ||
                                                inBandFECRecoveryCount.isMultiple(of: 50)
                                            {
                                                logger.notice(
                                                    "Audio in-band Opus FEC recovered missing packet (count=\(inBandFECRecoveryCount, privacy: .public))"
                                                )
                                            }
                                        } else {
                                            registerOutputQueuePressureDrop(1, "drop-fec-recovery-buffer")
                                        }
                                    }
                                }

                                let pendingConcealmentPacketCount = max(
                                    0,
                                    missingPacketCount - recoveredMissingPacketCount
                                )
                                let concealmentPacketCount = min(
                                    pendingConcealmentPacketCount,
                                    Self.maximumConcealmentPacketsPerBurst(
                                        availableOutputSlots: remainingOutputSlots
                                    )
                                )
                                if pendingConcealmentPacketCount > concealmentPacketCount {
                                    registerOutputQueuePressureDrop(
                                        pendingConcealmentPacketCount - concealmentPacketCount,
                                        "drop-loss-concealment-budget"
                                    )
                                }
                                if concealmentPacketCount > 0 {
                                    let concealmentFrameCount = max(
                                        minimumPacketSamples,
                                        estimatedSamplesPerPacket
                                    )
                                    var insertedConcealmentCount = 0
                                    for _ in 0 ..< concealmentPacketCount {
                                        guard remainingOutputSlots > 0 else {
                                            registerOutputQueuePressureDrop(
                                                concealmentPacketCount - insertedConcealmentCount,
                                                "drop-loss-concealment-buffer"
                                            )
                                            break
                                        }
                                        guard let silenceBuffer = Self.makeSilentPCMBuffer(
                                            format: decoder.outputFormat,
                                            frameCount: concealmentFrameCount
                                        ) else {
                                            registerOutputQueuePressureDrop(1, "alloc-loss-concealment-buffer")
                                            continue
                                        }
                                        if audioOutput.enqueue(pcmBuffer: silenceBuffer) {
                                            remainingOutputSlots = max(0, remainingOutputSlots - 1)
                                            insertedConcealmentCount += 1
                                        } else {
                                            registerOutputQueuePressureDrop(1, "drop-loss-concealment-buffer")
                                        }
                                    }
                                    if insertedConcealmentCount > 0 {
                                        let previousLossConcealmentEventCount =
                                            lossConcealmentEventCount
                                        lossConcealmentEventCount += insertedConcealmentCount
                                        if lossConcealmentEventCount == insertedConcealmentCount ||
                                            Self.didCounterCrossIntervalBoundary(
                                                previous: previousLossConcealmentEventCount,
                                                current: lossConcealmentEventCount,
                                                interval: 25
                                            )
                                        {
                                            logger.notice(
                                                "Audio packet loss concealment inserted buffers (count=\(lossConcealmentEventCount, privacy: .public), frameSamples=\(concealmentFrameCount, privacy: .public))"
                                            )
                                        }
                                    }
                                }
                            }
                            if let pcmBuffer = try decoder.decode(
                                payload: decodePayload,
                                decodeFEC: false
                            ) {
                                consecutiveDecodeFailures = 0
                                if decoder.requiresPlaybackSafetyGuard {
                                    guard ShadowClientRealtimeAudioPCMBufferGuard.isSafeForPlayback(
                                        pcmBuffer
                                    ) else {
                                        consecutiveDroppedOutputBuffers += 1
                                        if consecutiveDroppedOutputBuffers == 1 ||
                                            consecutiveDroppedOutputBuffers.isMultiple(of: 25)
                                        {
                                            logger.error(
                                                "Sanitizing suspicious decoded audio buffer (count=\(consecutiveDroppedOutputBuffers, privacy: .public), format=\(String(describing: pcmBuffer.format.commonFormat), privacy: .public), channels=\(pcmBuffer.format.channelCount, privacy: .public), frames=\(pcmBuffer.frameLength, privacy: .public))"
                                            )
                                        }
                                        ShadowClientRealtimeAudioPCMBufferGuard.replaceWithSilence(
                                            pcmBuffer
                                        )
                                        if audioOutput.enqueue(pcmBuffer: pcmBuffer) == false {
                                            registerOutputQueuePressureDrop(1, "drop-suspicious-buffer")
                                        } else {
                                            remainingOutputSlots = max(0, remainingOutputSlots - 1)
                                        }
                                        if consecutiveDroppedOutputBuffers >= 150 {
                                            logger.error(
                                                "Audio decoder produced repeated suspicious PCM buffers; continuing with sanitized output to keep session alive."
                                            )
                                            consecutiveDroppedOutputBuffers = 0
                                        }
                                        continue
                                    }
                                }
                                consecutiveDroppedOutputBuffers = 0
                                if audioOutput.enqueue(pcmBuffer: pcmBuffer) == false {
                                    registerOutputQueuePressureDrop(1, "drop-decoded-buffer")
                                    continue
                                }
                                remainingOutputSlots = max(0, remainingOutputSlots - 1)
                            }
                            lastDecodedSequenceNumber = readyPacket.sequenceNumber
                            lastDecodedTimestamp = readyPacket.timestamp
                        } catch {
                            consecutiveDecodeFailures += 1
                            if consecutiveDecodeFailures == 1 ||
                                consecutiveDecodeFailures.isMultiple(of: decodeFailureLogInterval)
                            {
                                logger.error(
                                    "Audio decode failed (count=\(consecutiveDecodeFailures, privacy: .public)): \(error.localizedDescription, privacy: .public)"
                                )
                            }
                            registerOutputQueuePressureDrop(1, "decode-error-drop")
                            if consecutiveDecodeFailures >= decodeFailureAbortThreshold {
                                let message =
                                    "Audio decode repeatedly failed (\(consecutiveDecodeFailures))."
                                logger.error("\(message, privacy: .public)")
                                handleReceiveLoopTermination(
                                    over: connection,
                                    output: audioOutput,
                                    state: .decoderFailed(message)
                                )
                                return
                            }
                            continue
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
        pingTask?.cancel()
        pingTask = nil
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
        pingTask = Task {
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
        let payloadType = Int(datagram[1] & 0x7F)
        let sequenceNumber = (UInt16(datagram[2]) << 8) | UInt16(datagram[3])
        let timestamp = (UInt32(datagram[4]) << 24) |
            (UInt32(datagram[5]) << 16) |
            (UInt32(datagram[6]) << 8) |
            UInt32(datagram[7])

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

    private static func estimatedAudioSamplesPerPacket(
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
        let sampleStep = max(1, sampleRate / 400)
        let normalizedSamples = max(
            minimumPacketSamples,
            min(
                maximumPacketSamples,
                max(sampleStep, (rawSamplesPerPacket / sampleStep) * sampleStep)
            )
        )
        return normalizedSamples
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
        guard observed != ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType else {
            return nil
        }
        guard (96 ... 127).contains(observed) else {
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
        guard normalizedPayload.payloadType != ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType else {
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
        droppedPacketCount: Int
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
        // first and shedding newest overflow packets beyond current output capacity.
        return (0, decodeCount, max(0, readyPacketCount - decodeCount))
    }

    internal static func audioReadyPacketDrainLimit(
        isDecodeCooldownActive: Bool,
        availableOutputSlots: Int,
        maximumDrainBatch: Int = 8
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

    internal static func maximumRecoveredAudioPacketsPerBurst(
        availableOutputSlots: Int
    ) -> Int {
        guard availableOutputSlots > 0 else {
            return 0
        }
        let normalizedSlots = max(1, availableOutputSlots)
        return min(4, max(1, normalizedSlots / 2))
    }

    internal static func maximumConcealmentPacketsPerBurst(
        availableOutputSlots: Int
    ) -> Int {
        guard availableOutputSlots > 0 else {
            return 0
        }
        let normalizedSlots = max(1, availableOutputSlots)
        return min(3, max(1, normalizedSlots / 2))
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
        channels: Int
    ) -> AudioQueuePressureProfile {
        let normalizedSampleRate = max(8_000, sampleRate)
        let normalizedChannels = max(1, channels)
        let estimatedPacketsPerSecond = max(
            25,
            Int((Double(normalizedSampleRate) / 960.0).rounded(.up))
        )
        let pressureSignalInterval = max(
            ShadowClientRealtimeSessionDefaults.audioOutputQueuePressureSignalInterval,
            estimatedPacketsPerSecond / 2
        )
        let pressureTrimInterval = max(
            ShadowClientRealtimeSessionDefaults.audioOutputQueuePressureTrimInterval,
            estimatedPacketsPerSecond
        )
        let pressureTrimToRecentPackets = max(
            4,
            min(
                16,
                max(
                    ShadowClientRealtimeSessionDefaults.audioOutputQueuePressureTrimToRecentPackets,
                    estimatedPacketsPerSecond / 8
                )
            )
        )
        let decodeSheddingLowWatermarkSlots = max(
            ShadowClientRealtimeSessionDefaults.audioOutputQueueDecodeSheddingLowWatermarkSlots,
            normalizedChannels > 2 ? 3 : 2
        )
        let targetQueuedWindowPackets = max(
            8,
            Int((Double(estimatedPacketsPerSecond) * 0.25).rounded(.up))
        )
        let maximumQueuedBuffers = min(
            36,
            max(
                12,
                max(
                    targetQueuedWindowPackets + normalizedChannels,
                    10 + (normalizedChannels * 2)
                )
            )
        )
        return .init(
            pressureSignalInterval: pressureSignalInterval,
            pressureTrimInterval: pressureTrimInterval,
            pressureTrimToRecentPackets: pressureTrimToRecentPackets,
            decodeSheddingLowWatermarkSlots: decodeSheddingLowWatermarkSlots,
            maximumQueuedBuffers: maximumQueuedBuffers
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
                  let nextSequence = nextAvailableSequence(after: expected)
            else {
                markPendingGapWait(expectedSequence: expected, nowUptime: nowUptime)
                break
            }
            clearPendingGapWaitState()
            expectedSequence = nextSequence
        }

        if packetsBySequence.count > maximumDepth {
            let overflowCount = packetsBySequence.count - maximumDepth
            removeOldestBufferedPackets(count: overflowCount)
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

private protocol ShadowClientRealtimeAudioPacketDecoding {
    var codec: ShadowClientAudioCodec { get }
    var sampleRate: Int { get }
    var channels: Int { get }
    var outputFormat: AVAudioFormat { get }
    var requiresPlaybackSafetyGuard: Bool { get }
    func decode(payload: Data) throws -> AVAudioPCMBuffer?
    func decode(payload: Data, decodeFEC: Bool) throws -> AVAudioPCMBuffer?
}

private extension ShadowClientRealtimeAudioPacketDecoding {
    var requiresPlaybackSafetyGuard: Bool { true }

    func decode(payload: Data, decodeFEC _: Bool) throws -> AVAudioPCMBuffer? {
        try decode(payload: payload)
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
    private static let minimumQueuedBufferCount = 16

    private let engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private let engineQueue = DispatchQueue(
        label: "com.skyline23.shadow-client.audio-engine-output",
        qos: .userInitiated
    )
    private let format: AVAudioFormat
    private let maximumQueuedBufferCount: Int
    private let queuedBufferLock = NSLock()
    private var queuedBufferCount = 0
    private var isStarted = false
    private var isTerminated = false
    private var isGraphConfigured = false

    init(
        format: AVAudioFormat,
        maximumQueuedBufferCount: Int = minimumQueuedBufferCount
    ) throws {
        self.format = format
        self.maximumQueuedBufferCount = max(
            Self.minimumQueuedBufferCount,
            maximumQueuedBufferCount
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
        queuedBufferLock.lock()
        if queuedBufferCount >= maximumQueuedBufferCount {
            queuedBufferLock.unlock()
            return false
        }
        queuedBufferCount += 1
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
        let hasCapacity = queuedBufferCount < maximumQueuedBufferCount
        queuedBufferLock.unlock()
        return hasCapacity
    }

    var availableEnqueueSlots: Int {
        queuedBufferLock.lock()
        let available = max(0, maximumQueuedBufferCount - queuedBufferCount)
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
        queuedBufferCount = max(0, queuedBufferCount - 1)
        queuedBufferLock.unlock()
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
