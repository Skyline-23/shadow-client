import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Encrypted Host control mode uses IDR recovery request packet")
func hostEncryptedControlModeRecoveryRequestShape() {
    let mode = ShadowClientHostControlChannelMode.encryptedV2(
        key: Data(repeating: 0xAB, count: 16)
    )
    let request = mode.makeIDRRequest(lastSeenFrameIndex: 0x1234_5678)

    #expect(request.type == ShadowClientHostControlMessageProfile.startATypeEncryptedV2)
    #expect(request.channelID == ShadowClientHostControlMessageProfile.urgentChannelID)
    #expect(request.payload == Data([0x00, 0x00]))
}

@Test("Plaintext Host control mode uses reference frame invalidation payload")
func hostPlaintextControlModeRecoveryRequestShape() {
    let mode = ShadowClientHostControlChannelMode.plaintext
    let request = mode.makeIDRRequest(lastSeenFrameIndex: nil)

    #expect(request.type == ShadowClientHostControlMessageProfile.invalidateReferenceFramesType)
    #expect(request.channelID == ShadowClientHostControlMessageProfile.urgentChannelID)
    #expect(request.payload.count == 24)
    #expect(request.payload == Data(repeating: 0, count: 24))
}

@Test("Reference frame invalidation payload encodes frame range in little endian")
func hostInvalidateReferenceFramesPayloadEncodesFrameBounds() {
    let payload = ShadowClientHostControlMessageProfile.invalidateReferenceFramesPayload(
        firstFrame: 0x0506_0708,
        lastFrame: 0x1516_1718
    )

    #expect(payload.count == 24)
    #expect(readUInt32LE(payload, at: 0) == 0x0506_0708)
    #expect(readUInt32LE(payload, at: 4) == 0)
    #expect(readUInt32LE(payload, at: 8) == 0x1516_1718)
    #expect(readUInt32LE(payload, at: 12) == 0)
    #expect(readUInt32LE(payload, at: 16) == 0)
    #expect(readUInt32LE(payload, at: 20) == 0)
}

private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
    var value: UInt32 = 0
    for byteIndex in 0 ..< 4 {
        value |= UInt32(data[offset + byteIndex]) << UInt32(byteIndex * 8)
    }
    return value
}
