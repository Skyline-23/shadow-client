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
