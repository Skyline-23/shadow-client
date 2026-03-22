import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Wake-on-LAN kit normalizes MAC addresses and defaults to UDP 9")
func wakeOnLANKitNormalizesMACAndPort() {
    #expect(ShadowClientWakeOnLANKit.normalizedMACAddress("aa-bb-cc-dd-ee-ff") == "AA:BB:CC:DD:EE:FF")
    #expect(ShadowClientWakeOnLANKit.normalizedMACAddress("AABBCCDDEEFF") == "AA:BB:CC:DD:EE:FF")
    #expect(ShadowClientWakeOnLANKit.normalizedMACAddress("00:00:00:00:00:00") == nil)
    #expect(ShadowClientWakeOnLANKit.resolvedPort(from: nil) == 9)
    #expect(ShadowClientWakeOnLANKit.resolvedPort(from: "7") == 7)
}

@Test("Wake-on-LAN kit builds the standard 102-byte magic packet")
func wakeOnLANKitBuildsMagicPacket() throws {
    let macBytes = try #require(
        ShadowClientWakeOnLANKit.macBytes(from: "AA:BB:CC:DD:EE:FF")
    )
    let packet = ShadowClientWakeOnLANKit.magicPacket(for: macBytes)

    #expect(packet.count == 102)
    #expect(packet.prefix(6) == Data(repeating: 0xFF, count: 6))
    #expect(packet.suffix(6) == Data(macBytes))
}
