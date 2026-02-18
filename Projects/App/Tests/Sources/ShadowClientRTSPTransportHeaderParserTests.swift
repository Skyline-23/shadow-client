import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("RTSP transport parser parses single server port")
func rtspTransportParserParsesSingleServerPort() {
    let header = "unicast;server_port=47998;source=192.168.0.12"

    let port = ShadowClientRTSPTransportHeaderParser.parseServerPort(from: header)

    #expect(port == 47_998)
}

@Test("RTSP transport parser returns nil when server port is missing")
func rtspTransportParserReturnsNilWhenServerPortIsMissing() {
    let header = "RTP/AVP/TCP;unicast;interleaved=0-1"

    let port = ShadowClientRTSPTransportHeaderParser.parseServerPort(from: header)

    #expect(port == nil)
}

@Test("RTSP transport parser returns nil for malformed server port")
func rtspTransportParserReturnsNilForMalformedServerPort() {
    let header = "unicast;server_port=abc-47999;source=192.168.0.12"

    let port = ShadowClientRTSPTransportHeaderParser.parseServerPort(from: header)

    #expect(port == nil)
}

@Test("RTSP transport parser parses first port from server port range")
func rtspTransportParserParsesFirstPortFromServerPortRange() {
    let header = "unicast;server_port=47998-47999;source=192.168.0.12"

    let port = ShadowClientRTSPTransportHeaderParser.parseServerPort(from: header)

    #expect(port == 47_998)
}

@Test("Sunshine ping payload parser returns nil for nil value")
func sunshinePingPayloadParserReturnsNilForNilValue() {
    let payload = ShadowClientRTSPTransportHeaderParser.parseSunshinePingPayload(from: nil)

    #expect(payload == nil)
}

@Test("Sunshine ping payload parser returns nil for empty value")
func sunshinePingPayloadParserReturnsNilForEmptyValue() {
    let payload = ShadowClientRTSPTransportHeaderParser.parseSunshinePingPayload(from: "   ")

    #expect(payload == nil)
}

@Test("Sunshine ping payload parser returns nil when payload length is not 16 bytes")
func sunshinePingPayloadParserReturnsNilForInvalidLength() {
    let payload = ShadowClientRTSPTransportHeaderParser.parseSunshinePingPayload(from: "123456789012345")

    #expect(payload == nil)
}

@Test("Sunshine ping payload parser accepts valid 16-byte payload")
func sunshinePingPayloadParserAcceptsValid16BytePayload() {
    let payload = ShadowClientRTSPTransportHeaderParser.parseSunshinePingPayload(from: "3727B184C4E23026")

    #expect(payload == Data("3727B184C4E23026".utf8))
}
