import Foundation
import Network
import os

enum ShadowClientSunshineControlChannelError: Error {
    case connectionTimedOut
    case connectionClosed
    case handshakeTimedOut
    case verifyConnectNotReceived
}

actor ShadowClientSunshineControlChannelRuntime {
    private let connectTimeout: Duration
    private let queue = DispatchQueue(label: "com.skyline23.shadowclient.control.enet")
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "ControlChannel")

    private var connection: NWConnection?
    private var receiveTask: Task<Void, Never>?
    private var outgoingPeerID: UInt16 = ShadowClientSunshineENetPacketCodec.maximumPeerID
    private var outgoingSessionID: UInt8 = 0
    private var outgoingReliableSequenceNumber: UInt16 = 0
    private var connectID: UInt32 = 0

    init(connectTimeout: Duration = ShadowClientSunshineControlChannelDefaults.connectTimeout) {
        self.connectTimeout = connectTimeout
    }

    func start(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        connectData: UInt32?
    ) async throws {
        stop()

        let connection = NWConnection(host: host, port: port, using: .udp)
        self.connection = connection
        resetSessionState()

        do {
            try await waitForReady(connection)

            connectID = UInt32.random(in: .min ... .max)
            outgoingReliableSequenceNumber = 1

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

            logger.notice(
                "Sunshine ENet control bootstrap ready on UDP \(port.rawValue, privacy: .public) peer=\(self.outgoingPeerID, privacy: .public)"
            )

            receiveTask = Task { [weak self] in
                guard let self else {
                    return
                }
                await self.receiveLoop(over: connection)
            }
        } catch {
            connection.cancel()
            self.connection = nil
            resetSessionState()
            throw error
        }
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        connection?.cancel()
        connection = nil
        resetSessionState()
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
        outgoingReliableSequenceNumber &+= 1
        let packet = ShadowClientSunshineENetPacketCodec.makeAcknowledgePacket(
            outgoingPeerID: outgoingPeerID,
            outgoingSessionID: outgoingSessionID,
            outgoingReliableSequenceNumber: outgoingReliableSequenceNumber,
            commandChannelID: commandChannelID,
            receivedReliableSequenceNumber: receivedReliableSequenceNumber,
            receivedSentTime: receivedSentTime
        )
        try await Self.send(bytes: packet, over: connection)
    }

    private func receiveLoop(over connection: NWConnection) async {
        while !Task.isCancelled {
            do {
                let datagram = try await Self.receiveDatagram(over: connection)
                guard let packet = ShadowClientSunshineENetPacketCodec.parsePacket(datagram),
                      let sentTime = packet.sentTime
                else {
                    continue
                }

                for command in packet.commands where command.isAcknowledgeRequired {
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
        outgoingReliableSequenceNumber = 0
        connectID = 0
    }

    private func currentSentTime() -> UInt16 {
        UInt16(truncatingIfNeeded: DispatchTime.now().uptimeNanoseconds / 1_000_000)
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
