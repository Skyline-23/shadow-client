import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Encrypted control codec writes Sunshine V2 envelope fields")
func sunshineEncryptedControlCodecEncodesEnvelope() throws {
    let codec = try ShadowClientHostControlEncryptionCodec(
        keyData: Data(repeating: 0x11, count: 16)
    )
    let packet = try codec.encryptControlMessage(
        type: 0x0302,
        payload: Data([0x00, 0x00]),
        sequence: 0x0102_0304
    )

    #expect(packet.count == 30)
    #expect(Array(packet[0 ... 1]) == [0x01, 0x00]) // encrypted header type
    #expect(Array(packet[2 ... 3]) == [0x1A, 0x00]) // length = 26 (LE)
    #expect(Array(packet[4 ... 7]) == [0x04, 0x03, 0x02, 0x01]) // sequence (LE)
}

@Test("Encrypted control codec decrypts host-originated V2 packet to V1 payload")
func sunshineEncryptedControlCodecDecryptsToV1Payload() throws {
    let codec = try ShadowClientHostControlEncryptionCodec(
        keyData: Data(repeating: 0x22, count: 16)
    )

    let hostEncryptedPacket = try codec.encryptControlMessage(
        type: 0x0307,
        payload: Data([0x00]),
        sequence: 7,
        sourceByte10: 0x48 // host-origin marker ('H')
    )
    let decrypted = try codec.decryptControlMessageToV1(hostEncryptedPacket)

    #expect(decrypted == Data([0x07, 0x03, 0x00]))
}

@Test("Encrypted control codec rejects invalid AES key length")
func sunshineEncryptedControlCodecRejectsInvalidKeyLength() {
    #expect(throws: ShadowClientHostControlEncryptionError.self) {
        _ = try ShadowClientHostControlEncryptionCodec(
            keyData: Data(repeating: 0x33, count: 8)
        )
    }
}
