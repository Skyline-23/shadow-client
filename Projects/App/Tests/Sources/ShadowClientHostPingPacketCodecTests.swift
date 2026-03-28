import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Host ping codec emits strict v2 packet when negotiated payload exists")
func hostPingCodecAppendsSequenceAfterPayload() {
    let payload = Data("3727B184C4E23026".utf8)
    let packets = ShadowClientHostPingPacketCodec.makePingPackets(
        sequence: 0x0102_0304,
        negotiatedPayload: payload
    )

    #expect(packets.count == 1)
    #expect(packets[0] == payload + Data([0x01, 0x02, 0x03, 0x04]))
}

@Test("Host ping codec emits no packets when payload is absent")
func hostPingCodecSkipsPingWithoutNegotiatedPayload() {
    let packets = ShadowClientHostPingPacketCodec.makePingPackets(
        sequence: 7,
        negotiatedPayload: nil
    )

    #expect(packets.isEmpty)
}
