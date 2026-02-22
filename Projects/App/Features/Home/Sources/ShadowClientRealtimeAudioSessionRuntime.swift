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
        targetDepth: 6,
        maximumDepth: 32
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
            decoderImplementationName = String(describing: type(of: resolvedDecoder))
            decoder = resolvedDecoder
            output = try ShadowClientRealtimeAudioEngineOutput(
                format: resolvedDecoder.outputFormat
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
            startReceiveLoop(
                over: udpConnection,
                preferredPayloadType: resolvedTrack.rtpPayloadType
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
                "Audio runtime started codec=\(resolvedTrack.codec.label, privacy: .public) payloadType=\(resolvedTrack.rtpPayloadType, privacy: .public) sampleRate=\(resolvedTrack.sampleRate, privacy: .public) channels=\(resolvedTrack.channelCount, privacy: .public) encryption=\(encryptionLabel, privacy: .public) decoder=\(decoderImplementationName, privacy: .public)"
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

        output?.stop()
        output = nil

        decoder = nil
        payloadDecryptor = nil
        jitterBuffer.reset(preferredPayloadType: nil)
        if emitIdleState {
            updateState(.idle)
        }
    }

    private func startReceiveLoop(
        over connection: NWConnection,
        preferredPayloadType: Int
    ) {
        receiveTask = Task { [weak self] in
            guard let self else {
                return
            }

            var currentPayloadType = preferredPayloadType
            var loggedUnexpectedPayloadTypes = Set<Int>()
            var consecutiveDroppedOutputBuffers = 0
            var consecutiveDroppedOutputQueueBuffers = 0
            var consecutiveDecryptFailures = 0
            while !Task.isCancelled {
                do {
                    guard let datagram = try await Self.receiveDatagram(over: connection),
                          !datagram.isEmpty
                    else {
                        continue
                    }

                    guard let packet = Self.parseRTPPacket(datagram) else {
                        continue
                    }

                    if packet.payloadType != currentPayloadType {
                        if let nextPayloadType = Self.payloadTypePreference(
                            observed: packet.payloadType,
                            current: currentPayloadType
                        ) {
                            let previousPayloadType = currentPayloadType
                            currentPayloadType = nextPayloadType
                            jitterBuffer.reset(preferredPayloadType: currentPayloadType)
                            logger.notice(
                                "Adapting RTP audio payload type from \(previousPayloadType, privacy: .public) to \(currentPayloadType, privacy: .public)"
                            )
                        } else {
                            if loggedUnexpectedPayloadTypes.insert(packet.payloadType).inserted {
                                logger.notice(
                                    "Ignoring RTP audio payload type \(packet.payloadType, privacy: .public) (expected \(currentPayloadType, privacy: .public))"
                                )
                            }
                            continue
                        }
                    }

                    let readyPackets = jitterBuffer.enqueue(
                        packet,
                        preferredPayloadType: currentPayloadType
                    )
                    if readyPackets.isEmpty {
                        continue
                    }

                    for readyPacket in readyPackets {
                        do {
                            guard let audioOutput = output else {
                                continue
                            }
                            guard audioOutput.hasEnqueueCapacity else {
                                consecutiveDroppedOutputQueueBuffers += 1
                                if consecutiveDroppedOutputQueueBuffers == 1 ||
                                    consecutiveDroppedOutputQueueBuffers.isMultiple(of: 25)
                                {
                                    logger.error(
                                        "Skipping audio decode due to output queue saturation (count=\(consecutiveDroppedOutputQueueBuffers, privacy: .public))"
                                    )
                                }
                                continue
                            }
                            guard let decoder else {
                                continue
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
                                        output?.stop()
                                        output = nil
                                        updateState(.decoderFailed(message))
                                        return
                                    }
                                    continue
                                }
                            } else {
                                decodePayload = readyPacket.payload
                            }
                            if let pcmBuffer = try decoder.decode(
                                payload: decodePayload
                            ) {
                                guard ShadowClientRealtimeAudioPCMBufferGuard.isSafeForPlayback(
                                    pcmBuffer
                                ) else {
                                    consecutiveDroppedOutputBuffers += 1
                                    if consecutiveDroppedOutputBuffers == 1 ||
                                        consecutiveDroppedOutputBuffers.isMultiple(of: 25)
                                    {
                                        logger.error(
                                            "Dropping suspicious decoded audio buffer (count=\(consecutiveDroppedOutputBuffers, privacy: .public))"
                                        )
                                    }
                                    if consecutiveDroppedOutputBuffers >= 150 {
                                        let message = "Audio decoder produced repeated suspicious PCM buffers."
                                        logger.error("\(message, privacy: .public)")
                                        output?.stop()
                                        output = nil
                                        updateState(.decoderFailed(message))
                                        return
                                    }
                                    continue
                                }
                                consecutiveDroppedOutputBuffers = 0
                                if audioOutput.enqueue(pcmBuffer: pcmBuffer) == false {
                                    consecutiveDroppedOutputQueueBuffers += 1
                                    if consecutiveDroppedOutputQueueBuffers == 1 ||
                                        consecutiveDroppedOutputQueueBuffers.isMultiple(of: 25)
                                    {
                                        logger.error(
                                            "Dropping decoded audio buffer due to output queue saturation (count=\(consecutiveDroppedOutputQueueBuffers, privacy: .public))"
                                        )
                                    }
                                    continue
                                }
                                consecutiveDroppedOutputQueueBuffers = 0
                            }
                        } catch {
                            let message = "Audio decode failed: \(error.localizedDescription)"
                            logger.error("\(message, privacy: .public)")
                            output?.stop()
                            output = nil
                            updateState(.decoderFailed(message))
                            return
                        }
                    }
                } catch {
                    if Task.isCancelled {
                        return
                    }
                    let message = "Audio RTP receive failed: \(error.localizedDescription)"
                    logger.error("\(message, privacy: .public)")
                    output?.stop()
                    output = nil
                    updateState(.disconnected(message))
                    return
                }
            }
        }
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

    internal static func payloadTypePreference(
        observed: Int,
        current: Int
    ) -> Int? {
        guard observed != current else {
            return nil
        }
        guard (96 ... 127).contains(observed) else {
            return nil
        }
        guard observed != ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType else {
            return nil
        }
        return observed
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
    private(set) var lockedPayloadType: Int?
    private var expectedSequence: UInt16?
    private var packetsBySequence: [UInt16: ShadowClientRealtimeAudioSessionRuntime.RTPPacket] = [:]

    init(
        targetDepth: Int,
        maximumDepth: Int,
        maximumDrainBatch: Int = 8
    ) {
        self.targetDepth = max(2, targetDepth)
        self.maximumDepth = max(self.targetDepth, maximumDepth)
        self.maximumDrainBatch = max(1, maximumDrainBatch)
    }

    mutating func reset(preferredPayloadType: Int?) {
        lockedPayloadType = preferredPayloadType
        expectedSequence = nil
        packetsBySequence.removeAll(keepingCapacity: false)
    }

    mutating func enqueue(
        _ packet: ShadowClientRealtimeAudioSessionRuntime.RTPPacket,
        preferredPayloadType: Int
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

        var readyPackets: [ShadowClientRealtimeAudioSessionRuntime.RTPPacket] = []
        while readyPackets.count < maximumDrainBatch,
              let expectedSequence,
              let nextPacket = packetsBySequence.removeValue(forKey: expectedSequence)
        {
            readyPackets.append(nextPacket)
            self.expectedSequence = expectedSequence &+ 1
        }

        if readyPackets.isEmpty, packetsBySequence.count >= targetDepth {
            let sortedSequenceNumbers = packetsBySequence.keys.sorted()
            if let firstSequence = sortedSequenceNumbers.first {
                expectedSequence = firstSequence
                while readyPackets.count < maximumDrainBatch,
                      let expectedSequence,
                      let nextPacket = packetsBySequence.removeValue(forKey: expectedSequence)
                {
                    readyPackets.append(nextPacket)
                    self.expectedSequence = expectedSequence &+ 1
                }
            }
        }

        if packetsBySequence.count > maximumDepth {
            let sortedSequenceNumbers = packetsBySequence.keys.sorted()
            let overflowCount = packetsBySequence.count - maximumDepth
            for sequence in sortedSequenceNumbers.prefix(overflowCount) {
                packetsBySequence.removeValue(forKey: sequence)
            }
        }

        return readyPackets
    }
}

private protocol ShadowClientRealtimeAudioPacketDecoding {
    var codec: ShadowClientAudioCodec { get }
    var sampleRate: Int { get }
    var channels: Int { get }
    var outputFormat: AVAudioFormat { get }
    func decode(payload: Data) throws -> AVAudioPCMBuffer?
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
            if track.channelCount > 2,
               let customDecoder = customDecoderAttempt.decoder
            {
                return ShadowClientRealtimeCustomDecoderAdapter(base: customDecoder)
            }
            do {
                return try ShadowClientRealtimeOpusAudioDecoder(
                    sampleRate: track.sampleRate,
                    channels: track.channelCount
                )
            } catch {
                if let customDecoder = customDecoderAttempt.decoder {
                    return ShadowClientRealtimeCustomDecoderAdapter(base: customDecoder)
                }
                if let customDecoderError = customDecoderAttempt.error {
                    throw NSError(
                        domain: "ShadowClientRealtimeAudioDecoderFactory",
                        code: 2,
                        userInfo: [
                            NSLocalizedDescriptionKey:
                                "Audio decoder bootstrap failed (custom decoder: \(customDecoderError.localizedDescription); system decoder: \(error.localizedDescription)).",
                        ]
                    )
                }
                throw error
            }
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

    func decode(payload: Data) throws -> AVAudioPCMBuffer? {
        try base.decode(payload: payload)
    }
}

private enum ShadowClientRealtimeAudioFormatFactory {
    static func opusInputFormat(
        sampleRate: Int,
        channels: Int
    ) -> AVAudioFormat? {
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatOpus,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
        ]
        if let channelLayoutData = channelLayoutData(for: channels) {
            settings[AVChannelLayoutKey] = channelLayoutData
        }
        return AVAudioFormat(settings: settings)
    }

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

private final class ShadowClientRealtimeOpusAudioDecoder: ShadowClientRealtimeAudioPacketDecoding {
    let codec: ShadowClientAudioCodec = .opus
    let sampleRate: Int
    let channels: Int
    let outputFormat: AVAudioFormat
    private let inputFormat: AVAudioFormat
    private let converter: AVAudioConverter
    private var compressedPacketBuffer: AVAudioCompressedBuffer
    private var compressedPacketCapacity: Int

    init(sampleRate: Int, channels: Int) throws {
        self.sampleRate = sampleRate
        self.channels = channels

        guard let inputFormat = ShadowClientRealtimeAudioFormatFactory.opusInputFormat(
            sampleRate: sampleRate,
            channels: channels
        ) else {
            throw NSError(
                domain: "ShadowClientRealtimeOpusAudioDecoder",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not create Opus input format.",
                ]
            )
        }
        self.inputFormat = inputFormat

        guard let outputFormat = ShadowClientRealtimeAudioFormatFactory.pcmFloatOutputFormat(
            sampleRate: sampleRate,
            channels: channels
        ) else {
            throw NSError(
                domain: "ShadowClientRealtimeOpusAudioDecoder",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not create Opus output format.",
                ]
            )
        }
        self.outputFormat = outputFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw NSError(
                domain: "ShadowClientRealtimeOpusAudioDecoder",
                code: 3,
                userInfo: [
                    NSLocalizedDescriptionKey: "Could not create Opus converter.",
                ]
            )
        }
        self.converter = converter
        let initialCompressedPacketCapacity = 2_048
        self.compressedPacketCapacity = initialCompressedPacketCapacity
        self.compressedPacketBuffer = AVAudioCompressedBuffer(
            format: inputFormat,
            packetCapacity: 1,
            maximumPacketSize: max(1, initialCompressedPacketCapacity)
        )
    }

    func decode(payload: Data) throws -> AVAudioPCMBuffer? {
        guard !payload.isEmpty else {
            return nil
        }
        ensureCompressedPacketBufferCapacity(minimumPacketSize: payload.count)
        payload.copyBytes(
            to: compressedPacketBuffer.data.assumingMemoryBound(to: UInt8.self),
            count: payload.count
        )
        compressedPacketBuffer.byteLength = UInt32(payload.count)
        compressedPacketBuffer.packetCount = 1
        if let packetDescriptions = compressedPacketBuffer.packetDescriptions {
            packetDescriptions[0] = AudioStreamPacketDescription(
                mStartOffset: 0,
                mVariableFramesInPacket: 0,
                mDataByteSize: UInt32(payload.count)
            )
        }

        let frameCapacity: AVAudioFrameCount = 5_760
        guard let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: frameCapacity
        ) else {
            return nil
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: pcmBuffer, error: &conversionError) { [self] _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            status.pointee = .haveData
            return self.compressedPacketBuffer
        }

        if let conversionError {
            throw conversionError
        }

        switch status {
        case .haveData, .inputRanDry:
            return pcmBuffer.frameLength > 0 ? pcmBuffer : nil
        case .endOfStream:
            return nil
        case .error:
            throw NSError(
                domain: "ShadowClientRealtimeOpusAudioDecoder",
                code: 4,
                userInfo: [
                    NSLocalizedDescriptionKey: "Opus conversion failed.",
                ]
            )
        @unknown default:
            return nil
        }
    }

    private func ensureCompressedPacketBufferCapacity(minimumPacketSize: Int) {
        guard minimumPacketSize > compressedPacketCapacity else {
            return
        }
        let nextCapacity = max(minimumPacketSize, compressedPacketCapacity * 2)
        compressedPacketCapacity = nextCapacity
        compressedPacketBuffer = AVAudioCompressedBuffer(
            format: inputFormat,
            packetCapacity: 1,
            maximumPacketSize: max(1, nextCapacity)
        )
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
    private static let maximumQueuedBufferCount = 16

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let queuedBufferLock = NSLock()
    private var queuedBufferCount = 0
    private var isStarted = false

    init(format: AVAudioFormat) throws {
        self.format = format
        engine.attach(player)
        engine.connect(
            player,
            to: engine.mainMixerNode,
            format: format
        )
        try engine.start()
        player.play()
        isStarted = true
    }

    func enqueue(pcmBuffer: AVAudioPCMBuffer) -> Bool {
        if !isStarted {
            try? engine.start()
            player.play()
            isStarted = true
        } else if !player.isPlaying {
            player.play()
        }

        queuedBufferLock.lock()
        if queuedBufferCount >= Self.maximumQueuedBufferCount {
            queuedBufferLock.unlock()
            return false
        }
        queuedBufferCount += 1
        queuedBufferLock.unlock()

        player.scheduleBuffer(
            pcmBuffer,
            completionCallbackType: .dataConsumed
        ) { [weak self] _ in
            self?.didConsumeQueuedBuffer()
        }
        return true
    }

    var hasEnqueueCapacity: Bool {
        queuedBufferLock.lock()
        let hasCapacity = queuedBufferCount < Self.maximumQueuedBufferCount
        queuedBufferLock.unlock()
        return hasCapacity
    }

    func stop() {
        guard isStarted else {
            return
        }
        player.stop()
        engine.stop()
        engine.reset()
        engine.detach(player)
        isStarted = false
        queuedBufferLock.lock()
        queuedBufferCount = 0
        queuedBufferLock.unlock()
    }

    private func didConsumeQueuedBuffer() {
        queuedBufferLock.lock()
        queuedBufferCount = max(0, queuedBufferCount - 1)
        queuedBufferLock.unlock()
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
