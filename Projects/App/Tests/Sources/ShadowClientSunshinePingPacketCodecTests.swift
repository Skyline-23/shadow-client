import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Sunshine ping codec appends big-endian sequence after negotiated payload")
func sunshinePingCodecAppendsSequenceAfterPayload() {
    let payload = Data("3727B184C4E23026".utf8)
    let packets = ShadowClientSunshinePingPacketCodec.makePingPackets(
        sequence: 0x0102_0304,
        negotiatedPayload: payload
    )

    #expect(packets.count == 1)
    #expect(packets[0] == payload + Data([0x01, 0x02, 0x03, 0x04]))
}

@Test("Sunshine ping codec falls back to legacy ASCII ping when payload is absent")
func sunshinePingCodecFallsBackToLegacyAsciiPing() {
    let packets = ShadowClientSunshinePingPacketCodec.makePingPackets(
        sequence: 7,
        negotiatedPayload: nil
    )

    #expect(packets == [Data("PING".utf8)])
}
