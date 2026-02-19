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
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "RealtimeSession")
    private let videoCodecSupport = ShadowClientVideoCodecSupport()
    private var rtspClient: ShadowClientRTSPInterleavedClient?
    private var streamTask: Task<Void, Never>?
    private var moonlightNVDepacketizer = ShadowClientMoonlightNVRTPDepacketizer()

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
        streamTask?.cancel()
    }

    public func connect(
        sessionURL: String,
        host _: String,
        appTitle _: String,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration
    ) async throws {
        try await disconnect()
        let resolvedVideoConfiguration = resolveRuntimeVideoConfiguration(videoConfiguration)
        await decoder.setPreferredOutputDimensions(
            width: resolvedVideoConfiguration.width,
            height: resolvedVideoConfiguration.height,
            fps: resolvedVideoConfiguration.fps
        )

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
        let track = try await client.start(
            url: url,
            videoConfiguration: resolvedVideoConfiguration,
            remoteInputKey: resolvedVideoConfiguration.remoteInputKey
        )

        moonlightNVDepacketizer.configureTailTruncationStrategy(
            Self.depacketizerTailTruncationStrategy(for: track.codec)
        )
        moonlightNVDepacketizer.reset()
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
                logger.error("Realtime stream task failed: \(error.localizedDescription, privacy: .public)")
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
        if marker {
            logger.notice("RTP packet marker set for codec \(String(describing: codec), privacy: .public), payload \(payload.count, privacy: .public) bytes")
        }
        if let frame = moonlightNVDepacketizer.ingest(payload: payload, marker: marker) {
            logger.notice("Moonlight NV frame assembled for codec \(String(describing: codec), privacy: .public): \(frame.count, privacy: .public) bytes")
            do {
                try await decodeFrame(
                    accessUnit: frame,
                    codec: codec,
                    parameterSets: codec == .av1 ? [] : initialParameterSets
                )
            } catch {
                logger.error("\(String(describing: codec), privacy: .public) decode failed: \(error.localizedDescription, privacy: .public)")
                throw error
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

    private func resolveRuntimeVideoConfiguration(
        _ configuration: ShadowClientRemoteSessionVideoConfiguration
    ) -> ShadowClientRemoteSessionVideoConfiguration {
        let resolvedCodecPreference = videoCodecSupport.resolvePreferredCodec(configuration.preferredCodec)
        return .init(
            width: configuration.width,
            height: configuration.height,
            fps: configuration.fps,
            bitrateKbps: configuration.bitrateKbps,
            preferredCodec: resolvedCodecPreference,
            enableHDR: configuration.enableHDR,
            enableSurroundAudio: configuration.enableSurroundAudio,
            enableYUV444: configuration.enableYUV444,
            remoteInputKey: configuration.remoteInputKey
        )
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
    let isRTP: Bool
    let channel: Int
    let marker: Bool
    let payloadType: Int
    let payload: Data
}

private struct ShadowClientSendableNWConnection: @unchecked Sendable {
    let connection: NWConnection
}

private actor ShadowClientRTSPInterleavedClient {
    private let timeout: Duration
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
    private var prePlayAudioPingConnection: NWConnection?
    private var controlConnectData: UInt32?
    private var controlChannelRuntime: ShadowClientSunshineControlChannelRuntime?
    private var controlChannelMode: ShadowClientSunshineControlChannelMode = .plaintext
    private var useSessionIdentifierV1 = false
    private var remoteInputKey: Data?
    private var negotiatedClientPortBase: UInt16 = ShadowClientRTSPProtocolProfile.clientPortBase

    init(timeout: Duration) {
        self.timeout = timeout
    }

    func start(
        url: URL,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration,
        remoteInputKey: Data?
    ) async throws -> ShadowClientRTSPVideoTrackDescriptor {
        self.remoteInputKey = remoteInputKey
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
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP OPTIONS failed: \(error.localizedDescription)"
            )
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
        let audioControls = (try? ShadowClientRTSPSessionDescriptionParser.parseAudioControlURLs(
            sdp: sdp,
            contentBase: contentBase,
            fallbackSessionURL: normalizedURL.absoluteString
        )) ?? []
        let audioSetupCandidates = audioControlURLCandidates(
            controlsFromSDP: audioControls,
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
                    try await reconnect(host: host, port: port)
                    let response = try await sendRequest(
                        method: ShadowClientRTSPRequestDefaults.setupMethod,
                        url: controlURL,
                        headers: headers
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
                    logger.notice("RTSP audio SETUP ok for \(controlURL, privacy: .public)")
                    break
                } catch {
                    logger.error("RTSP audio SETUP failed for \(controlURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        let controlHost = remoteHost ?? .init(host)
        await prepareAudioPingBeforePlay(host: controlHost)

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
                try await reconnect(host: host, port: port)
                let response = try await sendRequest(
                    method: ShadowClientRTSPRequestDefaults.setupMethod,
                    url: setupURL,
                    headers: headers
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
        logger.notice("RTSP video SETUP ok for payload type \(track.rtpPayloadType, privacy: .public) via \(selectedSetupURL ?? track.controlURL, privacy: .public)")

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
                try await reconnect(host: host, port: port)
                let response = try await sendRequest(
                    method: ShadowClientRTSPRequestDefaults.setupMethod,
                    url: controlURL,
                    headers: headers
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
            supportsEncryptedControlChannelV2: ShadowClientSunshineSessionDefaults.supportsEncryptedControlChannelV2 && remoteInputKey != nil
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
        logger.notice(
            "RTSP negotiation session-id-v1=\(handshakeNegotiation.supportsSessionIdentifierV1, privacy: .public) ml-flags=\(handshakeNegotiation.moonlightFeatureFlags, privacy: .public) encryption-enabled=\(handshakeNegotiation.encryptionEnabledFlags, privacy: .public) control-mode=\(controlModeLabel, privacy: .public)"
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
                try await reconnect(host: host, port: port)
                _ = try await sendRequest(
                    method: ShadowClientRTSPRequestDefaults.announceMethod,
                    url: announceTarget,
                    headers: announceHeaders,
                    body: announcePayload
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
                try await reconnect(host: host, port: port)
                _ = try await sendRequest(
                    method: ShadowClientRTSPRequestDefaults.playMethod,
                    url: playTarget,
                    headers: resolvedPlayHeaders
                )
                logger.notice("RTSP PLAY ok for \(playTarget, privacy: .public)")
                playSucceeded = true
                if playTarget == ShadowClientRTSPProtocolProfile.playPaths.first {
                    break
                }
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

        await attemptLegacyFirstFrameBootstrap(host: remoteHost ?? .init(host))
        await startSunshineControlChannelIfNeeded(host: host)
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

    private func startSunshineControlChannelIfNeeded(host: String) async {
        guard let controlServerPort else {
            logger.notice("RTSP control bootstrap skipped (no negotiated control server port)")
            return
        }

        if let controlChannelRuntime {
            await controlChannelRuntime.stop()
            self.controlChannelRuntime = nil
        }

        let controlHost = remoteHost ?? .init(host)
        let runtime = ShadowClientSunshineControlChannelRuntime()

        do {
            try await runtime.start(
                host: controlHost,
                port: controlServerPort,
                connectData: controlConnectData,
                mode: controlChannelMode
            )
            controlChannelRuntime = runtime
        } catch {
            logger.error("RTSP control bootstrap failed: \(error.localizedDescription, privacy: .public)")
            await runtime.stop()
        }
    }

    func stop() async {
        if let controlChannelRuntime {
            await controlChannelRuntime.stop()
        }
        controlChannelRuntime = nil

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
        prePlayAudioPingConnection?.cancel()
        prePlayAudioPingConnection = nil
        controlConnectData = nil
        controlChannelMode = .plaintext
        useSessionIdentifierV1 = false
        remoteInputKey = nil
        negotiatedClientPortBase = defaultClientPortBase
    }

    func receiveInterleavedVideoPackets(
        payloadType: Int,
        onVideoPacket: @escaping @Sendable (Data, Bool) async throws -> Void
    ) async throws {
        if let remoteHost, let videoServerPort {
            try await receiveUDPVideoPackets(
                host: remoteHost,
                port: videoServerPort,
                payloadType: payloadType,
                onVideoPacket: onVideoPacket
            )
            return
        }

        var effectivePayloadType = payloadType
        var hasReceivedVideoPayload = false
        var packetCount = 0

        while !Task.isCancelled {
            if let packet = try parseInterleavedPacketIfAvailable() {
                guard packet.isRTP, packet.channel == 0 else {
                    continue
                }

                packetCount += 1
                if packetCount == 1 {
                    logger.notice(
                        "First RTP video packet received: payloadType=\(packet.payloadType, privacy: .public), marker=\(packet.marker, privacy: .public), payloadBytes=\(packet.payload.count, privacy: .public)"
                    )
                }

                if packet.payloadType == effectivePayloadType {
                    hasReceivedVideoPayload = true
                    try await onVideoPacket(packet.payload, packet.marker)
                    continue
                }

                if !hasReceivedVideoPayload,
                   packet.payloadType != ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType
                {
                    logger.notice(
                        "RTSP payload type mismatch; adopting stream payload type \(packet.payloadType, privacy: .public) (expected \(effectivePayloadType, privacy: .public))"
                    )
                    effectivePayloadType = packet.payloadType
                    hasReceivedVideoPayload = true
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

    private func receiveUDPVideoPackets(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        payloadType: Int,
        onVideoPacket: @escaping @Sendable (Data, Bool) async throws -> Void
    ) async throws {
        let localHost = self.localHost
        let udpConnection = try await makeVideoUDPConnection(
            host: host,
            port: port,
            localHost: localHost
        )
        logger.notice("RTSP video receive switched to UDP \(String(describing: host), privacy: .public):\(port.rawValue, privacy: .public)")

        let pingPayload = videoPingPayload
        let rtspLogger = logger
        var audioPingConnection: NWConnection? = prePlayAudioPingConnection
        if audioPingConnection == nil, let audioServerPort {
            do {
                let connection = try await makeAudioUDPPingConnection(
                    host: host,
                    port: audioServerPort,
                    localHost: localHost
                )
                rtspLogger.notice("RTSP UDP audio ping socket ready on \(audioServerPort.rawValue, privacy: .public)")
                audioPingConnection = connection
            } catch {
                rtspLogger.error("RTSP UDP audio ping socket setup failed: \(error.localizedDescription, privacy: .public)")
            }
        }
        let audioPingPayload = self.audioPingPayload

        do {
            let initialVideoPings = ShadowClientSunshinePingPacketCodec.makePingPackets(
                sequence: 1,
                negotiatedPayload: pingPayload
            )
            for initialVideoPing in initialVideoPings {
                try await Self.send(bytes: initialVideoPing, over: udpConnection)
            }
            rtspLogger.notice("RTSP UDP video initial ping sent (variants=\(initialVideoPings.count, privacy: .public), bytes=\(initialVideoPings.first?.count ?? 0, privacy: .public))")
        } catch {
            rtspLogger.error("RTSP UDP video initial ping failed: \(error.localizedDescription, privacy: .public)")
        }

        if let audioPingConnection {
            do {
                let initialAudioPings = ShadowClientSunshinePingPacketCodec.makePingPackets(
                    sequence: 1,
                    negotiatedPayload: audioPingPayload
                )
                for initialAudioPing in initialAudioPings {
                    try await Self.send(bytes: initialAudioPing, over: audioPingConnection)
                }
                rtspLogger.notice("RTSP UDP audio initial ping sent (variants=\(initialAudioPings.count, privacy: .public), bytes=\(initialAudioPings.first?.count ?? 0, privacy: .public))")
            } catch {
                rtspLogger.error("RTSP UDP audio initial ping failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        let sendableVideoConnection = ShadowClientSendableNWConnection(connection: udpConnection)
        let sendableAudioConnection = audioPingConnection.map {
            ShadowClientSendableNWConnection(connection: $0)
        }

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
                        try await Self.send(bytes: pingPacket, over: sendableVideoConnection.connection)
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
        let audioPingTask = Task {
            guard let sendableAudioConnection else {
                return
            }
            var sequence: UInt32 = 1
            var loggedPingCount = 0
            while !Task.isCancelled {
                sequence &+= 1
                let pingPackets = ShadowClientSunshinePingPacketCodec.makePingPackets(
                    sequence: sequence,
                    negotiatedPayload: audioPingPayload
                )
                for pingPacket in pingPackets {
                    try? await Self.send(bytes: pingPacket, over: sendableAudioConnection.connection)
                }
                if loggedPingCount < 2 {
                    rtspLogger.notice("RTSP UDP audio ping sent (sequence=\(sequence, privacy: .public), variants=\(pingPackets.count, privacy: .public), bytes=\(pingPackets.first?.count ?? 0, privacy: .public))")
                    loggedPingCount += 1
                }
                try? await Task.sleep(for: ShadowClientRealtimeSessionDefaults.pingInterval)
            }
        }

        defer {
            pingTask.cancel()
            audioPingTask.cancel()
            audioPingConnection?.cancel()
            prePlayAudioPingConnection = nil
            udpConnection.cancel()
        }

        var effectivePayloadType = payloadType
        var hasReceivedVideoPayload = false
        var packetCount = 0

        while !Task.isCancelled {
            let datagram = try await receiveDatagram(over: udpConnection)
            guard !datagram.isEmpty else {
                continue
            }

            let packet = try parseRTPPacket(datagram, channel: 0)
            packetCount += 1
            if packetCount == 1 {
                logger.notice(
                    "First RTP video packet received: payloadType=\(packet.payloadType, privacy: .public), marker=\(packet.marker, privacy: .public), payloadBytes=\(packet.payload.count, privacy: .public)"
                )
            }

            if packet.payloadType == effectivePayloadType {
                hasReceivedVideoPayload = true
                try await onVideoPacket(packet.payload, packet.marker)
                continue
            }

            if !hasReceivedVideoPayload,
               packet.payloadType != ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType
            {
                logger.notice(
                    "RTSP payload type mismatch; adopting stream payload type \(packet.payloadType, privacy: .public) (expected \(effectivePayloadType, privacy: .public))"
                )
                effectivePayloadType = packet.payloadType
                hasReceivedVideoPayload = true
                try await onVideoPacket(packet.payload, packet.marker)
            }
        }
    }

    private func makeVideoUDPConnection(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        localHost: NWEndpoint.Host?
    ) async throws -> NWConnection {
        if let localHost,
           let clientPort = NWEndpoint.Port(rawValue: negotiatedClientPortBase)
        {
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: localHost,
                port: clientPort
            )
            let boundConnection = NWConnection(host: host, port: port, using: parameters)
            do {
                try await waitForReady(boundConnection)
                logger.notice("RTSP UDP video socket bound to \(String(describing: localHost), privacy: .public):\(self.negotiatedClientPortBase, privacy: .public)")
                return boundConnection
            } catch {
                logger.error("RTSP UDP video bind failed on \(String(describing: localHost), privacy: .public):\(self.negotiatedClientPortBase, privacy: .public): \(error.localizedDescription, privacy: .public)")
                boundConnection.cancel()
            }
        }

        let fallbackConnection = NWConnection(host: host, port: port, using: .udp)
        try await waitForReady(fallbackConnection)
        logger.notice("RTSP UDP video socket using ephemeral local port")
        return fallbackConnection
    }

    private func makeAudioUDPPingConnection(
        host: NWEndpoint.Host,
        port: NWEndpoint.Port,
        localHost: NWEndpoint.Host?
    ) async throws -> NWConnection {
        if let localHost,
           let clientPort = NWEndpoint.Port(rawValue: negotiatedClientPortBase + 1)
        {
            let parameters = NWParameters.udp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: localHost,
                port: clientPort
            )
            let boundConnection = NWConnection(host: host, port: port, using: parameters)
            do {
                try await waitForReady(boundConnection)
                logger.notice("RTSP UDP audio ping socket bound to \(String(describing: localHost), privacy: .public):\(clientPort.rawValue, privacy: .public)")
                return boundConnection
            } catch {
                logger.error("RTSP UDP audio ping bind failed on \(String(describing: localHost), privacy: .public):\(clientPort.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                boundConnection.cancel()
            }
        }

        let fallbackConnection = NWConnection(host: host, port: port, using: .udp)
        try await waitForReady(fallbackConnection)
        logger.notice("RTSP UDP audio ping socket using ephemeral local port")
        return fallbackConnection
    }

    private func prepareAudioPingBeforePlay(host: NWEndpoint.Host) async {
        guard prePlayAudioPingConnection == nil,
              let audioServerPort
        else {
            return
        }

        do {
            let connection = try await makeAudioUDPPingConnection(
                host: host,
                port: audioServerPort,
                localHost: localHost
            )
            prePlayAudioPingConnection = connection

            let prePlayPings = ShadowClientSunshinePingPacketCodec.makePingPackets(
                sequence: 1,
                negotiatedPayload: audioPingPayload
            )
            for packet in prePlayPings {
                try await Self.send(bytes: packet, over: connection)
            }
            logger.notice("RTSP UDP audio pre-PLAY ping sent (variants=\(prePlayPings.count, privacy: .public), bytes=\(prePlayPings.first?.count ?? 0, privacy: .public))")
        } catch {
            prePlayAudioPingConnection?.cancel()
            prePlayAudioPingConnection = nil
            logger.error("RTSP UDP audio pre-PLAY ping setup failed: \(error.localizedDescription, privacy: .public)")
        }
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
        guard payload.count >= ShadowClientRTSPProtocolProfile.rtpMinimumHeaderLength else {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
        }

        let version = payload[0] >> ShadowClientRTSPProtocolProfile.rtpVersionShift
        guard version == ShadowClientRTSPProtocolProfile.rtpVersion else {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
        }

        let hasPadding = (payload[0] & ShadowClientRTSPProtocolProfile.rtpPaddingMask) != 0
        let hasExtension = (payload[0] & ShadowClientRTSPProtocolProfile.rtpExtensionMask) != 0
        let csrcCount = Int(payload[0] & ShadowClientRTSPProtocolProfile.rtpCSRCCountMask)
        let marker = (payload[1] & ShadowClientRTSPProtocolProfile.rtpMarkerMask) != 0
        let payloadType = Int(payload[1] & ShadowClientRTSPProtocolProfile.rtpPayloadTypeMask)

        var headerLength = ShadowClientRTSPProtocolProfile.rtpMinimumHeaderLength + csrcCount * 4
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
            isRTP: true,
            channel: channel,
            marker: marker,
            payloadType: payloadType,
            payload: videoPayload
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

    private func receiveDatagram(over connection: NWConnection) async throws -> Data {
        try await Self.receiveDatagram(over: connection)
    }

    private static func receiveDatagram(over connection: NWConnection) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receiveMessage { content, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
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
