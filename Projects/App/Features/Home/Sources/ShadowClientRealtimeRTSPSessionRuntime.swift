import CoreVideo
import Darwin
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

private actor ShadowClientVideoDecodeQueue {
    private let capacity: Int
    private var bufferedUnits: [ShadowClientRealtimeRTSPSessionRuntime.VideoAccessUnit] = []
    private var waiters: [CheckedContinuation<ShadowClientRealtimeRTSPSessionRuntime.VideoAccessUnit?, Never>] = []
    private var closed = false

    init(capacity: Int) {
        self.capacity = max(2, capacity)
    }

    func enqueue(_ accessUnit: ShadowClientRealtimeRTSPSessionRuntime.VideoAccessUnit) {
        guard !closed else {
            return
        }

        if !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: accessUnit)
            return
        }

        if bufferedUnits.count >= capacity {
            bufferedUnits.removeFirst()
        }
        bufferedUnits.append(accessUnit)
    }

    func next() async -> ShadowClientRealtimeRTSPSessionRuntime.VideoAccessUnit? {
        if !bufferedUnits.isEmpty {
            return bufferedUnits.removeFirst()
        }
        if closed {
            return nil
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func close() {
        guard !closed else {
            return
        }
        closed = true
        bufferedUnits.removeAll(keepingCapacity: false)
        for waiter in waiters {
            waiter.resume(returning: nil)
        }
        waiters.removeAll(keepingCapacity: false)
    }
}

public actor ShadowClientRealtimeRTSPSessionRuntime {
    private struct VideoTransportSample: Sendable {
        let uptimeSeconds: TimeInterval
        let bytes: Int
    }

    fileprivate struct VideoAccessUnit: Sendable {
        let codec: ShadowClientVideoCodec
        let parameterSets: [Data]
        let data: Data
    }

    public let surfaceContext: ShadowClientRealtimeSessionSurfaceContext

    private let decoder: ShadowClientVideoToolboxDecoder
    private let connectTimeout: Duration
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "RealtimeSession")
    private let videoCodecSupport = ShadowClientVideoCodecSupport()
    private var rtspClient: ShadowClientRTSPInterleavedClient?
    private var receiveTask: Task<Void, Never>?
    private var decodeTask: Task<Void, Never>?
    private var videoDecodeQueue: ShadowClientVideoDecodeQueue?
    private var shadowClientNVDepacketizer = ShadowClientMoonlightNVRTPDepacketizer()
    private var hasLoggedDecodedFrameMetadata = false
    private var recentVideoTransportSamples: [VideoTransportSample] = []
    private var lastVideoStatPublishUptime: TimeInterval = 0
    private var activeVideoConfiguration: ShadowClientRemoteSessionVideoConfiguration?
    private var depacketizerCorruptionCount = 0
    private var firstDepacketizerCorruptionUptime: TimeInterval = 0
    private var lastDepacketizerRecoveryUptime: TimeInterval = 0
    private var decoderFailureCount = 0
    private var firstDecoderFailureUptime: TimeInterval = 0
    private var lastDecoderRecoveryUptime: TimeInterval = 0
    private var decoderRecoveryAttemptCount = 0
    private var firstDecoderRecoveryAttemptUptime: TimeInterval = 0
    private var av1DepacketizerRecoveryCount = 0
    private var firstAV1DepacketizerRecoveryUptime: TimeInterval = 0
    private var hasRenderedFirstFrame = false
    private var frameAssemblyLogCount = 0

    public init(
        surfaceContext: ShadowClientRealtimeSessionSurfaceContext = .init(),
        decoder: ShadowClientVideoToolboxDecoder = .init(),
        connectTimeout: Duration = ShadowClientRealtimeSessionDefaults.defaultConnectTimeout
    ) {
        self.surfaceContext = surfaceContext
        self.decoder = decoder
        self.connectTimeout = connectTimeout
    }

    deinit {
        receiveTask?.cancel()
        decodeTask?.cancel()
    }

    public func connect(
        sessionURL: String,
        host _: String,
        appTitle _: String,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration
    ) async throws {
        try await disconnect()
        let resolvedVideoConfiguration = resolveRuntimeVideoConfiguration(videoConfiguration)
        activeVideoConfiguration = resolvedVideoConfiguration
        let sessionSurfaceContext = self.surfaceContext
        await decoder.setPreferredOutputDimensions(
            width: resolvedVideoConfiguration.width,
            height: resolvedVideoConfiguration.height,
            fps: resolvedVideoConfiguration.fps
        )
        await decoder.configureAV1Fallback(
            hdrEnabled: resolvedVideoConfiguration.enableHDR,
            yuv444Enabled: resolvedVideoConfiguration.enableYUV444
        )
        hasLoggedDecodedFrameMetadata = false
        recentVideoTransportSamples.removeAll(keepingCapacity: false)
        lastVideoStatPublishUptime = 0
        depacketizerCorruptionCount = 0
        firstDepacketizerCorruptionUptime = 0
        lastDepacketizerRecoveryUptime = 0
        decoderFailureCount = 0
        firstDecoderFailureUptime = 0
        lastDecoderRecoveryUptime = 0
        decoderRecoveryAttemptCount = 0
        firstDecoderRecoveryAttemptUptime = 0
        av1DepacketizerRecoveryCount = 0
        firstAV1DepacketizerRecoveryUptime = 0
        hasRenderedFirstFrame = false
        frameAssemblyLogCount = 0

        await MainActor.run {
            sessionSurfaceContext.reset()
            sessionSurfaceContext.transition(to: .connecting)
        }

        let trimmed = sessionURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let _ = url.host else {
            throw ShadowClientRealtimeSessionRuntimeError.invalidSessionURL
        }

        let client = ShadowClientRTSPInterleavedClient(
            timeout: connectTimeout,
            onControlRoundTripSample: { [sessionSurfaceContext] roundTripMs in
                await MainActor.run {
                    sessionSurfaceContext.updateControlRoundTripMs(
                        Int(roundTripMs.rounded())
                    )
                }
            },
            onAudioOutputStateChanged: { [sessionSurfaceContext] audioState in
                await MainActor.run {
                    sessionSurfaceContext.updateAudioOutputState(audioState)
                }
            }
        )
        let track = try await client.start(
            url: url,
            videoConfiguration: resolvedVideoConfiguration,
            remoteInputKey: resolvedVideoConfiguration.remoteInputKey,
            remoteInputKeyID: resolvedVideoConfiguration.remoteInputKeyID
        )

        shadowClientNVDepacketizer.configureTailTruncationStrategy(
            Self.depacketizerTailTruncationStrategy(for: track.codec)
        )
        shadowClientNVDepacketizer.reset()
        await MainActor.run {
            surfaceContext.updateActiveVideoCodec(track.codec)
            surfaceContext.transition(to: .waitingForFirstFrame)
        }

        rtspClient = client
        let decodeQueue = ShadowClientVideoDecodeQueue(
            capacity: ShadowClientRealtimeSessionDefaults.videoDecodeQueueCapacity
        )
        videoDecodeQueue = decodeQueue

        receiveTask = Task { [weak self] in
            await self?.runReceiveLoop(
                client: client,
                track: track
            )
        }
        decodeTask = Task { [weak self] in
            await self?.runDecodeLoop()
        }

        try await waitForInitialRenderState(timeout: connectTimeout)
    }

    public func disconnect() async throws {
        receiveTask?.cancel()
        receiveTask = nil
        decodeTask?.cancel()
        decodeTask = nil
        await closeVideoDecodeQueue()

        if let rtspClient {
            await rtspClient.stop()
        }
        rtspClient = nil

        await decoder.reset()
        activeVideoConfiguration = nil
        hasLoggedDecodedFrameMetadata = false
        recentVideoTransportSamples.removeAll(keepingCapacity: false)
        lastVideoStatPublishUptime = 0
        depacketizerCorruptionCount = 0
        firstDepacketizerCorruptionUptime = 0
        lastDepacketizerRecoveryUptime = 0
        decoderFailureCount = 0
        firstDecoderFailureUptime = 0
        lastDecoderRecoveryUptime = 0
        decoderRecoveryAttemptCount = 0
        firstDecoderRecoveryAttemptUptime = 0
        av1DepacketizerRecoveryCount = 0
        firstAV1DepacketizerRecoveryUptime = 0
        hasRenderedFirstFrame = false
        frameAssemblyLogCount = 0
        await MainActor.run {
            surfaceContext.reset()
        }
    }

    public func sendInput(_ event: ShadowClientRemoteInputEvent) async throws {
        guard let rtspClient else {
            return
        }
        try await rtspClient.sendInput(event)
    }

    private func runReceiveLoop(
        client: ShadowClientRTSPInterleavedClient,
        track: ShadowClientRTSPVideoTrackDescriptor
    ) async {
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
            if Task.isCancelled {
                return
            }
            logger.error("Realtime stream task failed: \(error.localizedDescription, privacy: .public)")
            let surfaceContext = self.surfaceContext
            let nextState = Self.renderState(forStreamError: error)
            await MainActor.run {
                surfaceContext.transition(to: nextState)
            }
        }
        await closeVideoDecodeQueue()
    }

    private func runDecodeLoop() async {
        while !Task.isCancelled {
            guard let accessUnit = await dequeueVideoAccessUnit() else {
                return
            }

            do {
                try await decodeFrame(
                    accessUnit: accessUnit.data,
                    codec: accessUnit.codec,
                    parameterSets: accessUnit.parameterSets
                )
                decoderFailureCount = 0
                firstDecoderFailureUptime = 0
                if accessUnit.codec == .av1 {
                    av1DepacketizerRecoveryCount = 0
                    firstAV1DepacketizerRecoveryUptime = 0
                }
            } catch {
                logger.error("\(String(describing: accessUnit.codec), privacy: .public) decode failed: \(error.localizedDescription, privacy: .public)")
                if await handleDecoderFailure(codec: accessUnit.codec) {
                    continue
                }
                if accessUnit.codec == .av1 {
                    await failStreamingSession(
                        message: Self.av1RuntimeFallbackMessage(reason: "decoder recovery exhausted")
                    )
                    return
                }
                await failStreamingSession(message: error.localizedDescription)
                return
            }
        }
    }

    private func dequeueVideoAccessUnit() async -> VideoAccessUnit? {
        guard let videoDecodeQueue else {
            return nil
        }
        return await videoDecodeQueue.next()
    }

    private func closeVideoDecodeQueue() async {
        if let videoDecodeQueue {
            await videoDecodeQueue.close()
        }
        self.videoDecodeQueue = nil
    }

    private func failStreamingSession(message: String) async {
        logger.error("\(message, privacy: .public)")
        receiveTask?.cancel()
        let sessionSurfaceContext = self.surfaceContext
        await MainActor.run {
            sessionSurfaceContext.transition(to: .failed(message))
        }
        await closeVideoDecodeQueue()
    }

    private func consumeRTPPayload(
        codec: ShadowClientVideoCodec,
        payload: Data,
        marker: Bool,
        initialParameterSets: [Data]
    ) async throws {
        _ = marker
        switch shadowClientNVDepacketizer.ingestWithStatus(payload: payload, marker: marker) {
        case .noFrame:
            return
        case .droppedCorruptFrame:
            if await handleDepacketizerCorruption(codec: codec),
               codec == .av1
            {
                throw ShadowClientRealtimeSessionRuntimeError.transportFailure(
                    Self.av1RuntimeFallbackMessage(reason: "depacketizer recovery exhausted")
                )
            }
            return
        case let .frame(frame):
            frameAssemblyLogCount &+= 1
            if frameAssemblyLogCount <= 5 || frameAssemblyLogCount.isMultiple(of: 180) {
                logger.notice("ShadowClient NV frame assembled for codec \(String(describing: codec), privacy: .public): \(frame.count, privacy: .public) bytes")
            }
            depacketizerCorruptionCount = 0
            firstDepacketizerCorruptionUptime = 0

            await updateRuntimeVideoStats(frameBytes: frame.count)
            if codec == .av1,
               !Self.isLikelyValidAV1AccessUnit(frame)
            {
                logger.error("Dropping malformed AV1 access unit before decoder submit")
                if await handleDepacketizerCorruption(codec: codec),
                   codec == .av1
                {
                    throw ShadowClientRealtimeSessionRuntimeError.transportFailure(
                        Self.av1RuntimeFallbackMessage(reason: "invalid AV1 access unit stream")
                    )
                }
                return
            }
            if let videoDecodeQueue {
                await videoDecodeQueue.enqueue(
                    .init(
                        codec: codec,
                        parameterSets: initialParameterSets,
                        data: frame
                    )
                )
            }
        }
    }

    private func handleDepacketizerCorruption(codec: ShadowClientVideoCodec) async -> Bool {
        let now = ProcessInfo.processInfo.systemUptime
        if firstDepacketizerCorruptionUptime == 0 ||
            now - firstDepacketizerCorruptionUptime > ShadowClientRealtimeSessionDefaults.depacketizerCorruptionWindowSeconds
        {
            firstDepacketizerCorruptionUptime = now
            depacketizerCorruptionCount = 0
        }
        depacketizerCorruptionCount += 1

        guard depacketizerCorruptionCount >= ShadowClientRealtimeSessionDefaults.depacketizerCorruptionThreshold else {
            return false
        }
        guard now - lastDepacketizerRecoveryUptime >= ShadowClientRealtimeSessionDefaults.depacketizerRecoveryCooldownSeconds else {
            return false
        }

        lastDepacketizerRecoveryUptime = now
        depacketizerCorruptionCount = 0
        firstDepacketizerCorruptionUptime = 0
        if codec == .av1 {
            if firstAV1DepacketizerRecoveryUptime == 0 ||
                now - firstAV1DepacketizerRecoveryUptime > ShadowClientRealtimeSessionDefaults.av1DepacketizerRecoveryWindowSeconds
            {
                firstAV1DepacketizerRecoveryUptime = now
                av1DepacketizerRecoveryCount = 0
            }
            av1DepacketizerRecoveryCount += 1
            if av1DepacketizerRecoveryCount >= ShadowClientRealtimeSessionDefaults.av1MaxDepacketizerRecoveries {
                logger.error(
                    "AV1 depacketizer recovery attempts exceeded threshold; forcing HEVC fallback path"
                )
                return true
            }
        }
        logger.error("Video depacketizer detected sustained stream discontinuity for codec \(String(describing: codec), privacy: .public); requesting recovery frame")
        if let rtspClient {
            await rtspClient.requestVideoRecoveryFrame()
        }
        let sessionSurfaceContext = self.surfaceContext
        await MainActor.run {
            sessionSurfaceContext.transition(to: .waitingForFirstFrame)
        }
        return false
    }

    private func handleDecoderFailure(codec: ShadowClientVideoCodec) async -> Bool {
        if !hasRenderedFirstFrame, codec != .av1 {
            return false
        }

        let now = ProcessInfo.processInfo.systemUptime
        if firstDecoderFailureUptime == 0 ||
            now - firstDecoderFailureUptime > ShadowClientRealtimeSessionDefaults.decoderFailureWindowSeconds
        {
            firstDecoderFailureUptime = now
            decoderFailureCount = 0
        }
        decoderFailureCount += 1

        if hasRenderedFirstFrame, decoderFailureCount == 1 {
            logger.notice(
                "Video decoder dropped one frame for codec \(String(describing: codec), privacy: .public); awaiting recovery before forcing reset"
            )
            return true
        }

        guard now - lastDecoderRecoveryUptime >= ShadowClientRealtimeSessionDefaults.decoderRecoveryCooldownSeconds else {
            return true
        }

        lastDecoderRecoveryUptime = now
        decoderFailureCount = 0
        firstDecoderFailureUptime = 0
        hasLoggedDecodedFrameMetadata = false

        if firstDecoderRecoveryAttemptUptime == 0 ||
            now - firstDecoderRecoveryAttemptUptime > ShadowClientRealtimeSessionDefaults.decoderRecoveryAttemptWindowSeconds
        {
            firstDecoderRecoveryAttemptUptime = now
            decoderRecoveryAttemptCount = 0
        }
        decoderRecoveryAttemptCount += 1
        if codec == .av1,
           decoderRecoveryAttemptCount >= ShadowClientRealtimeSessionDefaults.av1MaxDecoderRecoveryAttempts
        {
            logger.error(
                "AV1 decoder recovery attempts exceeded threshold; forcing HEVC fallback path"
            )
            return false
        }

        logger.error(
            "Video decoder entered recovery for codec \(String(describing: codec), privacy: .public); resetting decoder and requesting recovery frame"
        )
        await decoder.reset()
        if let configuration = activeVideoConfiguration {
            await decoder.setPreferredOutputDimensions(
                width: configuration.width,
                height: configuration.height,
                fps: configuration.fps
            )
            await decoder.configureAV1Fallback(
                hdrEnabled: configuration.enableHDR,
                yuv444Enabled: configuration.enableYUV444
            )
        }
        if let rtspClient {
            await rtspClient.requestVideoRecoveryFrame()
        }
        let sessionSurfaceContext = self.surfaceContext
        await MainActor.run {
            sessionSurfaceContext.transition(to: .waitingForFirstFrame)
        }
        return true
    }

    private func decodeFrame(
        accessUnit: Data,
        codec: ShadowClientVideoCodec,
        parameterSets: [Data]
    ) async throws {
        let surfaceContext = self.surfaceContext
        let runtime = self
        try await decoder.decode(
            accessUnit: accessUnit,
            codec: codec,
            parameterSets: parameterSets
        ) { [surfaceContext] pixelBuffer in
            let sendableFrame = ShadowClientSendablePixelBuffer(value: pixelBuffer)
            await runtime.logDecodedFrameMetadataIfNeeded(
                codec: codec,
                pixelBuffer: sendableFrame.value
            )
            await MainActor.run {
                surfaceContext.frameStore.update(pixelBuffer: sendableFrame.value)
                surfaceContext.transition(to: .rendering)
            }
        }
    }

    private func resolveRuntimeVideoConfiguration(
        _ configuration: ShadowClientRemoteSessionVideoConfiguration
    ) -> ShadowClientRemoteSessionVideoConfiguration {
        let resolvedCodecPreference = videoCodecSupport.resolvePreferredCodec(
            configuration.preferredCodec,
            enableHDR: configuration.enableHDR,
            enableYUV444: configuration.enableYUV444
        )
        return .init(
            width: configuration.width,
            height: configuration.height,
            fps: configuration.fps,
            bitrateKbps: configuration.bitrateKbps,
            preferredCodec: resolvedCodecPreference,
            enableHDR: configuration.enableHDR,
            enableSurroundAudio: configuration.enableSurroundAudio,
            enableYUV444: configuration.enableYUV444,
            remoteInputKey: configuration.remoteInputKey,
            remoteInputKeyID: configuration.remoteInputKeyID
        )
    }

    private func updateRuntimeVideoStats(frameBytes: Int) async {
        let now = ProcessInfo.processInfo.systemUptime
        recentVideoTransportSamples.append(
            .init(uptimeSeconds: now, bytes: max(0, frameBytes))
        )
        recentVideoTransportSamples.removeAll {
            now - $0.uptimeSeconds > 1.0
        }

        guard let oldest = recentVideoTransportSamples.first else {
            return
        }

        let windowDuration = max(now - oldest.uptimeSeconds, 0.001)
        let totalBytes = recentVideoTransportSamples.reduce(0) { $0 + $1.bytes }
        let bitrateKbps = Int((Double(totalBytes) * 8.0 / 1_000.0) / windowDuration)
        let fps = Double(recentVideoTransportSamples.count) / windowDuration

        if now - lastVideoStatPublishUptime < 0.2 {
            return
        }
        lastVideoStatPublishUptime = now

        let sessionSurfaceContext = self.surfaceContext
        await MainActor.run {
            sessionSurfaceContext.updateRuntimeVideoStats(
                fps: fps,
                bitrateKbps: bitrateKbps
            )
        }
    }

    private func waitForInitialRenderState(timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout

        while clock.now < deadline {
            if Task.isCancelled {
                throw CancellationError()
            }

            let state = await MainActor.run {
                surfaceContext.renderState
            }

            switch state {
            case .rendering:
                return
            case let .disconnected(message):
                throw ShadowClientRealtimeSessionRuntimeError.transportFailure(message)
            case let .failed(message):
                throw ShadowClientRealtimeSessionRuntimeError.transportFailure(message)
            case .idle, .connecting, .waitingForFirstFrame:
                break
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        throw ShadowClientRealtimeSessionRuntimeError.transportFailure(
            "Timed out waiting for first frame."
        )
    }

    private func logDecodedFrameMetadataIfNeeded(
        codec: ShadowClientVideoCodec,
        pixelBuffer: CVPixelBuffer
    ) {
        hasRenderedFirstFrame = true
        guard !hasLoggedDecodedFrameMetadata else {
            return
        }
        hasLoggedDecodedFrameMetadata = true

        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let transfer = attachmentStringValue(
            forKey: kCVImageBufferTransferFunctionKey,
            pixelBuffer: pixelBuffer
        ) ?? "nil"
        let primaries = attachmentStringValue(
            forKey: kCVImageBufferColorPrimariesKey,
            pixelBuffer: pixelBuffer
        ) ?? "nil"
        let matrix = attachmentStringValue(
            forKey: kCVImageBufferYCbCrMatrixKey,
            pixelBuffer: pixelBuffer
        ) ?? "nil"

        logger.notice(
            "Decoded first frame metadata codec=\(String(describing: codec), privacy: .public) pixel-format=0x\(String(pixelFormat, radix: 16), privacy: .public) primaries=\(primaries, privacy: .public) transfer=\(transfer, privacy: .public) matrix=\(matrix, privacy: .public)"
        )
    }

    private func attachmentStringValue(
        forKey key: CFString,
        pixelBuffer: CVPixelBuffer
    ) -> String? {
        guard let attachment = CVBufferCopyAttachment(pixelBuffer, key, nil) else {
            return nil
        }
        if let value = attachment as? String {
            return value
        }
        if CFGetTypeID(attachment) == CFStringGetTypeID() {
            return attachment as? String
        }
        return nil
    }

    private static func depacketizerTailTruncationStrategy(
        for codec: ShadowClientVideoCodec
    ) -> ShadowClientMoonlightNVRTPDepacketizer.TailTruncationStrategy {
        switch codec {
        case .h264, .h265:
            // H264/H265 tolerate trailing zero padding and Sunshine doesn't guarantee valid lastPayloadLength.
            return .passthroughForAnnexBCodecs
        case .av1:
            return .trimUsingLastPacketLength
        }
    }

    private static func av1RuntimeFallbackMessage(reason: String) -> String {
        "AV1 decode failed (\(reason)). Runtime recovery exhausted; retry with HEVC fallback."
    }

    static func isLikelyValidAV1AccessUnit(_ accessUnit: Data) -> Bool {
        guard !accessUnit.isEmpty else {
            return false
        }

        var index = 0
        while index < accessUnit.count {
            let obuHeader = accessUnit[index]
            // forbidden bit and reserved bit should both be unset
            if (obuHeader & 0x80) != 0 || (obuHeader & 0x01) != 0 {
                return false
            }

            let hasExtension = (obuHeader & 0x04) != 0
            let hasSizeField = (obuHeader & 0x02) != 0
            guard hasSizeField else {
                return false
            }

            index += 1
            if hasExtension {
                guard index < accessUnit.count else {
                    return false
                }
                index += 1
            }

            guard let leb = decodeLEB128(in: accessUnit, from: index) else {
                return false
            }
            index = leb.nextIndex
            guard leb.value >= 0, index + leb.value <= accessUnit.count else {
                return false
            }
            index += leb.value
        }

        return true
    }

    private static func decodeLEB128(
        in data: Data,
        from startIndex: Int
    ) -> (value: Int, nextIndex: Int)? {
        guard startIndex < data.count else {
            return nil
        }

        var value = 0
        var shift = 0
        var index = startIndex

        while index < data.count, shift <= 56 {
            let byte = Int(data[index])
            value |= (byte & 0x7F) << shift
            index += 1
            if (byte & 0x80) == 0 {
                return (value, index)
            }
            shift += 7
        }

        return nil
    }

    private static func renderState(forStreamError error: Error) -> ShadowClientRealtimeSessionSurfaceContext.RenderState {
        let normalizedMessage = error.localizedDescription
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = normalizedMessage.isEmpty ? "RTSP transport connection closed." : normalizedMessage

        if isConnectionTerminationError(error, message: fallback) {
            return .disconnected(fallback)
        }

        return .failed(fallback)
    }

    private static func isConnectionTerminationError(_ error: Error, message: String) -> Bool {
        if let rtspError = error as? ShadowClientRTSPInterleavedClientError {
            switch rtspError {
            case .connectionClosed, .connectionFailed:
                return true
            case .invalidURL, .requestFailed, .invalidResponse:
                break
            }
        }

        let normalized = message.lowercased()
        let terminationSignatures = [
            "connection reset by peer",
            "connection closed",
            "connection timed out",
            "no message available on stream",
            "broken pipe",
            "network is down",
            "no route to host",
            "not connected",
            "network connection was lost",
            "software caused connection abort",
            "transport connection closed",
        ]
        return terminationSignatures.contains(where: normalized.contains)
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

struct ShadowClientRTPPacket {
    let isRTP: Bool
    let channel: Int
    let sequenceNumber: UInt16
    let marker: Bool
    let payloadType: Int
    let payload: Data
}

struct ShadowClientRTPPacketPayloadParseResult: Equatable, Sendable {
    let sequenceNumber: UInt16
    let marker: Bool
    let payloadType: Int
    let payload: Data
}

enum ShadowClientRTPPacketPayloadParserError: Error, Equatable {
    case invalidPacket
}

enum ShadowClientRTPPacketPayloadParser {
    static func parse(
        _ payload: Data
    ) throws -> ShadowClientRTPPacketPayloadParseResult {
        guard payload.count >= ShadowClientRTSPProtocolProfile.rtpMinimumHeaderLength else {
            throw ShadowClientRTPPacketPayloadParserError.invalidPacket
        }

        let version = payload[0] >> ShadowClientRTSPProtocolProfile.rtpVersionShift
        guard version == ShadowClientRTSPProtocolProfile.rtpVersion else {
            throw ShadowClientRTPPacketPayloadParserError.invalidPacket
        }

        let hasPadding = (payload[0] & ShadowClientRTSPProtocolProfile.rtpPaddingMask) != 0
        let hasExtension = (payload[0] & ShadowClientRTSPProtocolProfile.rtpExtensionMask) != 0
        let csrcCount = Int(payload[0] & ShadowClientRTSPProtocolProfile.rtpCSRCCountMask)
        let marker = (payload[1] & ShadowClientRTSPProtocolProfile.rtpMarkerMask) != 0
        let payloadType = Int(payload[1] & ShadowClientRTSPProtocolProfile.rtpPayloadTypeMask)
        let sequenceNumber = (UInt16(payload[2]) << 8) | UInt16(payload[3])

        var headerLength = ShadowClientRTSPProtocolProfile.rtpMinimumHeaderLength + csrcCount * 4
        guard payload.count >= headerLength else {
            throw ShadowClientRTPPacketPayloadParserError.invalidPacket
        }

        if hasExtension {
            // Moonlight/Sunshine RTP video packets carry a fixed 4-byte extension preamble
            // before NV packet data. The extension length field is not used in the same way
            // as generic RFC3550 streams, so we intentionally skip only these 4 bytes.
            headerLength += 4
            guard payload.count >= headerLength else {
                throw ShadowClientRTPPacketPayloadParserError.invalidPacket
            }
        }

        var endIndex = payload.count
        if hasPadding, let padding = payload.last {
            endIndex = max(headerLength, payload.count - Int(padding))
        }
        guard endIndex > headerLength else {
            throw ShadowClientRTPPacketPayloadParserError.invalidPacket
        }

        return ShadowClientRTPPacketPayloadParseResult(
            sequenceNumber: sequenceNumber,
            marker: marker,
            payloadType: payloadType,
            payload: Data(payload[headerLength..<endIndex])
        )
    }
}

struct ShadowClientRTPVideoReorderBuffer: Sendable {
    private let targetDepth: Int
    private let maximumDepth: Int
    private var expectedSequence: UInt16?
    private var packetsBySequence: [UInt16: ShadowClientRTPPacket] = [:]

    init(targetDepth: Int = 4, maximumDepth: Int = 96) {
        self.targetDepth = max(2, targetDepth)
        self.maximumDepth = max(self.targetDepth, maximumDepth)
    }

    mutating func reset() {
        expectedSequence = nil
        packetsBySequence.removeAll(keepingCapacity: false)
    }

    mutating func enqueue(_ packet: ShadowClientRTPPacket) -> [ShadowClientRTPPacket] {
        guard packetsBySequence[packet.sequenceNumber] == nil else {
            return []
        }

        packetsBySequence[packet.sequenceNumber] = packet
        if expectedSequence == nil {
            expectedSequence = packet.sequenceNumber
        }

        var readyPackets = drainContiguousPackets()
        if readyPackets.isEmpty, packetsBySequence.count >= targetDepth {
            advanceExpectedSequenceToNearestPacket()
            readyPackets = drainContiguousPackets()
        }

        trimOverflow()
        return readyPackets
    }

    private mutating func drainContiguousPackets() -> [ShadowClientRTPPacket] {
        var readyPackets: [ShadowClientRTPPacket] = []
        while let expectedSequence,
              let packet = packetsBySequence.removeValue(forKey: expectedSequence)
        {
            readyPackets.append(packet)
            self.expectedSequence = expectedSequence &+ 1
        }
        return readyPackets
    }

    private mutating func advanceExpectedSequenceToNearestPacket() {
        guard let expectedSequence,
              !packetsBySequence.isEmpty
        else {
            return
        }

        let orderedByDistance = packetsBySequence.keys.sorted { lhs, rhs in
            sequenceDistance(from: expectedSequence, to: lhs) <
                sequenceDistance(from: expectedSequence, to: rhs)
        }
        self.expectedSequence = orderedByDistance.first
    }

    private mutating func trimOverflow() {
        guard packetsBySequence.count > maximumDepth,
              let expectedSequence
        else {
            return
        }

        let keysByDistance = packetsBySequence.keys.sorted { lhs, rhs in
            sequenceDistance(from: expectedSequence, to: lhs) <
                sequenceDistance(from: expectedSequence, to: rhs)
        }
        let keysToKeep = Set(keysByDistance.prefix(maximumDepth))
        packetsBySequence = packetsBySequence.filter { keysToKeep.contains($0.key) }
    }

    private func sequenceDistance(from start: UInt16, to end: UInt16) -> UInt16 {
        end &- start
    }
}

private actor ShadowClientRTSPInterleavedClient {
    private let timeout: Duration
    private let onControlRoundTripSample: (@Sendable (Double) async -> Void)?
    private let onAudioOutputStateChanged: (@Sendable (ShadowClientRealtimeAudioOutputState) async -> Void)?
    private let defaultClientPortBase: UInt16 = ShadowClientRTSPProtocolProfile.clientPortBase
    private let queue = DispatchQueue(label: "com.skyline23.shadowclient.rtsp.connection")
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "RTSP")
    private var connection: NWConnection?
    private var readBuffer = Data()
    private var cseq = 1
    private var sessionHeader: String?
    private var remoteHost: NWEndpoint.Host?
    private var localHost: NWEndpoint.Host?
    private var audioServerPort: NWEndpoint.Port?
    private var videoServerPort: NWEndpoint.Port?
    private var controlServerPort: NWEndpoint.Port?
    private var audioPingPayload: Data?
    private var videoPingPayload: Data?
    private var audioTrackDescriptor: ShadowClientRTSPAudioTrackDescriptor?
    private var prePlayVideoUDPSocket: ShadowClientUDPDatagramSocket?
    private var prePlayVideoPingWarmupTask: Task<Void, Never>?
    private var controlConnectData: UInt32?
    private var controlChannelRuntime: ShadowClientSunshineControlChannelRuntime?
    private var controlChannelMode: ShadowClientSunshineControlChannelMode = .plaintext
    private var hasStartedControlChannelBootstrap = false
    private var useSessionIdentifierV1 = false
    private var remoteInputKey: Data?
    private var remoteInputKeyID: UInt32?
    private var audioEncryptionConfiguration: ShadowClientRealtimeAudioEncryptionConfiguration?
    private var negotiatedClientPortBase: UInt16 = ShadowClientRTSPProtocolProfile.clientPortBase
    private var loggedInputSendKinds = Set<String>()
    private var loggedInputDropKinds = Set<String>()

    init(
        timeout: Duration,
        onControlRoundTripSample: (@Sendable (Double) async -> Void)? = nil,
        onAudioOutputStateChanged: (@Sendable (ShadowClientRealtimeAudioOutputState) async -> Void)? = nil
    ) {
        self.timeout = timeout
        self.onControlRoundTripSample = onControlRoundTripSample
        self.onAudioOutputStateChanged = onAudioOutputStateChanged
    }

    func start(
        url: URL,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration,
        remoteInputKey: Data?,
        remoteInputKeyID: UInt32?
    ) async throws -> ShadowClientRTSPVideoTrackDescriptor {
        self.remoteInputKey = remoteInputKey
        self.remoteInputKeyID = remoteInputKeyID
        hasStartedControlChannelBootstrap = false
        loggedInputSendKinds.removeAll(keepingCapacity: true)
        loggedInputDropKinds.removeAll(keepingCapacity: true)
        audioTrackDescriptor = nil
        let normalizedURL = normalizeRTSPURL(url)
        guard let host = normalizedURL.host else {
            throw ShadowClientRTSPInterleavedClientError.invalidURL
        }
        remoteHost = .init(host)
        let portValue = normalizedURL.port ?? ShadowClientRTSPProtocolProfile.defaultPort
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
        if let resolvedHost = resolvedRemoteHost(from: connection) {
            remoteHost = resolvedHost
            logger.notice("RTSP resolved remote endpoint host \(String(describing: resolvedHost), privacy: .public)")
        }
        if let resolvedHost = resolvedLocalHost(from: connection) {
            localHost = resolvedHost
            logger.notice("RTSP resolved local endpoint host \(String(describing: resolvedHost), privacy: .public)")
        }
        logger.notice("RTSP connected to \(host, privacy: .public):\(portValue, privacy: .public)")
        logger.notice("RTSP session URL \(normalizedURL.absoluteString, privacy: .public)")

        do {
            _ = try await sendRequest(
                method: ShadowClientRTSPRequestDefaults.optionsMethod,
                url: normalizedURL.absoluteString,
                headers: [
                    ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
                ]
            )
        } catch {
            logger.notice(
                "RTSP OPTIONS retry on fresh TCP connection after failure: \(error.localizedDescription, privacy: .public)"
            )
            try await reconnect(host: host, port: port)
            do {
                _ = try await sendRequest(
                    method: ShadowClientRTSPRequestDefaults.optionsMethod,
                    url: normalizedURL.absoluteString,
                    headers: [
                        ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
                    ]
                )
            } catch {
                throw ShadowClientRTSPInterleavedClientError.requestFailed(
                    "RTSP OPTIONS failed: \(error.localizedDescription)"
                )
            }
        }

        let describe: ShadowClientRTSPResponse
        do {
            describe = try await sendDescribeRequest(
                url: normalizedURL.absoluteString,
                headers: [
                    ShadowClientRTSPRequestDefaults.headerAccept: ShadowClientRTSPRequestDefaults.acceptSDP,
                    ShadowClientRTSPRequestDefaults.headerIfModifiedSince: ShadowClientRTSPRequestDefaults.ifModifiedSinceEpoch,
                    ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
                ]
            )
        } catch {
            logger.notice(
                "RTSP DESCRIBE retry on fresh TCP connection after failure: \(error.localizedDescription, privacy: .public)"
            )
            // Some GameStream/Sunshine stacks close the RTSP socket after OPTIONS.
            // Retry DESCRIBE on a fresh socket before failing the handshake.
            try await reconnect(host: host, port: port)
            do {
                describe = try await sendDescribeRequest(
                    url: normalizedURL.absoluteString,
                    headers: [
                        ShadowClientRTSPRequestDefaults.headerAccept: ShadowClientRTSPRequestDefaults.acceptSDP,
                        ShadowClientRTSPRequestDefaults.headerIfModifiedSince: ShadowClientRTSPRequestDefaults.ifModifiedSinceEpoch,
                        ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
                    ]
                )
            } catch {
                throw ShadowClientRTSPInterleavedClientError.requestFailed(
                    "RTSP DESCRIBE failed: \(error.localizedDescription)"
                )
            }
        }
        let sdp = String(data: describe.body, encoding: .utf8) ?? ""
        logger.notice("RTSP DESCRIBE parsed body bytes \(describe.body.count, privacy: .public), characters \(sdp.count, privacy: .public)")

        // Keep one RTSP socket for the SETUP/ANNOUNCE/PLAY sequence, like Moonlight.
        // Sunshine can acknowledge PLAY on a new socket but still keep UDP routing tied
        // to the transport state negotiated on the original connection.
        try await reconnect(host: host, port: port)
        let contentBase =
            describe.headers[ShadowClientRTSPRequestDefaults.responseHeaderContentBase] ??
            describe.headers[ShadowClientRTSPRequestDefaults.responseHeaderContentLocation]
        let parsedTrack: ShadowClientRTSPVideoTrackDescriptor
        if sdp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parsedTrack = fallbackVideoTrackDescriptor(
                sessionURL: normalizedURL.absoluteString,
                describeSDP: nil,
                videoConfiguration: videoConfiguration
            )
            logger.notice("RTSP DESCRIBE returned empty SDP; using fallback video track \(parsedTrack.controlURL, privacy: .public)")
        } else {
            do {
                parsedTrack = try ShadowClientRTSPSessionDescriptionParser.parseVideoTrack(
                    sdp: sdp,
                    contentBase: contentBase,
                    fallbackSessionURL: normalizedURL.absoluteString
                )
            } catch {
                parsedTrack = fallbackVideoTrackDescriptor(
                    sessionURL: normalizedURL.absoluteString,
                    describeSDP: sdp,
                    videoConfiguration: videoConfiguration
                )
                logger.notice("RTSP track parse failed (\(error.localizedDescription, privacy: .public)); using fallback video track \(parsedTrack.controlURL, privacy: .public)")
            }
        }
        let announceCodec = preferredAnnounceCodec(
            preferredCodec: videoConfiguration.preferredCodec,
            describedCodec: parsedTrack.codec
        )
        if announceCodec != parsedTrack.codec {
            logger.notice(
                "RTSP overriding described codec \(String(describing: parsedTrack.codec), privacy: .public) with preferred codec \(String(describing: announceCodec), privacy: .public)"
            )
        }
        let track = ShadowClientRTSPVideoTrackDescriptor(
            codec: announceCodec,
            rtpPayloadType: parsedTrack.rtpPayloadType,
            controlURL: parsedTrack.controlURL,
            parameterSets: announceCodec == parsedTrack.codec ? parsedTrack.parameterSets : []
        )

        negotiatedClientPortBase = ShadowClientRTSPClientPortAllocator.selectClientPortBase(
            preferred: defaultClientPortBase,
            localHost: localHost
        )
        if negotiatedClientPortBase != defaultClientPortBase {
            logger.notice(
                "RTSP selected alternate client port base \(self.negotiatedClientPortBase, privacy: .public) (preferred \(self.defaultClientPortBase, privacy: .public))"
            )
        }
        let setupTransportHeader = ShadowClientRTSPProtocolProfile.setupTransportHeader(
            clientPortBase: negotiatedClientPortBase
        )
        let setupURLCandidates = videoControlURLCandidates(
            primary: track.controlURL,
            sessionURL: normalizedURL.absoluteString
        )
        let parsedAudioTrack = ShadowClientRTSPSessionDescriptionParser.parseAudioTrack(
            sdp: sdp,
            contentBase: contentBase,
            fallbackSessionURL: normalizedURL.absoluteString
        )
        if let parsedAudioTrack {
            audioTrackDescriptor = parsedAudioTrack
            logger.notice(
                "RTSP audio track parsed codec=\(parsedAudioTrack.codec.label, privacy: .public) payloadType=\(parsedAudioTrack.rtpPayloadType, privacy: .public) sampleRate=\(parsedAudioTrack.sampleRate, privacy: .public) channels=\(parsedAudioTrack.channelCount, privacy: .public)"
            )
        }
        let audioControls = (try? ShadowClientRTSPSessionDescriptionParser.parseAudioControlURLs(
            sdp: sdp,
            contentBase: contentBase,
            fallbackSessionURL: normalizedURL.absoluteString
        )) ?? []
        let prioritizedAudioControls = {
            if let parsedControlURL = parsedAudioTrack?.controlURL {
                return [parsedControlURL] + audioControls
            }
            return audioControls
        }()
        let audioSetupCandidates = audioControlURLCandidates(
            controlsFromSDP: prioritizedAudioControls,
            sessionURL: normalizedURL.absoluteString
        )
        if !audioSetupCandidates.isEmpty {
            for controlURL in audioSetupCandidates {
                var headers: [String: String] = [
                    ShadowClientRTSPRequestDefaults.headerTransport: setupTransportHeader,
                    ShadowClientRTSPRequestDefaults.headerIfModifiedSince: ShadowClientRTSPRequestDefaults.ifModifiedSinceEpoch,
                    ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
                ]
                if let sessionHeader {
                    headers[ShadowClientRTSPRequestDefaults.headerSession] = sessionHeader
                }

                do {
                    let response = try await sendRequestWithReconnectRetry(
                        method: ShadowClientRTSPRequestDefaults.setupMethod,
                        url: controlURL,
                        headers: headers,
                        host: host,
                        port: port
                    )
                    if sessionHeader == nil,
                       let session = response.headers[ShadowClientRTSPRequestDefaults.responseHeaderSession]
                    {
                        sessionHeader = session.split(separator: ";").first.map(String.init)
                    }
                    if let transport = response.headers[ShadowClientRTSPRequestDefaults.responseHeaderTransport],
                       let parsedPort = ShadowClientRTSPTransportHeaderParser.parseServerPort(from: transport)
                    {
                        audioServerPort = NWEndpoint.Port(rawValue: parsedPort)
                        logger.notice("RTSP negotiated UDP audio server port \(parsedPort, privacy: .public)")
                    }
                    audioPingPayload = ShadowClientRTSPTransportHeaderParser.parseSunshinePingPayload(
                        from: response.headers[ShadowClientRTSPRequestDefaults.responseHeaderPingPayload]
                    )
                    if let audioPingPayload,
                       let token = String(data: audioPingPayload, encoding: .utf8)
                    {
                        logger.notice("RTSP audio ping payload token \(token, privacy: .public)")
                    } else {
                        logger.notice("RTSP audio ping payload token unavailable; legacy ping fallback only")
                    }
                    logger.notice("RTSP audio SETUP ok for \(controlURL, privacy: .public)")
                    break
                } catch {
                    logger.error("RTSP audio SETUP failed for \(controlURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        let controlHost = remoteHost ?? .init(host)

        var setup: ShadowClientRTSPResponse?
        var selectedSetupURL: String?
        var setupError: Error?
        for setupURL in setupURLCandidates {
            do {
                var headers: [String: String] = [
                    ShadowClientRTSPRequestDefaults.headerTransport: setupTransportHeader,
                    ShadowClientRTSPRequestDefaults.headerIfModifiedSince: ShadowClientRTSPRequestDefaults.ifModifiedSinceEpoch,
                    ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
                ]
                if let sessionHeader {
                    headers[ShadowClientRTSPRequestDefaults.headerSession] = sessionHeader
                }
                let response = try await sendRequestWithReconnectRetry(
                    method: ShadowClientRTSPRequestDefaults.setupMethod,
                    url: setupURL,
                    headers: headers,
                    host: host,
                    port: port
                )
                setup = response
                selectedSetupURL = setupURL
                break
            } catch {
                setupError = error
                logger.error("RTSP video SETUP failed for \(setupURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        guard let setup else {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP video SETUP failed: \(setupError?.localizedDescription ?? "unknown")"
            )
        }
        if let session = setup.headers[ShadowClientRTSPRequestDefaults.responseHeaderSession] {
            sessionHeader = session.split(separator: ";").first.map(String.init)
        }
        if let transport = setup.headers[ShadowClientRTSPRequestDefaults.responseHeaderTransport],
           let parsedPort = ShadowClientRTSPTransportHeaderParser.parseServerPort(from: transport)
        {
            videoServerPort = NWEndpoint.Port(rawValue: parsedPort)
            logger.notice("RTSP negotiated UDP video server port \(parsedPort, privacy: .public)")
        } else {
            videoServerPort = nil
        }
        videoPingPayload = ShadowClientRTSPTransportHeaderParser.parseSunshinePingPayload(
            from: setup.headers[ShadowClientRTSPRequestDefaults.responseHeaderPingPayload]
        )
        if let videoPingPayload,
           let token = String(data: videoPingPayload, encoding: .utf8)
        {
            logger.notice("RTSP video ping payload token \(token, privacy: .public)")
        } else {
            logger.notice("RTSP video ping payload token unavailable; legacy ping fallback only")
        }
        logger.notice("RTSP video SETUP ok for payload type \(track.rtpPayloadType, privacy: .public) via \(selectedSetupURL ?? track.controlURL, privacy: .public)")
        prepareVideoPingBeforePlay(host: controlHost)

        var parsedControlConnectData: UInt32?
        var parsedControlServerPort: NWEndpoint.Port?
        let controlSetupCandidates = controlStreamURLCandidates(
            sessionURL: normalizedURL.absoluteString
        )
        for controlURL in controlSetupCandidates {
            var headers: [String: String] = [
                ShadowClientRTSPRequestDefaults.headerTransport: setupTransportHeader,
                ShadowClientRTSPRequestDefaults.headerIfModifiedSince: ShadowClientRTSPRequestDefaults.ifModifiedSinceEpoch,
                ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
            ]
            if let sessionHeader {
                headers[ShadowClientRTSPRequestDefaults.headerSession] = sessionHeader
            }

            do {
                let response = try await sendRequestWithReconnectRetry(
                    method: ShadowClientRTSPRequestDefaults.setupMethod,
                    url: controlURL,
                    headers: headers,
                    host: host,
                    port: port
                )
                if let transport = response.headers[ShadowClientRTSPRequestDefaults.responseHeaderTransport],
                   let parsedPort = ShadowClientRTSPTransportHeaderParser.parseServerPort(from: transport)
                {
                    parsedControlServerPort = NWEndpoint.Port(rawValue: parsedPort)
                    logger.notice("RTSP negotiated UDP control server port \(parsedPort, privacy: .public)")
                }
                if let parsed = ShadowClientRTSPTransportHeaderParser.parseSunshineControlConnectData(
                    from: response.headers[ShadowClientRTSPRequestDefaults.responseHeaderConnectData]
                ) {
                    parsedControlConnectData = parsed
                    logger.notice("RTSP control connect data \(parsed, privacy: .public)")
                }
                logger.notice("RTSP control SETUP ok for \(controlURL, privacy: .public)")
                break
            } catch {
                logger.error("RTSP control SETUP failed for \(controlURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        controlConnectData = parsedControlConnectData
        controlServerPort = parsedControlServerPort

        let handshakeNegotiation = ShadowClientSunshineHandshakeNegotiation(
            audioPingPayload: audioPingPayload,
            videoPingPayload: videoPingPayload,
            controlConnectData: parsedControlConnectData,
            encryptionRequestedFlags: parseSunshineEncryptionRequestedFlags(from: sdp),
            prefersSessionIdentifierV1: ShadowClientSunshineSessionDefaults.prefersSessionIdentifierV1,
            supportsEncryptedControlChannelV2: ShadowClientSunshineSessionDefaults.supportsEncryptedControlChannelV2 && remoteInputKey != nil,
            supportsEncryptedAudioTransport: remoteInputKey != nil && remoteInputKeyID != nil
        )
        useSessionIdentifierV1 = handshakeNegotiation.supportsSessionIdentifierV1
        if handshakeNegotiation.controlChannelEncryptionEnabled, let remoteInputKey
        {
            controlChannelMode = .encryptedV2(key: remoteInputKey)
        } else {
            controlChannelMode = .plaintext
        }
        let controlModeLabel: String
        switch controlChannelMode {
        case .plaintext:
            controlModeLabel = "plaintext"
        case .encryptedV2:
            controlModeLabel = "encrypted-v2"
        }
        if handshakeNegotiation.audioEncryptionEnabled,
           let remoteInputKey,
           let remoteInputKeyID
        {
            audioEncryptionConfiguration = .init(
                key: remoteInputKey,
                keyID: remoteInputKeyID
            )
        } else {
            audioEncryptionConfiguration = nil
        }
        let audioEncryptionLabel = handshakeNegotiation.audioEncryptionEnabled ? "encrypted" : "plaintext"
        logger.notice(
            "RTSP negotiation session-id-v1=\(handshakeNegotiation.supportsSessionIdentifierV1, privacy: .public) ml-flags=\(handshakeNegotiation.moonlightFeatureFlags, privacy: .public) encryption-enabled=\(handshakeNegotiation.encryptionEnabledFlags, privacy: .public) control-mode=\(controlModeLabel, privacy: .public) audio-mode=\(audioEncryptionLabel, privacy: .public)"
        )

        let announcePayload = ShadowClientRTSPAnnouncePayloadBuilder.build(
            hostAddress: host,
            videoConfiguration: videoConfiguration,
            codec: track.codec,
            videoPort: videoServerPort?.rawValue ?? ShadowClientRealtimeSessionDefaults.fallbackVideoPort,
            moonlightFeatureFlags: handshakeNegotiation.moonlightFeatureFlags,
            encryptionEnabledFlags: handshakeNegotiation.encryptionEnabledFlags
        )
        let announceTargets = announceURLCandidates(sessionURL: normalizedURL.absoluteString)
        var announceHeaders: [String: String] = [
            ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
            ShadowClientRTSPRequestDefaults.headerContentType: ShadowClientRTSPRequestDefaults.acceptSDP,
            ShadowClientRTSPRequestDefaults.headerContentLength: "\(announcePayload.count)",
        ]
        if let sessionHeader {
            announceHeaders[ShadowClientRTSPRequestDefaults.headerSession] = sessionHeader
        }

        var announceSucceeded = false
        for announceTarget in announceTargets {
            do {
                _ = try await sendRequestWithReconnectRetry(
                    method: ShadowClientRTSPRequestDefaults.announceMethod,
                    url: announceTarget,
                    headers: announceHeaders,
                    body: announcePayload,
                    host: host,
                    port: port
                )
                logger.notice("RTSP ANNOUNCE ok for \(announceTarget, privacy: .public)")
                announceSucceeded = true
                break
            } catch {
                logger.error("RTSP ANNOUNCE failed for \(announceTarget, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if !announceSucceeded {
            logger.error("RTSP ANNOUNCE did not succeed on any target; continuing to PLAY for compatibility")
        }

        let playHeaders: [String: String] = [
            ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
        ]
        let resolvedPlayHeaders: [String: String]
        if let sessionHeader {
            var headers = playHeaders
            headers["Session"] = sessionHeader
            resolvedPlayHeaders = headers
        } else {
            resolvedPlayHeaders = playHeaders
        }

        let playTargets = playURLCandidates(sessionURL: normalizedURL.absoluteString)
        var playSucceeded = false
        var lastPlayError: Error?
        for playTarget in playTargets {
            do {
                _ = try await sendRequestWithReconnectRetry(
                    method: ShadowClientRTSPRequestDefaults.playMethod,
                    url: playTarget,
                    headers: resolvedPlayHeaders,
                    host: host,
                    port: port
                )
                logger.notice("RTSP PLAY ok for \(playTarget, privacy: .public)")
                playSucceeded = true
                break
            } catch {
                lastPlayError = error
                logger.error("RTSP PLAY failed for \(playTarget, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        guard playSucceeded else {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP PLAY failed: \(lastPlayError?.localizedDescription ?? "unknown")"
            )
        }

        var didStartSunshineControl = false
        if controlServerPort != nil {
            await ensureSunshineControlChannelStarted(fallbackHost: remoteHost ?? .init(host))
            didStartSunshineControl = hasStartedControlChannelBootstrap
            if didStartSunshineControl {
                logger.debug("RTSP control path negotiated; Sunshine control bootstrap ready")
            } else {
                logger.debug("RTSP control path negotiated; Sunshine bootstrap unavailable, trying legacy first-frame compatibility probe")
            }
        }
        if !didStartSunshineControl {
            await attemptLegacyFirstFrameBootstrap(host: remoteHost ?? .init(host))
        }
        return track
    }

    private func preferredAnnounceCodec(
        preferredCodec: ShadowClientVideoCodecPreference,
        describedCodec: ShadowClientVideoCodec
    ) -> ShadowClientVideoCodec {
        switch preferredCodec {
        case .auto:
            return describedCodec
        case .av1:
            return .av1
        case .h265:
            return .h265
        case .h264:
            return .h264
        }
    }

    private func reconnect(
        host: String,
        port: NWEndpoint.Port
    ) async throws {
        connection?.cancel()
        connection = nil
        readBuffer.removeAll(keepingCapacity: false)

        let nextConnection = NWConnection(
            host: .init(host),
            port: port,
            using: .tcp
        )
        connection = nextConnection
        try await waitForReady(nextConnection)
        if let resolvedHost = resolvedRemoteHost(from: nextConnection) {
            remoteHost = resolvedHost
        } else {
            remoteHost = .init(host)
        }
        localHost = resolvedLocalHost(from: nextConnection)
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

    private func fallbackVideoTrackDescriptor(
        sessionURL: String,
        describeSDP: String?,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration
    ) -> ShadowClientRTSPVideoTrackDescriptor {
        let codec: ShadowClientVideoCodec
        switch videoConfiguration.preferredCodec {
        case .av1:
            codec = .av1
        case .h265:
            codec = .h265
        case .h264:
            codec = .h264
        case .auto:
            codec = inferFallbackCodec(fromDescribeSDP: describeSDP)
        }

        let controlURL = videoControlURLCandidates(
            primary: sessionURL,
            sessionURL: sessionURL
        ).first ?? sessionURL

        let payloadType = inferFallbackPayloadType(
            fromDescribeSDP: describeSDP,
            codec: codec
        )

        return ShadowClientRTSPVideoTrackDescriptor(
            codec: codec,
            rtpPayloadType: payloadType,
            controlURL: controlURL,
            parameterSets: []
        )
    }

    private func inferFallbackCodec(fromDescribeSDP sdp: String?) -> ShadowClientVideoCodec {
        guard let sdp else {
            return .h264
        }

        if sdp.localizedCaseInsensitiveContains(ShadowClientRTSPProtocolProfile.av1ClockRateMarker) {
            return .av1
        }
        if sdp.localizedCaseInsensitiveContains(ShadowClientRTSPProtocolProfile.h265ClockRateMarker) ||
            sdp.localizedCaseInsensitiveContains(ShadowClientRTSPProtocolProfile.hevcClockRateMarker) ||
            sdp.contains(ShadowClientRTSPProtocolProfile.hevcParameterSetMarker)
        {
            return .h265
        }
        return .h264
    }

    private func inferFallbackPayloadType(
        fromDescribeSDP sdp: String?,
        codec: ShadowClientVideoCodec
    ) -> Int {
        guard let sdp else {
            return ShadowClientRTSPProtocolProfile.fallbackVideoPayloadType
        }

        return ShadowClientRTSPSessionDescriptionParser.inferFallbackVideoPayloadType(
            sdp: sdp,
            preferredCodec: codec
        ) ?? ShadowClientRTSPProtocolProfile.fallbackVideoPayloadType
    }

    private func videoControlURLCandidates(
        primary: String,
        sessionURL: String
    ) -> [String] {
        var candidates: [String] = []

        func add(_ value: String?) {
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else {
                return
            }
            candidates.append(trimmed)
        }

        add(primary)
        ShadowClientRTSPProtocolProfile.videoControlPaths.forEach(add)

        if let parsedSessionURL = URL(string: sessionURL) {
            let normalizedBaseURL = normalizeRTSPURL(parsedSessionURL)
            var components = URLComponents(url: normalizedBaseURL, resolvingAgainstBaseURL: false)
            for path in ShadowClientRTSPProtocolProfile.videoControlPaths.map(ShadowClientRTSPProtocolProfile.absolutePath) {
                components?.path = path
                add(components?.url?.absoluteString)
            }
        }

        return candidates
    }

    private func audioControlURLCandidates(
        controlsFromSDP: [String],
        sessionURL: String
    ) -> [String] {
        var candidates: [String] = []

        func add(_ value: String?) {
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else {
                return
            }
            candidates.append(trimmed)
        }

        controlsFromSDP.forEach(add)
        ShadowClientRTSPProtocolProfile.audioControlPaths.forEach(add)

        if let parsedSessionURL = URL(string: sessionURL) {
            let normalizedBaseURL = normalizeRTSPURL(parsedSessionURL)
            var components = URLComponents(url: normalizedBaseURL, resolvingAgainstBaseURL: false)
            for path in ShadowClientRTSPProtocolProfile.audioControlPaths.map(ShadowClientRTSPProtocolProfile.absolutePath) {
                components?.path = path
                add(components?.url?.absoluteString)
            }
        }

        return candidates
    }

    private func controlStreamURLCandidates(sessionURL: String) -> [String] {
        var candidates: [String] = []

        func add(_ value: String?) {
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else {
                return
            }
            candidates.append(trimmed)
        }

        ShadowClientRTSPProtocolProfile.controlStreamPaths.forEach(add)

        if let parsedSessionURL = URL(string: sessionURL) {
            let normalizedBaseURL = normalizeRTSPURL(parsedSessionURL)
            var components = URLComponents(url: normalizedBaseURL, resolvingAgainstBaseURL: false)
            for path in ShadowClientRTSPProtocolProfile.controlStreamPaths.map(ShadowClientRTSPProtocolProfile.absolutePath) {
                components?.path = path
                add(components?.url?.absoluteString)
            }
        }

        return candidates
    }

    private func announceURLCandidates(sessionURL: String) -> [String] {
        var candidates: [String] = []

        func add(_ value: String?) {
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else {
                return
            }
            candidates.append(trimmed)
        }

        ShadowClientRTSPProtocolProfile.announcePaths.forEach(add)

        if let parsedSessionURL = URL(string: sessionURL) {
            let normalizedBaseURL = normalizeRTSPURL(parsedSessionURL)
            var components = URLComponents(url: normalizedBaseURL, resolvingAgainstBaseURL: false)
            for path in ShadowClientRTSPProtocolProfile.announcePaths.map(ShadowClientRTSPProtocolProfile.absolutePath) {
                components?.path = path
                add(components?.url?.absoluteString)
            }
        }

        return candidates
    }

    private func playURLCandidates(sessionURL: String) -> [String] {
        var candidates: [String] = []

        func add(_ value: String?) {
            guard let value else {
                return
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else {
                return
            }
            candidates.append(trimmed)
        }

        ShadowClientRTSPProtocolProfile.playPaths.forEach(add)
        add(sessionURL)
        return candidates
    }

    private func parseSunshineEncryptionRequestedFlags(from sdp: String) -> UInt32 {
        let lines = sdp
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            let lower = line.lowercased()
            guard let range = lower.range(
                of: ShadowClientSunshineHandshakeProfile.encryptionRequestedAttributePrefix
            ) else {
                continue
            }

            let rawValue = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = UInt32(rawValue) {
                return parsed
            }
        }

        return ShadowClientSunshineHandshakeProfile.encryptionDisabled
    }

    private func ensureSunshineControlChannelStarted(
        fallbackHost: NWEndpoint.Host
    ) async {
        guard !hasStartedControlChannelBootstrap else {
            return
        }
        let started = await startSunshineControlChannelIfNeeded(
            host: String(describing: fallbackHost)
        )
        hasStartedControlChannelBootstrap = started
    }

    private func startSunshineControlChannelIfNeeded(host: String) async -> Bool {
        guard let controlServerPort else {
            logger.notice("RTSP control bootstrap skipped (no negotiated control server port)")
            return true
        }

        if controlChannelRuntime != nil {
            return true
        }

        let controlHost = remoteHost ?? .init(host)
        let runtime = ShadowClientSunshineControlChannelRuntime(
            onRoundTripSample: onControlRoundTripSample
        )

        do {
            try await runtime.start(
                host: controlHost,
                port: controlServerPort,
                connectData: controlConnectData,
                mode: controlChannelMode
            )
            controlChannelRuntime = runtime
            return true
        } catch {
            logger.error("RTSP control bootstrap failed: \(error.localizedDescription, privacy: .public)")
            await runtime.stop()
            return false
        }
    }

    func stop() async {
        if let controlChannelRuntime {
            await controlChannelRuntime.stop()
        }
        controlChannelRuntime = nil
        hasStartedControlChannelBootstrap = false
        cancelPrePlayPingWarmupTasks()

        connection?.cancel()
        connection = nil
        readBuffer.removeAll(keepingCapacity: false)
        remoteHost = nil
        localHost = nil
        audioServerPort = nil
        videoServerPort = nil
        controlServerPort = nil
        audioPingPayload = nil
        videoPingPayload = nil
        audioTrackDescriptor = nil
        prePlayVideoUDPSocket?.close()
        prePlayVideoUDPSocket = nil
        controlConnectData = nil
        controlChannelMode = .plaintext
        useSessionIdentifierV1 = false
        remoteInputKey = nil
        remoteInputKeyID = nil
        audioEncryptionConfiguration = nil
        negotiatedClientPortBase = defaultClientPortBase
        loggedInputSendKinds.removeAll(keepingCapacity: false)
        loggedInputDropKinds.removeAll(keepingCapacity: false)
    }

    func sendInput(_ event: ShadowClientRemoteInputEvent) async throws {
        await ensureSunshineControlChannelStarted(
            fallbackHost: remoteHost ?? .init("127.0.0.1")
        )

        guard let controlChannelRuntime else {
            return
        }
        guard let packet = ShadowClientSunshineInputPacketCodec.encode(event) else {
            let kind = inputEventKind(event)
            if loggedInputDropKinds.insert(kind).inserted {
                logger.notice("Sunshine input dropped during encode for event \(kind, privacy: .public)")
            }
            return
        }

        let kind = inputEventKind(event)
        if loggedInputSendKinds.insert(kind).inserted {
            logger.notice(
                "Sunshine input send enabled for event \(kind, privacy: .public) channel=\(packet.channelID, privacy: .public) bytes=\(packet.payload.count, privacy: .public)"
            )
        }

        try await controlChannelRuntime.sendInputPacket(
            packet.payload,
            channelID: packet.channelID
        )
    }

    func requestVideoRecoveryFrame() async {
        await ensureSunshineControlChannelStarted(
            fallbackHost: remoteHost ?? .init("127.0.0.1")
        )
        guard let controlChannelRuntime else {
            return
        }
        await controlChannelRuntime.requestVideoRecoveryFrame()
    }

    private func inputEventKind(_ event: ShadowClientRemoteInputEvent) -> String {
        switch event {
        case .keyDown:
            return "keyDown"
        case .keyUp:
            return "keyUp"
        case .pointerMoved:
            return "pointerMoved"
        case .pointerButton:
            return "pointerButton"
        case .scroll:
            return "scroll"
        case .gamepadState:
            return "gamepadState"
        case .gamepadArrival:
            return "gamepadArrival"
        }
    }

    func receiveInterleavedVideoPackets(
        payloadType: Int,
        onVideoPacket: @escaping @Sendable (Data, Bool) async throws -> Void
    ) async throws {
        let audioTrack = audioTrackDescriptor
        if let remoteHost, let videoServerPort {
            try await receiveUDPVideoPackets(
                host: remoteHost,
                port: videoServerPort,
                payloadType: payloadType,
                audioTrack: audioTrack,
                onVideoPacket: onVideoPacket
            )
            return
        }

        var effectivePayloadType = payloadType
        var hasReceivedVideoPayload = false
        var packetCount = 0
        var reorderBuffer = ShadowClientRTPVideoReorderBuffer()

        while !Task.isCancelled {
            if let packet = try parseInterleavedPacketIfAvailable() {
                guard packet.isRTP, packet.channel == 0 else {
                    continue
                }

                packetCount += 1
                if packetCount == 1 {
                    await ensureSunshineControlChannelStarted(
                        fallbackHost: remoteHost ?? .init("127.0.0.1")
                    )
                    logger.notice(
                        "First RTP video packet received: payloadType=\(packet.payloadType, privacy: .public), marker=\(packet.marker, privacy: .public), payloadBytes=\(packet.payload.count, privacy: .public)"
                    )
                }

                if packet.payloadType == effectivePayloadType {
                    hasReceivedVideoPayload = true
                    let orderedPackets = reorderBuffer.enqueue(packet)
                    for orderedPacket in orderedPackets {
                        try await onVideoPacket(
                            orderedPacket.payload,
                            orderedPacket.marker
                        )
                    }
                    continue
                }

                if !hasReceivedVideoPayload,
                   packet.payloadType != ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType
                {
                    logger.notice(
                        "RTSP payload type mismatch; adopting stream payload type \(packet.payloadType, privacy: .public) (expected \(effectivePayloadType, privacy: .public))"
                    )
                    effectivePayloadType = packet.payloadType
                    reorderBuffer.reset()
                    hasReceivedVideoPayload = true
                    let orderedPackets = reorderBuffer.enqueue(packet)
                    for orderedPacket in orderedPackets {
                        try await onVideoPacket(
                            orderedPacket.payload,
                            orderedPacket.marker
                        )
                    }
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

    private func receiveUDPVideoPackets(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        payloadType: Int,
        audioTrack: ShadowClientRTSPAudioTrackDescriptor?,
        onVideoPacket: @escaping @Sendable (Data, Bool) async throws -> Void
    ) async throws {
        cancelPrePlayPingWarmupTasks()

        let localHost = self.localHost
        let udpSocket: ShadowClientUDPDatagramSocket
        if let prePlaySocket = prePlayVideoUDPSocket {
            udpSocket = prePlaySocket
            prePlayVideoUDPSocket = nil
            logger.notice("RTSP UDP video socket reused from pre-PLAY bootstrap")
        } else {
            udpSocket = try makeVideoUDPSocket(
                host: host,
                port: port,
                localHost: localHost
            )
        }
        logger.notice("RTSP video receive switched to UDP \(String(describing: host), privacy: .public):\(port.rawValue, privacy: .public)")

        let pingPayload = videoPingPayload
        let rtspLogger = logger
        let audioPingPayload = self.audioPingPayload
        let audioEncryptionConfiguration = self.audioEncryptionConfiguration
        let audioRuntime = ShadowClientRealtimeAudioSessionRuntime(
            stateDidChange: onAudioOutputStateChanged
        )

        do {
            let initialVideoPings = ShadowClientSunshinePingPacketCodec.makePingPackets(
                sequence: 1,
                negotiatedPayload: pingPayload
            )
            for initialVideoPing in initialVideoPings {
                try udpSocket.send(initialVideoPing)
            }
            rtspLogger.notice("RTSP UDP video initial ping sent (variants=\(initialVideoPings.count, privacy: .public), bytes=\(initialVideoPings.first?.count ?? 0, privacy: .public))")
        } catch {
            rtspLogger.error("RTSP UDP video initial ping failed: \(error.localizedDescription, privacy: .public)")
        }

        if let audioServerPort {
            do {
                try await audioRuntime.start(
                    remoteHost: host,
                    remotePort: audioServerPort,
                    localHost: localHost,
                    preferredLocalPort: negotiatedClientPortBase &+ 1,
                    track: audioTrack,
                    pingPayload: audioPingPayload,
                    encryption: audioEncryptionConfiguration
                )
                rtspLogger.notice("RTSP UDP audio receive switched to \(String(describing: host), privacy: .public):\(audioServerPort.rawValue, privacy: .public)")
            } catch {
                rtspLogger.error("RTSP UDP audio runtime setup failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        let sendableVideoSocket = udpSocket

        let pingTask = Task {
            var sequence: UInt32 = 1
            var loggedPingCount = 0
            var loggedPingError = false
            while !Task.isCancelled {
                sequence &+= 1
                do {
                    let pingPackets = ShadowClientSunshinePingPacketCodec.makePingPackets(
                        sequence: sequence,
                        negotiatedPayload: pingPayload
                    )
                    for pingPacket in pingPackets {
                        try sendableVideoSocket.send(pingPacket)
                    }
                    if loggedPingCount < 3 {
                        rtspLogger.notice("RTSP UDP video ping sent (sequence=\(sequence, privacy: .public), variants=\(pingPackets.count, privacy: .public), bytes=\(pingPackets.first?.count ?? 0, privacy: .public))")
                        loggedPingCount += 1
                    }
                } catch {
                    if !loggedPingError {
                        rtspLogger.error("RTSP UDP video ping send failed: \(error.localizedDescription, privacy: .public)")
                        loggedPingError = true
                    }
                }
                try? await Task.sleep(for: ShadowClientRealtimeSessionDefaults.pingInterval)
            }
        }

        defer {
            pingTask.cancel()
            audioRuntime.stop()
            udpSocket.close()
        }

        var effectivePayloadType = payloadType
        var hasReceivedVideoPayload = false
        var packetCount = 0
        var parseFailureCount = 0
        var datagramCount = 0
        var reorderBuffer = ShadowClientRTPVideoReorderBuffer()
        let receiveStart = ContinuousClock.now

        while !Task.isCancelled {
            guard let datagram = try udpSocket.receive(
                maximumLength: ShadowClientRealtimeSessionDefaults.maximumTransportReadLength
            ) else {
                if datagramCount == 0,
                   receiveStart.duration(to: ContinuousClock.now) >= ShadowClientRealtimeSessionDefaults.initialVideoDatagramTimeout
                {
                    throw ShadowClientRTSPInterleavedClientError.requestFailed(
                        "RTSP UDP video timeout: no video datagram received"
                    )
                }
                continue
            }
            guard !datagram.isEmpty else {
                continue
            }

            datagramCount += 1
            if datagramCount == 1 {
                logger.notice(
                    "First UDP video datagram received: bytes=\(datagram.count, privacy: .public), preview=\(Self.hexPreview(datagram), privacy: .public)"
                )
            }

            let packet: ShadowClientRTPPacket
            do {
                packet = try parseRTPPacket(datagram, channel: 0)
            } catch {
                parseFailureCount += 1
                if parseFailureCount <= ShadowClientRealtimeSessionDefaults.udpParseFailureLogLimit {
                    logger.error(
                        "RTSP UDP datagram ignored (RTP parse failed #\(parseFailureCount, privacy: .public)): \(error.localizedDescription, privacy: .public), bytes=\(datagram.count, privacy: .public), preview=\(Self.hexPreview(datagram), privacy: .public)"
                    )
                }
                continue
            }

            packetCount += 1
            if packetCount == 1 {
                await ensureSunshineControlChannelStarted(fallbackHost: host)
                logger.notice(
                    "First RTP video packet received: payloadType=\(packet.payloadType, privacy: .public), marker=\(packet.marker, privacy: .public), payloadBytes=\(packet.payload.count, privacy: .public)"
                )
            }

            if packet.payloadType == effectivePayloadType {
                hasReceivedVideoPayload = true
                let orderedPackets = reorderBuffer.enqueue(packet)
                for orderedPacket in orderedPackets {
                    try await onVideoPacket(
                        orderedPacket.payload,
                        orderedPacket.marker
                    )
                }
                continue
            }

            if !hasReceivedVideoPayload,
               packet.payloadType != ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType
            {
                logger.notice(
                    "RTSP payload type mismatch; adopting stream payload type \(packet.payloadType, privacy: .public) (expected \(effectivePayloadType, privacy: .public))"
                )
                effectivePayloadType = packet.payloadType
                reorderBuffer.reset()
                hasReceivedVideoPayload = true
                let orderedPackets = reorderBuffer.enqueue(packet)
                for orderedPacket in orderedPackets {
                    try await onVideoPacket(
                        orderedPacket.payload,
                        orderedPacket.marker
                    )
                }
            }
        }
    }

    private static func hexPreview(_ bytes: Data, limit: Int = 24) -> String {
        let prefix = bytes.prefix(limit)
            .map { String(format: "%02X", $0) }
            .joined()
        return bytes.count > limit ? prefix + "..." : prefix
    }

    private func makeVideoUDPSocket(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        localHost: NWEndpoint.Host?
    ) throws -> ShadowClientUDPDatagramSocket {
        let preferredLocalPort = negotiatedVideoPingPort()
        do {
            let socket = try ShadowClientUDPDatagramSocket(
                localHost: localHost,
                localPort: preferredLocalPort,
                remoteHost: host,
                remotePort: port.rawValue
            )
            logger.notice(
                "RTSP UDP video socket bound \(socket.localEndpointDescription(), privacy: .public) (preferred-client-port \(preferredLocalPort, privacy: .public))"
            )
            return socket
        } catch {
            logger.error(
                "RTSP UDP video bind on preferred client port \(preferredLocalPort, privacy: .public) failed: \(error.localizedDescription, privacy: .public); retrying with ephemeral port"
            )
            let socket = try ShadowClientUDPDatagramSocket(
                localHost: localHost,
                localPort: nil,
                remoteHost: host,
                remotePort: port.rawValue
            )
            logger.notice("RTSP UDP video socket bound \(socket.localEndpointDescription(), privacy: .public) (ephemeral-fallback)")
            return socket
        }
    }

    private func negotiatedVideoPingPort() -> UInt16 {
        negotiatedClientPortBase
    }

    private func prepareVideoPingBeforePlay(host: NWEndpoint.Host) {
        guard prePlayVideoUDPSocket == nil,
              let videoServerPort
        else {
            return
        }

        do {
            let socket = try makeVideoUDPSocket(
                host: host,
                port: videoServerPort,
                localHost: localHost
            )
            prePlayVideoUDPSocket = socket

            let prePlayPings = ShadowClientSunshinePingPacketCodec.makePingPackets(
                sequence: 1,
                negotiatedPayload: videoPingPayload
            )
            for packet in prePlayPings {
                try socket.send(packet)
            }
            logger.notice(
                "RTSP UDP video pre-PLAY ping sent (variants=\(prePlayPings.count, privacy: .public), bytes=\(prePlayPings.first?.count ?? 0, privacy: .public))"
            )
            prePlayVideoPingWarmupTask?.cancel()
            let payload = videoPingPayload
            prePlayVideoPingWarmupTask = Task { [logger] in
                var sequence: UInt32 = 1
                var loggedSendCount = 0
                while !Task.isCancelled {
                    sequence &+= 1
                    let pingPackets = ShadowClientSunshinePingPacketCodec.makePingPackets(
                        sequence: sequence,
                        negotiatedPayload: payload
                    )
                    for packet in pingPackets {
                        try? socket.send(packet)
                    }
                    if loggedSendCount < 2 {
                        logger.debug("RTSP UDP video pre-PLAY warmup ping sent (sequence=\(sequence, privacy: .public), variants=\(pingPackets.count, privacy: .public))")
                        loggedSendCount += 1
                    }
                    try? await Task.sleep(for: ShadowClientRealtimeSessionDefaults.pingInterval)
                }
            }
        } catch {
            prePlayVideoPingWarmupTask?.cancel()
            prePlayVideoPingWarmupTask = nil
            prePlayVideoUDPSocket?.close()
            prePlayVideoUDPSocket = nil
            logger.error("RTSP UDP video pre-PLAY ping setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func cancelPrePlayPingWarmupTasks() {
        prePlayVideoPingWarmupTask?.cancel()
        prePlayVideoPingWarmupTask = nil
    }

    private func attemptLegacyFirstFrameBootstrap(host: NWEndpoint.Host) async {
        guard let port = NWEndpoint.Port(
            rawValue: ShadowClientRTSPProtocolProfile.legacyFirstFrameBootstrapPort
        ) else {
            return
        }

        let bootstrapConnection = NWConnection(host: host, port: port, using: .tcp)
        do {
            try await waitForReady(
                bootstrapConnection,
                timeout: .milliseconds(700)
            )
            logger.notice("RTSP legacy first-frame bootstrap connected on \(port.rawValue, privacy: .public)")
        } catch {
            logger.debug("RTSP legacy first-frame bootstrap skipped: \(error.localizedDescription, privacy: .public)")
        }
        bootstrapConnection.cancel()
    }

    private func sendRequest(
        method: String,
        url: String,
        headers: [String: String],
        body: Data = Data()
    ) async throws -> ShadowClientRTSPResponse {
        guard let connection else {
            throw ShadowClientRTSPInterleavedClientError.connectionFailed
        }

        let requestPayload = buildRequestPayload(
            method: method,
            url: url,
            headers: headers,
            body: body
        )
        try await send(bytes: requestPayload, over: connection)

        let response = try await readResponse()
        logResponse(method: method, response: response)
        guard (200...299).contains(response.statusCode) else {
            let bodyText = String(data: response.body, encoding: .utf8) ?? ""
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP \(method) failed (\(response.statusCode)): \(bodyText)"
            )
        }
        return response
    }

    private func sendRequestWithReconnectRetry(
        method: String,
        url: String,
        headers: [String: String],
        body: Data = Data(),
        host: String,
        port: NWEndpoint.Port
    ) async throws -> ShadowClientRTSPResponse {
        do {
            return try await sendRequest(
                method: method,
                url: url,
                headers: headers,
                body: body
            )
        } catch {
            guard shouldRetryAfterReconnect(error) else {
                throw error
            }

            logger.notice(
                "RTSP \(method, privacy: .public) retrying after reconnect due to transport error: \(error.localizedDescription, privacy: .public)"
            )
            try await reconnect(host: host, port: port)
            return try await sendRequest(
                method: method,
                url: url,
                headers: headers,
                body: body
            )
        }
    }

    private func shouldRetryAfterReconnect(_ error: Error) -> Bool {
        if let rtspError = error as? ShadowClientRTSPInterleavedClientError {
            switch rtspError {
            case .requestFailed:
                return false
            case .invalidURL:
                return false
            case .connectionFailed, .invalidResponse, .connectionClosed:
                return true
            }
        }

        return true
    }

    private func sendDescribeRequest(
        url: String,
        headers: [String: String]
    ) async throws -> ShadowClientRTSPResponse {
        guard let connection else {
            throw ShadowClientRTSPInterleavedClientError.connectionFailed
        }

        let requestPayload = buildRequestPayload(
            method: ShadowClientRTSPRequestDefaults.describeMethod,
            url: url,
            headers: headers
        )
        try await send(bytes: requestPayload, over: connection)

        let rawResponse = try await readResponseUntilConnectionClose()
        let response = try parseRTSPResponseFromRawData(rawResponse)
        logResponse(method: ShadowClientRTSPRequestDefaults.describeMethod, response: response)

        guard (200...299).contains(response.statusCode) else {
            let bodyText = String(data: response.body, encoding: .utf8) ?? ""
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP DESCRIBE failed (\(response.statusCode)): \(bodyText)"
            )
        }

        return response
    }

    private func readResponseUntilConnectionClose() async throws -> Data {
        var response = Data()

        while true {
            do {
                let chunk = try await receiveBytes()
                if chunk.isEmpty {
                    break
                }
                response.append(chunk)
            } catch {
                if response.isEmpty {
                    throw error
                }

                logger.notice(
                    "RTSP read terminated after partial response (\(error.localizedDescription, privacy: .public)); proceeding with buffered bytes \(response.count, privacy: .public)"
                )
                break
            }
        }

        guard !response.isEmpty else {
            throw ShadowClientRTSPInterleavedClientError.connectionClosed
        }
        return response
    }

    private func parseRTSPResponseFromRawData(_ rawData: Data) throws -> ShadowClientRTSPResponse {
        let headerTerminatorCRLF = ShadowClientRTSPProtocolProfile.headerTerminatorCRLF
        let headerTerminatorLF = ShadowClientRTSPProtocolProfile.headerTerminatorLF
        let headerRange: Range<Int>
        let bodyStart: Int

        if let range = rawData.range(of: headerTerminatorCRLF) {
            headerRange = range
            bodyStart = range.upperBound
        } else if let range = rawData.range(of: headerTerminatorLF) {
            headerRange = range
            bodyStart = range.upperBound
        } else {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
        }

        let headerData = rawData[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
        }

        let lines = headerText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let statusLine = lines.first,
              statusLine.hasPrefix(ShadowClientRTSPRequestDefaults.protocolVersion),
              let statusCode = Int(statusLine.split(separator: " ").dropFirst().first ?? "")
        else {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
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

        let body: Data
        if let contentLength = Int(
            headers[ShadowClientRTSPRequestDefaults.responseHeaderContentLength] ?? ""
        ), contentLength >= 0 {
            let end = min(rawData.count, bodyStart + contentLength)
            body = Data(rawData[bodyStart..<end])
        } else {
            body = bodyStart <= rawData.count ? Data(rawData[bodyStart...]) : Data()
        }

        return ShadowClientRTSPResponse(
            statusCode: statusCode,
            headers: headers,
            body: body
        )
    }

    private func buildRequestPayload(
        method: String,
        url: String,
        headers: [String: String],
        body: Data = Data()
    ) -> Data {
        var lines: [String] = []
        lines.append("\(method) \(url) \(ShadowClientRTSPRequestDefaults.protocolVersion)")
        lines.append("CSeq: \(cseq)")
        cseq += 1
        lines.append(
            "\(ShadowClientRTSPRequestDefaults.headerClientVersion): \(ShadowClientRTSPRequestDefaults.clientVersionHeaderValue)"
        )
        if let hostHeader = ShadowClientRTSPProtocolProfile.hostHeaderValue(forRTSPURLString: url) {
            lines.append("\(ShadowClientRTSPRequestDefaults.headerHost): \(hostHeader)")
        }
        for key in headers.keys.sorted() {
            if let value = headers[key] {
                lines.append("\(key): \(value)")
            }
        }
        lines.append("")
        lines.append("")
        var payload = Data(lines.joined(separator: "\r\n").utf8)
        if !body.isEmpty {
            payload.append(body)
        }
        return payload
    }

    private func readResponse() async throws -> ShadowClientRTSPResponse {
        while true {
            if let response = parseRTSPResponseIfAvailable() {
                return response
            }

            do {
                let chunk = try await receiveBytes()
                guard !chunk.isEmpty else {
                    throw ShadowClientRTSPInterleavedClientError.connectionClosed
                }
                readBuffer.append(chunk)
            } catch {
                if let response = parseRTSPResponseIfAvailable() {
                    logger.notice(
                        "RTSP response completed after transport read error (\(error.localizedDescription, privacy: .public)); using buffered bytes"
                    )
                    return response
                }
                throw error
            }
        }
    }

    private func parseRTSPResponseIfAvailable() -> ShadowClientRTSPResponse? {
        let headerTerminatorCRLF = ShadowClientRTSPProtocolProfile.headerTerminatorCRLF
        let headerTerminatorLF = ShadowClientRTSPProtocolProfile.headerTerminatorLF
        let headerRange: Range<Int>
        let bodyStart: Int
        if let range = readBuffer.range(of: headerTerminatorCRLF) {
            headerRange = range
            bodyStart = range.upperBound
        } else if let range = readBuffer.range(of: headerTerminatorLF) {
            headerRange = range
            bodyStart = range.upperBound
        } else {
            return nil
        }
        let headerData = readBuffer[..<headerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        let lines = headerText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let statusLine = lines.first,
              statusLine.hasPrefix(ShadowClientRTSPRequestDefaults.protocolVersion),
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

        if let contentLength = Int(
            headers[ShadowClientRTSPRequestDefaults.responseHeaderContentLength] ?? ""
        ) {
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

        let contentType = headers[ShadowClientRTSPRequestDefaults.responseHeaderContentType]?.lowercased() ?? ""
        if contentType.contains(ShadowClientRTSPRequestDefaults.acceptSDP) {
            guard readBuffer.count > bodyStart else {
                return nil
            }

            let body = Data(readBuffer[bodyStart...])
            readBuffer.removeAll(keepingCapacity: false)
            return ShadowClientRTSPResponse(
                statusCode: statusCode,
                headers: headers,
                body: body
            )
        }

        readBuffer.removeSubrange(0..<bodyStart)
        return ShadowClientRTSPResponse(
            statusCode: statusCode,
            headers: headers,
            body: Data()
        )
    }

    private func logResponse(method: String, response: ShadowClientRTSPResponse) {
        let sortedHeaders = response.headers
            .map { key, value in "\(key)=\(value)" }
            .sorted()
            .joined(separator: "; ")

        logger.notice(
            "RTSP \(method, privacy: .public) <- status \(response.statusCode, privacy: .public), body \(response.body.count, privacy: .public) bytes, headers [\(sortedHeaders, privacy: .public)]"
        )

        guard method == ShadowClientRTSPRequestDefaults.describeMethod,
              !response.body.isEmpty,
              let preview = String(
                  data: response.body.prefix(ShadowClientRealtimeSessionDefaults.describeResponsePreviewByteCount),
                  encoding: .utf8
              )
        else {
            return
        }

        logger.notice("RTSP DESCRIBE body preview: \(preview, privacy: .public)")
    }

    private func parseInterleavedPacketIfAvailable() throws -> ShadowClientRTPPacket? {
        guard let first = readBuffer.first else {
            return nil
        }

        if first != ShadowClientRTSPProtocolProfile.interleavedFrameMagicByte {
            return nil
        }

        guard readBuffer.count >= ShadowClientRTSPProtocolProfile.interleavedHeaderLength else {
            return nil
        }

        let frameLength = Int(readBuffer[2]) << 8 | Int(readBuffer[3])
        let packetEnd = ShadowClientRTSPProtocolProfile.interleavedHeaderLength + frameLength
        guard readBuffer.count >= packetEnd else {
            return nil
        }

        let channel = Int(readBuffer[1])
        let payload = readBuffer[ShadowClientRTSPProtocolProfile.interleavedHeaderLength..<packetEnd]
        readBuffer.removeSubrange(0..<packetEnd)

        // Odd interleaved channels carry RTCP/control packets.
        // Skip them before RTP parsing to keep decode state clean.
        if channel % 2 == ShadowClientRTSPProtocolProfile.rtcpChannelParityRemainder {
            return ShadowClientRTPPacket(
                isRTP: false,
                channel: channel,
                sequenceNumber: 0,
                marker: false,
                payloadType: -1,
                payload: Data()
            )
        }

        return try parseRTPPacket(payload, channel: channel)
    }

    private func parseRTPPacket(
        _ payload: Data,
        channel: Int
    ) throws -> ShadowClientRTPPacket {
        let parsed: ShadowClientRTPPacketPayloadParseResult
        do {
            parsed = try ShadowClientRTPPacketPayloadParser.parse(payload)
        } catch {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
        }

        return ShadowClientRTPPacket(
            isRTP: true,
            channel: channel,
            sequenceNumber: parsed.sequenceNumber,
            marker: parsed.marker,
            payloadType: parsed.payloadType,
            payload: parsed.payload
        )
    }

    private func waitForReady(_ connection: NWConnection) async throws {
        try await waitForReady(connection, timeout: timeout)
    }

    private func waitForReady(
        _ connection: NWConnection,
        timeout: Duration
    ) async throws {
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
                    try await Task.sleep(for: timeout)
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

    private func resolvedRemoteHost(from connection: NWConnection) -> NWEndpoint.Host? {
        if case let .hostPort(host, _) = connection.currentPath?.remoteEndpoint {
            return host
        }

        if case let .hostPort(host, _) = connection.endpoint {
            return host
        }

        return nil
    }

    private func resolvedLocalHost(from connection: NWConnection) -> NWEndpoint.Host? {
        if case let .hostPort(host, _) = connection.currentPath?.localEndpoint {
            return host
        }
        return nil
    }

    private func send(bytes: Data, over connection: NWConnection) async throws {
        try await Self.send(bytes: bytes, over: connection)
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

    private func receiveBytes() async throws -> Data {
        guard let connection else {
            throw ShadowClientRTSPInterleavedClientError.connectionClosed
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(
                minimumIncompleteLength: ShadowClientRealtimeSessionDefaults.minimumTransportReadLength,
                maximumLength: ShadowClientRealtimeSessionDefaults.maximumTransportReadLength
            ) { content, _, isComplete, error in
                // Sunshine can close/reset a RTSP TCP socket right after writing a valid
                // response chunk. In that case Network.framework may deliver `content`
                // together with a terminal error. Keep the bytes and let response parsing
                // decide whether the message is complete.
                if let content, !content.isEmpty {
                    continuation.resume(returning: content)
                    return
                }

                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                if isComplete {
                    continuation.resume(returning: Data())
                    return
                }

                continuation.resume(returning: content ?? Data())
            }
        }
    }

}

private enum ShadowClientUDPDatagramSocketError: Error {
    case unsupportedAddress(String)
    case socketFailure(String)
}

private final class ShadowClientUDPDatagramSocket: @unchecked Sendable {
    private let descriptor: Int32
    private var remoteAddress: sockaddr_in
    private let addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
    private let closeLock = NSLock()
    private var isClosed = false

    init(
        localHost: NWEndpoint.Host?,
        localPort: UInt16?,
        remoteHost: NWEndpoint.Host,
        remotePort: UInt16
    ) throws {
        guard let remoteAddress = Self.makeIPv4Address(from: remoteHost, port: remotePort) else {
            throw ShadowClientUDPDatagramSocketError.unsupportedAddress(
                "Unsupported remote UDP endpoint: \(String(describing: remoteHost)):\(remotePort)"
            )
        }
        self.remoteAddress = remoteAddress

        descriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard descriptor >= 0 else {
            throw ShadowClientUDPDatagramSocketError.socketFailure(
                "socket() failed: \(String(cString: strerror(errno)))"
            )
        }

        var receiveTimeout = timeval(tv_sec: 0, tv_usec: 250_000)
        _ = setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &receiveTimeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var localAddress = Self.makeLocalIPv4Address(from: localHost, port: localPort)
        let bindStatus = withUnsafePointer(to: &localAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(descriptor, sockaddrPointer, addressLength)
            }
        }
        if bindStatus != 0 {
            let message = "bind() failed: \(String(cString: strerror(errno)))"
            Darwin.close(descriptor)
            throw ShadowClientUDPDatagramSocketError.socketFailure(message)
        }
    }

    deinit {
        close()
    }

    func send(_ datagram: Data) throws {
        var remoteAddress = remoteAddress
        let sentBytes = datagram.withUnsafeBytes { bytes in
            withUnsafePointer(to: &remoteAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    sendto(
                        descriptor,
                        bytes.baseAddress,
                        datagram.count,
                        0,
                        sockaddrPointer,
                        addressLength
                    )
                }
            }
        }

        if sentBytes < 0 {
            throw ShadowClientUDPDatagramSocketError.socketFailure(
                "sendto() failed: \(String(cString: strerror(errno)))"
            )
        }
    }

    func receive(maximumLength: Int) throws -> Data? {
        var buffer = [UInt8](repeating: 0, count: maximumLength)
        var sourceAddress = sockaddr_storage()
        var sourceLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let receivedBytes = buffer.withUnsafeMutableBytes { bytes in
            withUnsafeMutablePointer(to: &sourceAddress) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    recvfrom(
                        descriptor,
                        bytes.baseAddress,
                        bytes.count,
                        0,
                        sockaddrPointer,
                        &sourceLength
                    )
                }
            }
        }

        if receivedBytes < 0 {
            if errno == EAGAIN || errno == EWOULDBLOCK {
                return nil
            }
            throw ShadowClientUDPDatagramSocketError.socketFailure(
                "recvfrom() failed: \(String(cString: strerror(errno)))"
            )
        }

        guard receivedBytes > 0 else {
            return nil
        }
        return Data(buffer.prefix(receivedBytes))
    }

    func localEndpointDescription() -> String {
        var address = sockaddr_storage()
        var addressLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
        let status = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(descriptor, sockaddrPointer, &addressLength)
            }
        }
        guard status == 0 else {
            return "ephemeral:unknown"
        }

        guard address.ss_family == sa_family_t(AF_INET) else {
            return "ephemeral:unknown"
        }

        return withUnsafePointer(to: &address) { pointer -> String in
            pointer.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { sockaddrInPointer in
                var ipv4 = sockaddrInPointer.pointee.sin_addr
                let port = CFSwapInt16BigToHost(sockaddrInPointer.pointee.sin_port)
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                let converted = inet_ntop(
                    AF_INET,
                    &ipv4,
                    &buffer,
                    socklen_t(INET_ADDRSTRLEN)
                )
                guard converted != nil else {
                    return "0.0.0.0:\(port)"
                }
                return "\(String(cString: buffer)):\(port)"
            }
        }
    }

    func close() {
        closeLock.lock()
        let shouldClose = !isClosed
        if shouldClose {
            isClosed = true
        }
        closeLock.unlock()

        if shouldClose {
            Darwin.close(descriptor)
        }
    }

    private static func makeLocalIPv4Address(
        from host: NWEndpoint.Host?,
        port: UInt16?
    ) -> sockaddr_in {
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = CFSwapInt16HostToBig(port ?? 0)
        if let host, let parsed = parseIPv4Host(host) {
            address.sin_addr = parsed
        } else {
            address.sin_addr = in_addr(s_addr: CFSwapInt32HostToBig(INADDR_ANY))
        }
        return address
    }

    private static func makeIPv4Address(
        from host: NWEndpoint.Host,
        port: UInt16
    ) -> sockaddr_in? {
        guard let parsed = parseIPv4Host(host) else {
            return nil
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = CFSwapInt16HostToBig(port)
        address.sin_addr = parsed
        return address
    }

    private static func parseIPv4Host(_ host: NWEndpoint.Host) -> in_addr? {
        let hostString = String(describing: host).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hostString.isEmpty else {
            return nil
        }

        var parsed = in_addr()
        let result = hostString.withCString { cString in
            inet_pton(AF_INET, cString, &parsed)
        }
        guard result == 1 else {
            return nil
        }
        return parsed
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
