import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Sunshine input codec encodes keyboard keyDown packet")
func sunshineInputCodecEncodesKeyboardKeyDownPacket() {
    let encoded = ShadowClientSunshineInputPacketCodec.encode(
        .keyDown(keyCode: 13, characters: "w")
    )

    #expect(encoded != nil)
    #expect(encoded?.channelID == 0x02)

    guard let payload = encoded?.payload else {
        Issue.record("Expected keyboard payload")
        return
    }

    #expect(payload.count == 14)
    #expect(readUInt32BE(payload, at: 0) == 10)
    #expect(readUInt32LE(payload, at: 4) == 0x0000_0003)
    #expect(payload[8] == 0)
    #expect(readUInt16LE(payload, at: 9) == 0x8057)
    #expect(payload[11] == 0)
    #expect(readUInt16LE(payload, at: 12) == 0)
}

@Test("Sunshine input codec maps mac key code to US virtual key regardless of composed characters")
func sunshineInputCodecMapsMacKeyCodeIndependentlyOfKeyboardLayoutCharacters() {
    let encoded = ShadowClientSunshineInputPacketCodec.encode(
        .keyDown(keyCode: 0x0D, characters: "ㅈ")
    )

    #expect(encoded != nil)
    guard let payload = encoded?.payload else {
        Issue.record("Expected keyboard payload")
        return
    }

    #expect(readUInt16LE(payload, at: 9) == 0x8057)
}

@Test("Sunshine input codec uses character mapping for software keyboard synthetic key code")
func sunshineInputCodecUsesCharacterMappingForSoftwareKeyboardSyntheticKeyCode() {
    let encoded = ShadowClientSunshineInputPacketCodec.encode(
        .keyDown(
            keyCode: ShadowClientRemoteInputEvent.softwareKeyboardSyntheticKeyCode,
            characters: "1"
        )
    )

    #expect(encoded != nil)
    guard let payload = encoded?.payload else {
        Issue.record("Expected keyboard payload")
        return
    }

    #expect(readUInt16LE(payload, at: 9) == 0x8031)
}

@Test("Sunshine input codec encodes mouse button packet")
func sunshineInputCodecEncodesMouseButtonPacket() {
    let encoded = ShadowClientSunshineInputPacketCodec.encode(
        .pointerButton(button: .left, isPressed: true)
    )

    #expect(encoded != nil)
    #expect(encoded?.channelID == 0x03)

    guard let payload = encoded?.payload else {
        Issue.record("Expected mouse button payload")
        return
    }

    #expect(payload.count == 9)
    #expect(readUInt32BE(payload, at: 0) == 5)
    #expect(readUInt32LE(payload, at: 4) == 0x0000_0008)
    #expect(payload[8] == 0x01)
}

@Test("Sunshine input codec encodes relative mouse move packet")
func sunshineInputCodecEncodesRelativeMouseMovePacket() {
    let encoded = ShadowClientSunshineInputPacketCodec.encode(
        .pointerMoved(x: 2.4, y: -3.2)
    )

    #expect(encoded != nil)
    #expect(encoded?.channelID == 0x03)

    guard let payload = encoded?.payload else {
        Issue.record("Expected relative mouse move payload")
        return
    }

    #expect(payload.count == 12)
    #expect(readUInt32BE(payload, at: 0) == 8)
    #expect(readUInt32LE(payload, at: 4) == 0x0000_0007)
    #expect(readInt16BE(payload, at: 8) == 2)
    #expect(readInt16BE(payload, at: 10) == -3)
}

@Test("Sunshine input codec drops zero-delta relative mouse move packet")
func sunshineInputCodecDropsZeroDeltaRelativeMouseMovePacket() {
    let encoded = ShadowClientSunshineInputPacketCodec.encode(
        .pointerMoved(x: 0, y: 0)
    )

    #expect(encoded == nil)
}

@Test("Sunshine input codec encodes vertical scroll packet")
func sunshineInputCodecEncodesScrollPacket() {
    let encoded = ShadowClientSunshineInputPacketCodec.encode(
        .scroll(deltaX: 0, deltaY: 1)
    )

    #expect(encoded != nil)
    #expect(encoded?.channelID == 0x03)

    guard let payload = encoded?.payload else {
        Issue.record("Expected scroll payload")
        return
    }

    #expect(payload.count == 14)
    #expect(readUInt32BE(payload, at: 0) == 10)
    #expect(readUInt32LE(payload, at: 4) == 0x0000_000A)
    #expect(readInt16BE(payload, at: 8) == 120)
    #expect(readInt16BE(payload, at: 10) == 120)
}

@Test("Sunshine input codec drops unknown key event")
func sunshineInputCodecDropsUnknownKeyEvent() {
    let encoded = ShadowClientSunshineInputPacketCodec.encode(
        .keyDown(keyCode: 0x0A0A, characters: nil)
    )

    #expect(encoded == nil)
}

@Test("Sunshine input codec encodes multi-controller gamepad packet on gamepad channel")
func sunshineInputCodecEncodesGamepadStatePacket() {
    let state = ShadowClientRemoteGamepadState(
        controllerNumber: 1,
        activeGamepadMask: 0x0003,
        buttonFlags: 0x0023_1245,
        leftTrigger: 0x33,
        rightTrigger: 0x44,
        leftStickX: 1234,
        leftStickY: -2345,
        rightStickX: 3456,
        rightStickY: -4567
    )

    let encoded = ShadowClientSunshineInputPacketCodec.encode(.gamepadState(state))

    #expect(encoded != nil)
    #expect(encoded?.channelID == 0x11)

    guard let payload = encoded?.payload else {
        Issue.record("Expected gamepad payload")
        return
    }

    #expect(payload.count == 34)
    #expect(readUInt32BE(payload, at: 0) == 30)
    #expect(readUInt32LE(payload, at: 4) == 0x0000_000C)
    #expect(readUInt16LE(payload, at: 8) == 0x001A)
    #expect(readUInt16LE(payload, at: 10) == 1)
    #expect(readUInt16LE(payload, at: 12) == 0x0003)
    #expect(readUInt16LE(payload, at: 14) == 0x0014)
    #expect(readUInt16LE(payload, at: 16) == 0x1245)
    #expect(payload[18] == 0x33)
    #expect(payload[19] == 0x44)
    #expect(readInt16LE(payload, at: 20) == 1234)
    #expect(readInt16LE(payload, at: 22) == -2345)
    #expect(readInt16LE(payload, at: 24) == 3456)
    #expect(readInt16LE(payload, at: 26) == -4567)
    #expect(readUInt16LE(payload, at: 28) == 0x009C)
    #expect(readUInt16LE(payload, at: 30) == 0x0023)
    #expect(readUInt16LE(payload, at: 32) == 0x0055)
}

@Test("Sunshine input codec encodes gamepad arrival packet")
func sunshineInputCodecEncodesGamepadArrivalPacket() {
    let arrival = ShadowClientRemoteGamepadArrival(
        controllerNumber: 2,
        activeGamepadMask: 0x0007,
        type: 0x02,
        capabilities: 0x0001,
        supportedButtonFlags: 0x0001_FF3F
    )

    let encoded = ShadowClientSunshineInputPacketCodec.encode(.gamepadArrival(arrival))

    #expect(encoded != nil)
    #expect(encoded?.channelID == 0x12)

    guard let payload = encoded?.payload else {
        Issue.record("Expected gamepad arrival payload")
        return
    }

    #expect(payload.count == 16)
    #expect(readUInt32BE(payload, at: 0) == 12)
    #expect(readUInt32LE(payload, at: 4) == 0x5500_0004)
    #expect(payload[8] == 0x02)
    #expect(payload[9] == 0x02)
    #expect(readUInt16LE(payload, at: 10) == 0x0001)
    #expect(readUInt32LE(payload, at: 12) == 0x0001_FF3F)
}

@Test("Sunshine input codec default gamepad arrival advertises analog triggers with rumble and trigger rumble")
func sunshineInputCodecDefaultGamepadArrivalAdvertisesRumble() {
    let arrival = ShadowClientSunshineInputPacketCodec.defaultGamepadArrival(
        controllerNumber: 0,
        activeGamepadMask: 0x0001,
        supportedButtonFlags: 0x0000_FFFF
    )

    #expect(arrival.type == 0x02)
    #expect(arrival.capabilities == 0x0007)
}

private func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
    let b0 = UInt16(data[offset])
    let b1 = UInt16(data[offset + 1]) << 8
    return b0 | b1
}

private func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
    let b0 = UInt32(data[offset])
    let b1 = UInt32(data[offset + 1]) << 8
    let b2 = UInt32(data[offset + 2]) << 16
    let b3 = UInt32(data[offset + 3]) << 24
    return b0 | b1 | b2 | b3
}

private func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
    let b0 = UInt32(data[offset]) << 24
    let b1 = UInt32(data[offset + 1]) << 16
    let b2 = UInt32(data[offset + 2]) << 8
    let b3 = UInt32(data[offset + 3])
    return b0 | b1 | b2 | b3
}

private func readInt16BE(_ data: Data, at offset: Int) -> Int16 {
    let upper = UInt16(data[offset]) << 8
    let lower = UInt16(data[offset + 1])
    return Int16(bitPattern: upper | lower)
}

private func readInt16LE(_ data: Data, at offset: Int) -> Int16 {
    let lower = UInt16(data[offset])
    let upper = UInt16(data[offset + 1]) << 8
    return Int16(bitPattern: upper | lower)
}
