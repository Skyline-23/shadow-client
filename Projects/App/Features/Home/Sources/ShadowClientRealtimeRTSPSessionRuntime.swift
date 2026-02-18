import CoreVideo
import Foundation
import Network
import os

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
    public let surfaceContext: ShadowClientRealtimeSessionSurfaceContext

    private let decoder: ShadowClientVideoToolboxDecoder
    private let connectTimeout: Duration
    private var rtspClient: ShadowClientRTSPInterleavedClient?
    private var streamTask: Task<Void, Never>?
    private var h264Depacketizer = ShadowClientH264RTPDepacketizer()
    private var h265Depacketizer = ShadowClientH265RTPDepacketizer()

    public init(
        surfaceContext: ShadowClientRealtimeSessionSurfaceContext = .init(),
        decoder: ShadowClientVideoToolboxDecoder = .init(),
        connectTimeout: Duration = .seconds(8)
    ) {
        self.surfaceContext = surfaceContext
        self.decoder = decoder
        self.connectTimeout = connectTimeout
    }

    deinit {
        streamTask?.cancel()
    }

    public func connect(
        sessionURL: String,
        host _: String,
        appTitle _: String
    ) async throws {
        try await disconnect()

        await MainActor.run {
            surfaceContext.reset()
            surfaceContext.transition(to: .connecting)
        }

        let trimmed = sessionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let _ = url.host else {
            throw ShadowClientRealtimeSessionRuntimeError.invalidSessionURL
        }

        let client = ShadowClientRTSPInterleavedClient(
            timeout: connectTimeout
        )
        let track = try await client.start(url: url)

        h264Depacketizer.reset()
        h265Depacketizer.reset()
        await MainActor.run {
            surfaceContext.transition(to: .waitingForFirstFrame)
        }

        rtspClient = client
        streamTask = Task { [weak self] in
            guard let self else {
                return
            }

            do {
                try await client.receiveInterleavedVideoPackets(
                    payloadType: track.rtpPayloadType
                ) { payload, marker in
                    try await self.consumeRTPPayload(
                        codec: track.codec,
                        payload: payload,
                        marker: marker,
                        initialParameterSets: track.parameterSets
                    )
                }
            } catch {
                let surfaceContext = self.surfaceContext
                await MainActor.run {
                    surfaceContext.transition(to: .failed(error.localizedDescription))
                }
            }
        }
    }

    public func disconnect() async throws {
        streamTask?.cancel()
        streamTask = nil

        if let rtspClient {
            await rtspClient.stop()
        }
        rtspClient = nil

        await decoder.reset()
        await MainActor.run {
            surfaceContext.reset()
        }
    }

    private func consumeRTPPayload(
        codec: ShadowClientVideoCodec,
        payload: Data,
        marker: Bool,
        initialParameterSets: [Data]
    ) async throws {
        switch codec {
        case .h264:
            if let output = h264Depacketizer.ingest(payload: payload, marker: marker) {
                try await decodeFrame(
                    accessUnit: output.annexBAccessUnit,
                    codec: .h264,
                    parameterSets: output.parameterSets.isEmpty ? initialParameterSets : output.parameterSets
                )
            }
        case .h265:
            if let output = h265Depacketizer.ingest(payload: payload, marker: marker) {
                try await decodeFrame(
                    accessUnit: output,
                    codec: .h265,
                    parameterSets: initialParameterSets
                )
            }
        }
    }

    private func decodeFrame(
        accessUnit: Data,
        codec: ShadowClientVideoCodec,
        parameterSets: [Data]
    ) async throws {
        let surfaceContext = self.surfaceContext
        try await decoder.decode(
            accessUnit: accessUnit,
            codec: codec,
            parameterSets: parameterSets
        ) { [surfaceContext] pixelBuffer in
            let sendableFrame = ShadowClientSendablePixelBuffer(value: pixelBuffer)
            await MainActor.run {
                surfaceContext.frameStore.update(pixelBuffer: sendableFrame.value)
                surfaceContext.transition(to: .rendering)
            }
        }
    }
}

private struct ShadowClientSendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

private enum ShadowClientRTSPInterleavedClientError: Error, Equatable {
    case invalidURL
    case connectionFailed
    case requestFailed(String)
    case invalidResponse
    case connectionClosed
}

extension ShadowClientRTSPInterleavedClientError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "RTSP endpoint URL is invalid."
        case .connectionFailed:
            return "RTSP transport connection timed out."
        case let .requestFailed(message):
            return message
        case .invalidResponse:
            return "RTSP server returned an invalid response."
        case .connectionClosed:
            return "RTSP transport connection closed."
        }
    }
}

private struct ShadowClientRTSPResponse {
    let statusCode: Int
    let headers: [String: String]
    let body: Data
}

private struct ShadowClientRTPPacket {
    let marker: Bool
    let payloadType: Int
    let payload: Data
}

private actor ShadowClientRTSPInterleavedClient {
    private let timeout: Duration
    private let queue = DispatchQueue(label: "com.skyline23.shadowclient.rtsp.connection")
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "RTSP")
    private var connection: NWConnection?
    private var readBuffer = Data()
    private var cseq = 1
    private var sessionHeader: String?

    init(timeout: Duration) {
        self.timeout = timeout
    }

    func start(url: URL) async throws -> ShadowClientRTSPVideoTrackDescriptor {
        let normalizedURL = normalizeRTSPURL(url)
        guard let host = normalizedURL.host else {
            throw ShadowClientRTSPInterleavedClientError.invalidURL
        }
        let portValue = normalizedURL.port ?? 554
        guard let port = NWEndpoint.Port(rawValue: UInt16(portValue)) else {
            throw ShadowClientRTSPInterleavedClientError.invalidURL
        }

        let connection = NWConnection(
            host: .init(host),
            port: port,
            using: .tcp
        )
        self.connection = connection
        try await waitForReady(connection)
        logger.notice("RTSP connected to \(host, privacy: .public):\(portValue, privacy: .public)")

        do {
            _ = try await sendRequest(
                method: "OPTIONS",
                url: normalizedURL.absoluteString,
                headers: [
                    "User-Agent": "ShadowClient/1.0",
                ]
            )
        } catch {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP OPTIONS failed: \(error.localizedDescription)"
            )
        }

        let describe: ShadowClientRTSPResponse
        do {
            describe = try await sendRequest(
                method: "DESCRIBE",
                url: normalizedURL.absoluteString,
                headers: [
                    "Accept": "application/sdp",
                    "User-Agent": "ShadowClient/1.0",
                ]
            )
        } catch {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP DESCRIBE failed: \(error.localizedDescription)"
            )
        }
        let sdp = String(data: describe.body, encoding: .utf8) ?? ""
        let contentBase = describe.headers["content-base"] ?? describe.headers["content-location"]
        let track: ShadowClientRTSPVideoTrackDescriptor
        do {
            track = try ShadowClientRTSPSessionDescriptionParser.parseVideoTrack(
                sdp: sdp,
                contentBase: contentBase,
                fallbackSessionURL: normalizedURL.absoluteString
            )
        } catch {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP track parse failed: \(error.localizedDescription)"
            )
        }

        let setup: ShadowClientRTSPResponse
        do {
            setup = try await sendRequest(
                method: "SETUP",
                url: track.controlURL,
                headers: [
                    "Transport": "RTP/AVP/TCP;unicast;interleaved=0-1;mode=play",
                    "User-Agent": "ShadowClient/1.0",
                ]
            )
        } catch {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP video SETUP failed: \(error.localizedDescription)"
            )
        }
        if let session = setup.headers["session"] {
            sessionHeader = session.split(separator: ";").first.map(String.init)
        }
        logger.notice("RTSP video SETUP ok for payload type \(track.rtpPayloadType, privacy: .public)")

        let audioControls = (try? ShadowClientRTSPSessionDescriptionParser.parseAudioControlURLs(
            sdp: sdp,
            contentBase: contentBase,
            fallbackSessionURL: normalizedURL.absoluteString
        )) ?? []
        if !audioControls.isEmpty {
            var nextChannel = 2
            for controlURL in audioControls {
                var headers: [String: String] = [
                    "Transport": "RTP/AVP/TCP;unicast;interleaved=\(nextChannel)-\(nextChannel + 1);mode=play",
                    "User-Agent": "ShadowClient/1.0",
                ]
                if let sessionHeader {
                    headers["Session"] = sessionHeader
                }

                do {
                    _ = try await sendRequest(
                        method: "SETUP",
                        url: controlURL,
                        headers: headers
                    )
                    logger.notice("RTSP audio SETUP ok for \(controlURL, privacy: .public)")
                } catch {
                    logger.error("RTSP audio SETUP failed for \(controlURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
                nextChannel += 2
            }
        }

        var playHeaders: [String: String] = [
            "User-Agent": "ShadowClient/1.0",
        ]
        if let sessionHeader {
            playHeaders["Session"] = sessionHeader
        }
        do {
            _ = try await sendRequest(
                method: "PLAY",
                url: normalizedURL.absoluteString,
                headers: playHeaders
            )
        } catch {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP PLAY failed: \(error.localizedDescription)"
            )
        }
        logger.notice("RTSP PLAY ok")
        return track
    }

    private func normalizeRTSPURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        if components.path.isEmpty {
            components.path = "/"
        }
        return components.url ?? url
    }

    func stop() {
        connection?.cancel()
        connection = nil
        readBuffer.removeAll(keepingCapacity: false)
    }

    func receiveInterleavedVideoPackets(
        payloadType: Int,
        onVideoPacket: @escaping @Sendable (Data, Bool) async throws -> Void
    ) async throws {
        while !Task.isCancelled {
            if let packet = try parseInterleavedPacketIfAvailable() {
                if packet.payloadType == payloadType {
                    try await onVideoPacket(packet.payload, packet.marker)
                }
                continue
            }

            let chunk = try await receiveBytes()
            guard !chunk.isEmpty else {
                throw ShadowClientRTSPInterleavedClientError.connectionClosed
            }
            readBuffer.append(chunk)
        }
    }

    private func sendRequest(
        method: String,
        url: String,
        headers: [String: String]
    ) async throws -> ShadowClientRTSPResponse {
        guard let connection else {
            throw ShadowClientRTSPInterleavedClientError.connectionFailed
        }

        var lines: [String] = []
        lines.append("\(method) \(url) RTSP/1.0")
        lines.append("CSeq: \(cseq)")
        cseq += 1
        for key in headers.keys.sorted() {
            if let value = headers[key] {
                lines.append("\(key): \(value)")
            }
        }
        lines.append("")
        lines.append("")
        let requestPayload = lines.joined(separator: "\r\n")
        try await send(bytes: Data(requestPayload.utf8), over: connection)

        let response = try await readResponse()
        guard (200...299).contains(response.statusCode) else {
            let bodyText = String(data: response.body, encoding: .utf8) ?? ""
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP \(method) failed (\(response.statusCode)): \(bodyText)"
            )
        }
        return response
    }

    private func readResponse() async throws -> ShadowClientRTSPResponse {
        while true {
            if let response = parseRTSPResponseIfAvailable() {
                return response
            }

            let chunk = try await receiveBytes()
            guard !chunk.isEmpty else {
                throw ShadowClientRTSPInterleavedClientError.connectionClosed
            }
            readBuffer.append(chunk)
        }
    }

    private func parseRTSPResponseIfAvailable() -> ShadowClientRTSPResponse? {
        if let interleaved = try? parseInterleavedPacketIfAvailable() {
            _ = interleaved
        }

        guard let headerRange = readBuffer.range(of: Data([0x0D, 0x0A, 0x0D, 0x0A])) else {
            return nil
        }
        let headerData = readBuffer[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let statusLine = lines.first,
              statusLine.hasPrefix("RTSP/1.0"),
              let statusCode = Int(statusLine.split(separator: " ").dropFirst().first ?? "")
        else {
            return nil
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "") ?? 0
        let bodyStart = headerRange.upperBound
        let bodyEnd = bodyStart + contentLength
        guard readBuffer.count >= bodyEnd else {
            return nil
        }

        let body = Data(readBuffer[bodyStart..<bodyEnd])
        readBuffer.removeSubrange(0..<bodyEnd)
        return ShadowClientRTSPResponse(
            statusCode: statusCode,
            headers: headers,
            body: body
        )
    }

    private func parseInterleavedPacketIfAvailable() throws -> ShadowClientRTPPacket? {
        guard let first = readBuffer.first else {
            return nil
        }

        if first != 0x24 {
            return nil
        }

        guard readBuffer.count >= 4 else {
            return nil
        }

        let frameLength = Int(readBuffer[2]) << 8 | Int(readBuffer[3])
        let packetEnd = 4 + frameLength
        guard readBuffer.count >= packetEnd else {
            return nil
        }

        let payload = readBuffer[4..<packetEnd]
        readBuffer.removeSubrange(0..<packetEnd)
        return try parseRTPPacket(payload)
    }

    private func parseRTPPacket(_ payload: Data) throws -> ShadowClientRTPPacket {
        guard payload.count >= 12 else {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
        }

        let version = payload[0] >> 6
        guard version == 2 else {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
        }

        let hasPadding = (payload[0] & 0x20) != 0
        let hasExtension = (payload[0] & 0x10) != 0
        let csrcCount = Int(payload[0] & 0x0F)
        let marker = (payload[1] & 0x80) != 0
        let payloadType = Int(payload[1] & 0x7F)

        var headerLength = 12 + csrcCount * 4
        guard payload.count >= headerLength else {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
        }

        if hasExtension {
            guard payload.count >= headerLength + 4 else {
                throw ShadowClientRTSPInterleavedClientError.invalidResponse
            }
            let extLengthWords = Int(payload[headerLength + 2]) << 8 | Int(payload[headerLength + 3])
            headerLength += 4 + (extLengthWords * 4)
            guard payload.count >= headerLength else {
                throw ShadowClientRTSPInterleavedClientError.invalidResponse
            }
        }

        var endIndex = payload.count
        if hasPadding, let padding = payload.last {
            endIndex = max(headerLength, payload.count - Int(padding))
        }

        let videoPayload = Data(payload[headerLength..<endIndex])
        return ShadowClientRTPPacket(
            marker: marker,
            payloadType: payloadType,
            payload: videoPayload
        )
    }

    private func waitForReady(_ connection: NWConnection) async throws {
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

                    let gate = ResumeGate(
                        connection: connection,
                        continuation: continuation
                    )
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready:
                            gate.finish(.success(()))
                        case let .failed(error):
                            gate.finish(.failure(error))
                        case .cancelled:
                            gate.finish(.failure(ShadowClientRTSPInterleavedClientError.connectionClosed))
                        default:
                            break
                        }
                    }
                    connection.start(queue: self.queue)
                }
            }

            group.addTask {
                do {
                    try await Task.sleep(for: self.timeout)
                    connection.cancel()
                    return .failure(ShadowClientRTSPInterleavedClientError.connectionFailed)
                } catch {
                    return .failure(error)
                }
            }

            let first = await group.next() ?? .failure(ShadowClientRTSPInterleavedClientError.connectionFailed)
            group.cancelAll()
            return first
        }

        try result.get()
    }

    private func send(bytes: Data, over connection: NWConnection) async throws {
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

    private func receiveBytes() async throws -> Data {
        guard let connection else {
            throw ShadowClientRTSPInterleavedClientError.connectionClosed
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { content, _, isComplete, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if isComplete {
                    continuation.resume(returning: content ?? Data())
                    return
                }

                continuation.resume(returning: content ?? Data())
            }
        }
    }
}

private struct ShadowClientH265RTPDepacketizer: Sendable {
    private var currentNALUnits: [Data] = []
    private var fragmentedNALBuffer: Data?

    mutating func reset() {
        currentNALUnits = []
        fragmentedNALBuffer = nil
    }

    mutating func ingest(payload: Data, marker: Bool) -> Data? {
        guard payload.count >= 3 else {
            return marker ? flushIfNeeded() : nil
        }

        let nalType = (payload[0] >> 1) & 0x3F
        if nalType == 49 {
            ingestFragmentationUnit(payload)
        } else {
            currentNALUnits.append(payload)
        }

        if marker {
            return flushIfNeeded()
        }
        return nil
    }

    private mutating func ingestFragmentationUnit(_ payload: Data) {
        guard payload.count >= 3 else {
            return
        }

        let fuHeader = payload[2]
        let start = (fuHeader & 0x80) != 0
        let end = (fuHeader & 0x40) != 0
        let nalType = fuHeader & 0x3F
        let reconstructedFirstByte = (payload[0] & 0x81) | (nalType << 1)
        let reconstructedSecondByte = payload[1]
        let fuPayload = payload.dropFirst(3)

        if start {
            var nal = Data([reconstructedFirstByte, reconstructedSecondByte])
            nal.append(contentsOf: fuPayload)
            fragmentedNALBuffer = nal
            if end, let fragmentedNALBuffer {
                currentNALUnits.append(fragmentedNALBuffer)
                self.fragmentedNALBuffer = nil
            }
            return
        }

        guard var buffer = fragmentedNALBuffer else {
            return
        }
        buffer.append(contentsOf: fuPayload)
        fragmentedNALBuffer = buffer

        if end {
            currentNALUnits.append(buffer)
            fragmentedNALBuffer = nil
        }
    }

    private mutating func flushIfNeeded() -> Data? {
        guard !currentNALUnits.isEmpty else {
            return nil
        }

        var annexB = Data()
        for nal in currentNALUnits {
            annexB.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            annexB.append(nal)
        }
        currentNALUnits = []
        return annexB
    }
}
