import Foundation
import Network
import os

enum ShadowClientHostControlChannelError: Error {
    case connectionTimedOut
    case connectionClosed
    case handshakeTimedOut
    case verifyConnectNotReceived
    case commandAcknowledgeTimedOut
    case invalidEncryptedControlKey
    case encryptedControlEncodingFailed
}

actor ShadowClientHostControlChannelRuntime {
    private let connectTimeout: Duration
    private let commandAcknowledgeTimeout: Duration
    private let prioritizeNetworkTraffic: Bool
    private let onRoundTripSample: (@Sendable (Double) async -> Void)?
    private let onControllerFeedback: (@Sendable (ShadowClientHostControllerFeedbackEvent) async -> Void)?
    private let onHDRMode: (@Sendable (ShadowClientHostHDRModeEvent) async -> Void)?
    private let onHDRFrameState: (@Sendable (ShadowClientHDRFrameState) async -> Void)?
    private let onTermination: (@Sendable (ShadowClientHostTerminationEvent) async -> Void)?
    private let queue = DispatchQueue(
        label: "com.skyline23.shadowclient.control.enet",
        qos: .userInitiated
    )
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "ControlChannel")

    private var connection: NWConnection?
    private var receiveTask: Task<Void, Never>?
    private var periodicPingTask: Task<Void, Never>?
    private var outgoingPeerID: UInt16 = ShadowClientHostENetPacketCodec.maximumPeerID
    private var outgoingSessionID: UInt8 = 0
    private var controlReliableSequenceNumber: UInt16 = 0
    private var outgoingReliableSequenceByChannel: [UInt8: UInt16] = [:]
    private var connectID: UInt32 = 0
    private var controlChannelMode: ShadowClientHostControlChannelMode?
    private var controlEncryptionCodec: ShadowClientHostControlEncryptionCodec?
    private var controlEncryptionSequenceNumber: UInt32 = 0
    private var receivedControllerFeedbackEventCount: Int = 0
    private var receivedHDRModeEventCount: Int = 0
    private var receivedControlMessageTypeCounts: [UInt16: Int] = [:]
    private var controlDecryptFailureCount: Int = 0

    init(
        connectTimeout: Duration = ShadowClientHostControlChannelDefaults.connectTimeout,
        commandAcknowledgeTimeout: Duration = ShadowClientHostControlChannelDefaults.commandAcknowledgeTimeout,
        prioritizeNetworkTraffic: Bool = false,
        onRoundTripSample: (@Sendable (Double) async -> Void)? = nil,
        onControllerFeedback: (@Sendable (ShadowClientHostControllerFeedbackEvent) async -> Void)? = nil,
        onHDRMode: (@Sendable (ShadowClientHostHDRModeEvent) async -> Void)? = nil,
        onHDRFrameState: (@Sendable (ShadowClientHDRFrameState) async -> Void)? = nil,
        onTermination: (@Sendable (ShadowClientHostTerminationEvent) async -> Void)? = nil
    ) {
        self.connectTimeout = connectTimeout
        self.commandAcknowledgeTimeout = commandAcknowledgeTimeout
        self.prioritizeNetworkTraffic = prioritizeNetworkTraffic
        self.onRoundTripSample = onRoundTripSample
        self.onControllerFeedback = onControllerFeedback
        self.onHDRMode = onHDRMode
        self.onHDRFrameState = onHDRFrameState
        self.onTermination = onTermination
    }

    func start(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        connectData: UInt32?,
        mode: ShadowClientHostControlChannelMode
    ) async throws {
        stop()
        do {
            switch mode {
            case .plaintext:
                controlEncryptionCodec = nil
            case let .encryptedV2(key):
                controlEncryptionCodec = try ShadowClientHostControlEncryptionCodec(keyData: key)
            }
        } catch {
            throw ShadowClientHostControlChannelError.invalidEncryptedControlKey
        }
        controlChannelMode = mode

        let connection = NWConnection(
            host: host,
            port: port,
            using: ShadowClientStreamingTrafficPolicy.udpParameters(
                trafficClass: ShadowClientStreamingTrafficPolicy.control(
                    prioritized: prioritizeNetworkTraffic
                )
            )
        )
        self.connection = connection
        resetSessionState()

        do {
            try await waitForReady(connection)

            connectID = UInt32.random(in: .min ... .max)
            controlReliableSequenceNumber = 1

            let connectPacket = ShadowClientHostENetPacketCodec.makeConnectPacket(
                connectID: connectID,
                connectData: connectData ?? 0,
                sentTime: currentSentTime()
            )
            try await Self.send(bytes: connectPacket, over: connection)

            let verify = try await waitForVerifyConnect(over: connection, expectedConnectID: connectID)
            outgoingPeerID = verify.outgoingPeerID
            outgoingSessionID = verify.outgoingSessionID & ShadowClientHostENetProtocolProfile.sessionValueMask

            try await acknowledge(
                commandChannelID: verify.commandChannelID,
                receivedReliableSequenceNumber: verify.commandReliableSequenceNumber,
                receivedSentTime: verify.receivedSentTime,
                over: connection
            )
            try await sendBootstrapStartMessages(over: connection)

            logger.notice(
                "Lumen ENet control bootstrap ready on UDP \(port.rawValue, privacy: .public) peer=\(self.outgoingPeerID, privacy: .public)"
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
        controlChannelMode = nil
        resetSessionState()
    }

    func sendInputPacket(_ payload: Data, channelID: UInt8) async throws {
        guard let connection else {
            throw ShadowClientHostControlChannelError.connectionClosed
        }

        // Input events are high-frequency and the receive loop is already responsible
        // for processing ACKs. Waiting for ACK here can race with the receive loop and
        // cause dropped input when the ACK is consumed by the background receiver first.
        try await sendReliableControlMessageWithoutBlockingForAcknowledge(
            type: ShadowClientHostControlMessageProfile.inputDataType,
            payload: payload,
            channelID: channelID,
            over: connection
        )
    }

    func sendInputKeepAlive() async throws {
        guard let connection else {
            throw ShadowClientHostControlChannelError.connectionClosed
        }

        try await sendReliableControlMessageWithoutBlockingForAcknowledge(
            type: ShadowClientHostControlMessageProfile.periodicPingType,
            payload: ShadowClientHostControlMessageProfile.periodicPingPayload,
            over: connection
        )
    }

    func requestVideoRecoveryFrame(lastSeenFrameIndex: UInt32?) async {
        guard let connection else {
            return
        }
        guard let controlChannelMode else {
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
                "Lumen video recovery request sent type=\(request.type, privacy: .public) channel=\(request.channelID, privacy: .public)"
            )
        } catch {
            logger.error("Lumen video recovery request failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func requestInvalidateReferenceFrames(
        startFrameIndex: UInt32,
        endFrameIndex: UInt32
    ) async {
        guard let connection else {
            return
        }
        guard let controlChannelMode else {
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
                "Lumen reference frame invalidation request sent type=\(request.type, privacy: .public) channel=\(request.channelID, privacy: .public) range=\(startFrameIndex, privacy: .public)-\(endFrameIndex, privacy: .public)"
            )
        } catch {
            logger.error(
                "Lumen reference frame invalidation request failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func waitForVerifyConnect(
        over connection: NWConnection,
        expectedConnectID: UInt32
    ) async throws -> ShadowClientHostENetPacketCodec.VerifyConnect {
        let timeout = connectTimeout
        return try await withThrowingTaskGroup(
            of: ShadowClientHostENetPacketCodec.VerifyConnect.self,
            returning: ShadowClientHostENetPacketCodec.VerifyConnect.self
        ) { group in
            group.addTask {
                try await Self.receiveVerifyConnect(
                    over: connection,
                    expectedConnectID: expectedConnectID
                )
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw ShadowClientHostControlChannelError.handshakeTimedOut
            }

            guard let verify = try await group.next() else {
                group.cancelAll()
                throw ShadowClientHostControlChannelError.verifyConnectNotReceived
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
        let packet = ShadowClientHostENetPacketCodec.makeAcknowledgePacket(
            outgoingPeerID: outgoingPeerID,
            outgoingSessionID: outgoingSessionID,
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
                guard let packet = ShadowClientHostENetPacketCodec.parsePacket(datagram) else {
                    continue
                }

                for command in packet.commands {
                    await reportRoundTripSampleIfAvailable(
                        from: packet,
                        command: command
                    )
                    await processIncomingControlEvents(
                        from: packet,
                        command: command
                    )

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
                    logger.debug("Lumen ENet control receive loop ended: \(error.localizedDescription, privacy: .public)")
                }
                break
            }
        }
    }

    private func sendBootstrapStartMessages(over connection: NWConnection) async throws {
        guard let controlChannelMode else {
            throw ShadowClientHostControlChannelError.connectionClosed
        }

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
        channelID: UInt8 = ShadowClientHostControlMessageProfile.genericChannelID,
        over connection: NWConnection
    ) async throws {
        let controlPayload = try buildControlPayload(type: type, payload: payload)
        let reliableSequenceNumber = nextReliableSequenceNumber(for: channelID)
        let controlModeLabel = controlEncryptionCodec == nil ? "plain" : "enc-v2"
        logger.notice(
            "Lumen control send type=\(type, privacy: .public) relSeq=\(reliableSequenceNumber, privacy: .public) payloadBytes=\(controlPayload.count, privacy: .public) mode=\(controlModeLabel, privacy: .public)"
        )
        let packet = try ShadowClientHostENetPacketCodec.makeSendReliablePacket(
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
        channelID: UInt8 = ShadowClientHostControlMessageProfile.genericChannelID,
        over connection: NWConnection
    ) async throws {
        let controlPayload = try buildControlPayload(type: type, payload: payload)
        let reliableSequenceNumber = nextReliableSequenceNumber(for: channelID)
        let packet = try ShadowClientHostENetPacketCodec.makeSendReliablePacket(
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
                logger.error("Lumen encrypted control payload encoding failed: \(error.localizedDescription, privacy: .public)")
                throw ShadowClientHostControlChannelError.encryptedControlEncodingFailed
            }
        }

        return ShadowClientHostENetPacketCodec.makeControlMessagePayload(
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
                throw ShadowClientHostControlChannelError.commandAcknowledgeTimedOut
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
                "Lumen control ACK wait datagram bytes=\(datagram.count, privacy: .public) expectedRelSeq=\(expectedReliableSequenceNumber, privacy: .public)"
            )
            guard let packet = ShadowClientHostENetPacketCodec.parsePacket(datagram) else {
                logger.error("Lumen control ACK wait failed to parse ENet packet")
                continue
            }

            for command in packet.commands {
                await reportRoundTripSampleIfAvailable(
                    from: packet,
                    command: command
                )
                await processIncomingControlEvents(
                    from: packet,
                    command: command
                )

                logger.notice(
                    "Lumen control ACK wait command number=\(command.number, privacy: .public) flags=\(command.flags, privacy: .public) relSeq=\(command.reliableSequenceNumber, privacy: .public) channel=\(command.channelID, privacy: .public)"
                )
                if command.isAcknowledgeRequired, let sentTime = packet.sentTime {
                    try await acknowledge(
                        commandChannelID: command.channelID,
                        receivedReliableSequenceNumber: command.reliableSequenceNumber,
                        receivedSentTime: sentTime,
                        over: connection
                    )
                }

                if let acknowledge = ShadowClientHostENetPacketCodec.parseAcknowledge(
                    from: packet,
                    command: command
                ), acknowledge.receivedReliableSequenceNumber == expectedReliableSequenceNumber {
                    logger.notice(
                        "Lumen control ACK matched relSeq=\(acknowledge.receivedReliableSequenceNumber, privacy: .public)"
                    )
                    return
                }
            }
        }

        throw ShadowClientHostControlChannelError.commandAcknowledgeTimedOut
    }

    private func reportRoundTripSampleIfAvailable(
        from packet: ShadowClientHostENetPacketCodec.ParsedPacket,
        command: ShadowClientHostENetPacketCodec.ParsedPacket.Command
    ) async {
        guard let acknowledge = ShadowClientHostENetPacketCodec.parseAcknowledge(
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
              roundTripSampleMs <= ShadowClientHostControlChannelDefaults.maximumRoundTripSampleMs
        else {
            return
        }

        await onRoundTripSample?(roundTripSampleMs)
    }

    private func parseControllerFeedbackEvent(
        from packet: ShadowClientHostENetPacketCodec.ParsedPacket,
        command: ShadowClientHostENetPacketCodec.ParsedPacket.Command
    ) -> ShadowClientHostControllerFeedbackEvent? {
        guard let controlPayload = parseControlPayload(from: packet, command: command) else {
            return nil
        }

        let type = readUInt16LE(controlPayload, at: 0)
        let payload = Data(controlPayload.dropFirst(2))
        reportControlMessageTypeIfNeeded(type: type, payloadBytes: payload.count)
        return ShadowClientHostControlFeedbackCodec.parse(type: type, payload: payload)
    }

    private func parseTerminationEvent(
        from packet: ShadowClientHostENetPacketCodec.ParsedPacket,
        command: ShadowClientHostENetPacketCodec.ParsedPacket.Command
    ) -> ShadowClientHostTerminationEvent? {
        guard let controlPayload = parseControlPayload(from: packet, command: command) else {
            return nil
        }

        let type = readUInt16LE(controlPayload, at: 0)
        let payload = Data(controlPayload.dropFirst(2))
        return ShadowClientHostControlFeedbackCodec.parseTermination(
            type: type,
            payload: payload
        )
    }

    private func parseHDRModeEvent(
        from packet: ShadowClientHostENetPacketCodec.ParsedPacket,
        command: ShadowClientHostENetPacketCodec.ParsedPacket.Command
    ) -> ShadowClientHostHDRModeEvent? {
        guard let controlPayload = parseControlPayload(from: packet, command: command) else {
            return nil
        }

        let type = readUInt16LE(controlPayload, at: 0)
        let payload = Data(controlPayload.dropFirst(2))
        return ShadowClientHostControlFeedbackCodec.parseHDRMode(
            type: type,
            payload: payload
        )
    }

    private func parseHDRFrameStateEvent(
        from packet: ShadowClientHostENetPacketCodec.ParsedPacket,
        command: ShadowClientHostENetPacketCodec.ParsedPacket.Command
    ) -> ShadowClientHDRFrameState? {
        guard let controlPayload = parseControlPayload(from: packet, command: command) else {
            return nil
        }

        let type = readUInt16LE(controlPayload, at: 0)
        let payload = Data(controlPayload.dropFirst(2))
        return ShadowClientHostControlFeedbackCodec.parseHDRFrameState(
            type: type,
            payload: payload
        )
    }

    private func processIncomingControlEvents(
        from packet: ShadowClientHostENetPacketCodec.ParsedPacket,
        command: ShadowClientHostENetPacketCodec.ParsedPacket.Command
    ) async {
        if let feedbackEvent = parseControllerFeedbackEvent(
            from: packet,
            command: command
        ) {
            reportControllerFeedbackEventIfNeeded(feedbackEvent)
            await onControllerFeedback?(feedbackEvent)
        }

        if let hdrModeEvent = parseHDRModeEvent(
            from: packet,
            command: command
        ) {
            reportHDRModeEventIfNeeded(hdrModeEvent)
            await onHDRMode?(hdrModeEvent)
        }

        if let hdrFrameState = parseHDRFrameStateEvent(
            from: packet,
            command: command
        ) {
            await onHDRFrameState?(hdrFrameState)
        }

        if let terminationEvent = parseTerminationEvent(
            from: packet,
            command: command
        ) {
            logger.error(
                "Lumen control termination received reason=0x\(String(terminationEvent.reasonCode, radix: 16), privacy: .public)"
            )
            await onTermination?(terminationEvent)
        }
    }

    private func parseControlPayload(
        from packet: ShadowClientHostENetPacketCodec.ParsedPacket,
        command: ShadowClientHostENetPacketCodec.ParsedPacket.Command
    ) -> Data? {
        guard command.number == ShadowClientHostENetProtocolProfile.protocolCommandSendReliable else {
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
        return controlPayload
    }

    private func reportControllerFeedbackEventIfNeeded(
        _ event: ShadowClientHostControllerFeedbackEvent
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

    private func reportHDRModeEventIfNeeded(
        _ event: ShadowClientHostHDRModeEvent
    ) {
        receivedHDRModeEventCount &+= 1
        guard receivedHDRModeEventCount <= 12 ||
                receivedHDRModeEventCount.isMultiple(of: 120)
        else {
            return
        }

        logger.notice(
            "RUMBLE TRACE hdrMode #\(self.receivedHDRModeEventCount, privacy: .public): \(event.debugSummary, privacy: .public)"
        )
    }

    private func controllerFeedbackSummary(
        for event: ShadowClientHostControllerFeedbackEvent
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
        case ShadowClientHostControlMessageProfile.startATypeV1:
            return "startA-v1"
        case ShadowClientHostControlMessageProfile.startATypeEncryptedV2:
            return "startA-encryptedV2"
        case ShadowClientHostControlMessageProfile.startBType:
            return "startB"
        case ShadowClientHostControlMessageProfile.periodicPingType:
            return "periodicPing"
        case ShadowClientHostControlMessageProfile.inputDataType:
            return "inputData"
        case ShadowClientHostControlMessageProfile.invalidateReferenceFramesType:
            return "invalidateReferenceFrames"
        case ShadowClientHostControlMessageProfile.terminationType:
            return "termination"
        case ShadowClientHostControlMessageProfile.rumbleType:
            return "rumble"
        case ShadowClientHostControlMessageProfile.rumbleTriggersType:
            return "triggerRumble"
        case ShadowClientHostControlMessageProfile.setMotionEventType:
            return "setMotionEvent"
        case ShadowClientHostControlMessageProfile.setRGBLEDType:
            return "setRGBLED"
        case ShadowClientHostControlMessageProfile.adaptiveTriggersType:
            return "adaptiveTriggers"
        case ShadowClientHostControlMessageProfile.hdrModeType:
            return "hdrMode"
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
        var didLogENetPing = 0
        var lastPeerPingUptime: UInt64 = 0
        while !Task.isCancelled {
            do {
                let nowUptime = DispatchTime.now().uptimeNanoseconds
                if lastPeerPingUptime == 0 ||
                    nowUptime - lastPeerPingUptime >= ShadowClientHostENetProtocolProfile.peerPingIntervalNanoseconds {
                    let reliableSequenceNumber = nextReliableSequenceNumber(
                        for: ShadowClientHostENetProtocolProfile.wildcardSessionID
                    )
                    let pingPacket = ShadowClientHostENetPacketCodec.makePingPacket(
                        outgoingPeerID: outgoingPeerID,
                        outgoingSessionID: outgoingSessionID,
                        reliableSequenceNumber: reliableSequenceNumber,
                        sentTime: currentSentTime()
                    )
                    try await Self.send(bytes: pingPacket, over: connection)
                    lastPeerPingUptime = nowUptime
                    if didLogENetPing < 4 {
                        logger.notice(
                            "Lumen low-level ENet ping sent relSeq=\(reliableSequenceNumber, privacy: .public)"
                        )
                        didLogENetPing += 1
                    }
                }

                try await sendReliableControlMessageWithoutBlockingForAcknowledge(
                    type: ShadowClientHostControlMessageProfile.periodicPingType,
                    payload: ShadowClientHostControlMessageProfile.periodicPingPayload,
                    over: connection
                )
            } catch {
                if !didLogFailure {
                    logger.error("Lumen control periodic ping failed: \(error.localizedDescription, privacy: .public)")
                    didLogFailure = true
                }
            }
            try? await Task.sleep(for: ShadowClientHostControlMessageProfile.periodicPingInterval)
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
                        private var continuation: CheckedContinuation<Result<Void, Error>, Never>?

                        init(continuation: CheckedContinuation<Result<Void, Error>, Never>) {
                            self.continuation = continuation
                        }

                        func finish(_ result: Result<Void, Error>) -> Bool {
                            lock.lock()
                            defer { lock.unlock() }
                            guard let continuation else {
                                return false
                            }
                            self.continuation = nil
                            continuation.resume(returning: result)
                            return true
                        }
                    }

                    let gate = ResumeGate(continuation: continuation)
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
                            if gate.finish(.failure(ShadowClientHostControlChannelError.connectionClosed)) {
                                connection.stateUpdateHandler = nil
                            }
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
                    return .failure(ShadowClientHostControlChannelError.connectionTimedOut)
                } catch {
                    return .failure(error)
                }
            }

            let first = await group.next() ?? .failure(ShadowClientHostControlChannelError.connectionTimedOut)
            group.cancelAll()
            return first
        }

        try result.get()
    }

    private func resetSessionState() {
        outgoingPeerID = ShadowClientHostENetPacketCodec.maximumPeerID
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
        if channelID == ShadowClientHostENetProtocolProfile.wildcardSessionID {
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
    ) async throws -> ShadowClientHostENetPacketCodec.VerifyConnect {
        while !Task.isCancelled {
            let datagram = try await receiveDatagram(over: connection)
            guard let packet = ShadowClientHostENetPacketCodec.parsePacket(datagram),
                  let verify = ShadowClientHostENetPacketCodec.parseVerifyConnect(from: packet)
            else {
                continue
            }

            if verify.connectID == expectedConnectID {
                return verify
            }
        }

        throw ShadowClientHostControlChannelError.verifyConnectNotReceived
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
                    continuation.resume(throwing: ShadowClientHostControlChannelError.connectionClosed)
                    return
                }
                continuation.resume(returning: content)
            }
        }
    }
}
