import Foundation
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
        contentBase: "rtsp://wifi.skyline23.com:48010/",
        fallbackSessionURL: "rtsp://wifi.skyline23.com:48010"
    )

    #expect(track.codec == .h264)
    #expect(track.rtpPayloadType == 96)
    #expect(track.controlURL == "rtsp://wifi.skyline23.com:48010/streamid=0")
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
        contentBase: "rtsp://skyline23-pc.local:48010/",
        fallbackSessionURL: "rtsp://skyline23-pc.local:48010"
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
        contentBase: "rtsp://skyline23-pc.local:48010/",
        fallbackSessionURL: "rtsp://skyline23-pc.local:48010"
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
        contentBase: "rtsp://skyline23-pc.local:48010/",
        fallbackSessionURL: "rtsp://skyline23-pc.local:48010"
    )

    #expect(track.rtpPayloadType == 98)
    #expect(track.codec == .av1)
    #expect(track.parameterSets.count == 1)
    #expect(track.parameterSets[0] == Data([0x00, 0x00, 0x00, 0x01]))
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
        contentBase: "rtsp://skyline23-pc.local:48010/",
        fallbackSessionURL: "rtsp://skyline23-pc.local:48010"
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
        contentBase: "rtsp://skyline23-pc.local:48010/",
        fallbackSessionURL: "rtsp://skyline23-pc.local:48010"
    )

    #expect(track.codec == .av1)
    #expect(track.rtpPayloadType == ShadowClientRTSPProtocolProfile.fallbackVideoPayloadType)
    #expect(track.controlURL == "rtsp://skyline23-pc.local:48010/streamid=video")
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
        forRTSPURLString: "rtsp://wifi.skyline23.com:48010/streamid=video"
    )
    #expect(header == "wifi.skyline23.com:48010")
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

private let nvVideoPacketFlagContainsPicData: UInt8 = 0x01
private let nvVideoPacketFlagEOF: UInt8 = 0x02
private let nvVideoPacketFlagSOF: UInt8 = 0x04
private let moonlightFrameHeaderSize: UInt16 = 8

private func makeSyntheticNVVideoPacket(
    streamPacketIndex: UInt32,
    frameIndex: UInt32,
    flags: UInt8,
    payloadBytes: [UInt8],
    includeFrameHeaderWithLastPayloadLength lastPayloadLength: UInt16? = nil
) -> Data {
    var packetPayload = Data()
    if let lastPayloadLength {
        packetPayload.append(moonlightFrameHeader(lastPayloadLength: lastPayloadLength))
    }
    packetPayload.append(contentsOf: payloadBytes)

    var packet = Data()
    packet.append(contentsOf: littleEndianBytes(streamPacketIndex << 8))
    packet.append(contentsOf: littleEndianBytes(frameIndex))
    packet.append(flags)
    packet.append(0x00) // extraFlags
    packet.append(0x10) // multiFecFlags
    packet.append(0x00) // multiFecBlocks (current block 0, last block 0)
    packet.append(contentsOf: littleEndianBytes(UInt32(0))) // fecInfo
    packet.append(packetPayload)
    return packet
}

private func moonlightFrameHeader(lastPayloadLength: UInt16) -> Data {
    var header = Data([0x01, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00])
    let lastPayloadLengthBytes = littleEndianBytes(lastPayloadLength)
    header[4] = lastPayloadLengthBytes[0]
    header[5] = lastPayloadLengthBytes[1]
    return header
}

private func littleEndianBytes<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
    let littleEndianValue = value.littleEndian
    return withUnsafeBytes(of: littleEndianValue) { Array($0) }
}
