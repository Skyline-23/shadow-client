import Foundation

enum ShadowClientSunshineInputPacketCodec {
    struct EncodedInputPacket: Sendable {
        let channelID: UInt8
        let payload: Data
    }

    private enum Channel {
        static let keyboard: UInt8 = ShadowClientSunshineControlMessageProfile.keyboardChannelID
        static let mouse: UInt8 = ShadowClientSunshineControlMessageProfile.mouseChannelID
    }

    private enum PacketMagic {
        static let keyDown: UInt32 = 0x0000_0003
        static let keyUp: UInt32 = 0x0000_0004
        static let mouseButtonDown: UInt32 = 0x0000_0008
        static let mouseButtonUp: UInt32 = 0x0000_0009
        static let scroll: UInt32 = 0x0000_000A
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
                    virtualKey: virtualKey
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
                    virtualKey: virtualKey
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
        case .pointerMoved:
            return nil
        case let .scroll(_, deltaY):
            let scrollAmount = normalizedScrollAmount(deltaY)
            guard scrollAmount != 0 else {
                return nil
            }
            return .init(
                channelID: Channel.mouse,
                payload: makeScrollPacket(scrollAmount: scrollAmount)
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
        0x24: 0x0D, // Return
        0x30: 0x09, // Tab
        0x31: 0x20, // Space
        0x33: 0x08, // Backspace
        0x35: 0x1B, // Escape
        0x37: 0x5B, // Left Command
        0x38: 0xA0, // Left Shift
        0x39: 0x14, // Caps Lock
        0x3A: 0xA4, // Left Option
        0x3B: 0xA2, // Left Control
        0x3C: 0xA1, // Right Shift
        0x3D: 0xA5, // Right Option
        0x3E: 0xA3, // Right Control
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
        if let mapped = macKeyCodeToWindowsVirtualKey[macKeyCode] {
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
}
