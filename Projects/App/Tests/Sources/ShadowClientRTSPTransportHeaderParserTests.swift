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
    let payload = ShadowClientRTSPTransportHeaderParser.parseHostPingPayload(from: nil)

    #expect(payload == nil)
}

@Test("Sunshine ping payload parser returns nil for empty value")
func sunshinePingPayloadParserReturnsNilForEmptyValue() {
    let payload = ShadowClientRTSPTransportHeaderParser.parseHostPingPayload(from: "   ")

    #expect(payload == nil)
}

@Test("Sunshine ping payload parser returns nil when payload length is not 16 bytes")
func sunshinePingPayloadParserReturnsNilForInvalidLength() {
    let payload = ShadowClientRTSPTransportHeaderParser.parseHostPingPayload(from: "123456789012345")

    #expect(payload == nil)
}

@Test("Sunshine ping payload parser accepts valid 16-byte payload")
func sunshinePingPayloadParserAcceptsValid16BytePayload() {
    let payload = ShadowClientRTSPTransportHeaderParser.parseHostPingPayload(from: "3727B184C4E23026")

    #expect(payload == Data("3727B184C4E23026".utf8))
}

@Test("Sunshine ping payload parser strips quotes around payload")
func sunshinePingPayloadParserStripsQuotesAroundPayload() {
    let payload = ShadowClientRTSPTransportHeaderParser.parseHostPingPayload(from: "\"3727B184C4E23026\"")

    #expect(payload == Data("3727B184C4E23026".utf8))
}

@Test("Sunshine ping payload parser ignores trailing parameters")
func sunshinePingPayloadParserIgnoresTrailingParameters() {
    let payload = ShadowClientRTSPTransportHeaderParser.parseHostPingPayload(from: "\"3727B184C4E23026;foo=bar\"")

    #expect(payload == Data("3727B184C4E23026".utf8))
}

@Test("Sunshine ping payload parser returns first 16-byte token")
func sunshinePingPayloadParserReturnsFirst16ByteToken() {
    let payload = ShadowClientRTSPTransportHeaderParser.parseHostPingPayload(
        from: "short-token 3727B184C4E23026 1111222233334444"
    )

    #expect(payload == Data("3727B184C4E23026".utf8))
}

@Test("Sunshine control connect-data parser returns nil for nil value")
func sunshineControlConnectDataParserReturnsNilForNilValue() {
    let value = ShadowClientRTSPTransportHeaderParser.parseHostControlConnectData(from: nil)

    #expect(value == nil)
}

@Test("Sunshine control connect-data parser parses decimal value")
func sunshineControlConnectDataParserParsesDecimalValue() {
    let value = ShadowClientRTSPTransportHeaderParser.parseHostControlConnectData(from: "305419896")

    #expect(value == 305_419_896)
}

@Test("Sunshine control connect-data parser parses hex value")
func sunshineControlConnectDataParserParsesHexValue() {
    let value = ShadowClientRTSPTransportHeaderParser.parseHostControlConnectData(from: "0x12345678")

    #expect(value == 0x12345678)
}

@Test("Sunshine control connect-data parser parses quoted hex value with trailing parameters")
func sunshineControlConnectDataParserParsesQuotedHexValueWithTrailingParameters() {
    let value = ShadowClientRTSPTransportHeaderParser.parseHostControlConnectData(from: "\"0x2A\";foo=bar")

    #expect(value == 42)
}

@Test("Sunshine control connect-data parser returns nil for malformed values")
func sunshineControlConnectDataParserReturnsNilForMalformedValues() {
    let value = ShadowClientRTSPTransportHeaderParser.parseHostControlConnectData(from: "not-a-number")

    #expect(value == nil)
}
