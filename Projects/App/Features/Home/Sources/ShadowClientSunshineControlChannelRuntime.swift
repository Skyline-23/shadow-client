import Foundation
import Network
import os

enum ShadowClientSunshineControlChannelError: Error {
    case connectionTimedOut
    case connectionClosed
    case handshakeTimedOut
    case verifyConnectNotReceived
    case commandAcknowledgeTimedOut
    case invalidEncryptedControlKey
    case encryptedControlEncodingFailed
}

actor ShadowClientSunshineControlChannelRuntime {
    private let connectTimeout: Duration
    private let commandAcknowledgeTimeout: Duration
    private let onRoundTripSample: (@Sendable (Double) async -> Void)?
    private let onControllerFeedback: (@Sendable (ShadowClientSunshineControllerFeedbackEvent) async -> Void)?
    private let queue = DispatchQueue(label: "com.skyline23.shadowclient.control.enet")
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "ControlChannel")

    private var connection: NWConnection?
    private var receiveTask: Task<Void, Never>?
    private var periodicPingTask: Task<Void, Never>?
    private var outgoingPeerID: UInt16 = ShadowClientSunshineENetPacketCodec.maximumPeerID
    private var outgoingSessionID: UInt8 = 0
    private var controlReliableSequenceNumber: UInt16 = 0
    private var outgoingReliableSequenceByChannel: [UInt8: UInt16] = [:]
    private var connectID: UInt32 = 0
    private var controlChannelMode: ShadowClientSunshineControlChannelMode = .plaintext
    private var controlEncryptionCodec: ShadowClientSunshineControlEncryptionCodec?
    private var controlEncryptionSequenceNumber: UInt32 = 0
    private var receivedControllerFeedbackEventCount: Int = 0
    private var receivedControlMessageTypeCounts: [UInt16: Int] = [:]
    private var controlDecryptFailureCount: Int = 0

    init(
        connectTimeout: Duration = ShadowClientSunshineControlChannelDefaults.connectTimeout,
        commandAcknowledgeTimeout: Duration = ShadowClientSunshineControlChannelDefaults.commandAcknowledgeTimeout,
        onRoundTripSample: (@Sendable (Double) async -> Void)? = nil,
        onControllerFeedback: (@Sendable (ShadowClientSunshineControllerFeedbackEvent) async -> Void)? = nil
    ) {
        self.connectTimeout = connectTimeout
        self.commandAcknowledgeTimeout = commandAcknowledgeTimeout
        self.onRoundTripSample = onRoundTripSample
        self.onControllerFeedback = onControllerFeedback
    }

    func start(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        connectData: UInt32?,
        mode: ShadowClientSunshineControlChannelMode = .plaintext
    ) async throws {
        stop()
        do {
            switch mode {
            case .plaintext:
                controlEncryptionCodec = nil
            case let .encryptedV2(key):
                controlEncryptionCodec = try ShadowClientSunshineControlEncryptionCodec(keyData: key)
            }
        } catch {
            throw ShadowClientSunshineControlChannelError.invalidEncryptedControlKey
        }
        controlChannelMode = mode

        let connection = NWConnection(host: host, port: port, using: .udp)
        self.connection = connection
        resetSessionState()

        do {
            try await waitForReady(connection)

            connectID = UInt32.random(in: .min ... .max)
            controlReliableSequenceNumber = 1

            let connectPacket = ShadowClientSunshineENetPacketCodec.makeConnectPacket(
                connectID: connectID,
                connectData: connectData ?? 0,
                sentTime: currentSentTime()
            )
            try await Self.send(bytes: connectPacket, over: connection)

            let verify = try await waitForVerifyConnect(over: connection, expectedConnectID: connectID)
            outgoingPeerID = verify.outgoingPeerID
            outgoingSessionID = verify.outgoingSessionID & ShadowClientSunshineENetProtocolProfile.sessionValueMask

            try await acknowledge(
                commandChannelID: verify.commandChannelID,
                receivedReliableSequenceNumber: verify.commandReliableSequenceNumber,
                receivedSentTime: verify.receivedSentTime,
                over: connection
            )
            try await sendBootstrapStartMessages(over: connection)

            logger.notice(
                "Sunshine ENet control bootstrap ready on UDP \(port.rawValue, privacy: .public) peer=\(self.outgoingPeerID, privacy: .public)"
            )

            receiveTask = Task { [weak self] in
                guard let self else {
                    return
                }
                await self.receiveLoop(over: connection)
            }
            periodicPingTask = Task { [weak self] in
                guard let self else {
                    return
                }
                await self.periodicPingLoop(over: connection)
            }
        } catch {
            connection.cancel()
            self.connection = nil
            resetSessionState()
            throw error
        }
    }

    func stop() {
        periodicPingTask?.cancel()
        periodicPingTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        connection?.cancel()
        connection = nil
        controlEncryptionCodec = nil
        controlChannelMode = .plaintext
        resetSessionState()
    }

    func sendInputPacket(_ payload: Data, channelID: UInt8) async throws {
        guard let connection else {
            throw ShadowClientSunshineControlChannelError.connectionClosed
        }

        // Input events are high-frequency and the receive loop is already responsible
        // for processing ACKs. Waiting for ACK here can race with the receive loop and
        // cause dropped input when the ACK is consumed by the background receiver first.
        try await sendReliableControlMessageWithoutBlockingForAcknowledge(
            type: ShadowClientSunshineControlMessageProfile.inputDataType,
            payload: payload,
            channelID: channelID,
            over: connection
        )
    }

    func requestVideoRecoveryFrame(lastSeenFrameIndex: UInt32?) async {
        guard let connection else {
            return
        }

        let request = controlChannelMode.makeIDRRequest(lastSeenFrameIndex: lastSeenFrameIndex)
        do {
            try await sendReliableControlMessageWithoutBlockingForAcknowledge(
                type: request.type,
                payload: request.payload,
                channelID: request.channelID,
                over: connection
            )
            logger.notice(
                "Sunshine video recovery request sent type=\(request.type, privacy: .public) channel=\(request.channelID, privacy: .public)"
            )
        } catch {
            logger.error("Sunshine video recovery request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func requestInvalidateReferenceFrames(
        startFrameIndex: UInt32,
        endFrameIndex: UInt32
    ) async {
        guard let connection else {
            return
        }

        let request = controlChannelMode.makeReferenceFrameInvalidationRequest(
            startFrameIndex: startFrameIndex,
            endFrameIndex: endFrameIndex
        )
        do {
            try await sendReliableControlMessageWithoutBlockingForAcknowledge(
                type: request.type,
                payload: request.payload,
                channelID: request.channelID,
                over: connection
            )
            logger.notice(
                "Sunshine reference frame invalidation request sent type=\(request.type, privacy: .public) channel=\(request.channelID, privacy: .public) range=\(startFrameIndex, privacy: .public)-\(endFrameIndex, privacy: .public)"
            )
        } catch {
            logger.error(
                "Sunshine reference frame invalidation request failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func waitForVerifyConnect(
        over connection: NWConnection,
        expectedConnectID: UInt32
    ) async throws -> ShadowClientSunshineENetPacketCodec.VerifyConnect {
        let timeout = connectTimeout
        return try await withThrowingTaskGroup(
            of: ShadowClientSunshineENetPacketCodec.VerifyConnect.self,
            returning: ShadowClientSunshineENetPacketCodec.VerifyConnect.self
        ) { group in
            group.addTask {
                try await Self.receiveVerifyConnect(
                    over: connection,
                    expectedConnectID: expectedConnectID
                )
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw ShadowClientSunshineControlChannelError.handshakeTimedOut
            }

            guard let verify = try await group.next() else {
                group.cancelAll()
                throw ShadowClientSunshineControlChannelError.verifyConnectNotReceived
            }
            group.cancelAll()
            return verify
        }
    }

    private func acknowledge(
        commandChannelID: UInt8,
        receivedReliableSequenceNumber: UInt16,
        receivedSentTime: UInt16,
        over connection: NWConnection
    ) async throws {
        let acknowledgeSequence = nextReliableSequenceNumber(for: commandChannelID)
        let packet = ShadowClientSunshineENetPacketCodec.makeAcknowledgePacket(
            outgoingPeerID: outgoingPeerID,
            outgoingSessionID: outgoingSessionID,
            outgoingReliableSequenceNumber: acknowledgeSequence,
            commandChannelID: commandChannelID,
            receivedReliableSequenceNumber: receivedReliableSequenceNumber,
            receivedSentTime: receivedSentTime,
            sentTime: currentSentTime()
        )
        try await Self.send(bytes: packet, over: connection)
    }

    private func receiveLoop(over connection: NWConnection) async {
        while !Task.isCancelled {
            do {
                let datagram = try await Self.receiveDatagram(over: connection)
                guard let packet = ShadowClientSunshineENetPacketCodec.parsePacket(datagram) else {
                    continue
                }

                for command in packet.commands {
                    await reportRoundTripSampleIfAvailable(
                        from: packet,
                        command: command
                    )

                    if let feedbackEvent = parseControllerFeedbackEvent(
                        from: packet,
                        command: command
                    ) {
                        reportControllerFeedbackEventIfNeeded(feedbackEvent)
                        await onControllerFeedback?(feedbackEvent)
                    }

                    guard command.isAcknowledgeRequired else {
                        continue
                    }
                    guard let sentTime = packet.sentTime else {
                        continue
                    }
                    try await acknowledge(
                        commandChannelID: command.channelID,
                        receivedReliableSequenceNumber: command.reliableSequenceNumber,
                        receivedSentTime: sentTime,
                        over: connection
                    )
                }
            } catch {
                if !Task.isCancelled {
                    logger.debug("Sunshine ENet control receive loop ended: \(error.localizedDescription, privacy: .public)")
                }
                break
            }
        }
    }

    private func sendBootstrapStartMessages(over connection: NWConnection) async throws {
        try await sendReliableControlMessage(
            type: controlChannelMode.startAType,
            payload: controlChannelMode.startAPayload,
            over: connection
        )

        try await sendReliableControlMessage(
            type: controlChannelMode.startBType,
            payload: controlChannelMode.startBPayload,
            over: connection
        )
    }

    private func sendReliableControlMessage(
        type: UInt16,
        payload: Data,
        channelID: UInt8 = ShadowClientSunshineControlMessageProfile.genericChannelID,
        over connection: NWConnection
    ) async throws {
        let controlPayload = try buildControlPayload(type: type, payload: payload)
        let reliableSequenceNumber = nextReliableSequenceNumber(for: channelID)
        let controlModeLabel = controlEncryptionCodec == nil ? "plain" : "enc-v2"
        logger.notice(
            "Sunshine control send type=\(type, privacy: .public) relSeq=\(reliableSequenceNumber, privacy: .public) payloadBytes=\(controlPayload.count, privacy: .public) mode=\(controlModeLabel, privacy: .public)"
        )
        let packet = try ShadowClientSunshineENetPacketCodec.makeSendReliablePacket(
            outgoingPeerID: outgoingPeerID,
            outgoingSessionID: outgoingSessionID,
            reliableSequenceNumber: reliableSequenceNumber,
            channelID: channelID,
            sentTime: currentSentTime(),
            payload: controlPayload
        )
        try await Self.send(bytes: packet, over: connection)
        try await waitForAcknowledge(
            over: connection,
            expectedReliableSequenceNumber: reliableSequenceNumber
        )
    }

    private func sendReliableControlMessageWithoutBlockingForAcknowledge(
        type: UInt16,
        payload: Data,
        channelID: UInt8 = ShadowClientSunshineControlMessageProfile.genericChannelID,
        over connection: NWConnection
    ) async throws {
        let controlPayload = try buildControlPayload(type: type, payload: payload)
        let reliableSequenceNumber = nextReliableSequenceNumber(for: channelID)
        let packet = try ShadowClientSunshineENetPacketCodec.makeSendReliablePacket(
            outgoingPeerID: outgoingPeerID,
            outgoingSessionID: outgoingSessionID,
            reliableSequenceNumber: reliableSequenceNumber,
            channelID: channelID,
            sentTime: currentSentTime(),
            payload: controlPayload
        )
        try await Self.send(bytes: packet, over: connection)
    }

    private func buildControlPayload(
        type: UInt16,
        payload: Data
    ) throws -> Data {
        if let controlEncryptionCodec {
            do {
                let encryptedPayload = try controlEncryptionCodec.encryptControlMessage(
                    type: type,
                    payload: payload,
                    sequence: controlEncryptionSequenceNumber
                )
                controlEncryptionSequenceNumber &+= 1
                return encryptedPayload
            } catch {
                logger.error("Sunshine encrypted control payload encoding failed: \(error.localizedDescription, privacy: .public)")
                throw ShadowClientSunshineControlChannelError.encryptedControlEncodingFailed
            }
        }

        return ShadowClientSunshineENetPacketCodec.makeControlMessagePayload(
            type: type,
            payload: payload
        )
    }

    private func waitForAcknowledge(
        over connection: NWConnection,
        expectedReliableSequenceNumber: UInt16
    ) async throws {
        let timeout = commandAcknowledgeTimeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.receiveUntilAcknowledge(
                    over: connection,
                    expectedReliableSequenceNumber: expectedReliableSequenceNumber
                )
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ShadowClientSunshineControlChannelError.commandAcknowledgeTimedOut
            }

            _ = try await group.next()
            group.cancelAll()
        }
    }

    private func receiveUntilAcknowledge(
        over connection: NWConnection,
        expectedReliableSequenceNumber: UInt16
    ) async throws {
        while !Task.isCancelled {
            let datagram = try await Self.receiveDatagram(over: connection)
            logger.notice(
                "Sunshine control ACK wait datagram bytes=\(datagram.count, privacy: .public) expectedRelSeq=\(expectedReliableSequenceNumber, privacy: .public)"
            )
            guard let packet = ShadowClientSunshineENetPacketCodec.parsePacket(datagram) else {
                logger.error("Sunshine control ACK wait failed to parse ENet packet")
                continue
            }

            for command in packet.commands {
                await reportRoundTripSampleIfAvailable(
                    from: packet,
                    command: command
                )

                logger.notice(
                    "Sunshine control ACK wait command number=\(command.number, privacy: .public) flags=\(command.flags, privacy: .public) relSeq=\(command.reliableSequenceNumber, privacy: .public) channel=\(command.channelID, privacy: .public)"
                )
                if command.isAcknowledgeRequired, let sentTime = packet.sentTime {
                    try await acknowledge(
                        commandChannelID: command.channelID,
                        receivedReliableSequenceNumber: command.reliableSequenceNumber,
                        receivedSentTime: sentTime,
                        over: connection
                    )
                }

                if let acknowledge = ShadowClientSunshineENetPacketCodec.parseAcknowledge(
                    from: packet,
                    command: command
                ), acknowledge.receivedReliableSequenceNumber == expectedReliableSequenceNumber {
                    logger.notice(
                        "Sunshine control ACK matched relSeq=\(acknowledge.receivedReliableSequenceNumber, privacy: .public)"
                    )
                    return
                }
            }
        }

        throw ShadowClientSunshineControlChannelError.commandAcknowledgeTimedOut
    }

    private func reportRoundTripSampleIfAvailable(
        from packet: ShadowClientSunshineENetPacketCodec.ParsedPacket,
        command: ShadowClientSunshineENetPacketCodec.ParsedPacket.Command
    ) async {
        guard let acknowledge = ShadowClientSunshineENetPacketCodec.parseAcknowledge(
            from: packet,
            command: command
        ) else {
            return
        }

        let roundTripSampleMs = Self.roundTripMilliseconds(
            nowSentTime: currentSentTime(),
            echoedSentTime: acknowledge.receivedSentTime
        )
        guard roundTripSampleMs.isFinite,
              roundTripSampleMs >= 0,
              roundTripSampleMs <= ShadowClientSunshineControlChannelDefaults.maximumRoundTripSampleMs
        else {
            return
        }

        await onRoundTripSample?(roundTripSampleMs)
    }

    private func parseControllerFeedbackEvent(
        from packet: ShadowClientSunshineENetPacketCodec.ParsedPacket,
        command: ShadowClientSunshineENetPacketCodec.ParsedPacket.Command
    ) -> ShadowClientSunshineControllerFeedbackEvent? {
        guard command.number == ShadowClientSunshineENetProtocolProfile.protocolCommandSendReliable else {
            return nil
        }

        let commandBase = command.offset
        guard commandBase + 6 <= packet.rawData.count else {
            return nil
        }

        let payloadLength = Int(readUInt16BE(packet.rawData, at: commandBase + 4))
        let payloadStart = commandBase + 6
        guard payloadLength >= 2,
              payloadStart + payloadLength <= packet.rawData.count
        else {
            return nil
        }

        var controlPayload = Data(packet.rawData[payloadStart ..< (payloadStart + payloadLength)])

        if let controlEncryptionCodec {
            do {
                controlPayload = try controlEncryptionCodec.decryptControlMessageToV1(controlPayload)
            } catch {
                controlDecryptFailureCount &+= 1
                if controlDecryptFailureCount <= 8 || controlDecryptFailureCount.isMultiple(of: 60) {
                    logger.error(
                        "RUMBLE TRACE control decrypt failed #\(self.controlDecryptFailureCount, privacy: .public): \(error.localizedDescription, privacy: .public)"
                    )
                }
                return nil
            }
        }

        guard controlPayload.count >= 2 else {
            return nil
        }

        let type = readUInt16LE(controlPayload, at: 0)
        let payload = Data(controlPayload.dropFirst(2))
        reportControlMessageTypeIfNeeded(type: type, payloadBytes: payload.count)
        return ShadowClientSunshineControlFeedbackCodec.parse(type: type, payload: payload)
    }

    private func reportControllerFeedbackEventIfNeeded(
        _ event: ShadowClientSunshineControllerFeedbackEvent
    ) {
        receivedControllerFeedbackEventCount &+= 1
        guard receivedControllerFeedbackEventCount <= 16 ||
                receivedControllerFeedbackEventCount.isMultiple(of: 120)
        else {
            return
        }

        logger.notice(
            "RUMBLE TRACE control feedback #\(self.receivedControllerFeedbackEventCount, privacy: .public): \(self.controllerFeedbackSummary(for: event), privacy: .public)"
        )
    }

    private func controllerFeedbackSummary(
        for event: ShadowClientSunshineControllerFeedbackEvent
    ) -> String {
        switch event {
        case let .rumble(rumble):
            return "rumble controller=\(rumble.controllerNumber) low=\(rumble.lowFrequencyMotor) high=\(rumble.highFrequencyMotor)"
        case let .triggerRumble(trigger):
            return "trigger controller=\(trigger.controllerNumber) left=\(trigger.leftTriggerMotor) right=\(trigger.rightTriggerMotor)"
        }
    }

    private func reportControlMessageTypeIfNeeded(
        type: UInt16,
        payloadBytes: Int
    ) {
        let count = (receivedControlMessageTypeCounts[type] ?? 0) + 1
        receivedControlMessageTypeCounts[type] = count

        guard count <= 6 || count.isMultiple(of: 120) else {
            return
        }

        logger.notice(
            "RUMBLE TRACE control message type=0x\(String(type, radix: 16), privacy: .public) name=\(self.controlMessageName(type), privacy: .public) count=\(count, privacy: .public) payloadBytes=\(payloadBytes, privacy: .public)"
        )
    }

    private func controlMessageName(_ type: UInt16) -> String {
        switch type {
        case ShadowClientSunshineControlMessageProfile.startATypeLegacy:
            return "startA-legacy"
        case ShadowClientSunshineControlMessageProfile.startATypeEncryptedV2:
            return "startA-encryptedV2"
        case ShadowClientSunshineControlMessageProfile.startBType:
            return "startB"
        case ShadowClientSunshineControlMessageProfile.periodicPingType:
            return "periodicPing"
        case ShadowClientSunshineControlMessageProfile.inputDataType:
            return "inputData"
        case ShadowClientSunshineControlMessageProfile.invalidateReferenceFramesType:
            return "invalidateReferenceFrames"
        case ShadowClientSunshineControlMessageProfile.rumbleType:
            return "rumble"
        case ShadowClientSunshineControlMessageProfile.rumbleTriggersType:
            return "triggerRumble"
        default:
            return "unknown"
        }
    }

    private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1]) << 8
        return b0 | b1
    }

    private func readUInt16BE(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset]) << 8
        let b1 = UInt16(data[offset + 1])
        return b0 | b1
    }

    private func periodicPingLoop(over connection: NWConnection) async {
        var didLogFailure = false
        while !Task.isCancelled {
            do {
                try await sendReliableControlMessageWithoutBlockingForAcknowledge(
                    type: ShadowClientSunshineControlMessageProfile.periodicPingType,
                    payload: ShadowClientSunshineControlMessageProfile.periodicPingPayload,
                    over: connection
                )
            } catch {
                if !didLogFailure {
                    logger.error("Sunshine control periodic ping failed: \(error.localizedDescription, privacy: .public)")
                    didLogFailure = true
                }
            }
            try? await Task.sleep(for: ShadowClientSunshineControlMessageProfile.periodicPingInterval)
        }
    }

    private func waitForReady(_ connection: NWConnection) async throws {
        let timeout = connectTimeout
        let result = await withTaskGroup(
            of: Result<Void, Error>.self,
            returning: Result<Void, Error>.self
        ) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    final class ResumeGate: @unchecked Sendable {
                        private let lock = NSLock()
                        private let connection: NWConnection
                        private var continuation: CheckedContinuation<Result<Void, Error>, Never>?

                        init(
                            connection: NWConnection,
                            continuation: CheckedContinuation<Result<Void, Error>, Never>
                        ) {
                            self.connection = connection
                            self.continuation = continuation
                        }

                        func finish(_ result: Result<Void, Error>) {
                            lock.lock()
                            guard let continuation else {
                                lock.unlock()
                                return
                            }
                            self.continuation = nil
                            lock.unlock()

                            connection.stateUpdateHandler = nil
                            continuation.resume(returning: result)
                        }
                    }

                    let gate = ResumeGate(connection: connection, continuation: continuation)
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            gate.finish(.success(()))
                        case let .failed(error):
                            gate.finish(.failure(error))
                        case .cancelled:
                            gate.finish(.failure(ShadowClientSunshineControlChannelError.connectionClosed))
                        default:
                            break
                        }
                    }
                    connection.start(queue: self.queue)
                }
            }

            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    connection.cancel()
                    return .failure(ShadowClientSunshineControlChannelError.connectionTimedOut)
                } catch {
                    return .failure(error)
                }
            }

            let first = await group.next() ?? .failure(ShadowClientSunshineControlChannelError.connectionTimedOut)
            group.cancelAll()
            return first
        }

        try result.get()
    }

    private func resetSessionState() {
        outgoingPeerID = ShadowClientSunshineENetPacketCodec.maximumPeerID
        outgoingSessionID = 0
        controlReliableSequenceNumber = 0
        outgoingReliableSequenceByChannel.removeAll(keepingCapacity: false)
        connectID = 0
        controlEncryptionSequenceNumber = 0
        receivedControllerFeedbackEventCount = 0
        receivedControlMessageTypeCounts.removeAll(keepingCapacity: false)
        controlDecryptFailureCount = 0
    }

    private func nextReliableSequenceNumber(for channelID: UInt8) -> UInt16 {
        if channelID == ShadowClientSunshineENetProtocolProfile.wildcardSessionID {
            controlReliableSequenceNumber &+= 1
            return controlReliableSequenceNumber
        }

        var sequence = outgoingReliableSequenceByChannel[channelID] ?? 0
        sequence &+= 1
        outgoingReliableSequenceByChannel[channelID] = sequence
        return sequence
    }

    private func currentSentTime() -> UInt16 {
        UInt16(truncatingIfNeeded: DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    private static func roundTripMilliseconds(
        nowSentTime: UInt16,
        echoedSentTime: UInt16
    ) -> Double {
        Double(nowSentTime &- echoedSentTime)
    }

    private static func receiveVerifyConnect(
        over connection: NWConnection,
        expectedConnectID: UInt32
    ) async throws -> ShadowClientSunshineENetPacketCodec.VerifyConnect {
        while !Task.isCancelled {
            let datagram = try await receiveDatagram(over: connection)
            guard let packet = ShadowClientSunshineENetPacketCodec.parsePacket(datagram),
                  let verify = ShadowClientSunshineENetPacketCodec.parseVerifyConnect(from: packet)
            else {
                continue
            }

            if verify.connectID == expectedConnectID {
                return verify
            }
        }

        throw ShadowClientSunshineControlChannelError.verifyConnectNotReceived
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

    private static func receiveDatagram(over connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            connection.receiveMessage { content, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let content else {
                    continuation.resume(throwing: ShadowClientSunshineControlChannelError.connectionClosed)
                    return
                }
                continuation.resume(returning: content)
            }
        }
    }
}
