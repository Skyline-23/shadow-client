import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Encrypted RTSP codec writes big-endian Lumen envelope fields")
func encryptedRTSPCodecEncodesEnvelope() throws {
    let codec = try ShadowClientRTSPEncryptionCodec(
        keyData: Data(repeating: 0x11, count: 16)
    )

    let packet = try codec.encryptClientRTSPMessage(
        Data("OPTIONS rtsp://host/ RTSP/1.0\r\n\r\n".utf8),
        sequence: 0x0102_0304
    )

    #expect(Array(packet[0...3]) == [0x80, 0x00, 0x00, 0x1F])
    #expect(Array(packet[4...7]) == [0x01, 0x02, 0x03, 0x04])
    #expect(packet.count == ShadowClientRTSPEncryptionCodec.headerLength + 31)
}

@Test("Encrypted RTSP codec decrypts host-originated packets")
func encryptedRTSPCodecDecryptsHostPacket() throws {
    let codec = try ShadowClientRTSPEncryptionCodec(
        keyData: Data(repeating: 0x22, count: 16)
    )
    let plaintext = Data("RTSP/1.0 200 OK\r\nCSeq: 1\r\n\r\n".utf8)

    let packet = try codec.encryptClientRTSPMessage(
        plaintext,
        sequence: 7,
        sourceByte10: 0x48
    )
    let tag = Data(packet[8..<ShadowClientRTSPEncryptionCodec.headerLength])
    let ciphertext = Data(packet[ShadowClientRTSPEncryptionCodec.headerLength...])

    let decrypted = try codec.decryptHostRTSPMessage(
        sequence: 7,
        tag: tag,
        ciphertext: ciphertext
    )

    #expect(decrypted == plaintext)
}

@Test("RTSP profile accepts encrypted RTSP scheme")
func rtspProfileAcceptsEncryptedScheme() {
    #expect(
        ShadowClientRTSPProtocolProfile.hasAbsoluteRTSPScheme(
            "rtspenc://192.168.0.50:49010"
        )
    )
}
