import Foundation

enum ShadowClientHostInputPacketCodec {
    struct EncodedInputPacket: Sendable {
        let channelID: UInt8
        let payload: Data
    }

    private enum Channel {
        static let keyboard: UInt8 = ShadowClientHostControlMessageProfile.keyboardChannelID
        static let mouse: UInt8 = ShadowClientHostControlMessageProfile.mouseChannelID
        static let gamepadBase: UInt8 = ShadowClientHostControlMessageProfile.gamepadChannelBaseID
    }

    private enum PacketMagic {
        static let mouseMoveAbsolute: UInt32 = 0x0000_0005
        static let keyDown: UInt32 = 0x0000_0003
        static let keyUp: UInt32 = 0x0000_0004
        static let utf8Text: UInt32 = 0x0000_0017
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
        static let capabilityTriggerRumble: UInt16 = 0x04
        static let defaultCapabilities: UInt16 = capabilityAnalogTriggers |
            capabilityRumble |
            capabilityTriggerRumble
    }

    private enum MouseButton {
        static let left: UInt8 = 0x01
        static let middle: UInt8 = 0x02
        static let right: UInt8 = 0x03
    }

    static func encode(_ event: ShadowClientRemoteInputEvent) -> EncodedInputPacket? {
        switch event {
        case let .keyDown(keyCode, characters):
            guard let virtualKey = ShadowClientWindowsVirtualKeyMap.windowsVirtualKeyCode(
                keyCode: keyCode,
                characters: characters
            ) else {
                return nil
            }
            return .init(
                channelID: Channel.keyboard,
                payload: makeKeyboardPacket(
                    magic: PacketMagic.keyDown,
                    virtualKey: normalizedHostKeyboardKeyCode(virtualKey)
                )
            )
        case let .keyUp(keyCode, characters):
            guard let virtualKey = ShadowClientWindowsVirtualKeyMap.windowsVirtualKeyCode(
                keyCode: keyCode,
                characters: characters
            ) else {
                return nil
            }
            return .init(
                channelID: Channel.keyboard,
                payload: makeKeyboardPacket(
                    magic: PacketMagic.keyUp,
                    virtualKey: normalizedHostKeyboardKeyCode(virtualKey)
                )
            )
        case let .text(text):
            guard let payload = makeUTF8TextPacket(text) else {
                return nil
            }
            return .init(
                channelID: Channel.keyboard,
                payload: payload
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
        case let .pointerPosition(x, y, referenceWidth, referenceHeight):
            guard let payload = makeAbsoluteMouseMovePacket(
                x: x,
                y: y,
                referenceWidth: referenceWidth,
                referenceHeight: referenceHeight
            ) else {
                return nil
            }
            return .init(
                channelID: Channel.mouse,
                payload: payload
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

    private static func makeUTF8TextPacket(_ text: String) -> Data? {
        let payloadBytes = Array(text.utf8)
        guard !payloadBytes.isEmpty else {
            return nil
        }

        var packet = Data()
        packet.reserveCapacity(8 + payloadBytes.count)
        appendUInt32BE(UInt32(4 + payloadBytes.count), to: &packet)
        appendUInt32LE(PacketMagic.utf8Text, to: &packet)
        packet.append(contentsOf: payloadBytes)
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

    private static func makeAbsoluteMouseMovePacket(
        x: Double,
        y: Double,
        referenceWidth: Double,
        referenceHeight: Double
    ) -> Data? {
        let width = normalizedAbsoluteDimension(referenceWidth)
        let height = normalizedAbsoluteDimension(referenceHeight)
        guard width > 0, height > 0 else {
            return nil
        }

        let normalizedX = normalizedAbsoluteCoordinate(
            x,
            referenceDimension: width
        )
        let normalizedY = normalizedAbsoluteCoordinate(
            y,
            referenceDimension: height
        )

        var packet = Data()
        packet.reserveCapacity(18)
        appendUInt32BE(14, to: &packet) // sizeof(NV_ABS_MOUSE_MOVE_PACKET) - sizeof(size field)
        appendUInt32LE(PacketMagic.mouseMoveAbsolute, to: &packet)
        appendInt16BE(normalizedX, to: &packet)
        appendInt16BE(normalizedY, to: &packet)
        appendInt16BE(0, to: &packet)
        appendInt16BE(width, to: &packet)
        appendInt16BE(height, to: &packet)
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

    private static func normalizedAbsoluteDimension(_ dimension: Double) -> Int16 {
        Int16(clamping: max(1, Int(dimension.rounded())))
    }

    private static func normalizedAbsoluteCoordinate(
        _ coordinate: Double,
        referenceDimension: Int16
    ) -> Int16 {
        let upperBound = max(Int(referenceDimension) - 1, 0)
        let rounded = Int(coordinate.rounded())
        return Int16(clamping: min(max(rounded, 0), upperBound))
    }

    private static func normalizedHostKeyboardKeyCode(_ virtualKey: UInt16) -> UInt16 {
        // Moonlight sets the high bit for Apollo-host keyboard input to match
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
