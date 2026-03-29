import CoreVideo
import Darwin
import Foundation
import Network
import os
import ShadowClientFeatureSession

struct ShadowClientSendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

private extension Data {
    func readUInt32BE(at offset: Int) -> UInt32 {
        let b0 = UInt32(self[offset]) << 24
        let b1 = UInt32(self[offset + 1]) << 16
        let b2 = UInt32(self[offset + 2]) << 8
        let b3 = UInt32(self[offset + 3])
        return b0 | b1 | b2 | b3
    }
}

enum ShadowClientRTSPInterleavedClientError: Error, Equatable {
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

struct ShadowClientLumenControlTransportNegotiation: Sendable {
    let controlChannelMode: ShadowClientHostControlChannelMode
    let controlModeLabel: String
    let audioEncryptionConfiguration: ShadowClientRealtimeAudioEncryptionConfiguration?
    let audioEncryptionLabel: String

    static func resolve(
        handshakeNegotiation: ShadowClientHostHandshakeNegotiation,
        remoteInputKey: Data?,
        remoteInputKeyID: UInt32?
    ) throws -> Self {
        guard handshakeNegotiation.supportsSessionIdentifierV1 else {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "Lumen transport requires negotiated session ID ping support."
            )
        }
        guard handshakeNegotiation.controlChannelEncryptionEnabled,
              let remoteInputKey
        else {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "Lumen transport requires encrypted control stream v2 support."
            )
        }

        let audioEncryptionConfiguration: ShadowClientRealtimeAudioEncryptionConfiguration?
        if handshakeNegotiation.audioEncryptionEnabled,
           let remoteInputKeyID
        {
            audioEncryptionConfiguration = .init(
                key: remoteInputKey,
                keyID: remoteInputKeyID
            )
        } else {
            audioEncryptionConfiguration = nil
        }

        return Self(
            controlChannelMode: .encryptedV2(key: remoteInputKey),
            controlModeLabel: "encrypted-v2",
            audioEncryptionConfiguration: audioEncryptionConfiguration,
            audioEncryptionLabel: handshakeNegotiation.audioEncryptionEnabled ? "encrypted" : "plaintext"
        )
    }
}

struct ShadowClientRTPPacket {
    let isRTP: Bool
    let channel: Int
    let sequenceNumber: UInt16
    let marker: Bool
    let payloadType: Int
    let payloadOffset: Int
    let rawBytes: Data
    let payload: Data
}

struct ShadowClientRTPPacketPayloadParseResult: Equatable, Sendable {
    let sequenceNumber: UInt16
    let marker: Bool
    let payloadType: Int
    let payloadOffset: Int
    let rawBytes: Data
    let payload: Data
}

enum ShadowClientRTPPacketPayloadParserError: Error, Equatable {
    case invalidPacket
}

enum ShadowClientRTPPacketPayloadParser {
    static func parse(
        _ payload: Data
    ) throws -> ShadowClientRTPPacketPayloadParseResult {
        // Data slices may carry non-zero startIndex. Normalize once to keep direct
        // integer indexing stable across parser/depacketizer boundaries.
        let packetBytes = payload.startIndex == 0 ? payload : Data(payload)

        guard packetBytes.count >= ShadowClientRTSPProtocolProfile.rtpMinimumHeaderLength else {
            throw ShadowClientRTPPacketPayloadParserError.invalidPacket
        }

        let version = packetBytes[0] >> ShadowClientRTSPProtocolProfile.rtpVersionShift
        guard version == ShadowClientRTSPProtocolProfile.rtpVersion else {
            throw ShadowClientRTPPacketPayloadParserError.invalidPacket
        }

        let hasPadding = (packetBytes[0] & ShadowClientRTSPProtocolProfile.rtpPaddingMask) != 0
        let hasExtension = (packetBytes[0] & ShadowClientRTSPProtocolProfile.rtpExtensionMask) != 0
        let csrcCount = Int(packetBytes[0] & ShadowClientRTSPProtocolProfile.rtpCSRCCountMask)
        let marker = (packetBytes[1] & ShadowClientRTSPProtocolProfile.rtpMarkerMask) != 0
        let payloadType = Int(packetBytes[1] & ShadowClientRTSPProtocolProfile.rtpPayloadTypeMask)
        let sequenceNumber = (UInt16(packetBytes[2]) << 8) | UInt16(packetBytes[3])

        var headerLength = ShadowClientRTSPProtocolProfile.rtpMinimumHeaderLength + csrcCount * 4
        guard packetBytes.count >= headerLength else {
            throw ShadowClientRTPPacketPayloadParserError.invalidPacket
        }

        if hasExtension {
            // Moonlight/Lumen-host RTP video packets carry a fixed 4-byte extension preamble
            // before NV packet data. The extension length field is not used in the same way
            // as generic RFC3550 streams, so we intentionally skip only these 4 bytes.
            headerLength += 4
            guard packetBytes.count >= headerLength else {
                throw ShadowClientRTPPacketPayloadParserError.invalidPacket
            }
        }

        var endIndex = packetBytes.count
        if hasPadding, let padding = packetBytes.last {
            endIndex = max(headerLength, packetBytes.count - Int(padding))
        }
        guard endIndex > headerLength else {
            throw ShadowClientRTPPacketPayloadParserError.invalidPacket
        }

        return ShadowClientRTPPacketPayloadParseResult(
            sequenceNumber: sequenceNumber,
            marker: marker,
            payloadType: payloadType,
            payloadOffset: headerLength,
            rawBytes: packetBytes,
            payload: Data(packetBytes[headerLength..<endIndex])
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

        let readyPackets = drainContiguousPackets()
        if readyPackets.isEmpty, packetsBySequence.count >= targetDepth {
            // Moonlight FEC path rejects unrecoverable sequence gaps instead of
            // force-jumping into the middle of a frame.
            reset()
            return []
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

    private mutating func trimOverflow() {
        guard packetsBySequence.count > maximumDepth,
              let expectedSequence
        else {
            return
        }

        var overflow = packetsBySequence.count - maximumDepth
        while overflow > 0 {
            var farthestSequence: UInt16?
            var farthestDistance: UInt16 = 0
            for sequence in packetsBySequence.keys {
                let distance = sequenceDistance(from: expectedSequence, to: sequence)
                if farthestSequence == nil || distance > farthestDistance {
                    farthestSequence = sequence
                    farthestDistance = distance
                }
            }
            guard let farthestSequence else {
                break
            }
            packetsBySequence.removeValue(forKey: farthestSequence)
            overflow -= 1
        }
    }

    private func sequenceDistance(from start: UInt16, to end: UInt16) -> UInt16 {
        end &- start
    }
}

actor ShadowClientRTSPInterleavedClient {
    private let timeout: Duration
    private let onControlRoundTripSample: (@Sendable (Double) async -> Void)?
    private let onAudioOutputStateChanged: (@Sendable (ShadowClientRealtimeAudioOutputState) async -> Void)?
    private let onAudioPendingDurationChanged: (@Sendable (Double) async -> Void)?
    private let onHDRMode: (@Sendable (ShadowClientHostHDRModeEvent) async -> Void)?
    private let onHDRFrameState: (@Sendable (ShadowClientHDRFrameState) async -> Void)?
    private let onControllerFeedback: (@Sendable (ShadowClientHostControllerFeedbackEvent) async -> Void)?
    private let onTermination: (@Sendable (ShadowClientHostTerminationEvent) async -> Void)?
    private let inputChannelGateway = ShadowClientRealtimeInputChannelGateway()
    private let audioSessionActivation: (@Sendable () async -> Void)?
    private let audioSessionDeactivation: (@Sendable () async -> Void)?
    private let defaultClientPortBase: UInt16 = ShadowClientRTSPProtocolProfile.clientPortBase
    private let queue = DispatchQueue(
        label: "com.skyline23.shadowclient.rtsp.connection",
        qos: .userInitiated
    )
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "RTSP")
    private var connection: NWConnection?
    private var readBuffer = Data()
    private var encryptedReadBuffer = Data()
    private var cseq = 1
    private var rtspRequestSequence: UInt32 = 0
    private var sessionHeader: String?
    private var remoteHost: NWEndpoint.Host?
    private var localHost: NWEndpoint.Host?
    private var audioServerPort: NWEndpoint.Port?
    private var videoServerPort: NWEndpoint.Port?
    private var controlServerPort: NWEndpoint.Port?
    private var audioPingPayload: Data?
    private var videoPingPayload: Data?
    private var audioTrackDescriptor: ShadowClientRTSPAudioTrackDescriptor?
    private var prePlayAudioUDPConnection: NWConnection?
    private var prePlayAudioPingWarmupTask: Task<Void, Never>?
    private var prePlayVideoUDPSocket: ShadowClientUDPDatagramSocket?
    private var prePlayVideoPingWarmupTask: Task<Void, Never>?
    private var controlConnectData: UInt32?
    private var controlChannelRuntime: ShadowClientHostControlChannelRuntime?
    private var controlChannelMode: ShadowClientHostControlChannelMode?
    private var hasStartedControlChannelBootstrap = false
    private var useSessionIdentifierV1 = false
    private var remoteInputKey: Data?
    private var remoteInputKeyID: UInt32?
    private var audioEncryptionConfiguration: ShadowClientRealtimeAudioEncryptionConfiguration?
    private var negotiatedClientPortBase: UInt16 = ShadowClientRTSPProtocolProfile.clientPortBase
    private var rtspHostHeaderValue: String?
    private var rtspClientVersionHeaderValue = ShadowClientRTSPRequestDefaults.clientVersionHeaderValue
    private var rtspEncryptionCodec: ShadowClientRTSPEncryptionCodec?
    private var rtspSessionHost: String?
    private var rtspSessionPort: NWEndpoint.Port?
    private var playRecoveryTargets: [String] = ["/"]
    private var currentServerAppVersion: String?
    private var audioRuntime: ShadowClientRealtimeAudioSessionRuntime?
    private let videoFECUnrecoverableRecoveryRequestCooldownSeconds: TimeInterval = 0.35
    private let videoFECUnrecoverableRecoveryBurstWindowSeconds: TimeInterval = 2.0
    private let videoFECUnrecoverableRecoveryBurstThreshold = 1
    private var lastInteractiveInputEventUptime: TimeInterval = 0
    private var prioritizeNetworkTraffic = false

    init(
        timeout: Duration,
        onControlRoundTripSample: (@Sendable (Double) async -> Void)? = nil,
        onAudioOutputStateChanged: (@Sendable (ShadowClientRealtimeAudioOutputState) async -> Void)? = nil,
        onAudioPendingDurationChanged: (@Sendable (Double) async -> Void)? = nil,
        onHDRMode: (@Sendable (ShadowClientHostHDRModeEvent) async -> Void)? = nil,
        onHDRFrameState: (@Sendable (ShadowClientHDRFrameState) async -> Void)? = nil,
        onControllerFeedback: (@Sendable (ShadowClientHostControllerFeedbackEvent) async -> Void)? = nil,
        onTermination: (@Sendable (ShadowClientHostTerminationEvent) async -> Void)? = nil,
        audioSessionActivation: (@Sendable () async -> Void)? = nil,
        audioSessionDeactivation: (@Sendable () async -> Void)? = nil
    ) {
        self.timeout = timeout
        self.onControlRoundTripSample = onControlRoundTripSample
        self.onAudioOutputStateChanged = onAudioOutputStateChanged
        self.onAudioPendingDurationChanged = onAudioPendingDurationChanged
        self.onHDRMode = onHDRMode
        self.onHDRFrameState = onHDRFrameState
        self.onControllerFeedback = onControllerFeedback
        self.onTermination = onTermination
        self.audioSessionActivation = audioSessionActivation
        self.audioSessionDeactivation = audioSessionDeactivation
    }

    func start(
        url: URL,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration,
        remoteInputKey: Data?,
        remoteInputKeyID: UInt32?
    ) async throws -> ShadowClientRTSPVideoTrackDescriptor {
        if let controlChannelRuntime {
            await controlChannelRuntime.stop()
        }
        controlChannelRuntime = nil
        hasStartedControlChannelBootstrap = false
        cancelPrePlayPingWarmupTasks()
        if let prePlayAudioUDPConnection {
            prePlayAudioUDPConnection.cancel()
        }
        prePlayAudioUDPConnection = nil
        if let prePlayVideoUDPSocket {
            await prePlayVideoUDPSocket.close()
        }
        prePlayVideoUDPSocket = nil
        connection?.cancel()
        connection = nil
        readBuffer.removeAll(keepingCapacity: false)
        encryptedReadBuffer.removeAll(keepingCapacity: false)
        encryptedReadBuffer.removeAll(keepingCapacity: false)
        cseq = 1
        rtspRequestSequence = 0
        sessionHeader = nil
        remoteHost = nil
        localHost = nil
        audioServerPort = nil
        videoServerPort = nil
        controlServerPort = nil
        audioPingPayload = nil
        videoPingPayload = nil
        audioTrackDescriptor = nil
        controlConnectData = nil
        controlChannelMode = nil
        useSessionIdentifierV1 = false
        audioEncryptionConfiguration = nil
        negotiatedClientPortBase = defaultClientPortBase
        rtspHostHeaderValue = nil
        rtspClientVersionHeaderValue = ShadowClientRTSPRequestDefaults.clientVersionHeaderValue
        rtspEncryptionCodec = nil
        rtspSessionHost = nil
        rtspSessionPort = nil
        playRecoveryTargets = ["/"]
        currentServerAppVersion = nil

        self.remoteInputKey = remoteInputKey
        self.remoteInputKeyID = remoteInputKeyID
        prioritizeNetworkTraffic = videoConfiguration.prioritizeNetworkTraffic
        await inputChannelGateway.clear()
        lastInteractiveInputEventUptime = 0
        if Self.isEncryptedRTSPSessionURL(url) {
            guard let remoteInputKey else {
                throw ShadowClientRTSPInterleavedClientError.requestFailed(
                    "Lumen encrypted RTSP session is missing remote input key material."
                )
            }
            rtspEncryptionCodec = try ShadowClientRTSPEncryptionCodec(keyData: remoteInputKey)
        }
        let normalizedURL = normalizeRTSPURL(url)
        guard let host = normalizedURL.host else {
            throw ShadowClientRTSPInterleavedClientError.invalidURL
        }
        remoteHost = .init(host)
        currentServerAppVersion = videoConfiguration.serverAppVersion
        let portValue = normalizedURL.port ?? ShadowClientRTSPProtocolProfile.defaultPort
        rtspHostHeaderValue = ShadowClientRTSPProtocolProfile.hostHeaderValue(
            forRTSPURLString: normalizedURL.absoluteString
        ) ?? "\(host):\(portValue)"
        rtspClientVersionHeaderValue = Self.clientVersionHeaderValue(
            serverAppVersion: videoConfiguration.serverAppVersion
        )
        guard let port = NWEndpoint.Port(rawValue: UInt16(portValue)) else {
            throw ShadowClientRTSPInterleavedClientError.invalidURL
        }
        rtspSessionHost = host
        rtspSessionPort = port

        let connection = try await connectWithMoonlightRetry(
            host: host,
            port: port
        )
        self.connection = connection
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
            guard shouldRetryAfterReconnect(error) else {
                throw error
            }
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
            guard shouldRetryAfterReconnect(error) else {
                throw error
            }
            logger.notice(
                "RTSP DESCRIBE retry on fresh TCP connection after failure: \(error.localizedDescription, privacy: .public)"
            )
            // Some Lumen/GameStream stacks close the RTSP socket after OPTIONS.
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
        // Lumen can acknowledge PLAY on a new socket but still keep UDP routing tied
        // to the transport state negotiated on the original connection.
        try await reconnect(host: host, port: port)
        let contentBase =
            describe.headers[ShadowClientRTSPRequestDefaults.responseHeaderContentBase] ??
            describe.headers[ShadowClientRTSPRequestDefaults.responseHeaderContentLocation]
        guard !sdp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP DESCRIBE failed: empty SDP payload"
            )
        }
        let parsedTrack: ShadowClientRTSPVideoTrackDescriptor
        do {
            parsedTrack = try ShadowClientRTSPSessionDescriptionParser.parseVideoTrack(
                sdp: sdp,
                contentBase: contentBase,
                fallbackSessionURL: normalizedURL.absoluteString
            )
        } catch {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP track parse failed: \(error.localizedDescription)"
            )
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
            candidateRTPPayloadTypes: parsedTrack.candidateRTPPayloadTypes,
            controlURL: parsedTrack.controlURL,
            parameterSets: announceCodec == parsedTrack.codec ? parsedTrack.parameterSets : []
        )
        logger.notice(
            "RTSP ANNOUNCE preparing described-codec=\(parsedTrack.codec.rawValue, privacy: .public) announce-codec=\(announceCodec.rawValue, privacy: .public) bitStreamFormat=\(ShadowClientRTSPAnnounceProfile.bitStreamFormat(for: announceCodec), privacy: .public) hdr=\(videoConfiguration.enableHDR, privacy: .public) yuv444=\(videoConfiguration.enableYUV444, privacy: .public)"
        )
        let useModernControlStreamIdentifier = Self.isServerVersionAtLeast(
            videoConfiguration.serverAppVersion,
            major: 7,
            minor: 1,
            patch: 431
        )
        playRecoveryTargets = useModernControlStreamIdentifier ? ["/"] : ["streamid=video", "streamid=audio"]
        let preferredControlStreamPath = useModernControlStreamIdentifier ?
            "streamid=control/13/0" :
            "streamid=control/1/0"
        let requiresControlSetup = (Self.serverMajorVersion(videoConfiguration.serverAppVersion) ?? 7) >= 5
        let useLegacySetupTransport = (Self.serverMajorVersion(videoConfiguration.serverAppVersion) ?? 7) < 6

        negotiatedClientPortBase = ShadowClientRTSPClientPortAllocator.selectClientPortBase(
            preferred: defaultClientPortBase,
            localHost: localHost
        )
        if negotiatedClientPortBase != defaultClientPortBase {
            logger.notice(
                "RTSP selected alternate client port base \(self.negotiatedClientPortBase, privacy: .public) (preferred \(self.defaultClientPortBase, privacy: .public))"
            )
        }
        let setupTransportHeader = useLegacySetupTransport ?
            " " :
            ShadowClientRTSPProtocolProfile.setupTransportHeader(
                clientPortBase: negotiatedClientPortBase
            )
        let setupURLCandidates = videoControlURLCandidates(
            primary: track.controlURL,
            sessionURL: normalizedURL.absoluteString
        )
        let preferredOpusChannelCount =
            await ShadowClientRealtimeAudioSessionRuntime.preferredOpusChannelCountForNegotiation(
                surroundRequested: videoConfiguration.enableSurroundAudio,
                preferredSurroundChannelCount: videoConfiguration.preferredSurroundChannelCount
            )
        if videoConfiguration.enableSurroundAudio, preferredOpusChannelCount <= 2 {
            logger.notice(
                "RTSP audio negotiation downgraded to stereo because no runtime multichannel Opus decoder is available"
            )
        }
        var parsedAudioTrack = ShadowClientRTSPSessionDescriptionParser.parseAudioTrack(
            sdp: sdp,
            contentBase: contentBase,
            fallbackSessionURL: normalizedURL.absoluteString,
            preferredOpusChannelCount: preferredOpusChannelCount
        )
        if let negotiatedAudioTrack = parsedAudioTrack,
           !(await ShadowClientRealtimeAudioSessionRuntime.canDecode(track: negotiatedAudioTrack))
        {
            logger.notice(
                "RTSP selected audio track is not decodable at runtime (codec=\(negotiatedAudioTrack.codec.label, privacy: .public), channels=\(negotiatedAudioTrack.channelCount, privacy: .public)); retrying with stereo-preferred negotiation"
            )
            let stereoPreferredTrack = ShadowClientRTSPSessionDescriptionParser.parseAudioTrack(
                sdp: sdp,
                contentBase: contentBase,
                fallbackSessionURL: normalizedURL.absoluteString,
                preferredOpusChannelCount: 2
            )
            if let stereoPreferredTrack,
               await ShadowClientRealtimeAudioSessionRuntime.canDecode(track: stereoPreferredTrack)
            {
                parsedAudioTrack = stereoPreferredTrack
            } else {
                parsedAudioTrack = nil
            }
        }
        guard let parsedAudioTrack else {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP audio SETUP failed: no decodable audio track in SDP"
            )
        }
        audioTrackDescriptor = parsedAudioTrack
        logger.notice(
            "RTSP audio track parsed codec=\(parsedAudioTrack.codec.label, privacy: .public) payloadType=\(parsedAudioTrack.rtpPayloadType, privacy: .public) sampleRate=\(parsedAudioTrack.sampleRate, privacy: .public) channels=\(parsedAudioTrack.channelCount, privacy: .public)"
        )
        let audioControls = (try? ShadowClientRTSPSessionDescriptionParser.parseAudioControlURLs(
            sdp: sdp,
            contentBase: contentBase,
            fallbackSessionURL: normalizedURL.absoluteString
        )) ?? []
        let prioritizedAudioControls = {
            if let parsedControlURL = parsedAudioTrack.controlURL {
                return [parsedControlURL] + audioControls
            }
            return audioControls
        }()
        let audioSetupCandidates = audioControlURLCandidates(
            controlsFromSDP: prioritizedAudioControls,
            sessionURL: normalizedURL.absoluteString
        )
        var audioSetupSucceeded = false
        var lastAudioSetupError: Error?
        guard !audioSetupCandidates.isEmpty else {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP audio SETUP failed: no audio control URL"
            )
        }
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
                } else {
                    audioServerPort = NWEndpoint.Port(rawValue: ShadowClientRealtimeSessionDefaults.fallbackAudioPort)
                    logger.notice("RTSP audio server port missing in SETUP transport; using fallback \(ShadowClientRealtimeSessionDefaults.fallbackAudioPort, privacy: .public)")
                }
                audioPingPayload = ShadowClientRTSPTransportHeaderParser.parseHostPingPayload(
                    from: response.headers[ShadowClientRTSPRequestDefaults.responseHeaderPingPayload]
                )
                if let audioPingPayload,
                   let token = String(data: audioPingPayload, encoding: .utf8)
                {
                    logger.notice("RTSP audio ping payload token \(token, privacy: .public)")
                } else {
                    logger.notice("RTSP audio ping payload token unavailable")
                }
                logger.notice("RTSP audio SETUP ok for \(controlURL, privacy: .public)")
                audioSetupSucceeded = true
                break
            } catch {
                lastAudioSetupError = error
                logger.error("RTSP audio SETUP failed for \(controlURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        guard audioSetupSucceeded else {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP audio SETUP failed: \(lastAudioSetupError?.localizedDescription ?? "unknown")"
            )
        }
        guard sessionHeader != nil else {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP audio SETUP failed: missing session header"
            )
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
            videoServerPort = NWEndpoint.Port(rawValue: ShadowClientRealtimeSessionDefaults.fallbackVideoPort)
            logger.notice("RTSP video server port missing in SETUP transport; using fallback \(ShadowClientRealtimeSessionDefaults.fallbackVideoPort, privacy: .public)")
        }
        guard sessionHeader != nil else {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP SETUP failed: missing session header"
            )
        }
        videoPingPayload = ShadowClientRTSPTransportHeaderParser.parseHostPingPayload(
            from: setup.headers[ShadowClientRTSPRequestDefaults.responseHeaderPingPayload]
        )
        if let videoPingPayload,
           let token = String(data: videoPingPayload, encoding: .utf8)
        {
            logger.notice("RTSP video ping payload token \(token, privacy: .public)")
        } else {
            logger.notice("RTSP video ping payload token unavailable")
        }
        logger.notice("RTSP video SETUP ok for payload type \(track.rtpPayloadType, privacy: .public) via \(selectedSetupURL ?? track.controlURL, privacy: .public)")
        await prepareAudioPingBeforePlay(host: controlHost)
        await prepareVideoPingBeforePlay(host: controlHost)

        var parsedControlConnectData: UInt32?
        var parsedControlServerPort: NWEndpoint.Port?
        let controlSetupCandidates = controlStreamURLCandidates(
            sessionURL: normalizedURL.absoluteString,
            preferredControlPath: preferredControlStreamPath
        )
        var controlSetupSucceeded = false
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
                } else {
                    throw ShadowClientRTSPInterleavedClientError.requestFailed(
                        "RTSP control server port missing in SETUP transport"
                    )
                }
                if let parsed = ShadowClientRTSPTransportHeaderParser.parseHostControlConnectData(
                    from: response.headers[ShadowClientRTSPRequestDefaults.responseHeaderConnectData]
                ) {
                    parsedControlConnectData = parsed
                    logger.notice("RTSP control connect data \(parsed, privacy: .public)")
                }
                logger.notice("RTSP control SETUP ok for \(controlURL, privacy: .public)")
                controlSetupSucceeded = true
                break
            } catch {
                logger.error("RTSP control SETUP failed for \(controlURL, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        if requiresControlSetup, !controlSetupSucceeded {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP control SETUP failed: no successful control stream setup"
            )
        }
        controlConnectData = parsedControlConnectData
        controlServerPort = parsedControlServerPort

        let hostFeatureFlags = parseHostFeatureFlags(from: sdp)
        if videoConfiguration.preferredCodec == .auto,
           parsedTrack.codec != .av1,
           !sdp.localizedCaseInsensitiveContains(ShadowClientRTSPProtocolProfile.av1ClockRateMarker)
        {
            logger.notice(
                "RTSP auto codec staying on \(parsedTrack.codec.rawValue, privacy: .public) because SDP did not advertise an AV1 video track"
            )
        }
        if videoConfiguration.enableHDR, hostFeatureFlags == 0 {
            logger.notice(
                "RTSP host SDP reported zero session feature flags while HDR was requested; treating HDR capability as unsupported for this host advertisement"
            )
        }
        let encryptionSupportedFlags = parseHostEncryptionSupportedFlags(from: sdp)
        let encryptionRequestedFlags = parseHostEncryptionRequestedFlags(from: sdp)
        let effectiveEncryptionRequestedFlags = encryptionSupportedFlags == 0 ?
            encryptionRequestedFlags :
            (encryptionRequestedFlags & encryptionSupportedFlags)
        let handshakeNegotiation = ShadowClientHostHandshakeNegotiation(
            audioPingPayload: audioPingPayload,
            videoPingPayload: videoPingPayload,
            controlConnectData: parsedControlConnectData,
            encryptionRequestedFlags: effectiveEncryptionRequestedFlags,
            prefersSessionIdentifierV1: ShadowClientHostSessionDefaults.prefersSessionIdentifierV1,
            supportsEncryptedControlChannelV2: ShadowClientHostSessionDefaults.supportsEncryptedControlChannelV2 && remoteInputKey != nil,
            supportsEncryptedAudioTransport: remoteInputKey != nil && remoteInputKeyID != nil
        )
        let lumenTransportNegotiation = try ShadowClientLumenControlTransportNegotiation.resolve(
            handshakeNegotiation: handshakeNegotiation,
            remoteInputKey: remoteInputKey,
            remoteInputKeyID: remoteInputKeyID
        )
        useSessionIdentifierV1 = true
        controlChannelMode = lumenTransportNegotiation.controlChannelMode
        audioEncryptionConfiguration = lumenTransportNegotiation.audioEncryptionConfiguration
        logger.notice(
            "RTSP negotiation session-id-v1=\(handshakeNegotiation.supportsSessionIdentifierV1, privacy: .public) ml-flags=\(handshakeNegotiation.moonlightFeatureFlags, privacy: .public) ss-feature-flags=\(hostFeatureFlags, privacy: .public) encryption-supported=\(encryptionSupportedFlags, privacy: .public) encryption-requested=\(encryptionRequestedFlags, privacy: .public) encryption-enabled=\(handshakeNegotiation.encryptionEnabledFlags, privacy: .public) control-mode=\(lumenTransportNegotiation.controlModeLabel, privacy: .public) audio-mode=\(lumenTransportNegotiation.audioEncryptionLabel, privacy: .public)"
        )

        let clientDisplayCharacteristics = await ShadowClientLumenClientDisplayCharacteristicsResolver.current(
            hdrEnabled: videoConfiguration.enableHDR,
            scalePercent: videoConfiguration.displayScalePercent,
            hiDPIEnabled: videoConfiguration.requestHiDPI
        )
        let announcePayload = ShadowClientRTSPAnnouncePayloadBuilder.build(
            hostAddress: host,
            videoConfiguration: videoConfiguration,
            codec: track.codec,
            videoPort: videoServerPort?.rawValue ?? ShadowClientRealtimeSessionDefaults.fallbackVideoPort,
            moonlightFeatureFlags: handshakeNegotiation.moonlightFeatureFlags,
            encryptionEnabledFlags: handshakeNegotiation.encryptionEnabledFlags,
            clientDisplayCharacteristics: clientDisplayCharacteristics
        )
        let announceTargets = announceURLCandidates(
            sessionURL: normalizedURL.absoluteString,
            preferredTarget: useModernControlStreamIdentifier ? preferredControlStreamPath : "streamid=video"
        )
        var announceHeaders: [String: String] = [
            ShadowClientRTSPRequestDefaults.headerUserAgent: ShadowClientRTSPRequestDefaults.userAgent,
            ShadowClientRTSPRequestDefaults.headerContentType: ShadowClientRTSPRequestDefaults.acceptSDP,
            ShadowClientRTSPRequestDefaults.headerContentLength: "\(announcePayload.count)",
        ]
        if let sessionHeader {
            announceHeaders[ShadowClientRTSPRequestDefaults.headerSession] = sessionHeader
        }

        var announceSucceeded = false
        var lastAnnounceError: Error?
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
                lastAnnounceError = error
                logger.error("RTSP ANNOUNCE failed for \(announceTarget, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        guard announceSucceeded else {
            throw ShadowClientRTSPInterleavedClientError.requestFailed(
                "RTSP ANNOUNCE failed: \(lastAnnounceError?.localizedDescription ?? "unknown")"
            )
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

        var lastPlayError: Error?
        if useModernControlStreamIdentifier {
            let rootPlayTarget = "/"
            do {
                _ = try await sendRequestWithReconnectRetry(
                    method: ShadowClientRTSPRequestDefaults.playMethod,
                    url: rootPlayTarget,
                    headers: resolvedPlayHeaders,
                    host: host,
                    port: port
                )
                logger.notice("RTSP PLAY ok for \(rootPlayTarget, privacy: .public)")
            } catch {
                lastPlayError = error
                logger.error("RTSP PLAY failed for \(rootPlayTarget, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw ShadowClientRTSPInterleavedClientError.requestFailed(
                    "RTSP PLAY failed: \(lastPlayError?.localizedDescription ?? "unknown")"
                )
            }
        } else {
            let videoPlayTarget = "streamid=video"
            let audioPlayTarget = "streamid=audio"
            do {
                _ = try await sendRequestWithReconnectRetry(
                    method: ShadowClientRTSPRequestDefaults.playMethod,
                    url: videoPlayTarget,
                    headers: resolvedPlayHeaders,
                    host: host,
                    port: port
                )
                logger.notice("RTSP PLAY ok for \(videoPlayTarget, privacy: .public)")
            } catch {
                lastPlayError = error
                logger.error("RTSP PLAY failed for \(videoPlayTarget, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw ShadowClientRTSPInterleavedClientError.requestFailed(
                    "RTSP PLAY failed: \(lastPlayError?.localizedDescription ?? "unknown")"
                )
            }
            do {
                _ = try await sendRequestWithReconnectRetry(
                    method: ShadowClientRTSPRequestDefaults.playMethod,
                    url: audioPlayTarget,
                    headers: resolvedPlayHeaders,
                    host: host,
                    port: port
                )
                logger.notice("RTSP PLAY ok for \(audioPlayTarget, privacy: .public)")
            } catch {
                lastPlayError = error
                logger.error("RTSP PLAY failed for \(audioPlayTarget, privacy: .public): \(error.localizedDescription, privacy: .public)")
                throw ShadowClientRTSPInterleavedClientError.requestFailed(
                    "RTSP PLAY failed: \(lastPlayError?.localizedDescription ?? "unknown")"
                )
            }
        }

        var didStartHostControl = false
        if controlServerPort != nil {
            await ensureHostControlChannelStarted(fallbackHost: remoteHost ?? .init(host))
            didStartHostControl = hasStartedControlChannelBootstrap
            if didStartHostControl {
                logger.debug("RTSP control path negotiated; Lumen control bootstrap ready")
            } else {
                logger.error("RTSP control path negotiated; Lumen control bootstrap unavailable")
            }
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
        case .prores:
            return .prores
        }
    }

    private struct ServerAppVersion: Comparable {
        let major: Int
        let minor: Int
        let patch: Int

        static func < (lhs: ServerAppVersion, rhs: ServerAppVersion) -> Bool {
            if lhs.major != rhs.major {
                return lhs.major < rhs.major
            }
            if lhs.minor != rhs.minor {
                return lhs.minor < rhs.minor
            }
            return lhs.patch < rhs.patch
        }
    }

    private static func parseServerAppVersion(_ raw: String?) -> ServerAppVersion? {
        guard let raw else {
            return nil
        }
        let numericComponents = raw.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
        guard numericComponents.count >= 3 else {
            return nil
        }
        return .init(
            major: numericComponents[0],
            minor: numericComponents[1],
            patch: numericComponents[2]
        )
    }

    private static func serverMajorVersion(_ raw: String?) -> Int? {
        parseServerAppVersion(raw)?.major
    }

    private static func isServerVersionAtLeast(
        _ raw: String?,
        major: Int,
        minor: Int,
        patch: Int
    ) -> Bool {
        guard let parsed = parseServerAppVersion(raw) else {
            return true
        }
        return parsed >= .init(major: major, minor: minor, patch: patch)
    }

    private static func clientVersionHeaderValue(serverAppVersion: String?) -> String {
        let major = serverMajorVersion(serverAppVersion) ?? 7
        switch major {
        case 3:
            return "10"
        case 4:
            return "11"
        case 5:
            return "12"
        case 6:
            return "13"
        default:
            return "14"
        }
    }

    private func reconnect(
        host: String,
        port: NWEndpoint.Port
    ) async throws {
        connection?.cancel()
        connection = nil
        readBuffer.removeAll(keepingCapacity: false)

        let nextConnection = try await connectWithMoonlightRetry(
            host: host,
            port: port
        )
        connection = nextConnection
        if let resolvedHost = resolvedRemoteHost(from: nextConnection) {
            remoteHost = resolvedHost
        } else {
            remoteHost = .init(host)
        }
        localHost = resolvedLocalHost(from: nextConnection)
    }

    private func connectWithMoonlightRetry(
        host: String,
        port: NWEndpoint.Port
    ) async throws -> NWConnection {
        var connectRetries = 0
        let candidateHosts = Self.resolvedConnectionHostCandidates(for: host)

        while true {
            for candidateHost in candidateHosts {
                let candidateConnection = NWConnection(
                    host: candidateHost,
                    port: port,
                    using: ShadowClientStreamingTrafficPolicy.tcpParameters(
                        trafficClass: ShadowClientStreamingTrafficPolicy.rtsp(
                            prioritized: prioritizeNetworkTraffic
                        )
                    )
                )
                do {
                    try await waitForReady(
                        candidateConnection,
                        timeout: ShadowClientRealtimeSessionDefaults.rtspConnectTimeout
                    )
                    return candidateConnection
                } catch {
                    candidateConnection.cancel()

                    let canRetry =
                        (Self.isConnectionRefusedError(error) ||
                            Self.isLikelyRTSPTransportTerminationError(error)) &&
                        connectRetries < 20
                    guard canRetry else {
                        throw error
                    }
                }
            }

            connectRetries += 1
            try? await Task.sleep(for: ShadowClientRealtimeSessionDefaults.rtspConnectRetryDelay)
        }
    }

    private static func resolvedConnectionHostCandidates(for host: String) -> [NWEndpoint.Host] {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            return [NWEndpoint.Host(host)]
        }

        if parseIPv4Literal(trimmedHost) != nil || parseIPv6Literal(trimmedHost) != nil {
            return [NWEndpoint.Host(trimmedHost)]
        }

        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var resultPointer: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(trimmedHost, nil, &hints, &resultPointer)
        guard status == 0, let resultPointer else {
            return [NWEndpoint.Host(trimmedHost)]
        }
        defer { freeaddrinfo(resultPointer) }

        var seen = Set<String>()
        var candidates: [(host: String, rank: Int)] = []

        for pointer in sequence(first: resultPointer, next: { $0.pointee.ai_next }) {
            guard let sockaddrPointer = pointer.pointee.ai_addr else {
                continue
            }
            let hostString = numericHostString(from: sockaddrPointer, length: pointer.pointee.ai_addrlen)
            guard let hostString else {
                continue
            }
            let normalized = hostString.lowercased()
            guard seen.insert(normalized).inserted else {
                continue
            }
            candidates.append((host: hostString, rank: connectionHostRank(hostString)))
        }

        if candidates.isEmpty {
            return [NWEndpoint.Host(trimmedHost)]
        }

        return candidates
            .sorted {
                if $0.rank == $1.rank {
                    return $0.host.localizedCaseInsensitiveCompare($1.host) == .orderedAscending
                }
                return $0.rank < $1.rank
            }
            .map { NWEndpoint.Host($0.host) }
    }

    private static func parseIPv4Literal(_ host: String) -> in_addr? {
        var parsed = in_addr()
        let result = host.withCString { cString in
            inet_pton(AF_INET, cString, &parsed)
        }
        guard result == 1 else {
            return nil
        }
        return parsed
    }

    private static func parseIPv6Literal(_ host: String) -> in6_addr? {
        var parsed = in6_addr()
        let result = host.withCString { cString in
            inet_pton(AF_INET6, cString, &parsed)
        }
        guard result == 1 else {
            return nil
        }
        return parsed
    }

    private static func numericHostString(
        from address: UnsafeMutablePointer<sockaddr>,
        length: socklen_t
    ) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        let status = getnameinfo(
            address,
            length,
            &buffer,
            socklen_t(buffer.count),
            nil,
            0,
            NI_NUMERICHOST
        )
        guard status == 0 else {
            return nil
        }
        return String(cString: buffer)
    }

    private static func connectionHostRank(_ host: String) -> Int {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("169.254.") || normalized.hasPrefix("fe80:") {
            return 10
        }
        if normalized.contains(":") {
            return 1
        }
        return 0
    }

    private static func isConnectionRefusedError(_ error: Error) -> Bool {
        if let networkError = error as? NWError,
           case let .posix(code) = networkError,
           code == .ECONNREFUSED
        {
            return true
        }

        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain,
           nsError.code == Int(POSIXErrorCode.ECONNREFUSED.rawValue)
        {
            return true
        }
        if let networkError = error as? NWError,
           case let .posix(code) = networkError,
           code == .ECONNREFUSED
        {
            return true
        }
        return false
    }

    private static func isLikelyRTSPTransportTerminationError(_ error: Error) -> Bool {
        if let rtspError = error as? ShadowClientRTSPInterleavedClientError {
            switch rtspError {
            case .connectionClosed, .connectionFailed:
                return true
            case .invalidURL, .requestFailed, .invalidResponse:
                break
            }
        }
        let nsError = error as NSError
        if nsError.domain == "Network.NWError", nsError.code == 96 {
            return true
        }
        if nsError.domain == NSPOSIXErrorDomain,
           let posix = POSIXErrorCode(rawValue: Int32(nsError.code))
        {
            switch posix {
            case .ECONNRESET, .EPIPE, .ENOTCONN, .ECONNABORTED, .ETIMEDOUT, .ENETDOWN, .ENETUNREACH, .EHOSTUNREACH:
                return true
            default:
                break
            }
        }
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNetworkConnectionLost,
                 NSURLErrorTimedOut,
                 NSURLErrorCannotConnectToHost,
                 NSURLErrorCannotFindHost,
                 NSURLErrorNotConnectedToInternet:
                return true
            default:
                break
            }
        }

        if let networkError = error as? NWError,
           case let .posix(code) = networkError
        {
            switch code {
            case .ECONNRESET, .EPIPE, .ENOTCONN, .ECONNABORTED, .ETIMEDOUT, .ENETDOWN, .ENETUNREACH, .EHOSTUNREACH:
                return true
            default:
                break
            }
        }
        return false
    }

    private func normalizeRTSPURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        if components.scheme?.lowercased() == "rtspenc" {
            components.scheme = "rtsp"
        }
        if components.path.isEmpty {
            components.path = "/"
        }
        return components.url ?? url
    }

    private static func isEncryptedRTSPSessionURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "rtspenc"
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
        case .prores:
            codec = .prores
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
            candidateRTPPayloadTypes: [payloadType],
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

    private func controlStreamURLCandidates(
        sessionURL: String,
        preferredControlPath: String
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

        add(preferredControlPath)
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

    private func announceURLCandidates(
        sessionURL: String,
        preferredTarget: String
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

        add(preferredTarget)
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

    private func parseHostFeatureFlags(from sdp: String) -> UInt32 {
        parseHostUIntAttribute(
            from: sdp,
            prefix: ShadowClientHostHandshakeProfile.featureFlagsAttributePrefix
        ) ?? 0
    }

    private func parseHostEncryptionSupportedFlags(from sdp: String) -> UInt32 {
        parseHostUIntAttribute(
            from: sdp,
            prefix: ShadowClientHostHandshakeProfile.encryptionSupportedAttributePrefix
        ) ?? 0
    }

    private func parseHostEncryptionRequestedFlags(from sdp: String) -> UInt32 {
        parseHostUIntAttribute(
            from: sdp,
            prefix: ShadowClientHostHandshakeProfile.encryptionRequestedAttributePrefix
        ) ?? ShadowClientHostHandshakeProfile.encryptionDisabled
    }

    private func parseHostUIntAttribute(
        from sdp: String,
        prefix: String
    ) -> UInt32? {
        let lines = sdp
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines {
            let lower = line.lowercased()
            guard let range = lower.range(of: prefix) else {
                continue
            }

            let rawValue = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            if let parsed = UInt32(rawValue) {
                return parsed
            }
        }

        return nil
    }

    private func ensureHostControlChannelStarted(
        fallbackHost: NWEndpoint.Host
    ) async {
        guard !hasStartedControlChannelBootstrap else {
            return
        }
        let started = await startHostControlChannelIfNeeded(
            host: String(describing: fallbackHost)
        )
        hasStartedControlChannelBootstrap = started
    }

    private func startHostControlChannelIfNeeded(host: String) async -> Bool {
        guard let controlServerPort else {
            logger.notice("RTSP control bootstrap skipped (no negotiated control server port)")
            return true
        }
        guard let controlChannelMode else {
            logger.error("RTSP control bootstrap failed because Lumen control mode negotiation did not complete")
            return false
        }

        if controlChannelRuntime != nil {
            return true
        }

        let controlHost = remoteHost ?? .init(host)
        let runtime = ShadowClientHostControlChannelRuntime(
            prioritizeNetworkTraffic: prioritizeNetworkTraffic,
            onRoundTripSample: onControlRoundTripSample,
            onControllerFeedback: onControllerFeedback,
            onHDRMode: onHDRMode,
            onHDRFrameState: onHDRFrameState,
            onTermination: onTermination
        )

        do {
            try await runtime.start(
                host: controlHost,
                port: controlServerPort,
                connectData: controlConnectData,
                mode: controlChannelMode
            )
            controlChannelRuntime = runtime
            await inputChannelGateway.install(runtime)
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
        await inputChannelGateway.clear()
        controlChannelRuntime = nil
        hasStartedControlChannelBootstrap = false
        cancelPrePlayPingWarmupTasks()

        connection?.cancel()
        connection = nil
        readBuffer.removeAll(keepingCapacity: false)
        cseq = 1
        sessionHeader = nil
        remoteHost = nil
        localHost = nil
        audioServerPort = nil
        videoServerPort = nil
        controlServerPort = nil
        audioPingPayload = nil
        videoPingPayload = nil
        audioTrackDescriptor = nil
        prePlayAudioUDPConnection?.cancel()
        prePlayAudioUDPConnection = nil
        if let prePlayVideoUDPSocket {
            await prePlayVideoUDPSocket.close()
        }
        prePlayVideoUDPSocket = nil
        controlConnectData = nil
        controlChannelMode = nil
        useSessionIdentifierV1 = false
        remoteInputKey = nil
        remoteInputKeyID = nil
        audioEncryptionConfiguration = nil
        negotiatedClientPortBase = defaultClientPortBase
        rtspHostHeaderValue = nil
        rtspClientVersionHeaderValue = ShadowClientRTSPRequestDefaults.clientVersionHeaderValue
        rtspEncryptionCodec = nil
        currentServerAppVersion = nil
        lastInteractiveInputEventUptime = 0
    }

    nonisolated func sendInput(_ event: ShadowClientRemoteInputEvent) async throws {
        await noteInteractiveInput(event)
        try await inputChannelGateway.sendInput(
            event,
            ensureRuntime: { [weak self] in
                await self?.ensureInputControlChannelForGateway()
            },
            invalidateRuntime: { [weak self] runtime in
                await self?.invalidateInputControlChannelForGateway(runtime)
            }
        )
    }

    nonisolated func sendInputKeepAlive() async throws {
        try await inputChannelGateway.sendKeepAlive(
            ensureRuntime: { [weak self] in
                await self?.ensureInputControlChannelForGateway()
            },
            invalidateRuntime: { [weak self] runtime in
                await self?.invalidateInputControlChannelForGateway(runtime)
            }
        )
    }

    private func noteInteractiveInput(_ event: ShadowClientRemoteInputEvent) {
        guard Self.isInteractiveInputEvent(event) else {
            return
        }
        lastInteractiveInputEventUptime = ProcessInfo.processInfo.systemUptime
    }

    private static func isInteractiveInputEvent(_ event: ShadowClientRemoteInputEvent) -> Bool {
        switch event {
        case .keyDown, .keyUp, .text, .pointerMoved, .pointerPosition, .pointerButton, .scroll:
            return true
        case let .gamepadState(state):
            return ShadowClientRealtimeRTSPSessionRuntime
                .shouldTreatGamepadStateAsInteractiveForUDPDatagramRecovery(state)
        case .gamepadArrival:
            return false
        }
    }

    func requestVideoRecoveryFrame(lastSeenFrameIndex: UInt32?) async {
        await ensureHostControlChannelStarted(
            fallbackHost: remoteHost ?? .init("127.0.0.1")
        )
        guard let controlChannelRuntime else {
            return
        }
        await controlChannelRuntime.requestVideoRecoveryFrame(
            lastSeenFrameIndex: lastSeenFrameIndex
        )
    }

    func requestInvalidateReferenceFrames(
        startFrameIndex: UInt32,
        endFrameIndex: UInt32
    ) async {
        await ensureHostControlChannelStarted(
            fallbackHost: remoteHost ?? .init("127.0.0.1")
        )
        guard let controlChannelRuntime else {
            return
        }
        await controlChannelRuntime.requestInvalidateReferenceFrames(
            startFrameIndex: startFrameIndex,
            endFrameIndex: endFrameIndex
        )
    }

    private func ensureInputControlChannelForGateway() async -> ShadowClientHostControlChannelRuntime? {
        await ensureHostControlChannelStarted(
            fallbackHost: remoteHost ?? .init("127.0.0.1")
        )
        return controlChannelRuntime
    }

    private func invalidateInputControlChannelForGateway(
        _ runtime: ShadowClientHostControlChannelRuntime
    ) async {
        guard let controlChannelRuntime else {
            hasStartedControlChannelBootstrap = false
            await inputChannelGateway.install(nil)
            return
        }
        guard controlChannelRuntime === runtime else {
            return
        }
        await controlChannelRuntime.stop()
        self.controlChannelRuntime = nil
        hasStartedControlChannelBootstrap = false
        await inputChannelGateway.install(nil)
    }

    func receiveInterleavedVideoPackets(
        payloadType: Int,
        videoPayloadCandidates: Set<Int>,
        onVideoPacket: @escaping @Sendable (Data, Bool) async throws -> Void
    ) async throws {
        let audioTrack = audioTrackDescriptor
        if let remoteHost, let videoServerPort {
            var udpReceiveRetryCount = 0
            let maxInSessionUDPVideoReceiveRetries = 3
            while !Task.isCancelled {
                do {
                    try await receiveUDPVideoPackets(
                        host: remoteHost,
                        port: videoServerPort,
                        payloadType: payloadType,
                        videoPayloadCandidates: videoPayloadCandidates,
                        audioTrack: audioTrack,
                        onVideoPacket: onVideoPacket
                    )
                    return
                } catch {
                    if let udpSocketError = error as? ShadowClientUDPDatagramSocketError {
                        logger.error(
                            "RTSP UDP video receive loop failed op=\(udpSocketError.operation?.rawValue ?? "unknown", privacy: .public) transient=\(udpSocketError.isTransient, privacy: .public) error=\(udpSocketError.localizedDescription, privacy: .public)"
                        )
                    } else {
                        logger.error(
                            "RTSP UDP video receive loop failed with non-socket error: \(error.localizedDescription, privacy: .public)"
                        )
                    }
                    guard ShadowClientRealtimeRTSPSessionRuntime
                        .shouldRetryInSessionAfterUDPVideoReceiveError(error)
                    else {
                        throw error
                    }
                    udpReceiveRetryCount &+= 1
                    if udpReceiveRetryCount > maxInSessionUDPVideoReceiveRetries {
                        logger.error(
                            "RTSP UDP video in-session receive retry exhausted (attempts=\(udpReceiveRetryCount, privacy: .public)); escalating to transport reconnect"
                        )
                        throw ShadowClientRealtimeSessionRuntimeError.transportFailure(
                            .udpVideoProlongedDatagramInactivityAfterStartup
                        )
                    }
                    logger.error(
                        "RTSP UDP video receive became inactive; retrying in-session UDP receive (attempt=\(udpReceiveRetryCount, privacy: .public))"
                    )
                    await requestVideoRecoveryFrame(lastSeenFrameIndex: nil)
                    try? await Task.sleep(for: .milliseconds(200))
                }
            }
            throw CancellationError()
        }

        var packetCount = 0
        var fecReconstructionQueue = makeVideoFECReconstructionQueue()
        var lastFECRecoveryRequestUptime: TimeInterval = 0
        var firstFECUnrecoverableUptime: TimeInterval = 0
        var fecUnrecoverableBurstCount = 0

        while !Task.isCancelled {
            if let packet = try parseInterleavedPacketIfAvailable() {
                guard packet.isRTP, packet.channel == 0 else {
                    continue
                }

                packetCount += 1
                if packetCount == 1 {
                    await ensureHostControlChannelStarted(
                        fallbackHost: remoteHost ?? .init("127.0.0.1")
                    )
                    logger.notice(
                        "First RTP video packet received: payloadType=\(packet.payloadType, privacy: .public), marker=\(packet.marker, privacy: .public), payloadBytes=\(packet.payload.count, privacy: .public)"
                    )
                }

                let ingestResult = fecReconstructionQueue.ingest(packet)
                if ingestResult.droppedUnrecoverableBlock {
                    logger.error("Video FEC reconstruction dropped unrecoverable block")
                    // Drop the whole reconstructed batch on unrecoverable loss to avoid forwarding
                    // continuity-tainted payloads to the depacketizer/decoder path.
                    fecReconstructionQueue = makeVideoFECReconstructionQueue()
                    let now = ProcessInfo.processInfo.systemUptime
                    if firstFECUnrecoverableUptime == 0 ||
                        now - firstFECUnrecoverableUptime > videoFECUnrecoverableRecoveryBurstWindowSeconds
                    {
                        firstFECUnrecoverableUptime = now
                        fecUnrecoverableBurstCount = 0
                    }
                    fecUnrecoverableBurstCount += 1
                    if fecUnrecoverableBurstCount == 1 ||
                        fecUnrecoverableBurstCount == videoFECUnrecoverableRecoveryBurstThreshold
                    {
                        logger.notice(
                            "Video FEC unrecoverable burst progress count=\(fecUnrecoverableBurstCount, privacy: .public)/\(self.videoFECUnrecoverableRecoveryBurstThreshold, privacy: .public)"
                        )
                    }
                    guard ShadowClientRealtimeRTSPSessionRuntime.shouldRequestVideoRecoveryAfterFECUnrecoverableBurst(
                        now: now,
                        firstUnrecoverableUptime: firstFECUnrecoverableUptime,
                        unrecoverableCount: fecUnrecoverableBurstCount,
                        lastRequestUptime: lastFECRecoveryRequestUptime,
                        burstWindow: videoFECUnrecoverableRecoveryBurstWindowSeconds,
                        burstThreshold: videoFECUnrecoverableRecoveryBurstThreshold,
                        minimumInterval: videoFECUnrecoverableRecoveryRequestCooldownSeconds
                    ) else {
                        continue
                    }
                    lastFECRecoveryRequestUptime = now
                    firstFECUnrecoverableUptime = 0
                    fecUnrecoverableBurstCount = 0
                    await requestVideoRecoveryFrame(lastSeenFrameIndex: nil)
                    continue
                }
                if !ingestResult.orderedDataPackets.isEmpty, fecUnrecoverableBurstCount > 0 {
                    firstFECUnrecoverableUptime = 0
                    fecUnrecoverableBurstCount = 0
                }
                for orderedPacket in ingestResult.orderedDataPackets {
                    try await onVideoPacket(
                        orderedPacket.payload,
                        orderedPacket.marker
                    )
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
        videoPayloadCandidates: Set<Int>,
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
            udpSocket = try await makeVideoUDPSocket(
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
            prioritizeNetworkTraffic: prioritizeNetworkTraffic,
            stateDidChange: onAudioOutputStateChanged,
            pendingDurationDidChange: onAudioPendingDurationChanged
        )
        self.audioRuntime = audioRuntime
        let prePlayAudioConnection = prePlayAudioUDPConnection
        prePlayAudioUDPConnection = nil
        prePlayAudioPingWarmupTask?.cancel()
        prePlayAudioPingWarmupTask = nil

        do {
            let initialVideoPings = ShadowClientHostPingPacketCodec.makePingPackets(
                sequence: 1,
                negotiatedPayload: pingPayload
            )
            if initialVideoPings.isEmpty {
                rtspLogger.notice("RTSP UDP video initial ping skipped because the host did not negotiate a ping payload")
            } else {
                for initialVideoPing in initialVideoPings {
                    try await udpSocket.send(initialVideoPing)
                }
                rtspLogger.notice("RTSP UDP video initial ping sent (variants=\(initialVideoPings.count, privacy: .public), bytes=\(initialVideoPings.first?.count ?? 0, privacy: .public))")
            }
        } catch {
            rtspLogger.error("RTSP UDP video initial ping failed: \(error.localizedDescription, privacy: .public)")
        }

        let audioSessionDeactivation = self.audioSessionDeactivation
        var didActivateAudioSession = false
        if let audioServerPort {
            do {
                if let audioSessionActivation {
                    await audioSessionActivation()
                    didActivateAudioSession = true
                }
                try await audioRuntime.start(
                    remoteHost: host,
                    remotePort: audioServerPort,
                    localHost: localHost,
                    preferredLocalPort: negotiatedClientPortBase &+ 1,
                    track: audioTrack,
                    pingPayload: audioPingPayload,
                    encryption: audioEncryptionConfiguration,
                    existingConnection: prePlayAudioConnection
                )
                rtspLogger.notice("RTSP UDP audio receive switched to \(String(describing: host), privacy: .public):\(audioServerPort.rawValue, privacy: .public)")
            } catch {
                if didActivateAudioSession, let audioSessionDeactivation {
                    await audioSessionDeactivation()
                    didActivateAudioSession = false
                }
                rtspLogger.error("RTSP UDP audio runtime setup failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        let sendableVideoSocket = udpSocket

        let pingTask = Task {
            var sequence: UInt32 = 1
            var loggedPingCount = 0
            var loggedPingError = false
            var loggedSkip = false
            while !Task.isCancelled {
                sequence &+= 1
                let pingPackets = ShadowClientHostPingPacketCodec.makePingPackets(
                    sequence: sequence,
                    negotiatedPayload: pingPayload
                )
                guard !pingPackets.isEmpty else {
                    if !loggedSkip {
                        rtspLogger.notice("RTSP UDP video ping loop disabled because the host did not negotiate a ping payload")
                        loggedSkip = true
                    }
                    try? await Task.sleep(for: ShadowClientRealtimeSessionDefaults.pingInterval)
                    continue
                }
                do {
                    for pingPacket in pingPackets {
                        try await sendableVideoSocket.send(pingPacket)
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
            self.audioRuntime = nil
            Task {
                if didActivateAudioSession, let audioSessionDeactivation {
                    await audioSessionDeactivation()
                }
                await udpSocket.close()
            }
        }

        _ = audioTrack
        var packetCount = 0
        var parseFailureCount = 0
        var datagramCount = 0
        var fecReconstructionQueue = makeVideoFECReconstructionQueue()
        var lastFECRecoveryRequestUptime: TimeInterval = 0
        var firstFECUnrecoverableUptime: TimeInterval = 0
        var fecUnrecoverableBurstCount = 0
        let receiveStart = ContinuousClock.now
        var lastVideoDatagramUptime = ProcessInfo.processInfo.systemUptime
        var hasPendingPostStartDatagramStall = false

        while !Task.isCancelled {
            guard let datagram = try await udpSocket.receive(
                maximumLength: ShadowClientRealtimeSessionDefaults.maximumTransportReadLength
            ) else {
                let now = ProcessInfo.processInfo.systemUptime
                let secondsSinceLastDatagram = now - lastVideoDatagramUptime
                if datagramCount == 0,
                   receiveStart.duration(to: ContinuousClock.now) >=
                    ShadowClientRealtimeSessionDefaults.initialVideoDatagramTimeout
                {
                    logger.error(
                        "RTSP UDP video startup traffic missing (silence=\(secondsSinceLastDatagram, privacy: .public)s); terminating session"
                    )
                    throw ShadowClientRealtimeSessionRuntimeError.transportFailure(
                        .udpVideoNoStartupDatagrams
                    )
                }
                if ShadowClientRealtimeRTSPSessionRuntime.shouldTreatUDPVideoDatagramReceiveAsStalledAfterStartup(
                    datagramCount: datagramCount,
                    secondsSinceLastDatagram: secondsSinceLastDatagram
                ) {
                    if !hasPendingPostStartDatagramStall {
                        logger.notice(
                            "RTSP UDP video datagram silence observed after startup (silence=\(secondsSinceLastDatagram, privacy: .public)s); treating as idle video suppression and keeping session alive"
                        )
                        hasPendingPostStartDatagramStall = true
                    }
                    if ShadowClientRealtimeRTSPSessionRuntime.shouldRequestVideoRecoveryForUDPDatagramInactivity(
                        now: now,
                        lastRecoveryRequestUptime: lastFECRecoveryRequestUptime,
                        lastInteractiveInputEventUptime: lastInteractiveInputEventUptime,
                        secondsSinceLastDatagram: secondsSinceLastDatagram
                    ) {
                        lastFECRecoveryRequestUptime = now
                        logger.notice(
                            "RTSP UDP video inactivity triggered recovery request (silence=\(secondsSinceLastDatagram, privacy: .public)s)"
                        )
                        await requestVideoRecoveryFrame(lastSeenFrameIndex: nil)
                    }
                }
                continue
            }
            guard !datagram.isEmpty else {
                continue
            }

            if hasPendingPostStartDatagramStall {
                let resumedAfterSilenceSeconds = ProcessInfo.processInfo.systemUptime - lastVideoDatagramUptime
                logger.notice(
                    "RTSP UDP video datagram flow resumed after inactivity stall (silence=\(resumedAfterSilenceSeconds, privacy: .public)s)"
                )
                hasPendingPostStartDatagramStall = false
            }
            datagramCount += 1
            lastVideoDatagramUptime = ProcessInfo.processInfo.systemUptime
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
                await ensureHostControlChannelStarted(fallbackHost: host)
                logger.notice(
                    "First RTP video packet received: payloadType=\(packet.payloadType, privacy: .public), marker=\(packet.marker, privacy: .public), payloadBytes=\(packet.payload.count, privacy: .public)"
                )
            }

            let ingestResult = fecReconstructionQueue.ingest(packet)
            if ingestResult.droppedUnrecoverableBlock {
                logger.error("Video FEC reconstruction dropped unrecoverable block")
                // Do not forward ordered packets from an unrecoverable FEC block.
                fecReconstructionQueue = makeVideoFECReconstructionQueue()
                let now = ProcessInfo.processInfo.systemUptime
                if firstFECUnrecoverableUptime == 0 ||
                    now - firstFECUnrecoverableUptime > videoFECUnrecoverableRecoveryBurstWindowSeconds
                {
                    firstFECUnrecoverableUptime = now
                    fecUnrecoverableBurstCount = 0
                }
                fecUnrecoverableBurstCount += 1
                if fecUnrecoverableBurstCount == 1 ||
                    fecUnrecoverableBurstCount == videoFECUnrecoverableRecoveryBurstThreshold
                {
                    logger.notice(
                        "Video FEC unrecoverable burst progress count=\(fecUnrecoverableBurstCount, privacy: .public)/\(self.videoFECUnrecoverableRecoveryBurstThreshold, privacy: .public)"
                    )
                }
                guard ShadowClientRealtimeRTSPSessionRuntime.shouldRequestVideoRecoveryAfterFECUnrecoverableBurst(
                    now: now,
                    firstUnrecoverableUptime: firstFECUnrecoverableUptime,
                    unrecoverableCount: fecUnrecoverableBurstCount,
                    lastRequestUptime: lastFECRecoveryRequestUptime,
                    burstWindow: videoFECUnrecoverableRecoveryBurstWindowSeconds,
                    burstThreshold: videoFECUnrecoverableRecoveryBurstThreshold,
                    minimumInterval: videoFECUnrecoverableRecoveryRequestCooldownSeconds
                ) else {
                    continue
                }
                lastFECRecoveryRequestUptime = now
                firstFECUnrecoverableUptime = 0
                fecUnrecoverableBurstCount = 0
                await requestVideoRecoveryFrame(lastSeenFrameIndex: nil)
                continue
            }
            if !ingestResult.orderedDataPackets.isEmpty, fecUnrecoverableBurstCount > 0 {
                firstFECUnrecoverableUptime = 0
                fecUnrecoverableBurstCount = 0
            }
            for orderedPacket in ingestResult.orderedDataPackets {
                try await onVideoPacket(
                    orderedPacket.payload,
                    orderedPacket.marker
                )
            }
        }
    }

    func updateVideoRenderingState(isRendering: Bool) {
        audioRuntime?.updateVideoRenderingState(isRendering: isRendering)
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
    ) async throws -> ShadowClientUDPDatagramSocket {
        let preferredLocalPort = negotiatedVideoPingPort()
        do {
            let socket = try ShadowClientUDPDatagramSocket(
                localHost: localHost,
                localPort: preferredLocalPort,
                remoteHost: host,
                remotePort: port.rawValue,
                trafficClass: ShadowClientStreamingTrafficPolicy.video(
                    prioritized: prioritizeNetworkTraffic
                )
            )
            let endpointDescription = await socket.localEndpointDescription()
            logger.notice(
                "RTSP UDP video socket bound \(endpointDescription, privacy: .public) (preferred-client-port \(preferredLocalPort, privacy: .public))"
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
                remotePort: port.rawValue,
                trafficClass: ShadowClientStreamingTrafficPolicy.video(
                    prioritized: prioritizeNetworkTraffic
                )
            )
            let endpointDescription = await socket.localEndpointDescription()
            logger.notice("RTSP UDP video socket bound \(endpointDescription, privacy: .public) (ephemeral-fallback)")
            return socket
        }
    }

    private func makeVideoFECReconstructionQueue() -> ShadowClientRTPVideoFECReconstructionQueue {
        let negotiatedShardPayloadSize = Int(ShadowClientRTSPAnnounceProfile.packetSize)
        let multiFECCapable = Self.isServerVersionAtLeast(
            currentServerAppVersion,
            major: 7,
            minor: 1,
            patch: 431
        )
        return ShadowClientRTPVideoFECReconstructionQueue(
            fixedShardPayloadSize: negotiatedShardPayloadSize,
            multiFECCapable: multiFECCapable
        )
    }

    private func negotiatedVideoPingPort() -> UInt16 {
        negotiatedClientPortBase
    }

    private func prepareVideoPingBeforePlay(host: NWEndpoint.Host) async {
        guard prePlayVideoUDPSocket == nil,
              let videoServerPort
        else {
            return
        }

        do {
            let socket = try await makeVideoUDPSocket(
                host: host,
                port: videoServerPort,
                localHost: localHost
            )
            prePlayVideoUDPSocket = socket

            let prePlayPings = ShadowClientHostPingPacketCodec.makePingPackets(
                sequence: 1,
                negotiatedPayload: videoPingPayload
            )
            if prePlayPings.isEmpty {
                logger.notice("RTSP UDP video pre-PLAY ping skipped because the host did not negotiate a ping payload")
            } else {
                for packet in prePlayPings {
                    try await socket.send(packet)
                }
                logger.notice(
                    "RTSP UDP video pre-PLAY ping sent (variants=\(prePlayPings.count, privacy: .public), bytes=\(prePlayPings.first?.count ?? 0, privacy: .public))"
                )
            }
            prePlayVideoPingWarmupTask?.cancel()
            if !prePlayPings.isEmpty {
                let payload = videoPingPayload
                prePlayVideoPingWarmupTask = Task { [logger] in
                    var sequence: UInt32 = 1
                    var loggedSendCount = 0
                    while !Task.isCancelled {
                        sequence &+= 1
                        let pingPackets = ShadowClientHostPingPacketCodec.makePingPackets(
                            sequence: sequence,
                            negotiatedPayload: payload
                        )
                        for packet in pingPackets {
                            try? await socket.send(packet)
                        }
                        if loggedSendCount < 2 {
                            logger.debug("RTSP UDP video pre-PLAY warmup ping sent (sequence=\(sequence, privacy: .public), variants=\(pingPackets.count, privacy: .public))")
                            loggedSendCount += 1
                        }
                        try? await Task.sleep(for: ShadowClientRealtimeSessionDefaults.pingInterval)
                    }
                }
            }
        } catch {
            prePlayVideoPingWarmupTask?.cancel()
            prePlayVideoPingWarmupTask = nil
            if let prePlayVideoUDPSocket {
                await prePlayVideoUDPSocket.close()
            }
            prePlayVideoUDPSocket = nil
            logger.error("RTSP UDP video pre-PLAY ping setup failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func cancelPrePlayPingWarmupTasks() {
        prePlayAudioPingWarmupTask?.cancel()
        prePlayAudioPingWarmupTask = nil
        prePlayVideoPingWarmupTask?.cancel()
        prePlayVideoPingWarmupTask = nil
    }

    private func prepareAudioPingBeforePlay(host: NWEndpoint.Host) async {
        guard prePlayAudioUDPConnection == nil,
              let audioServerPort
        else {
            return
        }

        do {
            let connection = try await ShadowClientRealtimeAudioTransportBootstrap.bootstrapUDPConnection(
                remoteHost: host,
                remotePort: audioServerPort,
                localHost: localHost,
                preferredLocalPort: negotiatedClientPortBase &+ 1,
                prioritizeNetworkTraffic: prioritizeNetworkTraffic,
                queue: queue,
                logger: logger,
                readyMessagePrefix: "RTSP UDP audio pre-PLAY socket ready",
                fallbackReadyMessagePrefix: "RTSP UDP audio pre-PLAY socket ready (ephemeral fallback)"
            )
            prePlayAudioUDPConnection = connection

            let prePlayPings = ShadowClientHostPingPacketCodec.makePingPackets(
                sequence: 1,
                negotiatedPayload: audioPingPayload
            )
            if prePlayPings.isEmpty {
                logger.notice("RTSP UDP audio pre-PLAY ping skipped because the host did not negotiate a ping payload")
            } else {
                for packet in prePlayPings {
                    try await ShadowClientRealtimeAudioTransportBootstrap.send(
                        bytes: packet,
                        over: connection
                    )
                }
                logger.notice(
                    "RTSP UDP audio pre-PLAY ping sent (variants=\(prePlayPings.count, privacy: .public), bytes=\(prePlayPings.first?.count ?? 0, privacy: .public))"
                )
            }

            prePlayAudioPingWarmupTask?.cancel()
            if !prePlayPings.isEmpty {
                let payload = audioPingPayload
                prePlayAudioPingWarmupTask = Task { [logger] in
                    var sequence: UInt32 = 1
                    var loggedSendCount = 0
                    var loggedPingError = false
                    while !Task.isCancelled {
                        sequence &+= 1
                        let pingPackets = ShadowClientHostPingPacketCodec.makePingPackets(
                            sequence: sequence,
                            negotiatedPayload: payload
                        )
                        do {
                            for packet in pingPackets {
                                try await ShadowClientRealtimeAudioTransportBootstrap.send(
                                    bytes: packet,
                                    over: connection
                                )
                            }
                            if loggedSendCount < 2 {
                                logger.debug(
                                    "RTSP UDP audio pre-PLAY warmup ping sent (sequence=\(sequence, privacy: .public), variants=\(pingPackets.count, privacy: .public))"
                                )
                                loggedSendCount += 1
                            }
                        } catch {
                            if !loggedPingError {
                                logger.error("RTSP UDP audio pre-PLAY ping failed: \(error.localizedDescription, privacy: .public)")
                                loggedPingError = true
                            }
                        }
                        try? await Task.sleep(for: ShadowClientRealtimeSessionDefaults.pingInterval)
                    }
                }
            }
        } catch {
            prePlayAudioPingWarmupTask?.cancel()
            prePlayAudioPingWarmupTask = nil
            prePlayAudioUDPConnection?.cancel()
            prePlayAudioUDPConnection = nil
            logger.error("RTSP UDP audio pre-PLAY ping setup failed: \(error.localizedDescription, privacy: .public)")
        }
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
        func sendOverFreshConnection() async throws -> ShadowClientRTSPResponse {
            try await reconnect(host: host, port: port)
            return try await sendRequest(
                method: method,
                url: url,
                headers: headers,
                body: body
            )
        }

        do {
            return try await sendOverFreshConnection()
        } catch {
            guard shouldRetryAfterReconnect(error) else {
                throw error
            }

            logger.notice(
                "RTSP \(method, privacy: .public) retrying after reconnect due to transport error: \(error.localizedDescription, privacy: .public)"
            )
            return try await sendOverFreshConnection()
        }
    }

    private func shouldRetryAfterReconnect(_ error: Error) -> Bool {
        Self.isConnectionRefusedError(error) || Self.isLikelyRTSPTransportTerminationError(error)
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

        if rtspEncryptionCodec != nil {
            let response = try await readResponse()
            logResponse(method: ShadowClientRTSPRequestDefaults.describeMethod, response: response)

            guard (200...299).contains(response.statusCode) else {
                let bodyText = String(data: response.body, encoding: .utf8) ?? ""
                throw ShadowClientRTSPInterleavedClientError.requestFailed(
                    "RTSP DESCRIBE failed (\(response.statusCode)): \(bodyText)"
                )
            }

            return response
        }

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
            "\(ShadowClientRTSPRequestDefaults.headerClientVersion): \(rtspClientVersionHeaderValue)"
        )
        if let hostHeader = ShadowClientRTSPProtocolProfile.hostHeaderValue(forRTSPURLString: url) ?? rtspHostHeaderValue {
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
                payloadOffset: 0,
                rawBytes: Data(),
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
            payloadOffset: parsed.payloadOffset,
            rawBytes: parsed.rawBytes,
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
                    timeoutError: { ShadowClientRTSPInterleavedClientError.connectionFailed },
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
                        if gate.finish(.failure(ShadowClientRTSPInterleavedClientError.connectionClosed)) {
                            connection.stateUpdateHandler = nil
                        }
                    default:
                        break
                    }
                }
                connection.start(queue: self.queue)
            }
        } onCancel: {
            if gate.finish(.failure(CancellationError())) {
                connection.stateUpdateHandler = nil
                connection.cancel()
            }
        }
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
        if let rtspEncryptionCodec {
            let encrypted = try rtspEncryptionCodec.encryptClientRTSPMessage(
                bytes,
                sequence: rtspRequestSequence
            )
            rtspRequestSequence &+= 1
            try await Self.send(bytes: encrypted, over: connection)
            return
        }

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

        if rtspEncryptionCodec != nil {
            return try await receiveEncryptedRTSPMessage(over: connection)
        }

        return try await withThrowingTaskGroup(
            of: Data.self,
            returning: Data.self
        ) { group in
            group.addTask {
                try await Self.receiveBytesWithoutTimeout(over: connection)
            }
            group.addTask {
                try await Task.sleep(for: ShadowClientRealtimeSessionDefaults.rtspReceiveTimeout)
                throw ShadowClientRTSPInterleavedClientError.connectionFailed
            }

            guard let result = try await group.next() else {
                group.cancelAll()
                throw ShadowClientRTSPInterleavedClientError.connectionFailed
            }
            group.cancelAll()
            return result
        }
    }

    private func receiveEncryptedRTSPMessage(
        over connection: NWConnection
    ) async throws -> Data {
        while true {
            if let plaintext = try parseEncryptedRTSPMessageIfAvailable() {
                return plaintext
            }

            let chunk = try await withThrowingTaskGroup(
                of: Data.self,
                returning: Data.self
            ) { group in
                group.addTask {
                    try await Self.receiveBytesWithoutTimeout(over: connection)
                }
                group.addTask {
                    try await Task.sleep(for: ShadowClientRealtimeSessionDefaults.rtspReceiveTimeout)
                    throw ShadowClientRTSPInterleavedClientError.connectionFailed
                }

                guard let result = try await group.next() else {
                    group.cancelAll()
                    throw ShadowClientRTSPInterleavedClientError.connectionFailed
                }
                group.cancelAll()
                return result
            }

            guard !chunk.isEmpty else {
                throw ShadowClientRTSPInterleavedClientError.connectionClosed
            }
            encryptedReadBuffer.append(chunk)
        }
    }

    private func parseEncryptedRTSPMessageIfAvailable() throws -> Data? {
        guard let rtspEncryptionCodec else {
            return nil
        }

        let headerLength = ShadowClientRTSPEncryptionCodec.headerLength
        guard encryptedReadBuffer.count >= headerLength else {
            return nil
        }

        let typeAndLength = encryptedReadBuffer.readUInt32BE(at: 0)
        guard (typeAndLength & ShadowClientRTSPEncryptionCodec.encryptedMessageTypeBit) != 0 else {
            throw ShadowClientRTSPInterleavedClientError.invalidResponse
        }

        let ciphertextLength = Int(typeAndLength & ~ShadowClientRTSPEncryptionCodec.encryptedMessageTypeBit)
        let messageLength = headerLength + ciphertextLength
        guard encryptedReadBuffer.count >= messageLength else {
            return nil
        }

        let sequence = encryptedReadBuffer.readUInt32BE(at: 4)
        let tag = Data(encryptedReadBuffer[8..<headerLength])
        let ciphertext = Data(encryptedReadBuffer[headerLength..<messageLength])
        encryptedReadBuffer.removeSubrange(0..<messageLength)

        return try rtspEncryptionCodec.decryptHostRTSPMessage(
            sequence: sequence,
            tag: tag,
            ciphertext: ciphertext
        )
    }

    private static func receiveBytesWithoutTimeout(
        over connection: NWConnection
    ) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(
                minimumIncompleteLength: ShadowClientRealtimeSessionDefaults.minimumTransportReadLength,
                maximumLength: ShadowClientRealtimeSessionDefaults.maximumTransportReadLength
            ) { content, _, isComplete, error in
                // Lumen can close/reset a RTSP TCP socket right after writing a valid
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
