import Foundation
import Network
import Testing
@testable import ShadowClientFeatureHome

@Test("RTSP SDP parser extracts H264 video track and parameter sets")
func rtspSdpParserExtractsH264Track() throws {
    let sdp = """
    v=0
    o=- 0 0 IN IP4 127.0.0.1
    s=No Name
    t=0 0
    a=control:*
    m=video 0 RTP/AVP 96
    a=rtpmap:96 H264/90000
    a=fmtp:96 packetization-mode=1;sprop-parameter-sets=Z0IAH5WoFAFuQA==,aM4G4g==
    a=control:streamid=0
    """

    let track = try ShadowClientRTSPSessionDescriptionParser.parseVideoTrack(
        sdp: sdp,
        contentBase: "rtsp://stream-host.example.invalid:48010/",
        fallbackSessionURL: "rtsp://stream-host.example.invalid:48010"
    )

    #expect(track.codec == .h264)
    #expect(track.rtpPayloadType == 96)
    #expect(track.controlURL == "rtsp://stream-host.example.invalid:48010/streamid=0")
    #expect(track.parameterSets.count == 2)
    #expect(track.parameterSets[0].count > 4)
}

@Test("RTSP SDP parser infers payload type from rtpmap when media line omits payload")
func rtspSdpParserInfersPayloadTypeFromRTPMap() throws {
    let sdp = """
    v=0
    o=- 0 0 IN IP4 127.0.0.1
    s=No Name
    t=0 0
    a=control:*
    m=video 0 RTP/AVP
    a=rtpmap:97 H264/90000
    a=fmtp:97 packetization-mode=1;sprop-parameter-sets=Z0IAH5WoFAFuQA==,aM4G4g==
    a=control:streamid=video
    """

    let track = try ShadowClientRTSPSessionDescriptionParser.parseVideoTrack(
        sdp: sdp,
        contentBase: "rtsp://example-pc.local:48010/",
        fallbackSessionURL: "rtsp://example-pc.local:48010"
    )

    #expect(track.rtpPayloadType == 97)
    #expect(track.codec == .h264)
}

@Test("RTSP SDP parser recognizes AV1 rtpmap")
func rtspSdpParserExtractsAV1Track() throws {
    let sdp = """
    v=0
    o=- 0 0 IN IP4 127.0.0.1
    s=No Name
    t=0 0
    a=control:*
    m=video 0 RTP/AVP 98
    a=rtpmap:98 AV1/90000
    a=fmtp:98 profile=0;level-idx=8;tier=0
    a=control:streamid=video
    """

    let track = try ShadowClientRTSPSessionDescriptionParser.parseVideoTrack(
        sdp: sdp,
        contentBase: "rtsp://example-pc.local:48010/",
        fallbackSessionURL: "rtsp://example-pc.local:48010"
    )

    #expect(track.rtpPayloadType == 98)
    #expect(track.codec == .av1)
    #expect(track.parameterSets.isEmpty)
}

@Test("RTSP SDP parser infers video track when Sunshine-style DESCRIBE omits media section")
func rtspSdpParserHandlesDescribeWithoutMediaSection() throws {
    let sdp = """
    a=x-ss-general.featureFlags:3
    a=x-ss-general.encryptionSupported:5
    a=x-ss-general.encryptionRequested:1
    a=x-nv-video[0].refPicInvalidation:1
    sprop-parameter-sets=AAAAAU
    a=rtpmap:98 AV1/90000
    a=fmtp:97 surround-params=21101
    """

    let track = try ShadowClientRTSPSessionDescriptionParser.parseVideoTrack(
        sdp: sdp,
        contentBase: "rtsp://example-pc.local:48010/",
        fallbackSessionURL: "rtsp://example-pc.local:48010"
    )

    #expect(track.rtpPayloadType == 98)
    #expect(track.codec == .av1)
    #expect(track.parameterSets.count == 1)
    #expect(track.parameterSets[0] == Data([0x00, 0x00, 0x00, 0x01]))
}

@Test("RTSP SDP parser keeps non-dynamic video payload types")
func rtspSdpParserKeepsNonDynamicPayloadType() throws {
    let sdp = """
    v=0
    o=- 0 0 IN IP4 127.0.0.1
    s=No Name
    t=0 0
    c=IN IP4 127.0.0.1
    m=video 0 RTP/AVP 0
    a=rtpmap:0 H264/90000
    a=fmtp:0 packetization-mode=1;sprop-parameter-sets=Z0IAH5WoFAFuQA==,aM4G4g==
    a=control:streamid=video
    """

    let track = try ShadowClientRTSPSessionDescriptionParser.parseVideoTrack(
        sdp: sdp,
        contentBase: nil,
        fallbackSessionURL: "rtsp://example.com/stream"
    )

    #expect(track.codec == .h264)
    #expect(track.rtpPayloadType == 0)
    #expect(track.candidateRTPPayloadTypes.contains(0))
}

@Test("RTSP SDP parser extracts Opus audio track metadata")
func rtspSdpParserExtractsOpusAudioTrack() {
    let sdp = """
    v=0
    o=- 0 0 IN IP4 127.0.0.1
    s=No Name
    t=0 0
    m=audio 0 RTP/AVP 97
    a=rtpmap:97 opus/48000/2
    a=fmtp:97 sprop-stereo=1;maxplaybackrate=48000
    a=control:audio/0/0
    """

    let track = ShadowClientRTSPSessionDescriptionParser.parseAudioTrack(
        sdp: sdp,
        contentBase: "rtsp://example-pc.local:48010/",
        fallbackSessionURL: "rtsp://example-pc.local:48010/"
    )

    #expect(track != nil)
    #expect(track?.codec == .opus)
    #expect(track?.rtpPayloadType == 97)
    #expect(track?.sampleRate == 48_000)
    #expect(track?.channelCount == 2)
    #expect(track?.controlURL == "rtsp://example-pc.local:48010/audio/0/0")
}

@Test("RTSP SDP parser infers Opus for Sunshine PT97 surround params without rtpmap")
func rtspSdpParserInfersSunshineOpusWithoutRtpmap() {
    let sdp = """
    v=0
    o=- 0 0 IN IP4 127.0.0.1
    s=No Name
    t=0 0
    m=audio 0 RTP/AVP 97
    a=fmtp:97 surround-params=21101
    a=control:streamid=audio
    """

    let track = ShadowClientRTSPSessionDescriptionParser.parseAudioTrack(
        sdp: sdp,
        contentBase: "rtsp://example-pc.local:48010/",
        fallbackSessionURL: "rtsp://example-pc.local:48010/"
    )

    #expect(track != nil)
    #expect(track?.codec == .opus)
    #expect(track?.rtpPayloadType == 97)
    #expect(track?.sampleRate == 48_000)
    #expect(track?.channelCount == 2)
}

@Test("RTSP SDP parser infers 5.1 channels from Sunshine surround params")
func rtspSdpParserInfersSurroundChannelCountFromSurroundParams() {
    let sdp = """
    v=0
    o=- 0 0 IN IP4 127.0.0.1
    s=No Name
    t=0 0
    m=audio 0 RTP/AVP 97
    a=fmtp:97 surround-params=642012453
    a=control:streamid=audio
    """

    let track = ShadowClientRTSPSessionDescriptionParser.parseAudioTrack(
        sdp: sdp,
        contentBase: "rtsp://example-pc.local:48010/",
        fallbackSessionURL: "rtsp://example-pc.local:48010/"
    )

    #expect(track != nil)
    #expect(track?.codec == .opus)
    #expect(track?.channelCount == 6)
}

@Test("RTSP SDP parser keeps default channel count when surround params are malformed")
func rtspSdpParserIgnoresMalformedSurroundParams() {
    let sdp = """
    v=0
    o=- 0 0 IN IP4 127.0.0.1
    s=No Name
    t=0 0
    m=audio 0 RTP/AVP 97
    a=fmtp:97 surround-params=invalid
    a=control:streamid=audio
    """

    let track = ShadowClientRTSPSessionDescriptionParser.parseAudioTrack(
        sdp: sdp,
        contentBase: "rtsp://example-pc.local:48010/",
        fallbackSessionURL: "rtsp://example-pc.local:48010/"
    )

    #expect(track != nil)
    #expect(track?.codec == .opus)
    #expect(track?.channelCount == 2)
}

@Test("RTSP SDP parser infers audio track from Sunshine global fmtp lines without m=audio")
func rtspSdpParserInfersAudioTrackWithoutAudioMediaSection() {
    let sdp = """
    a=x-ss-general.featureFlags:3
    a=x-ss-general.encryptionSupported:5
    a=x-ss-general.encryptionRequested:1
    a=rtpmap:98 AV1/90000
    a=fmtp:97 surround-params=21101
    a=fmtp:97 surround-params=642012453
    a=fmtp:97 surround-params=88001234567
    a=control:streamid=audio/0/0
    """

    let track = ShadowClientRTSPSessionDescriptionParser.parseAudioTrack(
        sdp: sdp,
        contentBase: "rtsp://example-pc.local:48010/",
        fallbackSessionURL: "rtsp://example-pc.local:48010/"
    )

    #expect(track != nil)
    #expect(track?.codec == .opus)
    #expect(track?.rtpPayloadType == 97)
    #expect(track?.sampleRate == 48_000)
    #expect(track?.channelCount == 8)
}

@Test("RTSP SDP parser prefers stereo surround params when stereo is requested")
func rtspSdpParserPrefersStereoSurroundParamsForStereoRequest() {
    let sdp = """
    a=fmtp:97 surround-params=21101
    a=fmtp:97 surround-params=642012453
    a=fmtp:97 surround-params=88001234567
    """

    let track = ShadowClientRTSPSessionDescriptionParser.parseAudioTrack(
        sdp: sdp,
        contentBase: "rtsp://example-pc.local:48010/",
        fallbackSessionURL: "rtsp://example-pc.local:48010/",
        preferredOpusChannelCount: 2
    )

    #expect(track != nil)
    #expect(track?.codec == .opus)
    #expect(track?.channelCount == 2)
}

@Test("RTSP SDP parser prefers 5.1 surround params when surround is requested")
func rtspSdpParserPrefersSurroundParamsForSurroundRequest() {
    let sdp = """
    a=fmtp:97 surround-params=21101
    a=fmtp:97 surround-params=642012453
    a=fmtp:97 surround-params=88001234567
    """

    let track = ShadowClientRTSPSessionDescriptionParser.parseAudioTrack(
        sdp: sdp,
        contentBase: "rtsp://example-pc.local:48010/",
        fallbackSessionURL: "rtsp://example-pc.local:48010/",
        preferredOpusChannelCount: 6
    )

    #expect(track != nil)
    #expect(track?.codec == .opus)
    #expect(track?.channelCount == 6)
}

@Test("RTSP SDP parser extracts AV1 codec configuration from fmtp config attribute")
func rtspSdpParserExtractsAV1CodecConfigurationFromFmtpConfig() throws {
    let sdp = """
    v=0
    o=- 0 0 IN IP4 127.0.0.1
    s=No Name
    t=0 0
    a=control:*
    m=video 0 RTP/AVP 98
    a=rtpmap:98 AV1/90000
    a=fmtp:98 config=gQJABQ==
    a=control:streamid=video
    """

    let track = try ShadowClientRTSPSessionDescriptionParser.parseVideoTrack(
        sdp: sdp,
        contentBase: "rtsp://example-pc.local:48010/",
        fallbackSessionURL: "rtsp://example-pc.local:48010"
    )

    #expect(track.codec == .av1)
    #expect(track.parameterSets.count == 1)
    #expect(track.parameterSets[0] == Data([0x81, 0x02, 0x40, 0x05]))
}

@Test("RTSP SDP parser falls back to Sunshine codec hint when m=video payload list is empty")
func rtspSdpParserHandlesSunshineVideoMediaWithoutPayloadType() throws {
    let sdp = """
    v=0
    o=- 0 0 IN IP4 127.0.0.1
    s=No Name
    t=0 0
    m=video 47998
    a=control:streamid=video
    a=x-nv-vqos[0].bitStreamFormat:2
    """

    let track = try ShadowClientRTSPSessionDescriptionParser.parseVideoTrack(
        sdp: sdp,
        contentBase: "rtsp://example-pc.local:48010/",
        fallbackSessionURL: "rtsp://example-pc.local:48010"
    )

    #expect(track.codec == .av1)
    #expect(track.rtpPayloadType == ShadowClientRTSPProtocolProfile.fallbackVideoPayloadType)
    #expect(track.controlURL == "rtsp://example-pc.local:48010/streamid=video")
}

@Test("RTSP fallback payload inference prefers codec-specific RTP map")
func rtspFallbackPayloadInferencePrefersCodecMatch() {
    let sdp = """
    v=0
    o=- 0 0 IN IP4 127.0.0.1
    s=No Name
    t=0 0
    a=rtpmap:96 H264/90000
    a=rtpmap:98 AV1/90000
    a=fmtp:98 profile=0;level-idx=8;tier=0
    """

    let payloadType = ShadowClientRTSPSessionDescriptionParser.inferFallbackVideoPayloadType(
        sdp: sdp,
        preferredCodec: .av1
    )

    #expect(payloadType == 98)
}

@Test("RTSP fallback payload inference returns nil without SDP payload hints")
func rtspFallbackPayloadInferenceReturnsNilWithoutHints() {
    let sdp = """
    v=0
    o=- 0 0 IN IP4 127.0.0.1
    s=No Name
    t=0 0
    """

    let payloadType = ShadowClientRTSPSessionDescriptionParser.inferFallbackVideoPayloadType(
        sdp: sdp,
        preferredCodec: .av1
    )

    #expect(payloadType == nil)
}

@Test("RTSP transport parser extracts server port")
func rtspTransportParserExtractsServerPort() {
    let header = "unicast;server_port=47998-47999;source=192.168.0.12"
    let port = ShadowClientRTSPTransportHeaderParser.parseServerPort(from: header)
    #expect(port == 47_998)
}

@Test("RTSP host header includes explicit URL port")
func rtspHostHeaderIncludesExplicitPort() {
    let header = ShadowClientRTSPProtocolProfile.hostHeaderValue(
        forRTSPURLString: "rtsp://stream-host.example.invalid:48010/streamid=video"
    )
    #expect(header == "stream-host.example.invalid:48010")
}

@Test("RTSP host header brackets IPv6 literal when URL has explicit port")
func rtspHostHeaderBracketsIPv6Literal() {
    let header = ShadowClientRTSPProtocolProfile.hostHeaderValue(
        forRTSPURLString: "rtsp://[2001:db8::1]:48010/streamid=video"
    )
    #expect(header == "[2001:db8::1]:48010")
}

@Test("RTSP transport parser returns nil when server port is missing")
func rtspTransportParserHandlesMissingServerPort() {
    let header = "RTP/AVP/TCP;unicast;interleaved=0-1"
    let port = ShadowClientRTSPTransportHeaderParser.parseServerPort(from: header)
    #expect(port == nil)
}

@Test("RTP payload parser keeps Moonlight extension payload bytes after fixed extension preamble")
func rtpPayloadParserKeepsMoonlightExtensionPayloadBytes() throws {
    let packet = Data([
        0x90, 0x00, 0x00, 0x01, // v=2, X=1, PT=0, sequence=1
        0x00, 0x00, 0x00, 0x02, // timestamp
        0x00, 0x00, 0x00, 0x03, // SSRC
        0xBE, 0xDE, 0x00, 0x01, // extension header (1 word)
        0x11, 0x22, 0x33, 0x44, // extension payload (4 bytes)
        0xAA, 0xBB, 0xCC, // RTP payload
    ])

    let parsed = try ShadowClientRTPPacketPayloadParser.parse(packet)
    #expect(parsed.sequenceNumber == 1)
    #expect(parsed.payloadType == 0)
    #expect(parsed.marker == false)
    #expect(parsed.payload == Data([0x11, 0x22, 0x33, 0x44, 0xAA, 0xBB, 0xCC]))
}

@Test("RTP payload parser accepts non-zero extension length without requiring RFC3550 extension words")
func rtpPayloadParserAcceptsMoonlightExtensionLengthField() throws {
    let packet = Data([
        0x90, 0x00, 0x00, 0x01,
        0x00, 0x00, 0x00, 0x02,
        0x00, 0x00, 0x00, 0x03,
        0xBE, 0xDE, 0x00, 0x02, // non-zero extension length field
        0xAA, 0xBB, 0xCC, 0xDD,
    ])

    let parsed = try ShadowClientRTPPacketPayloadParser.parse(packet)
    #expect(parsed.sequenceNumber == 1)
    #expect(parsed.payload == Data([0xAA, 0xBB, 0xCC, 0xDD]))
}

@Test("RTP payload parser supports sliced Data input with non-zero start index")
func rtpPayloadParserSupportsSlicedDataInput() throws {
    let packet = Data([
        0x90, 0x00, 0x00, 0x01, // v=2, X=1, PT=0, sequence=1
        0x00, 0x00, 0x00, 0x02, // timestamp
        0x00, 0x00, 0x00, 0x03, // SSRC
        0xBE, 0xDE, 0x00, 0x01, // extension header (1 word)
        0xAA, 0xBB, 0xCC, 0xDD, // extension payload (4 bytes)
    ])
    let wrapped = Data([0xFE, 0xED]) + packet
    let slicedPacket = wrapped[2..<wrapped.count]

    let parsed = try ShadowClientRTPPacketPayloadParser.parse(slicedPacket)

    #expect(parsed.sequenceNumber == 1)
    #expect(parsed.payload == Data([0xAA, 0xBB, 0xCC, 0xDD]))
    #expect(parsed.payload.startIndex == 0)
}

@Test("RTSP video payload adoption rejects audio payload type and control payload type")
func rtspVideoPayloadAdoptionRejectsAudioAndControlPayloadTypes() {
    let audioTrack = ShadowClientRTSPAudioTrackDescriptor(
        codec: .opus,
        rtpPayloadType: 97,
        sampleRate: 48_000,
        channelCount: 2,
        controlURL: nil,
        formatParameters: [:]
    )

    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldAdoptVideoPayloadType(
            observedPayloadType: 97,
            currentPayloadType: 98,
            audioPayloadType: audioTrack.rtpPayloadType,
            videoPayloadCandidates: Set([98])
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldAdoptVideoPayloadType(
            observedPayloadType: ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType,
            currentPayloadType: 98,
            audioPayloadType: audioTrack.rtpPayloadType,
            videoPayloadCandidates: Set([98])
        )
    )
}

@Test("RTSP video payload adoption accepts static payload type on early mismatch")
func rtspVideoPayloadAdoptionAcceptsStaticPayloadTypeOnEarlyMismatch() {
    let audioTrack = ShadowClientRTSPAudioTrackDescriptor(
        codec: .opus,
        rtpPayloadType: 97,
        sampleRate: 48_000,
        channelCount: 2,
        controlURL: nil,
        formatParameters: [:]
    )

    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldAdoptVideoPayloadType(
            observedPayloadType: 0,
            currentPayloadType: 98,
            audioPayloadType: audioTrack.rtpPayloadType,
            videoPayloadCandidates: Set([98])
        )
    )
}

@Test("RTSP video payload adoption accepts non-candidate dynamic payload on early mismatch")
func rtspVideoPayloadAdoptionAcceptsNonCandidateDynamicPayloadOnEarlyMismatch() {
    let audioTrack = ShadowClientRTSPAudioTrackDescriptor(
        codec: .opus,
        rtpPayloadType: 97,
        sampleRate: 48_000,
        channelCount: 2,
        controlURL: nil,
        formatParameters: [:]
    )

    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldAdoptVideoPayloadType(
            observedPayloadType: 99,
            currentPayloadType: 98,
            audioPayloadType: audioTrack.rtpPayloadType,
            videoPayloadCandidates: Set([98])
        )
    )
}

@Test("RTSP video payload adaptation observation threshold switches immediately before first frame lock")
func rtspVideoPayloadAdaptationObservationThresholdSwitchesImmediately() {
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.videoPayloadTypeObservationThreshold(
            observedPayloadType: 98,
            videoPayloadCandidates: Set([98])
        ) == 1
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.videoPayloadTypeObservationThreshold(
            observedPayloadType: 99,
            videoPayloadCandidates: Set([98])
        ) == 1
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.videoPayloadTypeObservationThreshold(
            observedPayloadType: 0,
            videoPayloadCandidates: Set([98])
        ) == 1
    )
}

@Test("Video RTP reorder buffer reorders nearby out-of-order packets")
func videoRtpReorderBufferReordersNearbyPackets() {
    var reorderBuffer = ShadowClientRTPVideoReorderBuffer(
        targetDepth: 3,
        maximumDepth: 16
    )
    let packet100 = makeVideoRTPPacket(sequenceNumber: 100, payloadByte: 0x10)
    let packet102 = makeVideoRTPPacket(sequenceNumber: 102, payloadByte: 0x12)
    let packet101 = makeVideoRTPPacket(sequenceNumber: 101, payloadByte: 0x11)

    let firstReady = reorderBuffer.enqueue(packet100)
    #expect(firstReady.map(\.sequenceNumber) == [100])

    let secondReady = reorderBuffer.enqueue(packet102)
    #expect(secondReady.isEmpty)

    let thirdReady = reorderBuffer.enqueue(packet101)
    #expect(thirdReady.map(\.sequenceNumber) == [101, 102])
}

@Test("Video RTP reorder buffer drops buffered gap run instead of force-skipping sequence")
func videoRtpReorderBufferDropsGapRunAtDepthThreshold() {
    var reorderBuffer = ShadowClientRTPVideoReorderBuffer(
        targetDepth: 3,
        maximumDepth: 16
    )
    let packet200 = makeVideoRTPPacket(sequenceNumber: 200, payloadByte: 0x20)
    let packet202 = makeVideoRTPPacket(sequenceNumber: 202, payloadByte: 0x22)
    let packet203 = makeVideoRTPPacket(sequenceNumber: 203, payloadByte: 0x23)
    let packet204 = makeVideoRTPPacket(sequenceNumber: 204, payloadByte: 0x24)
    let packet201 = makeVideoRTPPacket(sequenceNumber: 201, payloadByte: 0x21)

    let firstReady = reorderBuffer.enqueue(packet200)
    #expect(firstReady.map(\.sequenceNumber) == [200])

    let secondReady = reorderBuffer.enqueue(packet202)
    #expect(secondReady.isEmpty)

    let thirdReady = reorderBuffer.enqueue(packet203)
    #expect(thirdReady.isEmpty)

    let fourthReady = reorderBuffer.enqueue(packet204)
    #expect(fourthReady.isEmpty)

    let recoveryReady = reorderBuffer.enqueue(packet201)
    #expect(recoveryReady.map(\.sequenceNumber) == [201])
}

@Test("Sunshine ping payload parser accepts 16-byte ASCII payload")
func sunshinePingPayloadParserAcceptsAsciiPayload() {
    let payload = ShadowClientRTSPTransportHeaderParser.parseSunshinePingPayload(from: "3727B184C4E23026")
    #expect(payload == Data("3727B184C4E23026".utf8))
}

@Test("Sunshine ping packet codec emits strict v2 packet when negotiated payload exists")
func sunshinePingPacketCodecEmitsStrictV2Packet() {
    let negotiatedPayload = Data("A1B2C3D4E5F60708".utf8)
    let packets = ShadowClientSunshinePingPacketCodec.makePingPackets(
        sequence: 7,
        negotiatedPayload: negotiatedPayload
    )

    #expect(packets.count == 1)
    #expect(packets[0].count == 20)
    #expect(Data(packets[0].prefix(16)) == negotiatedPayload)
    #expect(Data(packets[0].suffix(4)) == Data([0x00, 0x00, 0x00, 0x07]))
}

@Test("Sunshine ping packet codec emits legacy ASCII ping when negotiated payload is unavailable")
func sunshinePingPacketCodecEmitsLegacyAsciiFallback() {
    let packets = ShadowClientSunshinePingPacketCodec.makePingPackets(
        sequence: 42,
        negotiatedPayload: nil
    )

    #expect(packets.count == 1)
    #expect(packets[0] == Data("PING".utf8))
}

@Test("H264 depacketizer emits access unit for single NAL packet on marker")
func h264DepacketizerSingleNal() {
    var depacketizer = ShadowClientH264RTPDepacketizer()
    let nal = Data([0x65, 0x88, 0x84, 0x21]) // IDR slice

    let output = depacketizer.ingest(payload: nal, marker: true)

    #expect(output != nil)
    #expect(output?.parameterSets.count == 0)
    #expect(output?.annexBAccessUnit.starts(with: Data([0x00, 0x00, 0x00, 0x01, 0x65])) == true)
}

@Test("H264 depacketizer rebuilds FU-A fragments into one access unit")
func h264DepacketizerFuA() {
    var depacketizer = ShadowClientH264RTPDepacketizer()

    // FU indicator(type 28, nal_ref_idc=3) + FU header(start, nal_type=5)
    let first = Data([0x7C, 0x85, 0x11, 0x22, 0x33])
    // Middle
    let middle = Data([0x7C, 0x05, 0x44, 0x55])
    // End
    let end = Data([0x7C, 0x45, 0x66, 0x77])

    #expect(depacketizer.ingest(payload: first, marker: false) == nil)
    #expect(depacketizer.ingest(payload: middle, marker: false) == nil)
    let output = depacketizer.ingest(payload: end, marker: true)

    #expect(output != nil)
    #expect(output?.annexBAccessUnit.starts(with: Data([0x00, 0x00, 0x00, 0x01, 0x65])) == true)
    #expect(output?.annexBAccessUnit.count == 4 + 1 + 7)
}

@Test("H265 depacketizer splits AP payload into individual NAL units")
func h265DepacketizerAggregationPacket() {
    var depacketizer = ShadowClientH265RTPDepacketizer()
    let firstNAL = Data([0x42, 0x01, 0xAA])
    let secondNAL = Data([0x44, 0x01, 0xBB, 0xCC])

    var packet = Data([
        0x60, 0x01, // nal_type=48 (AP)
        0x00, 0x03, // first NAL length
    ])
    packet.append(firstNAL)
    packet.append(contentsOf: [
        0x00, 0x04, // second NAL length
    ])
    packet.append(secondNAL)

    let output = depacketizer.ingest(payload: packet, marker: true)

    var expected = Data([0x00, 0x00, 0x00, 0x01])
    expected.append(firstNAL)
    expected.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
    expected.append(secondNAL)
    #expect(output == expected)
}

@Test("AV1 depacketizer reassembles SOF/EOF packets and truncates EOF payload using lastPayloadLength")
func av1DepacketizerReassemblesSofEofPacketsUsingLastPayloadLength() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let frameIndex: UInt32 = 17

    let sofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 120,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0xAA, 0xBB],
        includeFrameHeaderWithLastPayloadLength: 3
    )
    let eofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 121,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0xCC, 0xDD, 0xEE, 0x00, 0x00]
    )

    #expect(depacketizer.ingest(payload: sofPacket, marker: false) == nil)
    let frame = depacketizer.ingest(payload: eofPacket, marker: true)

    #expect(frame == Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE]))
}

@Test("AV1 depacketizer publishes completed-frame metadata for sync gate diagnostics")
func av1DepacketizerPublishesCompletedFrameMetadata() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let framePayload = Data([0x41, 0x42, 0x43])
    let packet = makeSyntheticNVVideoPacket(
        streamPacketIndex: 190,
        frameIndex: 52,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: Array(framePayload),
        includeFrameHeaderWithLastPayloadLength: moonlightFrameHeaderSize + UInt16(framePayload.count),
        frameHeaderFrameType: 2
    )

    let frame = depacketizer.ingest(payload: packet, marker: true)
    let metadata = depacketizer.consumeLastCompletedFrameMetadata()

    #expect(frame == framePayload)
    #expect(metadata?.frameIndex == 52)
    #expect(metadata?.firstStreamPacketIndex == 190)
    #expect(metadata?.frameHeaderType == 0x01)
    #expect(metadata?.frameType == 2)
    #expect(metadata?.frameHeaderSize == Int(moonlightFrameHeaderSize))
    #expect(metadata?.lastPacketPayloadLength == moonlightFrameHeaderSize + UInt16(framePayload.count))
    #expect(depacketizer.consumeLastCompletedFrameMetadata() == nil)
}

@Test("AV1 depacketizer publishes frame type 4 and 5 metadata for sync-gate recovery admission")
func av1DepacketizerPublishesFrameType4And5MetadataForSyncGate() {
    for frameType in [UInt8(4), UInt8(5)] {
        var depacketizer = ShadowClientAV1RTPDepacketizer()
        let framePayload = Data([0x51, 0x52, frameType])
        let packet = makeSyntheticNVVideoPacket(
            streamPacketIndex: 300 + UInt32(frameType),
            frameIndex: 70 + UInt32(frameType),
            flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
            payloadBytes: Array(framePayload),
            includeFrameHeaderWithLastPayloadLength: moonlightFrameHeaderSize + UInt16(framePayload.count),
            frameHeaderFrameType: frameType
        )

        let frame = depacketizer.ingest(payload: packet, marker: true)
        let metadata = depacketizer.consumeLastCompletedFrameMetadata()

        #expect(frame == framePayload)
        #expect(metadata?.frameType == frameType)
        #expect(
            ShadowClientRealtimeRTSPSessionRuntime.isAV1SyncFrameType(
                frameType,
                allowsReferenceInvalidatedFrame: false
            ) == false
        )
        #expect(
            ShadowClientRealtimeRTSPSessionRuntime.isAV1SyncFrameType(
                frameType,
                allowsReferenceInvalidatedFrame: true
            )
        )
    }
}

@Test("Moonlight NV depacketizer passthrough strategy ignores invalid lastPayloadLength for H264/H265")
func moonlightNvDepacketizerPassthroughIgnoresInvalidLastPayloadLength() {
    var depacketizer = ShadowClientMoonlightNVRTPDepacketizer(
        tailTruncationStrategy: .passthroughForAnnexBCodecs
    )
    let frameIndex: UInt32 = 29
    let firstPayload: [UInt8] = [0x00, 0x00, 0x00, 0x01, 0x67, 0x64, 0x00, 0x1F]
    let eofPayload: [UInt8] = [0x00, 0x00, 0x00, 0x01, 0x65, 0x88, 0x84, 0x21, 0x00, 0x00]

    let sofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 220,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: firstPayload,
        includeFrameHeaderWithLastPayloadLength: 4
    )
    let eofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 221,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: eofPayload
    )

    #expect(depacketizer.ingest(payload: sofPacket, marker: false) == nil)
    let frame = depacketizer.ingest(payload: eofPacket, marker: true)

    #expect(frame == Data(firstPayload + eofPayload))
}

@Test("Moonlight NV depacketizer trim strategy drops invalid lastPayloadLength frames")
func moonlightNvDepacketizerTrimDropsInvalidLastPayloadLength() {
    var depacketizer = ShadowClientMoonlightNVRTPDepacketizer(
        tailTruncationStrategy: .trimUsingLastPacketLength
    )
    let frameIndex: UInt32 = 30

    let sofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 240,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x11, 0x22],
        includeFrameHeaderWithLastPayloadLength: 4
    )
    let eofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 241,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0x33, 0x44, 0x55]
    )

    #expect(depacketizer.ingest(payload: sofPacket, marker: false) == nil)
    let frame = depacketizer.ingest(payload: eofPacket, marker: true)

    #expect(frame == nil)
}

@Test("AV1 depacketizer drops discontinuous streamPacketIndex sequence")
func av1DepacketizerDropsCorruptPacketSequence() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let frameIndex: UInt32 = 33

    let sofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 200,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x10, 0x11],
        includeFrameHeaderWithLastPayloadLength: 2
    )
    let corruptEofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 202,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0x22, 0x33]
    )

    #expect(depacketizer.ingest(payload: sofPacket, marker: false) == nil)
    let frame = depacketizer.ingest(payload: corruptEofPacket, marker: true)

    #expect(frame == nil)
}

@Test("AV1 depacketizer emits explicit corruption status for discontinuous packet sequence")
func av1DepacketizerReportsCorruptPacketSequenceStatus() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let frameIndex: UInt32 = 34

    let sofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 210,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x10, 0x11],
        includeFrameHeaderWithLastPayloadLength: 2
    )
    let corruptEofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 212,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0x22, 0x33]
    )

    let firstResult = depacketizer.ingestWithStatus(payload: sofPacket, marker: false)
    switch firstResult {
    case .noFrame:
        break
    default:
        Issue.record("Expected no frame for SOF packet")
    }

    let secondResult = depacketizer.ingestWithStatus(payload: corruptEofPacket, marker: true)
    switch secondResult {
    case .droppedCorruptFrame:
        break
    default:
        Issue.record("Expected droppedCorruptFrame for discontinuous stream packet sequence")
    }
}

@Test("AV1 depacketizer classifies forward frame gaps as corruption for recovery")
func av1DepacketizerClassifiesForwardFrameGapAsCorruption() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()

    let firstFramePayload = Data([0x10, 0x20])
    let firstFramePacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 300,
        frameIndex: 40,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: Array(firstFramePayload),
        includeFrameHeaderWithLastPayloadLength: moonlightFrameHeaderSize + UInt16(firstFramePayload.count)
    )

    let gapFramePayload = Data([0x30, 0x40])
    let gapFramePacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 400,
        frameIndex: 42,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: Array(gapFramePayload),
        includeFrameHeaderWithLastPayloadLength: moonlightFrameHeaderSize + UInt16(gapFramePayload.count)
    )

    let firstResult = depacketizer.ingestWithStatus(payload: firstFramePacket, marker: true)
    switch firstResult {
    case let .frame(frame):
        #expect(frame == firstFramePayload)
    default:
        Issue.record("Expected first frame to decode successfully")
    }

    let gapResult = depacketizer.ingestWithStatus(payload: gapFramePacket, marker: true)
    switch gapResult {
    case .droppedCorruptFrame:
        break
    default:
        Issue.record("Expected droppedCorruptFrame for forward frame gap")
    }
}

@Test("AV1 depacketizer supports single packet with SOF|EOF flags")
func av1DepacketizerSupportsSinglePacketSofEofFrame() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let framePayload = Data([0x44, 0x55, 0x66])
    let packet = makeSyntheticNVVideoPacket(
        streamPacketIndex: 501,
        frameIndex: 64,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: Array(framePayload),
        includeFrameHeaderWithLastPayloadLength: moonlightFrameHeaderSize + UInt16(framePayload.count)
    )

    let frame = depacketizer.ingest(payload: packet, marker: true)

    #expect(frame == framePayload)
}

@Test("AV1 depacketizer reset clears partial frame assembly after queue trim")
func av1DepacketizerResetClearsPartialFrameAssembly() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()

    let partialFrameSOF = makeSyntheticNVVideoPacket(
        streamPacketIndex: 600,
        frameIndex: 77,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x11, 0x22, 0x33],
        includeFrameHeaderWithLastPayloadLength: 2
    )
    let staleFrameEOF = makeSyntheticNVVideoPacket(
        streamPacketIndex: 601,
        frameIndex: 77,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0x44, 0x55]
    )

    #expect(depacketizer.ingest(payload: partialFrameSOF, marker: false) == nil)
    depacketizer.reset()
    #expect(depacketizer.ingest(payload: staleFrameEOF, marker: true) == nil)

    let cleanFramePayload = Data([0x99, 0xAA, 0xBB])
    let cleanFramePacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 602,
        frameIndex: 78,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: Array(cleanFramePayload),
        includeFrameHeaderWithLastPayloadLength: moonlightFrameHeaderSize + UInt16(cleanFramePayload.count)
    )

    #expect(depacketizer.ingest(payload: cleanFramePacket, marker: true) == cleanFramePayload)
}

@Test("AV1 depacketizer handles sliced packet buffers without index trap")
func av1DepacketizerHandlesSlicedPacketBuffers() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let frameIndex: UInt32 = 91
    let sofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 700,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0xAA, 0xBB],
        includeFrameHeaderWithLastPayloadLength: 3
    )
    let eofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 701,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0xCC, 0xDD, 0xEE, 0x00, 0x00]
    )

    let wrappedSOF = Data([0x11, 0x22]) + sofPacket
    let wrappedEOF = Data([0x33, 0x44]) + eofPacket
    let slicedSOF = wrappedSOF[2..<wrappedSOF.count]
    let slicedEOF = wrappedEOF[2..<wrappedEOF.count]

    #expect(depacketizer.ingest(payload: slicedSOF, marker: false) == nil)
    let frame = depacketizer.ingest(payload: slicedEOF, marker: true)

    #expect(frame == Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE]))
}

@Test("AV1 depacketizer ignores packets without picture-data flag")
func av1DepacketizerSkipsPacketsWithoutPictureDataFlag() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let packet = makeSyntheticNVVideoPacket(
        streamPacketIndex: 502,
        frameIndex: 65,
        flags: nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: [0xAB],
        includeFrameHeaderWithLastPayloadLength: moonlightFrameHeaderSize + 1
    )

    let result = depacketizer.ingestWithStatus(payload: packet, marker: true)
    switch result {
    case .droppedCorruptFrame:
        break
    default:
        Issue.record("Expected droppedCorruptFrame when packet has no picture data")
    }
}

@Test("AV1 depacketizer ignores FEC parity shards from Sunshine payload stream")
func av1DepacketizerIgnoresFECParityShards() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let frameIndex: UInt32 = 66

    let sofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 510,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0xAA, 0xBB],
        includeFrameHeaderWithLastPayloadLength: moonlightFrameHeaderSize + 3
    )
    let parityPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 511,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData,
        payloadBytes: [0x99, 0x88, 0x77],
        fecInfo: (1 << 22) | (1 << 12)
    )
    let eofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 512,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0xCC, 0xDD, 0xEE]
    )

    #expect(depacketizer.ingest(payload: sofPacket, marker: false) == nil)
    #expect(depacketizer.ingest(payload: parityPacket, marker: false) == nil)
    let frame = depacketizer.ingest(payload: eofPacket, marker: true)

    #expect(frame == Data([0xAA, 0xBB, 0xCC, 0xDD, 0xEE]))
}

@Test("AV1 depacketizer ignores stale parity shards without rewinding continuity watermark")
func av1DepacketizerDoesNotRewindContinuityOnStaleParityShard() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let frameIndex: UInt32 = 67

    let sofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 600,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x01, 0x02],
        includeFrameHeaderWithLastPayloadLength: moonlightFrameHeaderSize + 3
    )
    let parityPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 601,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData,
        payloadBytes: [0x91, 0x92, 0x93],
        fecInfo: (1 << 22) | (1 << 12)
    )
    let staleParityPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 599,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData,
        payloadBytes: [0x81, 0x82, 0x83],
        fecInfo: (1 << 22) | (1 << 12)
    )
    let eofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 602,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0x03, 0x04, 0x05]
    )

    #expect(depacketizer.ingest(payload: sofPacket, marker: false) == nil)
    #expect(depacketizer.ingest(payload: parityPacket, marker: false) == nil)
    #expect(depacketizer.ingest(payload: staleParityPacket, marker: false) == nil)
    let frame = depacketizer.ingest(payload: eofPacket, marker: true)

    #expect(frame == Data([0x01, 0x02, 0x03, 0x04, 0x05]))
}

@Test("AV1 depacketizer accepts late data shard when parity shard arrives early")
func av1DepacketizerAcceptsLateDataAfterEarlyParityArrival() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let frameIndex: UInt32 = 68
    let dataShardCount: UInt32 = 2

    let sofPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 700,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x10, 0x11],
        includeFrameHeaderWithLastPayloadLength: moonlightFrameHeaderSize + 2,
        fecInfo: (dataShardCount << 22) | (0 << 12)
    )
    let earlyParityPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 702,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData,
        payloadBytes: [0x99, 0x98],
        fecInfo: (dataShardCount << 22) | (2 << 12)
    )
    let lateEofDataPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 701,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0x12, 0x13],
        fecInfo: (dataShardCount << 22) | (1 << 12)
    )

    #expect(depacketizer.ingest(payload: sofPacket, marker: false) == nil)
    #expect(depacketizer.ingest(payload: earlyParityPacket, marker: false) == nil)
    let frame = depacketizer.ingest(payload: lateEofDataPacket, marker: true)

    #expect(frame == Data([0x10, 0x11, 0x12, 0x13]))
}

@Test("AV1 depacketizer rejects block-boundary streamPacketIndex jump without SOF")
func av1DepacketizerRejectsBlockBoundaryJumpWithoutSOF() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    let frameIndex: UInt32 = 69
    let dataShardCount: UInt32 = 2

    let firstDataPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 800,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x21, 0x22],
        includeFrameHeaderWithLastPayloadLength: moonlightFrameHeaderSize + 2,
        fecInfo: (dataShardCount << 22) | (0 << 12)
    )
    let secondDataPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 801,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData,
        payloadBytes: [0x23, 0x24],
        fecInfo: (dataShardCount << 22) | (1 << 12)
    )
    let parityPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 802,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData,
        payloadBytes: [0xAA, 0xBB],
        fecInfo: (dataShardCount << 22) | (2 << 12)
    )
    let nextBlockDataPacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 803,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0x25, 0x26],
        fecInfo: (dataShardCount << 22) | (0 << 12)
    )
    let nextFramePacket = makeSyntheticNVVideoPacket(
        streamPacketIndex: 900,
        frameIndex: frameIndex + 1,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: [0x31, 0x32],
        includeFrameHeaderWithLastPayloadLength: moonlightFrameHeaderSize + 2
    )

    #expect(depacketizer.ingest(payload: firstDataPacket, marker: false) == nil)
    #expect(depacketizer.ingest(payload: secondDataPacket, marker: false) == nil)
    #expect(depacketizer.ingest(payload: parityPacket, marker: false) == nil)
    #expect(depacketizer.ingest(payload: nextBlockDataPacket, marker: true) == nil)

    // Depacketizer should recover on the next valid frame boundary.
    let recoveredFrame = depacketizer.ingest(payload: nextFramePacket, marker: true)
    #expect(recoveredFrame == Data([0x31, 0x32]))
}

@Test("AV1 video FEC reconstruction queue recovers one missing data shard and emits ordered packets")
func av1VideoFECReconstructionQueueRecoversSingleMissingDataShard() {
    var queue = ShadowClientRTPVideoFECReconstructionQueue()
    let frameIndex: UInt32 = 420
    let dataShards: UInt32 = 2
    let fecPercentage: UInt32 = 50 // 2 data shards -> 1 parity shard
    let baseSequenceNumber: UInt16 = 1_000
    let blockInfo = makeMultiFecBlocks(currentBlock: 0, lastBlock: 0)

    let missingDataPayload = makeSyntheticNVVideoPacket(
        streamPacketIndex: 2_000,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x41, 0x42, 0x43],
        fecInfo: (dataShards << 22) | (0 << 12) | (fecPercentage << 4),
        multiFecBlocks: blockInfo
    )
    let presentDataPayload = makeSyntheticNVVideoPacket(
        streamPacketIndex: 2_001,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0x00, 0x00, 0x00],
        fecInfo: (dataShards << 22) | (1 << 12) | (fecPercentage << 4),
        multiFecBlocks: blockInfo
    )
    let parityPayload = makeSyntheticNVVideoPacket(
        streamPacketIndex: 2_002,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData,
        payloadBytes: [0x41, 0x42, 0x43],
        fecInfo: (dataShards << 22) | (2 << 12) | (fecPercentage << 4),
        multiFecBlocks: blockInfo
    )

    let presentDataPacket = makeVideoRTPPacket(
        sequenceNumber: baseSequenceNumber &+ 1,
        marker: true,
        payloadType: 98,
        payload: presentDataPayload
    )
    let parityPacket = makeVideoRTPPacket(
        sequenceNumber: baseSequenceNumber &+ 2,
        marker: false,
        payloadType: 98,
        payload: parityPayload
    )

    let firstResult = queue.ingest(presentDataPacket)
    #expect(firstResult.orderedDataPackets.isEmpty)
    #expect(!firstResult.droppedUnrecoverableBlock)

    let secondResult = queue.ingest(parityPacket)
    #expect(!secondResult.droppedUnrecoverableBlock)
    #expect(secondResult.orderedDataPackets.count == 2)
    #expect(secondResult.orderedDataPackets.map(\.sequenceNumber) == [baseSequenceNumber, baseSequenceNumber &+ 1])
    #expect(secondResult.orderedDataPackets[1].payload == presentDataPayload)
    #expect((secondResult.orderedDataPackets[0].payload[8] & nvVideoPacketFlagSOF) != 0)
    #expect((secondResult.orderedDataPackets[0].payload[8] & nvVideoPacketFlagEOF) == 0)
    #expect(secondResult.orderedDataPackets[0].payload.count == missingDataPayload.count)
}

@Test("AV1 video FEC reconstruction queue marks unrecoverable block on transition and emits no packets")
func av1VideoFECReconstructionQueueMarksUnrecoverableTransitionBlockDrop() {
    var queue = ShadowClientRTPVideoFECReconstructionQueue()
    let frameIndex: UInt32 = 421
    let dataShards: UInt32 = 2
    let fecPercentage: UInt32 = 50 // 2 data shards -> 1 parity shard

    let firstBlockDataPayload = makeSyntheticNVVideoPacket(
        streamPacketIndex: 3_000,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x10, 0x11, 0x12],
        fecInfo: (dataShards << 22) | (0 << 12) | (fecPercentage << 4),
        multiFecBlocks: makeMultiFecBlocks(currentBlock: 0, lastBlock: 1)
    )
    let nextBlockDataPayload = makeSyntheticNVVideoPacket(
        streamPacketIndex: 3_002,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x20, 0x21, 0x22],
        fecInfo: (dataShards << 22) | (0 << 12) | (fecPercentage << 4),
        multiFecBlocks: makeMultiFecBlocks(currentBlock: 1, lastBlock: 1)
    )

    let firstBlockPacket = makeVideoRTPPacket(
        sequenceNumber: 1_500,
        marker: false,
        payloadType: 98,
        payload: firstBlockDataPayload
    )
    let nextBlockPacket = makeVideoRTPPacket(
        sequenceNumber: 1_502,
        marker: false,
        payloadType: 98,
        payload: nextBlockDataPayload
    )

    let firstResult = queue.ingest(firstBlockPacket)
    #expect(firstResult.orderedDataPackets.isEmpty)
    #expect(!firstResult.droppedUnrecoverableBlock)

    let transitionResult = queue.ingest(nextBlockPacket)
    #expect(transitionResult.orderedDataPackets.isEmpty)
    #expect(transitionResult.droppedUnrecoverableBlock)
}

@Test("AV1 video FEC reconstruction queue defers emission until final FEC block of frame")
func av1VideoFECReconstructionQueueDefersSubmissionUntilFinalBlock() {
    var queue = ShadowClientRTPVideoFECReconstructionQueue()
    let frameIndex: UInt32 = 700
    let dataShards: UInt32 = 1
    let fecInfo: UInt32 = (dataShards << 22) | (0 << 12) | (0 << 4)

    let block0Payload = makeSyntheticNVVideoPacket(
        streamPacketIndex: 4_000,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x01, 0x02],
        fecInfo: fecInfo,
        multiFecBlocks: makeMultiFecBlocks(currentBlock: 0, lastBlock: 1)
    )
    let block1Payload = makeSyntheticNVVideoPacket(
        streamPacketIndex: 4_001,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0x03, 0x04],
        fecInfo: fecInfo,
        multiFecBlocks: makeMultiFecBlocks(currentBlock: 1, lastBlock: 1)
    )

    let block0Packet = makeVideoRTPPacket(
        sequenceNumber: 2_000,
        marker: false,
        payloadType: 98,
        payload: block0Payload
    )
    let block1Packet = makeVideoRTPPacket(
        sequenceNumber: 2_001,
        marker: true,
        payloadType: 98,
        payload: block1Payload
    )

    let firstResult = queue.ingest(block0Packet)
    #expect(firstResult.orderedDataPackets.isEmpty)
    #expect(!firstResult.droppedUnrecoverableBlock)

    let secondResult = queue.ingest(block1Packet)
    #expect(!secondResult.droppedUnrecoverableBlock)
    #expect(secondResult.orderedDataPackets.count == 2)
    #expect(secondResult.orderedDataPackets.map(\.sequenceNumber) == [2_000, 2_001])
}

@Test("AV1 video FEC reconstruction queue drops frame when intermediate FEC block is missing")
func av1VideoFECReconstructionQueueDropsFrameOnMissingIntermediateBlock() {
    var queue = ShadowClientRTPVideoFECReconstructionQueue()
    let frameIndex: UInt32 = 701
    let dataShards: UInt32 = 1
    let fecInfo: UInt32 = (dataShards << 22) | (0 << 12) | (0 << 4)

    let block0Payload = makeSyntheticNVVideoPacket(
        streamPacketIndex: 4_100,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF,
        payloadBytes: [0x10],
        fecInfo: fecInfo,
        multiFecBlocks: makeMultiFecBlocks(currentBlock: 0, lastBlock: 2)
    )
    let block2Payload = makeSyntheticNVVideoPacket(
        streamPacketIndex: 4_102,
        frameIndex: frameIndex,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagEOF,
        payloadBytes: [0x30],
        fecInfo: fecInfo,
        multiFecBlocks: makeMultiFecBlocks(currentBlock: 2, lastBlock: 2)
    )

    let block0Packet = makeVideoRTPPacket(
        sequenceNumber: 2_100,
        marker: false,
        payloadType: 98,
        payload: block0Payload
    )
    let block2Packet = makeVideoRTPPacket(
        sequenceNumber: 2_102,
        marker: true,
        payloadType: 98,
        payload: block2Payload
    )

    let firstResult = queue.ingest(block0Packet)
    #expect(firstResult.orderedDataPackets.isEmpty)
    #expect(!firstResult.droppedUnrecoverableBlock)

    let secondResult = queue.ingest(block2Packet)
    #expect(secondResult.orderedDataPackets.isEmpty)
    #expect(secondResult.droppedUnrecoverableBlock)
}

@Test("AV1 video FEC reconstruction queue normalizes legacy non-multi-FEC block metadata")
func av1VideoFECReconstructionQueueNormalizesLegacyNonMultiFECMetadata() {
    var queue = ShadowClientRTPVideoFECReconstructionQueue(
        fixedShardPayloadSize: nil,
        multiFECCapable: false
    )
    let packet = makeVideoRTPPacket(
        sequenceNumber: 2_200,
        marker: true,
        payloadType: 98,
        payload: makeSyntheticNVVideoPacket(
            streamPacketIndex: 4_200,
            frameIndex: 702,
            flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
            payloadBytes: [0x7A, 0x7B],
            fecInfo: (1 << 22) | (0 << 12) | (0 << 4),
            multiFecBlocks: makeMultiFecBlocks(currentBlock: 2, lastBlock: 2)
        )
    )

    let result = queue.ingest(packet)
    #expect(!result.droppedUnrecoverableBlock)
    #expect(result.orderedDataPackets.count == 1)
}

@Test("AV1 video FEC reconstruction queue reconstructs missing shard using fixed payload size")
func av1VideoFECReconstructionQueueUsesFixedShardPayloadSizeForRecoveredShard() {
    var queue = ShadowClientRTPVideoFECReconstructionQueue(
        fixedShardPayloadSize: 40,
        multiFECCapable: true
    )

    let parityPacket = makeVideoRTPPacket(
        sequenceNumber: 2_301,
        marker: true,
        payloadType: 98,
        payload: makeSyntheticNVVideoPacket(
            streamPacketIndex: 4_301,
            frameIndex: 703,
            flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
            payloadBytes: [0xAA, 0xBB, 0xCC, 0xDD],
            fecInfo: (1 << 22) | (1 << 12) | (100 << 4),
            multiFecBlocks: makeMultiFecBlocks(currentBlock: 0, lastBlock: 0)
        )
    )

    let result = queue.ingest(parityPacket)
    #expect(!result.droppedUnrecoverableBlock)
    #expect(result.orderedDataPackets.count == 1)
    #expect(result.orderedDataPackets[0].payload.count == 40)
}

@Test("AV1 depacketizer applies Sunshine 7.1.446 frame header profile for 0x81 packets")
func av1DepacketizerUsesVersionAware41ByteHeader() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    depacketizer.configureFrameHeaderProfile(appVersion: "7.1.446.0")
    let framePayload = Data([0xAA, 0xBB, 0xCC])
    let packet = makeSyntheticNVVideoPacket(
        streamPacketIndex: 513,
        frameIndex: 67,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: Array(framePayload),
        includeFrameHeaderWithLastPayloadLength: 41 + UInt16(framePayload.count),
        frameHeaderSize: 41,
        frameHeaderFirstByte: 0x81
    )

    let frame = depacketizer.ingest(payload: packet, marker: true)
    #expect(frame == framePayload)
}

@Test("AV1 depacketizer uses conservative fixed frame-header parsing when app version is unavailable")
func av1DepacketizerFallsBackToConservativeFixedFrameHeaderProfile() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    depacketizer.configureFrameHeaderProfile(appVersion: nil)
    let framePayload = Data([0xC1, 0xC2, 0xC3])
    let packet = makeSyntheticNVVideoPacket(
        streamPacketIndex: 514,
        frameIndex: 68,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: Array(framePayload),
        includeFrameHeaderWithLastPayloadLength: 8 + UInt16(framePayload.count),
        frameHeaderSize: 8,
        frameHeaderFirstByte: 0x01
    )

    let frame = depacketizer.ingest(payload: packet, marker: true)
    #expect(frame == framePayload)
}

@Test("AV1 depacketizer normalizes legacy non-multi-FEC block metadata from app version")
func av1DepacketizerNormalizesLegacyNonMultiFECMetadataFromVersion() {
    var depacketizer = ShadowClientAV1RTPDepacketizer()
    depacketizer.configureFrameHeaderProfile(appVersion: "7.1.430.0")

    let framePayload = Data([0x7D, 0x7E])
    let packet = makeSyntheticNVVideoPacket(
        streamPacketIndex: 515,
        frameIndex: 69,
        flags: nvVideoPacketFlagContainsPicData | nvVideoPacketFlagSOF | nvVideoPacketFlagEOF,
        payloadBytes: Array(framePayload),
        includeFrameHeaderWithLastPayloadLength: moonlightFrameHeaderSize + UInt16(framePayload.count),
        multiFecBlocks: makeMultiFecBlocks(currentBlock: 2, lastBlock: 2)
    )

    let frame = depacketizer.ingest(payload: packet, marker: true)
    #expect(frame == framePayload)
}

@Test("Realtime runtime AV1 access-unit validator accepts basic size-delimited OBU payloads")
func realtimeRuntimeAv1AccessUnitValidatorAcceptsBasicObuSequence() {
    // OBU temporal delimiter (type=2, size=0) + OBU frame (type=6, size=1, payload=0x00)
    let accessUnit = Data([0x12, 0x00, 0x32, 0x01, 0x00])
    #expect(ShadowClientRealtimeRTSPSessionRuntime.isLikelyValidAV1AccessUnit(accessUnit))
}

@Test("Realtime runtime AV1 access-unit validator rejects malformed payloads")
func realtimeRuntimeAv1AccessUnitValidatorRejectsMalformedPayloads() {
    // Reserved bit set (bit0)
    let invalidHeader = Data([0x13, 0x00])
    // Declared size larger than available payload
    let invalidSize = Data([0x32, 0x05, 0x00])

    #expect(!ShadowClientRealtimeRTSPSessionRuntime.isLikelyValidAV1AccessUnit(invalidHeader))
    #expect(!ShadowClientRealtimeRTSPSessionRuntime.isLikelyValidAV1AccessUnit(invalidSize))
}

@Test("Realtime runtime drops malformed AV1 access units before VideoToolbox decode")
func realtimeRuntimeDropsMalformedAv1AccessUnitsBeforeDecode() {
    let validAccessUnit = Data([0x12, 0x00, 0x32, 0x01, 0x00])
    let malformedAccessUnit = Data([0x32, 0x05, 0x00])

    #expect(
        ShadowClientRealtimeRTSPSessionRuntime
            .isLikelyValidAV1AccessUnit(validAccessUnit)
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime
            .isLikelyValidAV1AccessUnit(malformedAccessUnit)
    )
}

@Test("Realtime runtime depacketizer shedding follows packet-shedding policy")
func realtimeRuntimeDepacketizerSheddingClassifier() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldShedDepacketizerWork(
            allowsPacketLevelShedding: false,
            bufferedDecodeUnits: ShadowClientRealtimeSessionDefaults.videoDepacketizerDecodeQueueShedHighWatermark
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldShedDepacketizerWork(
            allowsPacketLevelShedding: false,
            bufferedDecodeUnits: ShadowClientRealtimeSessionDefaults.videoDepacketizerDecodeQueueShedHighWatermark - 1
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldShedDepacketizerWork(
            allowsPacketLevelShedding: true,
            bufferedDecodeUnits: ShadowClientRealtimeSessionDefaults.videoDepacketizerDecodeQueueShedHighWatermark + 8
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldShedDepacketizerWork(
            allowsPacketLevelShedding: true,
            bufferedDecodeUnits: ShadowClientRealtimeSessionDefaults.videoDepacketizerDecodeQueueShedHighWatermark + 4
        )
    )
}

@Test("Video queue pressure policy maps from depacketizer tail strategy")
func realtimeRuntimeVideoQueuePressurePolicyClassifier() {
    let annexBPolicy = ShadowClientVideoQueuePressurePolicy.fromTailTruncationStrategy(
        .passthroughForAnnexBCodecs
    )
    let strictBoundaryPolicy = ShadowClientVideoQueuePressurePolicy.fromTailTruncationStrategy(
        .trimUsingLastPacketLength
    )

    #expect(annexBPolicy.allowsDepacketizerPacketShedding)
    #expect(annexBPolicy.allowsDecodeQueueProducerTrim)
    #expect(annexBPolicy.allowsDecodeQueueConsumerTrim)
    #expect(!strictBoundaryPolicy.allowsDepacketizerPacketShedding)
    #expect(strictBoundaryPolicy.allowsDecodeQueueProducerTrim)
    #expect(strictBoundaryPolicy.allowsDecodeQueueConsumerTrim)
}

@Test("Realtime runtime decode-queue recovery classifier suppresses producer trim/shed loops")
func realtimeRuntimeDecodeQueueRecoveryClassifier() {
    #expect(!ShadowClientRealtimeRTSPSessionRuntime.shouldTriggerDecodeQueueRecovery(source: "producer-trim"))
    #expect(!ShadowClientRealtimeRTSPSessionRuntime.shouldTriggerDecodeQueueRecovery(source: "producer-shed"))
    #expect(ShadowClientRealtimeRTSPSessionRuntime.shouldTriggerDecodeQueueRecovery(source: "consumer-trim"))
    #expect(ShadowClientRealtimeRTSPSessionRuntime.shouldTriggerDecodeQueueRecovery(source: "depacketize-shed"))
}

@Test("Realtime runtime queue pressure recovery escalation requires output stall when frames were already rendering")
func realtimeRuntimeQueuePressureRecoveryEscalationRequiresOutputStall() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldEscalateQueuePressureToRecovery(
            now: 100,
            lastDecodedFrameOutputUptime: 99.8,
            minimumStallSeconds: ShadowClientRealtimeSessionDefaults.videoQueuePressureRecoveryMinimumOutputStallSeconds
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldEscalateQueuePressureToRecovery(
            now: 100,
            lastDecodedFrameOutputUptime: 99.0,
            minimumStallSeconds: ShadowClientRealtimeSessionDefaults.videoQueuePressureRecoveryMinimumOutputStallSeconds
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldEscalateQueuePressureToRecovery(
            now: 100,
            lastDecodedFrameOutputUptime: 0,
            minimumStallSeconds: ShadowClientRealtimeSessionDefaults.videoQueuePressureRecoveryMinimumOutputStallSeconds
        )
    )
}

@Test("Realtime runtime queue pressure profile scales with bitrate and fps")
func realtimeRuntimeQueuePressureProfileScalesWithWorkload() {
    let baseline = ShadowClientRealtimeRTSPSessionRuntime.queuePressureProfile(
        for: .init(
            width: 1_920,
            height: 1_080,
            fps: 60,
            bitrateKbps: 20_000
        )
    )
    let heavy = ShadowClientRealtimeRTSPSessionRuntime.queuePressureProfile(
        for: .init(
            width: 3_840,
            height: 2_160,
            fps: 120,
            bitrateKbps: 120_000
        )
    )

    #expect(heavy.receiveQueueCapacity > baseline.receiveQueueCapacity)
    #expect(heavy.receiveQueuePressureTrimToRecentPackets > baseline.receiveQueuePressureTrimToRecentPackets)
    #expect(heavy.receiveQueueDropRecoveryThreshold > baseline.receiveQueueDropRecoveryThreshold)
    #expect(heavy.receiveQueueIngressSheddingMaximumBurstPackets >= baseline.receiveQueueIngressSheddingMaximumBurstPackets)
    #expect(heavy.decodeQueueCapacity >= baseline.decodeQueueCapacity)
    #expect(heavy.decodeQueueConsumerMaxBufferedUnits >= baseline.decodeQueueConsumerMaxBufferedUnits)
}

@Test("Realtime runtime queue pressure profile caps receive queue growth for bitrate outliers")
func realtimeRuntimeQueuePressureProfileCapsBitrateOutliers() {
    let outlier = ShadowClientRealtimeRTSPSessionRuntime.queuePressureProfile(
        for: .init(
            width: 3_840,
            height: 2_160,
            fps: 120,
            bitrateKbps: 500_000
        )
    )

    let payloadBytes = max(
        256,
        ShadowClientRealtimeSessionDefaults.videoEstimatedPacketPayloadBytes
    )
    let naivePacketsPerSecond = Int(
        (
            (Double(500_000) * 1_000.0 / 8.0) / Double(payloadBytes)
        ).rounded(.up)
    )
    let naiveCapacityAtMinimumWindow = min(
        ShadowClientRealtimeSessionDefaults.videoReceiveQueueMaximumCapacity,
        max(
            ShadowClientRealtimeSessionDefaults.videoReceiveQueueCapacity,
            Int(
                (
                    Double(naivePacketsPerSecond) *
                        ShadowClientRealtimeSessionDefaults.videoReceiveQueueMinimumTargetWindowSeconds
                ).rounded(.up)
            )
        )
    )

    #expect(outlier.receiveQueueCapacity < naiveCapacityAtMinimumWindow)
    #expect(
        outlier.receiveQueueCapacity <=
            ShadowClientRealtimeSessionDefaults.videoReceiveQueueMaximumPacketsPerFrameEstimate *
            ShadowClientRealtimeSessionDefaults.videoReceiveQueueMaximumFrameWindow
    )
}

@Test("Realtime runtime queue profile probes decode pressure faster for packet-thin streams")
func realtimeRuntimeQueuePressureProfileUsesFasterProbeForPacketThinStreams() {
    let packetThin = ShadowClientRealtimeRTSPSessionRuntime.queuePressureProfile(
        for: .init(
            width: 1_280,
            height: 720,
            fps: 120,
            bitrateKbps: 4_000
        )
    )

    #expect(
        packetThin.depacketizerDecodeQueueProbeIntervalPackets <
            ShadowClientRealtimeSessionDefaults.videoDepacketizerDecodeQueueProbeIntervalPackets
    )
}

@Test("Realtime runtime video frame-boundary classifier accepts marker or NV EOF packet")
func realtimeRuntimeVideoFrameBoundaryClassifier() {
    let markerBoundary = ShadowClientRealtimeRTSPSessionRuntime.isLikelyVideoFrameBoundary(
        marker: true,
        payload: Data()
    )
    #expect(markerBoundary)

    var eofPayload = Data(repeating: 0, count: 16)
    eofPayload[eofPayload.startIndex + 8] = 0x02 // EOF
    eofPayload[eofPayload.startIndex + 11] = 0xF0 // current=3, last=3
    let eofBoundary = ShadowClientRealtimeRTSPSessionRuntime.isLikelyVideoFrameBoundary(
        marker: false,
        payload: eofPayload
    )
    #expect(eofBoundary)

    var nonBoundaryPayload = eofPayload
    nonBoundaryPayload[nonBoundaryPayload.startIndex + 11] = 0x70 // current=3, last=1
    let nonBoundary = ShadowClientRealtimeRTSPSessionRuntime.isLikelyVideoFrameBoundary(
        marker: false,
        payload: nonBoundaryPayload
    )
    #expect(!nonBoundary)
}

@Test("Realtime runtime video frame-start classifier requires SOF and first FEC block")
func realtimeRuntimeVideoFrameStartClassifier() {
    var sofPayload = Data(repeating: 0, count: 16)
    sofPayload[sofPayload.startIndex + 8] = 0x04 // SOF
    sofPayload[sofPayload.startIndex + 11] = 0x00 // current block = 0
    let sofStart = ShadowClientRealtimeRTSPSessionRuntime.isLikelyVideoFrameStart(
        payload: sofPayload
    )
    #expect(sofStart)

    var nonSOFPayload = sofPayload
    nonSOFPayload[nonSOFPayload.startIndex + 8] = 0x00
    let nonSOFStart = ShadowClientRealtimeRTSPSessionRuntime.isLikelyVideoFrameStart(
        payload: nonSOFPayload
    )
    #expect(!nonSOFStart)

    var nonFirstFECBlockPayload = sofPayload
    nonFirstFECBlockPayload[nonFirstFECBlockPayload.startIndex + 11] = 0x10 // current block = 1
    let nonFirstFECBlockStart = ShadowClientRealtimeRTSPSessionRuntime.isLikelyVideoFrameStart(
        payload: nonFirstFECBlockPayload
    )
    #expect(!nonFirstFECBlockStart)

    var containsPicDataOnlyPayload = sofPayload
    containsPicDataOnlyPayload[containsPicDataOnlyPayload.startIndex + 8] = 0x01 // picture-data only
    let containsPicDataOnlyStart = ShadowClientRealtimeRTSPSessionRuntime.isLikelyVideoFrameStart(
        payload: containsPicDataOnlyPayload
    )
    #expect(!containsPicDataOnlyStart)
}

@Test("Realtime runtime stall detector triggers recovery when decode submits continue without frame output")
func realtimeRuntimeStallDetectorTriggersRecoveryForActiveDecodePath() {
    let shouldRecover = ShadowClientRealtimeRTSPSessionRuntime.shouldTriggerDecoderOutputStallRecovery(
        hasRenderedFirstFrame: true,
        now: 100.0,
        lastDecodeSubmitUptime: 99.8,
        lastDecodedFrameOutputUptime: 98.5
    )

    #expect(shouldRecover)
}

@Test("Realtime runtime stall detector ignores stale decode submit timestamps")
func realtimeRuntimeStallDetectorIgnoresInactiveDecodePath() {
    let shouldRecover = ShadowClientRealtimeRTSPSessionRuntime.shouldTriggerDecoderOutputStallRecovery(
        hasRenderedFirstFrame: true,
        now: 100.0,
        lastDecodeSubmitUptime: 98.9,
        lastDecodedFrameOutputUptime: 98.0
    )

    #expect(!shouldRecover)
}

@Test("Realtime runtime stall detector does not trigger before first rendered frame")
func realtimeRuntimeStallDetectorRequiresFirstRenderedFrame() {
    let shouldRecover = ShadowClientRealtimeRTSPSessionRuntime.shouldTriggerDecoderOutputStallRecovery(
        hasRenderedFirstFrame: false,
        now: 100.0,
        lastDecodeSubmitUptime: 99.8,
        lastDecodedFrameOutputUptime: 98.2
    )

    #expect(!shouldRecover)
}

@Test("Realtime runtime keeps decoder stall recovery non-fatal when decode submissions are stale")
func realtimeRuntimeKeepsDecoderStallRecoveryNonFatalWithoutRecentDecodeSubmit() {
    let shouldKeepNonFatal =
        ShadowClientRealtimeRTSPSessionRuntime.shouldKeepDecoderOutputStallRecoveryNonFatal(
            now: 100.0,
            lastDecodeSubmitUptime: 98.0,
            recentIngressGraceSeconds: 1.25
        )

    #expect(shouldKeepNonFatal)
}

@Test("Realtime runtime allows normal decoder stall escalation when decode submissions are recent")
func realtimeRuntimeAllowsDecoderStallEscalationWithRecentDecodeSubmit() {
    let shouldKeepNonFatal =
        ShadowClientRealtimeRTSPSessionRuntime.shouldKeepDecoderOutputStallRecoveryNonFatal(
            now: 100.0,
            lastDecodeSubmitUptime: 99.4,
            recentIngressGraceSeconds: 1.25
        )

    #expect(!shouldKeepNonFatal)
}

@Test("Realtime runtime expands stall threshold when queue pressure and consumer-trim pressure are both active")
func realtimeRuntimeStallThresholdExpansionUnderPressure() {
    let baseThreshold =
        ShadowClientRealtimeSessionDefaults.decoderOutputStallThresholdSeconds
    let expandedThreshold =
        ShadowClientRealtimeRTSPSessionRuntime.effectiveDecoderOutputStallThresholdSeconds(
            baseThreshold: baseThreshold,
            isPipelineUnderIngressPressure: true,
            hasRecentConsumerTrimPressure: true
        )
    let baseActiveWindow =
        ShadowClientRealtimeSessionDefaults.decoderOutputStallActiveDecodeWindowSeconds
    let expandedActiveWindow =
        ShadowClientRealtimeRTSPSessionRuntime.effectiveDecoderOutputStallActiveDecodeWindowSeconds(
            baseWindow: baseActiveWindow,
            isPipelineUnderIngressPressure: true,
            hasRecentConsumerTrimPressure: true
        )

    #expect(expandedThreshold > baseThreshold)
    #expect(expandedActiveWindow > baseActiveWindow)
}

@Test("Realtime runtime stall detector honors expanded thresholds under pressure")
func realtimeRuntimeStallDetectorHonorsExpandedThresholds() {
    let expandedThreshold =
        ShadowClientRealtimeRTSPSessionRuntime.effectiveDecoderOutputStallThresholdSeconds(
            isPipelineUnderIngressPressure: true,
            hasRecentConsumerTrimPressure: true
        )
    let expandedActiveWindow =
        ShadowClientRealtimeRTSPSessionRuntime.effectiveDecoderOutputStallActiveDecodeWindowSeconds(
            isPipelineUnderIngressPressure: true,
            hasRecentConsumerTrimPressure: true
        )

    let shouldRecover = ShadowClientRealtimeRTSPSessionRuntime.shouldTriggerDecoderOutputStallRecovery(
        hasRenderedFirstFrame: true,
        now: 100.0,
        lastDecodeSubmitUptime: 100.0 - (expandedActiveWindow * 0.8),
        lastDecodedFrameOutputUptime: 100.0 - (expandedThreshold * 0.8),
        activeDecodeWindowSeconds: expandedActiveWindow,
        stallThresholdSeconds: expandedThreshold
    )

    #expect(!shouldRecover)
}

@Test("Realtime runtime raises stall candidate threshold under queue pressure")
func realtimeRuntimeStallCandidateThresholdExpansionUnderPressure() {
    let baseThreshold = ShadowClientRealtimeRTSPSessionRuntime
        .effectiveDecoderOutputStallCandidateThreshold(
            isPipelineUnderIngressPressure: false,
            hasRecentConsumerTrimPressure: false
        )
    let pressureThreshold = ShadowClientRealtimeRTSPSessionRuntime
        .effectiveDecoderOutputStallCandidateThreshold(
            isPipelineUnderIngressPressure: true,
            hasRecentConsumerTrimPressure: false
        )
    let consumerTrimThreshold = ShadowClientRealtimeRTSPSessionRuntime
        .effectiveDecoderOutputStallCandidateThreshold(
            isPipelineUnderIngressPressure: true,
            hasRecentConsumerTrimPressure: true
        )

    #expect(baseThreshold == ShadowClientRealtimeSessionDefaults.decoderOutputStallCandidateThreshold)
    #expect(pressureThreshold == ShadowClientRealtimeSessionDefaults.decoderOutputStallCandidateThresholdUnderPressure)
    #expect(consumerTrimThreshold == ShadowClientRealtimeSessionDefaults.decoderOutputStallCandidateThresholdConsumerTrim)
    #expect(baseThreshold < pressureThreshold)
    #expect(pressureThreshold < consumerTrimThreshold)
}

@Test("Realtime runtime suppresses stall recovery while ingress pressure is active within grace window")
func realtimeRuntimeSuppressesStallRecoveryForIngressPressure() {
    let shouldSuppress = ShadowClientRealtimeRTSPSessionRuntime.shouldSuppressDecoderOutputStallRecovery(
        now: 100.0,
        lastDecodedFrameOutputUptime: 98.2,
        isPipelineUnderIngressPressure: true
    )

    #expect(shouldSuppress)
}

@Test("Realtime runtime does not suppress stall recovery after ingress-pressure suppression ceiling")
func realtimeRuntimeDoesNotSuppressStallRecoveryAfterIngressPressureSuppressionCeiling() {
    let shouldSuppress = ShadowClientRealtimeRTSPSessionRuntime.shouldSuppressDecoderOutputStallRecovery(
        now: 100.0,
        lastDecodedFrameOutputUptime: 87.0,
        isPipelineUnderIngressPressure: true
    )

    #expect(!shouldSuppress)
}

@Test("Realtime runtime decode queue recovery gate ignores consumer-trim pressure source")
func realtimeRuntimeDecodeQueueRecoveryGateIgnoresConsumerTrim() {
    let shouldTrigger = ShadowClientRealtimeRTSPSessionRuntime.shouldTriggerDecodeQueueRecovery(
        source: "consumer-trim"
    )

    #expect(!shouldTrigger)
}

@Test("Realtime runtime marks queue pressure signal as recent inside configured window")
func realtimeRuntimeRecentQueuePressureSignalWindowMatchesExpectation() {
    let isRecent = ShadowClientRealtimeRTSPSessionRuntime.isRecentQueuePressureSignal(
        now: 100.0,
        lastSignalUptime: 98.0,
        windowSeconds: 2.5
    )
    let isStale = ShadowClientRealtimeRTSPSessionRuntime.isRecentQueuePressureSignal(
        now: 100.0,
        lastSignalUptime: 96.0,
        windowSeconds: 2.5
    )

    #expect(isRecent)
    #expect(!isStale)
}

@Test("Realtime runtime prefers soft decoder output-stall recovery while queue pressure remains active")
func realtimeRuntimePrefersSoftDecoderOutputStallRecoveryUnderQueuePressure() {
    let shouldUseSoftRecovery = ShadowClientRealtimeRTSPSessionRuntime.shouldUseSoftDecoderOutputStallRecovery(
        isPipelineUnderIngressPressure: true,
        recoveryAttemptCount: 2,
        softRecoveryAttemptLimit: 2
    )
    let shouldUseSoftRecoveryAfterLimit = ShadowClientRealtimeRTSPSessionRuntime.shouldUseSoftDecoderOutputStallRecovery(
        isPipelineUnderIngressPressure: true,
        recoveryAttemptCount: 3,
        softRecoveryAttemptLimit: 2
    )
    let shouldUseSoftRecoveryWithoutPressure = ShadowClientRealtimeRTSPSessionRuntime.shouldUseSoftDecoderOutputStallRecovery(
        isPipelineUnderIngressPressure: false,
        recoveryAttemptCount: 1,
        softRecoveryAttemptLimit: 2
    )

    #expect(shouldUseSoftRecovery)
    #expect(!shouldUseSoftRecoveryAfterLimit)
    #expect(!shouldUseSoftRecoveryWithoutPressure)
}

@Test("Realtime runtime counter boundary helper detects interval crossing")
func realtimeRuntimeCounterBoundaryHelperDetectsIntervalCrossing() {
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.didCounterCrossIntervalBoundary(
            previous: 23,
            current: 24,
            interval: 24
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.didCounterCrossIntervalBoundary(
            previous: 24,
            current: 48,
            interval: 24
        )
    )
}

@Test("Realtime runtime counter boundary helper ignores non-crossing and invalid intervals")
func realtimeRuntimeCounterBoundaryHelperIgnoresNonCrossing() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.didCounterCrossIntervalBoundary(
            previous: 24,
            current: 47,
            interval: 24
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.didCounterCrossIntervalBoundary(
            previous: 48,
            current: 48,
            interval: 24
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.didCounterCrossIntervalBoundary(
            previous: 10,
            current: 20,
            interval: 0
        )
    )
}

@Test("Realtime runtime recovery request gate suppresses duplicate requests while one is pending")
func realtimeRuntimeRecoveryRequestGateSuppressesPendingDuplicates() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldAllowVideoRecoveryFrameRequest(
            now: 10.0,
            lastRequestUptime: 9.6,
            isRequestPending: true,
            minimumInterval: 0.25,
            pendingTimeout: 2.0,
            isPipelineUnderIngressPressure: false,
            pressureMinimumInterval: 2.0
        )
    )
}

@Test("Realtime runtime recovery request gate reopens after pending timeout")
func realtimeRuntimeRecoveryRequestGateReopensAfterPendingTimeout() {
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldAllowVideoRecoveryFrameRequest(
            now: 10.0,
            lastRequestUptime: 7.0,
            isRequestPending: true,
            minimumInterval: 0.75,
            pendingTimeout: 2.0,
            isPipelineUnderIngressPressure: false,
            pressureMinimumInterval: 2.0
        )
    )
}

@Test("Realtime runtime recovery request gate honors cooldown when no request is pending")
func realtimeRuntimeRecoveryRequestGateHonorsCooldown() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldAllowVideoRecoveryFrameRequest(
            now: 10.0,
            lastRequestUptime: 9.7,
            isRequestPending: false,
            minimumInterval: 0.5,
            pendingTimeout: 2.0,
            isPipelineUnderIngressPressure: false,
            pressureMinimumInterval: 2.0
        )
    )
}

@Test("Realtime runtime recovery request gate applies stronger cooldown during ingress pressure")
func realtimeRuntimeRecoveryRequestGateHonorsIngressPressureCooldown() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldAllowVideoRecoveryFrameRequest(
            now: 10.0,
            lastRequestUptime: 8.6,
            isRequestPending: false,
            minimumInterval: 0.75,
            pendingTimeout: 2.0,
            isPipelineUnderIngressPressure: true,
            pressureMinimumInterval: 2.0
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldAllowVideoRecoveryFrameRequest(
            now: 10.0,
            lastRequestUptime: 7.6,
            isRequestPending: false,
            minimumInterval: 0.75,
            pendingTimeout: 2.0,
            isPipelineUnderIngressPressure: true,
            pressureMinimumInterval: 2.0
        )
    )
}

@Test("Realtime runtime FEC unrecoverable burst gate suppresses requests below threshold")
func realtimeRuntimeFECUnrecoverableBurstGateSuppressesBelowThreshold() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldRequestVideoRecoveryAfterFECUnrecoverableBurst(
            now: 10.0,
            firstUnrecoverableUptime: 9.7,
            unrecoverableCount: 1,
            lastRequestUptime: 0.0,
            burstWindow: 1.5,
            burstThreshold: 2,
            minimumInterval: 1.0
        )
    )
}

@Test("Realtime runtime FEC unrecoverable burst gate allows request at threshold within window")
func realtimeRuntimeFECUnrecoverableBurstGateAllowsThresholdWithinWindow() {
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldRequestVideoRecoveryAfterFECUnrecoverableBurst(
            now: 10.0,
            firstUnrecoverableUptime: 9.2,
            unrecoverableCount: 2,
            lastRequestUptime: 8.0,
            burstWindow: 1.5,
            burstThreshold: 2,
            minimumInterval: 1.0
        )
    )
}

@Test("Realtime runtime FEC unrecoverable burst gate suppresses stale-window and cooldown violations")
func realtimeRuntimeFECUnrecoverableBurstGateSuppressesStaleOrCooldownViolations() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldRequestVideoRecoveryAfterFECUnrecoverableBurst(
            now: 10.0,
            firstUnrecoverableUptime: 7.0,
            unrecoverableCount: 3,
            lastRequestUptime: 0.0,
            burstWindow: 1.5,
            burstThreshold: 2,
            minimumInterval: 1.0
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldRequestVideoRecoveryAfterFECUnrecoverableBurst(
            now: 10.0,
            firstUnrecoverableUptime: 9.4,
            unrecoverableCount: 3,
            lastRequestUptime: 9.3,
            burstWindow: 1.5,
            burstThreshold: 2,
            minimumInterval: 1.0
        )
    )
}

@Test("Realtime runtime UDP video stall detector ignores startup and triggers only after post-start inactivity threshold")
func realtimeRuntimeUDPVideoStallDetectorUsesPostStartInactivityThreshold() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldTreatUDPVideoDatagramReceiveAsStalledAfterStartup(
            datagramCount: 0,
            secondsSinceLastDatagram: 30.0,
            inactivityTimeoutSeconds: 4.0
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldTreatUDPVideoDatagramReceiveAsStalledAfterStartup(
            datagramCount: 24,
            secondsSinceLastDatagram: 3.9,
            inactivityTimeoutSeconds: 4.0
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldTreatUDPVideoDatagramReceiveAsStalledAfterStartup(
            datagramCount: 24,
            secondsSinceLastDatagram: 4.0,
            inactivityTimeoutSeconds: 4.0
        )
    )
}

@Test("Realtime runtime keeps post-start UDP inactivity non-terminal")
func realtimeRuntimeUDPVideoInactivityEscalationThreshold() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldEscalateUDPVideoDatagramInactivityToFallback(
            now: 10.0,
            firstObservedStallUptime: 0.0,
            lastInteractiveInputUptime: 0.0,
            fallbackThresholdSeconds: 12.0
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldEscalateUDPVideoDatagramInactivityToFallback(
            now: 21.9,
            firstObservedStallUptime: 10.0,
            lastInteractiveInputUptime: 20.0,
            fallbackThresholdSeconds: 12.0
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldEscalateUDPVideoDatagramInactivityToFallback(
            now: 22.0,
            firstObservedStallUptime: 10.0,
            lastInteractiveInputUptime: 8.0,
            fallbackThresholdSeconds: 12.0
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldEscalateUDPVideoDatagramInactivityToFallback(
            now: 25.0,
            firstObservedStallUptime: 10.0,
            lastInteractiveInputUptime: 10.5,
            fallbackThresholdSeconds: 12.0
        )
    )
}

@Test("Realtime runtime requests in-session UDP socket recycle after prolonged post-start inactivity")
func realtimeRuntimeUDPVideoSocketRecycleClassifier() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldRecycleUDPVideoSocketAfterInactivity(
            datagramCount: 0,
            secondsSinceLastDatagram: 30.0,
            recycleThresholdSeconds: 15.0
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldRecycleUDPVideoSocketAfterInactivity(
            datagramCount: 24,
            secondsSinceLastDatagram: 14.9,
            recycleThresholdSeconds: 15.0
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldRecycleUDPVideoSocketAfterInactivity(
            datagramCount: 24,
            secondsSinceLastDatagram: 15.0,
            recycleThresholdSeconds: 15.0
        )
    )
}

@Test("Realtime runtime requests in-session UDP socket recycle after prolonged startup inactivity")
func realtimeRuntimeUDPVideoStartupSocketRecycleClassifier() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldRecycleUDPVideoSocketForStartupInactivity(
            secondsSinceReceiveStart: 14.9,
            recycleThresholdSeconds: 15.0
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldRecycleUDPVideoSocketForStartupInactivity(
            secondsSinceReceiveStart: 15.0,
            recycleThresholdSeconds: 15.0
        )
    )
}

@Test("Realtime runtime fallback classifier ignores post-start inactivity timeout errors")
func realtimeRuntimeInterleavedFallbackClassifierIgnoresPostStartInactivityErrors() {
    let noDatagramError = NSError(
        domain: "ShadowClientTest",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "RTSP UDP video timeout: no video datagram received"]
    )
    let stallError = NSError(
        domain: "ShadowClientTest",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "RTSP UDP video timeout: video datagram stream stalled after startup"]
    )
    let prolongedError = NSError(
        domain: "ShadowClientTest",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "RTSP UDP video timeout: prolonged datagram inactivity after startup"]
    )
    let unrelatedError = NSError(
        domain: "ShadowClientTest",
        code: 4,
        userInfo: [NSLocalizedDescriptionKey: "RTSP request parsing failed"]
    )

    #expect(
        ShadowClientRealtimeRTSPSessionRuntime
            .shouldFallbackToInterleavedTransportAfterUDPReceiveError(noDatagramError)
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime
            .shouldFallbackToInterleavedTransportAfterUDPReceiveError(stallError)
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime
            .shouldFallbackToInterleavedTransportAfterUDPReceiveError(prolongedError)
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime
            .shouldFallbackToInterleavedTransportAfterUDPReceiveError(unrelatedError)
    )
}

@Test("Realtime runtime in-session UDP retry classifier treats sustained inactivity as terminal")
func realtimeRuntimeInSessionUDPReceiveRetryClassifier() {
    let noStartupDatagramError = NSError(
        domain: "ShadowClientTest",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "RTSP UDP video timeout: no startup datagrams received"]
    )
    let prolongedInactivityError = NSError(
        domain: "ShadowClientTest",
        code: 10,
        userInfo: [NSLocalizedDescriptionKey: "RTSP UDP video timeout: prolonged datagram inactivity after startup"]
    )
    let recycleRequestedError = NSError(
        domain: "ShadowClientTest",
        code: 11,
        userInfo: [NSLocalizedDescriptionKey: "RTSP UDP video receive recycle requested: prolonged datagram inactivity after startup"]
    )
    let nwStreamError = NSError(
        domain: "Network.NWError",
        code: 96,
        userInfo: [NSLocalizedDescriptionKey: "No message available on STREAM"]
    )
    let closedError = NSError(
        domain: "ShadowClientTest",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "RTSP transport connection closed"]
    )
    let unrelatedError = NSError(
        domain: "ShadowClientTest",
        code: 3,
        userInfo: [NSLocalizedDescriptionKey: "decoder setup failed"]
    )

    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime
            .shouldRetryInSessionAfterUDPVideoReceiveError(noStartupDatagramError)
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime
            .shouldRetryInSessionAfterUDPVideoReceiveError(prolongedInactivityError)
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime
            .shouldRetryInSessionAfterUDPVideoReceiveError(recycleRequestedError)
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime
            .shouldRetryInSessionAfterUDPVideoReceiveError(nwStreamError)
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime
            .shouldRetryInSessionAfterUDPVideoReceiveError(closedError)
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime
            .shouldRetryInSessionAfterUDPVideoReceiveError(unrelatedError)
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime
            .shouldRetryInSessionAfterUDPVideoReceiveError(CancellationError())
    )
}

@Test("Realtime runtime UDP inactivity recovery request is input-agnostic and cooldown-driven")
func realtimeRuntimeUDPInactivityRecoveryRequestRequiresRecentInput() {
    let now: TimeInterval = 100
    let lastRecoveryRequest: TimeInterval = 95
    let secondsSinceLastDatagram: TimeInterval = 5

    #expect(
        ShadowClientRealtimeRTSPSessionRuntime
            .shouldRequestVideoRecoveryForUDPDatagramInactivity(
                now: now,
                lastRecoveryRequestUptime: lastRecoveryRequest,
                lastInteractiveInputEventUptime: 0,
                secondsSinceLastDatagram: secondsSinceLastDatagram
            )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime
            .shouldRequestVideoRecoveryForUDPDatagramInactivity(
                now: now,
                lastRecoveryRequestUptime: lastRecoveryRequest,
                lastInteractiveInputEventUptime: 80,
                secondsSinceLastDatagram: secondsSinceLastDatagram
            )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime
            .shouldRequestVideoRecoveryForUDPDatagramInactivity(
                now: now,
                lastRecoveryRequestUptime: lastRecoveryRequest,
                lastInteractiveInputEventUptime: 98,
                secondsSinceLastDatagram: secondsSinceLastDatagram
            )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime
            .shouldRequestVideoRecoveryForUDPDatagramInactivity(
                now: now,
                lastRecoveryRequestUptime: 99.5,
                lastInteractiveInputEventUptime: 99,
                secondsSinceLastDatagram: secondsSinceLastDatagram
            )
    )
}

@Test("Realtime runtime gamepad interaction classifier requires explicit gamepad button input for UDP inactivity recovery")
func realtimeRuntimeGamepadInteractionClassifierForUDPInactivityRecovery() {
    let neutralJitterState = ShadowClientRemoteGamepadState(
        controllerNumber: 0,
        activeGamepadMask: 1,
        buttonFlags: 0,
        leftTrigger: 2,
        rightTrigger: 1,
        leftStickX: 320,
        leftStickY: -512,
        rightStickX: 780,
        rightStickY: -640
    )
    let buttonPressedState = ShadowClientRemoteGamepadState(
        controllerNumber: 0,
        activeGamepadMask: 1,
        buttonFlags: 1,
        leftTrigger: 0,
        rightTrigger: 0,
        leftStickX: 0,
        leftStickY: 0,
        rightStickX: 0,
        rightStickY: 0
    )
    let triggerActiveState = ShadowClientRemoteGamepadState(
        controllerNumber: 0,
        activeGamepadMask: 1,
        buttonFlags: 0,
        leftTrigger: 18,
        rightTrigger: 0,
        leftStickX: 0,
        leftStickY: 0,
        rightStickX: 0,
        rightStickY: 0
    )
    let stickActiveState = ShadowClientRemoteGamepadState(
        controllerNumber: 0,
        activeGamepadMask: 1,
        buttonFlags: 0,
        leftTrigger: 0,
        rightTrigger: 0,
        leftStickX: 2400,
        leftStickY: 0,
        rightStickX: 0,
        rightStickY: 0
    )

    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime
            .shouldTreatGamepadStateAsInteractiveForUDPDatagramRecovery(neutralJitterState)
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime
            .shouldTreatGamepadStateAsInteractiveForUDPDatagramRecovery(buttonPressedState)
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime
            .shouldTreatGamepadStateAsInteractiveForUDPDatagramRecovery(triggerActiveState)
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime
            .shouldTreatGamepadStateAsInteractiveForUDPDatagramRecovery(stickActiveState)
    )
}

@Test("Realtime runtime treats canceled input send errors as transient and does not reset control channel")
func realtimeRuntimeInputSendClassifierTreatsCanceledAsTransient() {
    let nwCanceled = NSError(domain: "Network.NWError", code: 89)
    let urlCanceled = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
    let posixCanceled = NWError.posix(.ECANCELED)
    let posixNotConnected = NWError.posix(.ENOTCONN)

    #expect(ShadowClientRealtimeRTSPSessionRuntime.isTransientInputSendError(nwCanceled))
    #expect(ShadowClientRealtimeRTSPSessionRuntime.isTransientInputSendError(urlCanceled))
    #expect(ShadowClientRealtimeRTSPSessionRuntime.isTransientInputSendError(posixCanceled))
    #expect(ShadowClientRealtimeRTSPSessionRuntime.isTransientInputSendError(posixNotConnected))

    #expect(!ShadowClientRealtimeRTSPSessionRuntime.shouldResetInputControlChannelAfterSendError(nwCanceled))
    #expect(!ShadowClientRealtimeRTSPSessionRuntime.shouldResetInputControlChannelAfterSendError(posixCanceled))
    #expect(!ShadowClientRealtimeRTSPSessionRuntime.shouldResetInputControlChannelAfterSendError(posixNotConnected))
}

@Test("Realtime runtime resets control channel after transient input-send burst inside short window")
func realtimeRuntimeResetsControlChannelAfterTransientInputSendBurst() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldResetControlChannelAfterTransientInputSendFailures(
            failureCount: 5,
            now: 10.0,
            firstFailureUptime: 8.0,
            burstWindowSeconds: 3.0,
            burstThreshold: 6
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldResetControlChannelAfterTransientInputSendFailures(
            failureCount: 6,
            now: 10.0,
            firstFailureUptime: 8.0,
            burstWindowSeconds: 3.0,
            burstThreshold: 6
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldResetControlChannelAfterTransientInputSendFailures(
            failureCount: 6,
            now: 12.1,
            firstFailureUptime: 8.0,
            burstWindowSeconds: 3.0,
            burstThreshold: 6
        )
    )
}

@Test("Realtime runtime resets control channel for fatal send errors")
func realtimeRuntimeInputSendClassifierResetsForFatalErrors() {
    let nwNoMessageAvailableOnStream = NSError(domain: "Network.NWError", code: 96)

    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.isTransientInputSendError(
            nwNoMessageAvailableOnStream
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldResetInputControlChannelAfterSendError(
            nwNoMessageAvailableOnStream
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldResetInputControlChannelAfterSendError(
            ShadowClientSunshineControlChannelError.connectionClosed
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldResetInputControlChannelAfterSendError(
            ShadowClientSunshineControlChannelError.commandAcknowledgeTimedOut
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldResetInputControlChannelAfterSendError(
            NWError.posix(.ECONNRESET)
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldResetInputControlChannelAfterSendError(
            NWError.posix(.EPIPE)
        )
    )
}

@Test("Realtime runtime render submit pacing drops frame when publishing faster than session fps")
func realtimeRuntimeRenderSubmitPacingDropsWhenOverBudget() {
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldDropRenderSubmitForSessionFPS(
            now: 10.005,
            lastRenderedFramePublishUptime: 10.0,
            sessionFPS: 60,
            pacingToleranceRatio: 0.90
        )
    )
}

@Test("Realtime runtime render submit pacing allows frame when cadence budget is met")
func realtimeRuntimeRenderSubmitPacingAllowsWhenBudgetMet() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldDropRenderSubmitForSessionFPS(
            now: 10.030,
            lastRenderedFramePublishUptime: 10.0,
            sessionFPS: 60,
            pacingToleranceRatio: 0.90
        )
    )
}

@Test("Realtime runtime stall recovery aborts when recovery limit is exceeded")
func realtimeRuntimeStallRecoveryAbortsOnRecoveryLimit() {
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldAbortDecoderOutputStallRecovery(
            recoveryAttemptCount: 4,
            maxRecoveryAttempts: 4
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldAbortDecoderOutputStallRecovery(
            recoveryAttemptCount: 3,
            maxRecoveryAttempts: 4
        )
    )
}

@Test("Realtime runtime fatal decoder initialization errors abort recovery")
func realtimeRuntimeFatalDecoderInitializationErrorsAbortRecovery() {
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldAbortDecoderRecovery(
            forDecoderError: ShadowClientVideoToolboxDecoderError.cannotCreateDecoder(-12915)
        )
    )
}

@Test("Realtime runtime decode-failed statuses classify recoverable and fatal VT statuses")
func realtimeRuntimeDecodeFailedStatusClassification() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldAbortDecoderRecovery(
            forDecoderError: ShadowClientVideoToolboxDecoderError.decodeFailed(-12903)
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldAbortDecoderRecovery(
            forDecoderError: ShadowClientVideoToolboxDecoderError.decodeFailed(-12909)
        )
    )
}

@Test("Realtime runtime recoverable decode errors do not abort recovery")
func realtimeRuntimeRecoverableDecodeErrorsDoNotAbortRecovery() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldAbortDecoderRecovery(
            forDecoderError: ShadowClientVideoToolboxDecoderError.decodeFailed(-12909)
        )
    )
}

@Test("Realtime runtime immediate decoder-reset policy treats AV1 -12909 as soft recovery")
func realtimeRuntimeImmediateDecoderResetPolicyTreatsAV1RecoverableFailureAsSoft() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.requiresImmediateDecoderReset(
            codec: .av1,
            decodeFailureStatus: -12909
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.requiresImmediateDecoderReset(
            codec: .av1,
            decodeFailureStatus: -12903
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.requiresImmediateDecoderReset(
            codec: .h264,
            decodeFailureStatus: -12903
        )
    )
}

@Test("Realtime runtime soft-drop policy classifies AV1 -12909 without hard reset")
func realtimeRuntimeSoftDropPolicyClassifiesAV1RecoverableFailure() {
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldTreatDecoderFailureAsSoftFrameDrop(
            codec: .av1,
            decodeFailureStatus: -12909
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldTreatDecoderFailureAsSoftFrameDrop(
            codec: .av1,
            decodeFailureStatus: -12903
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldTreatDecoderFailureAsSoftFrameDrop(
            codec: .h264,
            decodeFailureStatus: -12909
        )
    )
}

@Test("Realtime runtime AV1 fast-fallback counter excludes soft-drop status -12909")
func realtimeRuntimeAV1FastFallbackCounterExcludesSoftDropStatus() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldCountAV1RecoverableFailureForFastFallback(
            -12909
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldCountAV1RecoverableFailureForFastFallback(
            -12903
        )
    )
}

@Test("Realtime runtime AV1 soft-recovery request starts on third recoverable failure")
func realtimeRuntimeAV1SoftRecoveryRequestThreshold() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldRequestAV1SoftRecoveryFrameAfterRecoverableFailures(
            1
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldRequestAV1SoftRecoveryFrameAfterRecoverableFailures(
            2
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldRequestAV1SoftRecoveryFrameAfterRecoverableFailures(
            3
        )
    )
}

@Test("Realtime runtime AV1 recoverable failure burst can trigger local decoder reset")
func realtimeRuntimeAV1RecoverableFailureBurstLocalResetThreshold() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldResetAV1DecoderAfterRecoverableFailureBurst(
            recoverableFailureCount: 2,
            now: 10.0,
            lastDecoderRecoveryUptime: 0,
            recoveryCooldownSeconds: 0.75
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldResetAV1DecoderAfterRecoverableFailureBurst(
            recoverableFailureCount: 3,
            now: 10.0,
            lastDecoderRecoveryUptime: 0,
            recoveryCooldownSeconds: 0.75
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldResetAV1DecoderAfterRecoverableFailureBurst(
            recoverableFailureCount: 3,
            now: 10.0,
            lastDecoderRecoveryUptime: 9.6,
            recoveryCooldownSeconds: 0.75
        )
    )
}

@Test("Realtime runtime AV1 soft-recovery requires output stall evidence")
func realtimeRuntimeAV1SoftRecoveryRequestRequiresOutputStall() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldRequestAV1SoftRecoveryFrameAfterRecoverableFailures(
            recoverableFailureCount: 3,
            now: 10.0,
            lastDecodedFrameOutputUptime: 9.4,
            minimumOutputStallSeconds: 1.5
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldRequestAV1SoftRecoveryFrameAfterRecoverableFailures(
            recoverableFailureCount: 3,
            now: 10.0,
            lastDecodedFrameOutputUptime: 8.0,
            minimumOutputStallSeconds: 1.5
        )
    )
}

@Test("Realtime runtime AV1 soft-recovery enters sync gate on recoverable-failure burst even without output stall")
func realtimeRuntimeAV1SoftRecoverySyncGatePolicyUsesFailureBurstGuard() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldEnterSyncGateForAV1SoftRecoveryRequest(
            recoverableFailureCount: 2,
            now: 10.0,
            lastDecodedFrameOutputUptime: 6.0,
            minimumOutputStallSeconds: 1.5
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldEnterSyncGateForAV1SoftRecoveryRequest(
            recoverableFailureCount: 3,
            now: 10.0,
            lastDecodedFrameOutputUptime: 9.2,
            minimumOutputStallSeconds: 1.5
        )
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldEnterSyncGateForAV1SoftRecoveryRequest(
            recoverableFailureCount: 3,
            now: 10.0,
            lastDecodedFrameOutputUptime: 8.0,
            minimumOutputStallSeconds: 1.5
        )
    )
}

@Test("Realtime runtime AV1 reference invalidation range uses Moonlight 0x20 window")
func realtimeRuntimeAV1ReferenceInvalidationRangeUsesMoonlightWindow() {
    let range = ShadowClientRealtimeRTSPSessionRuntime.av1ReferenceInvalidationRange(
        endFrameIndex: 0x0100
    )
    #expect(range.start == 0x00E0)
    #expect(range.end == 0x0100)
}

@Test("Realtime runtime AV1 reference invalidation range clamps at zero for early frames")
func realtimeRuntimeAV1ReferenceInvalidationRangeClampsAtZero() {
    let range = ShadowClientRealtimeRTSPSessionRuntime.av1ReferenceInvalidationRange(
        endFrameIndex: 0x0010
    )
    #expect(range.start == 0)
    #expect(range.end == 0x0010)
}

@Test("Realtime runtime decode failure status extraction reports decode status")
func realtimeRuntimeDecodeFailureStatusExtractionReportsDecodeStatus() {
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.decodeFailureStatus(
            from: ShadowClientVideoToolboxDecoderError.decodeFailed(-12909)
        ) == -12909
    )
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.decodeFailureStatus(
            from: ShadowClientVideoToolboxDecoderError.missingParameterSets
        ) == nil
    )
}

@Test("Realtime runtime AV1 sync-frame classifier defaults to IDR-only admission")
func realtimeRuntimeAV1SyncFrameClassifierDefaultsToIDR() {
    #expect(ShadowClientRealtimeRTSPSessionRuntime.isAV1SyncFrameType(2))
    #expect(!ShadowClientRealtimeRTSPSessionRuntime.isAV1SyncFrameType(1))
    #expect(!ShadowClientRealtimeRTSPSessionRuntime.isAV1SyncFrameType(5))
    #expect(!ShadowClientRealtimeRTSPSessionRuntime.isAV1SyncFrameType(nil))
}

@Test("Realtime runtime AV1 sync-frame classifier admits type 5 after recovery-frame invalidation request")
func realtimeRuntimeAV1SyncFrameClassifierAdmitsRefInvalidatedFrameWhenAllowed() {
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.isAV1SyncFrameType(
            5,
            allowsReferenceInvalidatedFrame: true
        )
    )
}

@Test("Realtime runtime AV1 sync-frame classifier admits type 4 after recovery-frame invalidation request")
func realtimeRuntimeAV1SyncFrameClassifierAdmitsType4WhenAllowed() {
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.isAV1SyncFrameType(
            4,
            allowsReferenceInvalidatedFrame: true
        )
    )
}

@Test("Realtime runtime AV1 sync-frame classifier rejects Sunshine frame type 104")
func realtimeRuntimeAV1SyncFrameClassifierRejectsSunshine104() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.isAV1SyncFrameType(
            104,
            allowsReferenceInvalidatedFrame: true
        )
    )
}

@Test("Realtime runtime keeps decoder failure history when successful decode occurs inside failure window")
func realtimeRuntimeKeepsDecoderFailureHistoryWithinWindow() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldClearDecoderFailureHistoryOnSuccessfulDecode(
            now: 12.0,
            firstFailureUptime: 11.2,
            windowSeconds: 1.5
        )
    )
}

@Test("Realtime runtime clears decoder failure history when successful decode occurs after failure window")
func realtimeRuntimeClearsDecoderFailureHistoryOutsideWindow() {
    #expect(
        ShadowClientRealtimeRTSPSessionRuntime.shouldClearDecoderFailureHistoryOnSuccessfulDecode(
            now: 14.0,
            firstFailureUptime: 11.0,
            windowSeconds: 1.5
        )
    )
}

@Test("Realtime runtime transient decoder errors do not abort recovery")
func realtimeRuntimeTransientDecoderErrorsDoNotAbortRecovery() {
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldAbortDecoderRecovery(
            forDecoderError: ShadowClientVideoToolboxDecoderError.missingParameterSets
        )
    )
    #expect(
        !ShadowClientRealtimeRTSPSessionRuntime.shouldAbortDecoderRecovery(
            forDecoderError: ShadowClientVideoToolboxDecoderError.missingFrameDimensions
        )
    )
}

private let nvVideoPacketFlagContainsPicData: UInt8 = 0x01
private let nvVideoPacketFlagEOF: UInt8 = 0x02
private let nvVideoPacketFlagSOF: UInt8 = 0x04
private let moonlightFrameHeaderSize: UInt16 = 8

private func makeSyntheticNVVideoPacket(
    streamPacketIndex: UInt32,
    frameIndex: UInt32,
    flags: UInt8,
    payloadBytes: [UInt8],
    includeFrameHeaderWithLastPayloadLength lastPayloadLength: UInt16? = nil,
    frameHeaderSize: UInt16 = moonlightFrameHeaderSize,
    frameHeaderFirstByte: UInt8 = 0x01,
    frameHeaderFrameType: UInt8 = 0x01,
    fecInfo: UInt32 = 0,
    multiFecFlags: UInt8 = 0x10,
    multiFecBlocks: UInt8 = 0x00
) -> Data {
    var packetPayload = Data()
    if let lastPayloadLength {
        packetPayload.append(
            moonlightFrameHeader(
                lastPayloadLength: lastPayloadLength,
                frameHeaderSize: frameHeaderSize,
                firstByte: frameHeaderFirstByte,
                frameType: frameHeaderFrameType
            )
        )
    }
    packetPayload.append(contentsOf: payloadBytes)

    var packet = Data()
    packet.append(contentsOf: littleEndianBytes(streamPacketIndex << 8))
    packet.append(contentsOf: littleEndianBytes(frameIndex))
    packet.append(flags)
    packet.append(0x00) // extraFlags
    packet.append(multiFecFlags)
    packet.append(multiFecBlocks)
    packet.append(contentsOf: littleEndianBytes(fecInfo)) // fecInfo
    packet.append(packetPayload)
    return packet
}

private func makeMultiFecBlocks(currentBlock: UInt8, lastBlock: UInt8) -> UInt8 {
    ((currentBlock & 0x03) << 4) | ((lastBlock & 0x03) << 6)
}

private func moonlightFrameHeader(
    lastPayloadLength: UInt16,
    frameHeaderSize: UInt16 = moonlightFrameHeaderSize,
    firstByte: UInt8 = 0x01,
    frameType: UInt8 = 0x01
) -> Data {
    let resolvedHeaderSize = max(Int(frameHeaderSize), 8)
    var header = Data(repeating: 0, count: resolvedHeaderSize)
    header[0] = firstByte
    header[3] = frameType
    let lastPayloadLengthBytes = littleEndianBytes(lastPayloadLength)
    header[4] = lastPayloadLengthBytes[0]
    header[5] = lastPayloadLengthBytes[1]
    return header
}

private func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    let littleEndianValue = value.littleEndian
    return withUnsafeBytes(of: littleEndianValue) { Array($0) }
}

private func makeVideoRTPPacket(
    sequenceNumber: UInt16,
    payloadByte: UInt8
) -> ShadowClientRTPPacket {
    makeVideoRTPPacket(
        sequenceNumber: sequenceNumber,
        marker: false,
        payloadType: 0,
        payload: Data([payloadByte])
    )
}

private func makeVideoRTPPacket(
    sequenceNumber: UInt16,
    marker: Bool,
    payloadType: Int,
    payload: Data
) -> ShadowClientRTPPacket {
    var rawBytes = Data([
        0x80 | 0x10,
        UInt8((marker ? 0x80 : 0x00) | UInt8(payloadType & 0x7F)),
        UInt8(sequenceNumber >> 8),
        UInt8(truncatingIfNeeded: sequenceNumber),
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00,
    ])
    rawBytes.append(payload)
    return ShadowClientRTPPacket(
        isRTP: true,
        channel: 0,
        sequenceNumber: sequenceNumber,
        marker: marker,
        payloadType: payloadType,
        payloadOffset: 16,
        rawBytes: rawBytes,
        payload: payload
    )
}
