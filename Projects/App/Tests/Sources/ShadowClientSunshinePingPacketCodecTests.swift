import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Sunshine ping codec appends big-endian sequence after negotiated payload")
func sunshinePingCodecAppendsSequenceAfterPayload() {
    let payload = Data("3727B184C4E23026".utf8)
    let packets = ShadowClientHostPingPacketCodec.makePingPackets(
        sequence: 0x0102_0304,
        negotiatedPayload: payload
    )

    #expect(packets.count == 2)
    #expect(packets[0] == payload + Data([0x01, 0x02, 0x03, 0x04]))
    #expect(packets[1] == Data("PING".utf8))
}

@Test("Sunshine ping codec falls back to legacy ASCII ping when payload is absent")
func sunshinePingCodecFallsBackToLegacyAsciiPing() {
    let packets = ShadowClientHostPingPacketCodec.makePingPackets(
        sequence: 7,
        negotiatedPayload: nil
    )

    #expect(packets == [Data("PING".utf8)])
}
