import Foundation
import Network
import os

enum ShadowClientRealtimeAudioTransportBootstrap {
    static func bootstrapUDPSocket(
        remoteHost: NWEndpoint.Host,
        remotePort: NWEndpoint.Port,
        localHost: NWEndpoint.Host?,
        preferredLocalPort: UInt16?,
        prioritizeNetworkTraffic: Bool,
        logger: Logger,
        readyMessagePrefix: String,
        fallbackReadyMessagePrefix: String
    ) async throws -> ShadowClientUDPDatagramSocket {
        do {
            let socket = try ShadowClientUDPDatagramSocket(
                localHost: localHost,
                localPort: preferredLocalPort,
                remoteHost: remoteHost,
                remotePort: remotePort.rawValue,
                trafficClass: ShadowClientStreamingTrafficPolicy.audio(
                    prioritized: prioritizeNetworkTraffic
                )
            )
            let endpointDescription = await socket.localEndpointDescription()
            logger.notice("\(readyMessagePrefix, privacy: .public) \(endpointDescription, privacy: .public)")
            return socket
        } catch {
            guard preferredLocalPort != nil else {
                throw error
            }
            logger.error(
                "Audio UDP bind on preferred client port \(preferredLocalPort ?? 0, privacy: .public) failed: \(error.localizedDescription, privacy: .public); retrying with ephemeral port"
            )
            let socket = try ShadowClientUDPDatagramSocket(
                localHost: localHost,
                localPort: nil,
                remoteHost: remoteHost,
                remotePort: remotePort.rawValue,
                trafficClass: ShadowClientStreamingTrafficPolicy.audio(
                    prioritized: prioritizeNetworkTraffic
                )
            )
            let endpointDescription = await socket.localEndpointDescription()
            logger.notice("\(fallbackReadyMessagePrefix, privacy: .public) \(endpointDescription, privacy: .public)")
            return socket
        }
    }

    static func bootstrapUDPConnection(
        remoteHost: NWEndpoint.Host,
        remotePort: NWEndpoint.Port,
        localHost: NWEndpoint.Host?,
        preferredLocalPort: UInt16?,
        prioritizeNetworkTraffic: Bool,
        queue: DispatchQueue,
        logger: Logger,
        readyMessagePrefix: String,
        fallbackReadyMessagePrefix: String
    ) async throws -> NWConnection {
        func makeParameters(localPort: UInt16?) -> NWParameters {
            ShadowClientStreamingTrafficPolicy.udpParameters(
                localHost: localHost,
                localPort: localPort,
                trafficClass: ShadowClientStreamingTrafficPolicy.audio(
                    prioritized: prioritizeNetworkTraffic
                )
            )
        }

        let primaryConnection = NWConnection(
            host: remoteHost,
            port: remotePort,
            using: makeParameters(localPort: preferredLocalPort)
        )
        do {
            try await waitForReady(
                primaryConnection,
                timeout: .seconds(2),
                queue: queue
            )
            logLocalEndpoint(
                primaryConnection,
                messagePrefix: readyMessagePrefix,
                logger: logger
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
                timeout: .seconds(2),
                queue: queue
            )
            logLocalEndpoint(
                fallbackConnection,
                messagePrefix: fallbackReadyMessagePrefix,
                logger: logger
            )
            return fallbackConnection
        }
    }

    static func sendInitialPing(
        over connection: NWConnection,
        pingPayload: Data?,
        logger: Logger,
        messagePrefix: String
    ) async throws {
        let initialPackets = ShadowClientHostPingPacketCodec.makePingPackets(
            sequence: 1,
            negotiatedPayload: pingPayload
        )
        for packet in initialPackets {
            try await send(bytes: packet, over: connection)
        }
        logger.notice(
            "\(messagePrefix, privacy: .public) (variants=\(initialPackets.count, privacy: .public), bytes=\(initialPackets.first?.count ?? 0, privacy: .public))"
        )
    }

    static func sendInitialPing(
        over socket: ShadowClientUDPDatagramSocket,
        pingPayload: Data?,
        logger: Logger,
        messagePrefix: String
    ) async throws {
        let initialPackets = ShadowClientHostPingPacketCodec.makePingPackets(
            sequence: 1,
            negotiatedPayload: pingPayload
        )
        for packet in initialPackets {
            try await send(bytes: packet, over: socket)
        }
        logger.notice(
            "\(messagePrefix, privacy: .public) (variants=\(initialPackets.count, privacy: .public), bytes=\(initialPackets.first?.count ?? 0, privacy: .public))"
        )
    }

    static func startPingLoop(
        over connection: NWConnection,
        pingPayload: Data?,
        logger: Logger,
        successMessagePrefix: String,
        errorMessagePrefix: String,
        successLogLimit: Int = 3
    ) -> Task<Void, Never> {
        Task.detached {
            var sequence: UInt32 = 1
            var loggedPingCount = 0
            var loggedPingError = false
            while !Task.isCancelled {
                sequence &+= 1
                let pingPackets = ShadowClientHostPingPacketCodec.makePingPackets(
                    sequence: sequence,
                    negotiatedPayload: pingPayload
                )
                do {
                    for pingPacket in pingPackets {
                        try await send(bytes: pingPacket, over: connection)
                    }
                    if loggedPingCount < successLogLimit {
                        logger.notice(
                            "\(successMessagePrefix, privacy: .public) (sequence=\(sequence, privacy: .public), variants=\(pingPackets.count, privacy: .public), bytes=\(pingPackets.first?.count ?? 0, privacy: .public))"
                        )
                        loggedPingCount += 1
                    }
                } catch {
                    if !loggedPingError {
                        logger.error("\(errorMessagePrefix, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        loggedPingError = true
                    }
                }
                try? await Task.sleep(for: ShadowClientRealtimeSessionDefaults.pingInterval)
            }
        }
    }

    static func startPingLoop(
        over socket: ShadowClientUDPDatagramSocket,
        pingPayload: Data?,
        logger: Logger,
        successMessagePrefix: String,
        errorMessagePrefix: String,
        successLogLimit: Int = 3
    ) -> Task<Void, Never> {
        Task.detached {
            var sequence: UInt32 = 1
            var loggedPingCount = 0
            var loggedPingError = false
            while !Task.isCancelled {
                sequence &+= 1
                let pingPackets = ShadowClientHostPingPacketCodec.makePingPackets(
                    sequence: sequence,
                    negotiatedPayload: pingPayload
                )
                do {
                    for pingPacket in pingPackets {
                        try await send(bytes: pingPacket, over: socket)
                    }
                    if loggedPingCount < successLogLimit {
                        logger.notice(
                            "\(successMessagePrefix, privacy: .public) (sequence=\(sequence, privacy: .public), variants=\(pingPackets.count, privacy: .public), bytes=\(pingPackets.first?.count ?? 0, privacy: .public))"
                        )
                        loggedPingCount += 1
                    }
                } catch {
                    if !loggedPingError {
                        logger.error("\(errorMessagePrefix, privacy: .public): \(error.localizedDescription, privacy: .public)")
                        loggedPingError = true
                    }
                }
                try? await Task.sleep(for: ShadowClientRealtimeSessionDefaults.pingInterval)
            }
        }
    }

    static func send(
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

    static func send(
        bytes: Data,
        over socket: ShadowClientUDPDatagramSocket
    ) async throws {
        try await socket.send(bytes)
    }

    static func logLocalEndpoint(
        _ connection: NWConnection,
        messagePrefix: String,
        logger: Logger
    ) {
        guard case let .hostPort(host, port) = connection.currentPath?.localEndpoint else {
            logger.notice("\(messagePrefix, privacy: .public)")
            return
        }
        logger.notice(
            "\(messagePrefix, privacy: .public) \(String(describing: host), privacy: .public):\(port.rawValue, privacy: .public)"
        )
    }

    private static func waitForReady(
        _ connection: NWConnection,
        timeout: Duration,
        queue: DispatchQueue
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
                            domain: "ShadowClientRealtimeAudioTransportBootstrap",
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
                connection.start(queue: queue)
            }
        } onCancel: {
            if gate.finish(.failure(CancellationError())) {
                connection.stateUpdateHandler = nil
                connection.cancel()
            }
        }
    }
}
