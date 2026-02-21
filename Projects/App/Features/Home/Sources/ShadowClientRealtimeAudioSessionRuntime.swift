import AVFoundation
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
        pingPayload: Data?
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

        do {
            let resolvedDecoder = try ShadowClientRealtimeAudioDecoderFactory.make(
                for: resolvedTrack
            )
            decoder = resolvedDecoder
            output = try ShadowClientRealtimeAudioEngineOutput(
                format: resolvedDecoder.outputFormat
            )
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
            logger.notice(
                "Audio runtime started codec=\(resolvedTrack.codec.label, privacy: .public) payloadType=\(resolvedTrack.rtpPayloadType, privacy: .public) sampleRate=\(resolvedTrack.sampleRate, privacy: .public) channels=\(resolvedTrack.channelCount, privacy: .public)"
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

            var loggedUnexpectedPayloadTypes = Set<Int>()
            var consecutiveDroppedOutputBuffers = 0
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

                    if packet.payloadType != preferredPayloadType {
                        if loggedUnexpectedPayloadTypes.insert(packet.payloadType).inserted {
                            logger.notice(
                                "Ignoring RTP audio payload type \(packet.payloadType, privacy: .public) (expected \(preferredPayloadType, privacy: .public))"
                            )
                        }
                        continue
                    }

                    let readyPackets = jitterBuffer.enqueue(
                        packet,
                        preferredPayloadType: preferredPayloadType
                    )
                    if readyPackets.isEmpty {
                        continue
                    }

                    for readyPacket in readyPackets {
                        do {
                            guard let decoder else {
                                continue
                            }
                            if let pcmBuffer = try decoder.decode(
                                payload: readyPacket.payload
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
                                output?.enqueue(pcmBuffer: pcmBuffer)
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
        let result = await withTaskGroup(
            of: Result<Void, Error>.self,
            returning: Result<Void, Error>.self
        ) { group in
            group.addTask { [connectionQueue] in
                await withCheckedContinuation {
                    (continuation: CheckedContinuation<Result<Void, Error>, Never>) in
                    final class ResumeGate: @unchecked Sendable {
                        private let lock = NSLock()
                        private var continuation: CheckedContinuation<Result<Void, Error>, Never>?
                        private let connection: NWConnection

                        init(
                            continuation: CheckedContinuation<Result<Void, Error>, Never>,
                            connection: NWConnection
                        ) {
                            self.continuation = continuation
                            self.connection = connection
                        }

                        func resume(with result: Result<Void, Error>) {
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

                    let gate = ResumeGate(
                        continuation: continuation,
                        connection: connection
                    )
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            gate.resume(with: .success(()))
                        case let .failed(error):
                            gate.resume(with: .failure(error))
                        case .cancelled:
                            gate.resume(with: .failure(CancellationError()))
                        default:
                            break
                        }
                    }
                    connection.start(queue: connectionQueue)
                }
            }

            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    connection.cancel()
                    return .failure(
                        NSError(
                            domain: "ShadowClientRealtimeAudioSessionRuntime",
                            code: 1,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Audio UDP connection timed out.",
                            ]
                        )
                    )
                } catch {
                    return .failure(error)
                }
            }

            let first = await group.next() ?? .failure(CancellationError())
            group.cancelAll()
            return first
        }

        try result.get()
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
            payload: Data(datagram[headerLength..<endIndex])
        )
    }
}

private struct ShadowClientRealtimeAudioRTPJitterBuffer: Sendable {
    private let targetDepth: Int
    private let maximumDepth: Int
    private(set) var lockedPayloadType: Int?
    private var expectedSequence: UInt16?
    private var packetsBySequence: [UInt16: ShadowClientRealtimeAudioSessionRuntime.RTPPacket] = [:]

    init(targetDepth: Int, maximumDepth: Int) {
        self.targetDepth = max(2, targetDepth)
        self.maximumDepth = max(self.targetDepth, maximumDepth)
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
        while let expectedSequence,
              let nextPacket = packetsBySequence.removeValue(forKey: expectedSequence)
        {
            readyPackets.append(nextPacket)
            self.expectedSequence = expectedSequence &+ 1
        }

        if readyPackets.isEmpty, packetsBySequence.count >= targetDepth {
            let sortedSequenceNumbers = packetsBySequence.keys.sorted()
            if let firstSequence = sortedSequenceNumbers.first {
                expectedSequence = firstSequence
                while let expectedSequence,
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
    static func make(
        for track: ShadowClientRTSPAudioTrackDescriptor
    ) throws -> any ShadowClientRealtimeAudioPacketDecoding {
        switch track.codec {
        case .opus:
            return try ShadowClientRealtimeOpusAudioDecoder(
                sampleRate: track.sampleRate,
                channels: track.channelCount
            )
        case .l16:
            return ShadowClientRealtimeL16AudioDecoder(
                sampleRate: track.sampleRate,
                channels: track.channelCount
            )
        case .pcmu:
            return ShadowClientRealtimeG711AudioDecoder(
                sampleRate: track.sampleRate,
                channels: track.channelCount,
                variant: .uLaw
            )
        case .pcma:
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
}

private final class ShadowClientRealtimeOpusAudioDecoder: ShadowClientRealtimeAudioPacketDecoding {
    let codec: ShadowClientAudioCodec = .opus
    let sampleRate: Int
    let channels: Int
    let outputFormat: AVAudioFormat
    private let inputFormat: AVAudioFormat
    private let converter: AVAudioConverter

    init(sampleRate: Int, channels: Int) throws {
        self.sampleRate = sampleRate
        self.channels = channels

        guard let inputFormat = AVAudioFormat(
            settings: [
                AVFormatIDKey: kAudioFormatOpus,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channels,
            ]
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

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(channels),
            interleaved: false
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
    }

    func decode(payload: Data) throws -> AVAudioPCMBuffer? {
        guard !payload.isEmpty else {
            return nil
        }

        let compressedBuffer = AVAudioCompressedBuffer(
            format: inputFormat,
            packetCapacity: 1,
            maximumPacketSize: max(1, payload.count)
        )

        payload.copyBytes(
            to: compressedBuffer.data.assumingMemoryBound(to: UInt8.self),
            count: payload.count
        )
        compressedBuffer.byteLength = UInt32(payload.count)
        compressedBuffer.packetCount = 1
        if let packetDescriptions = compressedBuffer.packetDescriptions {
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
        let status = converter.convert(to: pcmBuffer, error: &conversionError) { _, status in
            if didProvideInput {
                status.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            status.pointee = .haveData
            return compressedBuffer
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
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
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

    func enqueue(pcmBuffer: AVAudioPCMBuffer) {
        if !isStarted {
            try? engine.start()
            player.play()
            isStarted = true
        } else if !player.isPlaying {
            player.play()
        }

        player.scheduleBuffer(
            pcmBuffer,
            completionHandler: nil
        )
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
    }
}
