import Foundation

enum ShadowClientSunshineInputPacketCodec {
    struct EncodedInputPacket: Sendable {
        let channelID: UInt8
        let payload: Data
    }

    private enum Channel {
        static let keyboard: UInt8 = ShadowClientSunshineControlMessageProfile.keyboardChannelID
        static let mouse: UInt8 = ShadowClientSunshineControlMessageProfile.mouseChannelID
        static let gamepadBase: UInt8 = ShadowClientSunshineControlMessageProfile.gamepadChannelBaseID
    }

    private enum PacketMagic {
        static let keyDown: UInt32 = 0x0000_0003
        static let keyUp: UInt32 = 0x0000_0004
        static let mouseMoveRelative: UInt32 = 0x0000_0007
        static let mouseButtonDown: UInt32 = 0x0000_0008
        static let mouseButtonUp: UInt32 = 0x0000_0009
        static let scroll: UInt32 = 0x0000_000A
        static let multiControllerGen5: UInt32 = 0x0000_000C
        static let controllerArrival: UInt32 = 0x5500_0004
    }

    private enum MultiControllerPacket {
        static let headerB: UInt16 = 0x001A
        static let midB: UInt16 = 0x0014
        static let tailA: UInt16 = 0x009C
        static let tailB: UInt16 = 0x0055
    }

    private enum ControllerArrivalPacket {
        static let typePlayStation: UInt8 = 0x02
        static let capabilityAnalogTriggers: UInt16 = 0x01
        static let capabilityRumble: UInt16 = 0x02
        static let defaultCapabilities: UInt16 = capabilityAnalogTriggers | capabilityRumble
    }

    private enum MouseButton {
        static let left: UInt8 = 0x01
        static let middle: UInt8 = 0x02
        static let right: UInt8 = 0x03
    }

    static func encode(_ event: ShadowClientRemoteInputEvent) -> EncodedInputPacket? {
        switch event {
        case let .keyDown(keyCode, characters):
            guard let virtualKey = windowsVirtualKeyCode(
                macKeyCode: keyCode,
                characters: characters
            ) else {
                return nil
            }
            return .init(
                channelID: Channel.keyboard,
                payload: makeKeyboardPacket(
                    magic: PacketMagic.keyDown,
                    virtualKey: normalizedSunshineKeyboardKeyCode(virtualKey)
                )
            )
        case let .keyUp(keyCode, characters):
            guard let virtualKey = windowsVirtualKeyCode(
                macKeyCode: keyCode,
                characters: characters
            ) else {
                return nil
            }
            return .init(
                channelID: Channel.keyboard,
                payload: makeKeyboardPacket(
                    magic: PacketMagic.keyUp,
                    virtualKey: normalizedSunshineKeyboardKeyCode(virtualKey)
                )
            )
        case let .pointerButton(button, isPressed):
            guard let mappedButton = mouseButtonValue(button) else {
                return nil
            }
            return .init(
                channelID: Channel.mouse,
                payload: makeMouseButtonPacket(
                    magic: isPressed ? PacketMagic.mouseButtonDown : PacketMagic.mouseButtonUp,
                    button: mappedButton
                )
            )
        case let .pointerMoved(x, y):
            let deltaX = normalizedMouseDelta(x)
            let deltaY = normalizedMouseDelta(y)
            guard deltaX != 0 || deltaY != 0 else {
                return nil
            }
            return .init(
                channelID: Channel.mouse,
                payload: makeRelativeMouseMovePacket(
                    deltaX: deltaX,
                    deltaY: deltaY
                )
            )
        case let .scroll(_, deltaY):
            let scrollAmount = normalizedScrollAmount(deltaY)
            guard scrollAmount != 0 else {
                return nil
            }
            return .init(
                channelID: Channel.mouse,
                payload: makeScrollPacket(scrollAmount: scrollAmount)
            )
        case let .gamepadState(state):
            return .init(
                channelID: gamepadChannelID(for: state.controllerNumber),
                payload: makeMultiControllerPacket(state)
            )
        case let .gamepadArrival(arrival):
            return .init(
                channelID: gamepadChannelID(for: arrival.controllerNumber),
                payload: makeControllerArrivalPacket(arrival)
            )
        }
    }

    private static func makeKeyboardPacket(
        magic: UInt32,
        virtualKey: UInt16,
        modifiers: UInt8 = 0,
        flags: UInt8 = 0
    ) -> Data {
        var packet = Data()
        packet.reserveCapacity(14)
        appendUInt32BE(10, to: &packet) // sizeof(NV_KEYBOARD_PACKET) - sizeof(size field)
        appendUInt32LE(magic, to: &packet)
        packet.append(flags)
        appendUInt16LE(virtualKey, to: &packet)
        packet.append(modifiers)
        appendUInt16LE(0, to: &packet)
        return packet
    }

    private static func makeMouseButtonPacket(
        magic: UInt32,
        button: UInt8
    ) -> Data {
        var packet = Data()
        packet.reserveCapacity(9)
        appendUInt32BE(5, to: &packet) // sizeof(NV_MOUSE_BUTTON_PACKET) - sizeof(size field)
        appendUInt32LE(magic, to: &packet)
        packet.append(button)
        return packet
    }

    private static func makeRelativeMouseMovePacket(
        deltaX: Int16,
        deltaY: Int16
    ) -> Data {
        var packet = Data()
        packet.reserveCapacity(12)
        appendUInt32BE(8, to: &packet) // sizeof(NV_REL_MOUSE_MOVE_PACKET) - sizeof(size field)
        appendUInt32LE(PacketMagic.mouseMoveRelative, to: &packet)
        appendInt16BE(deltaX, to: &packet)
        appendInt16BE(deltaY, to: &packet)
        return packet
    }

    private static func makeScrollPacket(scrollAmount: Int16) -> Data {
        var packet = Data()
        packet.reserveCapacity(14)
        appendUInt32BE(10, to: &packet) // sizeof(NV_SCROLL_PACKET) - sizeof(size field)
        appendUInt32LE(PacketMagic.scroll, to: &packet)
        appendInt16BE(scrollAmount, to: &packet)
        appendInt16BE(scrollAmount, to: &packet)
        appendInt16BE(0, to: &packet)
        return packet
    }

    private static func makeMultiControllerPacket(_ state: ShadowClientRemoteGamepadState) -> Data {
        var packet = Data()
        packet.reserveCapacity(34)
        appendUInt32BE(30, to: &packet) // sizeof(NV_MULTI_CONTROLLER_PACKET) - sizeof(size field)
        appendUInt32LE(PacketMagic.multiControllerGen5, to: &packet)
        appendUInt16LE(MultiControllerPacket.headerB, to: &packet)
        appendUInt16LE(UInt16(state.controllerNumber), to: &packet)
        appendUInt16LE(state.activeGamepadMask, to: &packet)
        appendUInt16LE(MultiControllerPacket.midB, to: &packet)
        appendUInt16LE(UInt16(truncatingIfNeeded: state.buttonFlags), to: &packet)
        packet.append(state.leftTrigger)
        packet.append(state.rightTrigger)
        appendInt16LE(state.leftStickX, to: &packet)
        appendInt16LE(state.leftStickY, to: &packet)
        appendInt16LE(state.rightStickX, to: &packet)
        appendInt16LE(state.rightStickY, to: &packet)
        appendUInt16LE(MultiControllerPacket.tailA, to: &packet)
        appendUInt16LE(UInt16(truncatingIfNeeded: state.buttonFlags >> 16), to: &packet)
        appendUInt16LE(MultiControllerPacket.tailB, to: &packet)
        return packet
    }

    private static func makeControllerArrivalPacket(_ arrival: ShadowClientRemoteGamepadArrival) -> Data {
        var packet = Data()
        packet.reserveCapacity(16)
        appendUInt32BE(12, to: &packet) // sizeof(SS_CONTROLLER_ARRIVAL_PACKET) - sizeof(size field)
        appendUInt32LE(PacketMagic.controllerArrival, to: &packet)
        packet.append(arrival.controllerNumber)
        packet.append(arrival.type)
        appendUInt16LE(arrival.capabilities, to: &packet)
        appendUInt32LE(arrival.supportedButtonFlags, to: &packet)
        return packet
    }

    static func defaultGamepadArrival(
        controllerNumber: UInt8,
        activeGamepadMask: UInt16,
        supportedButtonFlags: UInt32
    ) -> ShadowClientRemoteGamepadArrival {
        ShadowClientRemoteGamepadArrival(
            controllerNumber: controllerNumber,
            activeGamepadMask: activeGamepadMask,
            type: ControllerArrivalPacket.typePlayStation,
            capabilities: ControllerArrivalPacket.defaultCapabilities,
            supportedButtonFlags: supportedButtonFlags
        )
    }

    private static func gamepadChannelID(for controllerNumber: UInt8) -> UInt8 {
        let clampedIndex = min(controllerNumber, 0x0F)
        return Channel.gamepadBase &+ clampedIndex
    }

    private static func normalizedScrollAmount(_ delta: Double) -> Int16 {
        if delta == 0 {
            return 0
        }

        let scaled = Int((delta * 120).rounded())
        if scaled == 0 {
            return delta > 0 ? 120 : -120
        }
        return Int16(clamping: scaled)
    }

    private static func normalizedMouseDelta(_ delta: Double) -> Int16 {
        if delta == 0 {
            return 0
        }

        let rounded = Int(delta.rounded())
        if rounded == 0 {
            return delta > 0 ? 1 : -1
        }
        return Int16(clamping: rounded)
    }

    private static func normalizedSunshineKeyboardKeyCode(_ virtualKey: UInt16) -> UInt16 {
        // Moonlight sets the high bit for Sunshine keyboard input to match
        // the server-side scancode normalization path.
        0x8000 | virtualKey
    }

    private static func mouseButtonValue(_ button: ShadowClientRemoteMouseButton) -> UInt8? {
        switch button {
        case .left:
            return MouseButton.left
        case .middle:
            return MouseButton.middle
        case .right:
            return MouseButton.right
        case .other:
            return nil
        }
    }

    private static let macKeyCodeToWindowsVirtualKey: [UInt16: UInt16] = [
        0x00: 0x41, // A
        0x01: 0x53, // S
        0x02: 0x44, // D
        0x03: 0x46, // F
        0x04: 0x48, // H
        0x05: 0x47, // G
        0x06: 0x5A, // Z
        0x07: 0x58, // X
        0x08: 0x43, // C
        0x09: 0x56, // V
        0x0A: 0xE2, // ISO Section / Non-US backslash
        0x0B: 0x42, // B
        0x0C: 0x51, // Q
        0x0D: 0x57, // W
        0x0E: 0x45, // E
        0x0F: 0x52, // R
        0x10: 0x59, // Y
        0x11: 0x54, // T
        0x12: 0x31, // 1
        0x13: 0x32, // 2
        0x14: 0x33, // 3
        0x15: 0x34, // 4
        0x16: 0x36, // 6
        0x17: 0x35, // 5
        0x18: 0xBB, // =
        0x19: 0x39, // 9
        0x1A: 0x37, // 7
        0x1B: 0xBD, // -
        0x1C: 0x38, // 8
        0x1D: 0x30, // 0
        0x1E: 0xDD, // ]
        0x1F: 0x4F, // O
        0x20: 0x55, // U
        0x21: 0xDB, // [
        0x22: 0x49, // I
        0x23: 0x50, // P
        0x24: 0x0D, // Return
        0x25: 0x4C, // L
        0x26: 0x4A, // J
        0x27: 0xDE, // '
        0x28: 0x4B, // K
        0x29: 0xBA, // ;
        0x2A: 0xDC, // \
        0x2B: 0xBC, // ,
        0x2C: 0xBF, // /
        0x2D: 0x4E, // N
        0x2E: 0x4D, // M
        0x2F: 0xBE, // .
        0x30: 0x09, // Tab
        0x31: 0x20, // Space
        0x32: 0xC0, // `
        0x33: 0x08, // Backspace
        0x34: 0x0D, // Keypad Enter
        0x35: 0x1B, // Escape
        0x36: 0x5C, // Right Command
        0x37: 0x5B, // Left Command
        0x38: 0xA0, // Left Shift
        0x39: 0x14, // Caps Lock
        0x3A: 0xA4, // Left Option
        0x3B: 0xA2, // Left Control
        0x3C: 0xA1, // Right Shift
        0x3D: 0xA5, // Right Option
        0x3E: 0xA3, // Right Control
        0x41: 0x6E, // Keypad .
        0x43: 0x6A, // Keypad *
        0x45: 0x6B, // Keypad +
        0x47: 0x0C, // Keypad Clear
        0x4B: 0x6F, // Keypad /
        0x4C: 0x0D, // Keypad Enter
        0x4E: 0x6D, // Keypad -
        0x51: 0x6C, // Keypad =
        0x52: 0x60, // Keypad 0
        0x53: 0x61, // Keypad 1
        0x54: 0x62, // Keypad 2
        0x55: 0x63, // Keypad 3
        0x56: 0x64, // Keypad 4
        0x57: 0x65, // Keypad 5
        0x58: 0x66, // Keypad 6
        0x59: 0x67, // Keypad 7
        0x5B: 0x68, // Keypad 8
        0x5C: 0x69, // Keypad 9
        0x7A: 0x70, // F1
        0x78: 0x71, // F2
        0x63: 0x72, // F3
        0x76: 0x73, // F4
        0x60: 0x74, // F5
        0x61: 0x75, // F6
        0x62: 0x76, // F7
        0x64: 0x77, // F8
        0x65: 0x78, // F9
        0x6D: 0x79, // F10
        0x67: 0x7A, // F11
        0x6F: 0x7B, // F12
        0x72: 0x2D, // Insert/Help
        0x73: 0x24, // Home
        0x74: 0x21, // Page Up
        0x75: 0x2E, // Forward Delete
        0x77: 0x23, // End
        0x79: 0x22, // Page Down
        0x7B: 0x25, // Left Arrow
        0x7C: 0x27, // Right Arrow
        0x7D: 0x28, // Down Arrow
        0x7E: 0x26, // Up Arrow
    ]

    private static let characterToWindowsVirtualKey: [Character: UInt16] = [
        " ": 0x20,
        "-": 0xBD,
        "=": 0xBB,
        "[": 0xDB,
        "]": 0xDD,
        "\\": 0xDC,
        ";": 0xBA,
        "'": 0xDE,
        ",": 0xBC,
        ".": 0xBE,
        "/": 0xBF,
        "`": 0xC0,
    ]

    private static func windowsVirtualKeyCode(
        macKeyCode: UInt16,
        characters: String?
    ) -> UInt16? {
        if macKeyCode != ShadowClientRemoteInputEvent.softwareKeyboardSyntheticKeyCode,
           let mapped = macKeyCodeToWindowsVirtualKey[macKeyCode]
        {
            return mapped
        }

        guard let characters,
              let scalar = characters.unicodeScalars.first
        else {
            return nil
        }

        if scalar.value == 0xF700 { return 0x26 } // Up arrow
        if scalar.value == 0xF701 { return 0x28 } // Down arrow
        if scalar.value == 0xF702 { return 0x25 } // Left arrow
        if scalar.value == 0xF703 { return 0x27 } // Right arrow
        if scalar.value == 0x0D { return 0x0D } // Return
        if scalar.value == 0x09 { return 0x09 } // Tab
        if scalar.value == 0x08 || scalar.value == 0x7F { return 0x08 } // Backspace/Delete
        if scalar.value == 0x1B { return 0x1B } // Escape

        if scalar.isASCII {
            let ascii = UInt8(scalar.value)
            if ascii >= 0x61, ascii <= 0x7A { // a-z
                return UInt16(ascii - 0x20) // A-Z
            }
            if ascii >= 0x41, ascii <= 0x5A { // A-Z
                return UInt16(ascii)
            }
            if ascii >= 0x30, ascii <= 0x39 { // 0-9
                return UInt16(ascii)
            }
            if let mapped = characterToWindowsVirtualKey[Character(UnicodeScalar(ascii))] {
                return mapped
            }
        }

        return nil
    }

    private static func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) {
            data.append(contentsOf: $0)
        }
    }

    private static func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) {
            data.append(contentsOf: $0)
        }
    }

    private static func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        var bigEndianValue = value.bigEndian
        withUnsafeBytes(of: &bigEndianValue) {
            data.append(contentsOf: $0)
        }
    }

    private static func appendInt16BE(_ value: Int16, to data: inout Data) {
        var bigEndianValue = value.bigEndian
        withUnsafeBytes(of: &bigEndianValue) {
            data.append(contentsOf: $0)
        }
    }

    private static func appendInt16LE(_ value: Int16, to data: inout Data) {
        var littleEndianValue = value.littleEndian
        withUnsafeBytes(of: &littleEndianValue) {
            data.append(contentsOf: $0)
        }
    }
}
