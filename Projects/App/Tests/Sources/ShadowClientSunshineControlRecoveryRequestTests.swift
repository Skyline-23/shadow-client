import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Encrypted Sunshine control mode uses IDR recovery request packet")
func sunshineEncryptedControlModeRecoveryRequestShape() {
    let mode = ShadowClientSunshineControlChannelMode.encryptedV2(
        key: Data(repeating: 0xAB, count: 16)
    )

    #expect(mode.recoveryRequestType == ShadowClientSunshineControlMessageProfile.startATypeEncryptedV2)
    #expect(mode.recoveryRequestChannelID == ShadowClientSunshineControlMessageProfile.urgentChannelID)
    #expect(mode.recoveryRequestPayload == Data([0x00, 0x00]))
}

@Test("Plaintext Sunshine control mode uses reference frame invalidation payload")
func sunshinePlaintextControlModeRecoveryRequestShape() {
    let mode = ShadowClientSunshineControlChannelMode.plaintext

    #expect(mode.recoveryRequestType == ShadowClientSunshineControlMessageProfile.invalidateReferenceFramesType)
    #expect(mode.recoveryRequestChannelID == ShadowClientSunshineControlMessageProfile.urgentChannelID)
    #expect(mode.recoveryRequestPayload.count == 24)
    #expect(mode.recoveryRequestPayload == Data(repeating: 0, count: 24))
}

@Test("Reference frame invalidation payload encodes frame range in little endian")
func sunshineInvalidateReferenceFramesPayloadEncodesFrameBounds() {
    let payload = ShadowClientSunshineControlMessageProfile.invalidateReferenceFramesPayload(
        firstFrame: 0x0102_0304_0506_0708,
        lastFrame: 0x1112_1314_1516_1718
    )

    #expect(payload.count == 24)
    #expect(readUInt64LE(payload, at: 0) == 0x0102_0304_0506_0708)
    #expect(readUInt64LE(payload, at: 8) == 0x1112_1314_1516_1718)
    #expect(readUInt64LE(payload, at: 16) == 0)
}

private func readUInt64LE(_ data: Data, at offset: Int) -> UInt64 {
    var value: UInt64 = 0
    for byteIndex in 0 ..< 8 {
        value |= UInt64(data[offset + byteIndex]) << UInt64(byteIndex * 8)
    }
    return value
}
