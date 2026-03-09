import Foundation

#if os(iOS)
import UIKit
#endif

enum ShadowClientWindowsVirtualKeyMap {
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

    static func windowsVirtualKeyCode(
        keyCode: UInt16,
        characters: String?
    ) -> UInt16? {
        if let pretranslated = ShadowClientRemoteInputEvent.pretranslatedWindowsVirtualKeyCode(
            from: keyCode
        ) {
            return pretranslated
        }

        if keyCode != ShadowClientRemoteInputEvent.softwareKeyboardSyntheticKeyCode,
           let mapped = macKeyCodeToWindowsVirtualKey[keyCode]
        {
            return mapped
        }

        return windowsVirtualKeyCode(fromCharacters: characters)
    }

    #if os(iOS)
    static func windowsVirtualKeyCode(
        keyboardHIDUsage: UIKeyboardHIDUsage,
        characters: String?
    ) -> UInt16? {
        if let mapped = windowsVirtualKeyCode(forHIDUsageRawValue: UInt16(keyboardHIDUsage.rawValue)) {
            return mapped
        }
        return windowsVirtualKeyCode(fromCharacters: characters)
    }
    #endif

    private static func windowsVirtualKeyCode(fromCharacters characters: String?) -> UInt16? {
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
            if ascii >= 0x61, ascii <= 0x7A {
                return UInt16(ascii - 0x20)
            }
            if ascii >= 0x41, ascii <= 0x5A {
                return UInt16(ascii)
            }
            if ascii >= 0x30, ascii <= 0x39 {
                return UInt16(ascii)
            }
            if let mapped = characterToWindowsVirtualKey[Character(UnicodeScalar(ascii))] {
                return mapped
            }
        }

        return nil
    }

    #if os(iOS)
    private static func windowsVirtualKeyCode(forHIDUsageRawValue usage: UInt16) -> UInt16? {
        switch usage {
        case 0x04 ... 0x1D:
            return 0x41 + (usage - 0x04)
        case 0x1E ... 0x26:
            return 0x31 + (usage - 0x1E)
        case 0x27:
            return 0x30
        case 0x28:
            return 0x0D
        case 0x29:
            return 0x1B
        case 0x2A:
            return 0x08
        case 0x2B:
            return 0x09
        case 0x2C:
            return 0x20
        case 0x2D:
            return 0xBD
        case 0x2E:
            return 0xBB
        case 0x2F:
            return 0xDB
        case 0x30:
            return 0xDD
        case 0x31, 0x64:
            return 0xDC
        case 0x32:
            return 0xE2
        case 0x33:
            return 0xBA
        case 0x34:
            return 0xDE
        case 0x35:
            return 0xC0
        case 0x36:
            return 0xBC
        case 0x37:
            return 0xBE
        case 0x38:
            return 0xBF
        case 0x39:
            return 0x14
        case 0x3A ... 0x45:
            return 0x70 + (usage - 0x3A)
        case 0x46:
            return 0x2C
        case 0x47:
            return 0x91
        case 0x48:
            return 0x13
        case 0x49:
            return 0x2D
        case 0x4A:
            return 0x24
        case 0x4B:
            return 0x21
        case 0x4C:
            return 0x2E
        case 0x4D:
            return 0x23
        case 0x4E:
            return 0x22
        case 0x4F:
            return 0x27
        case 0x50:
            return 0x25
        case 0x51:
            return 0x28
        case 0x52:
            return 0x26
        case 0x53:
            return 0x0C
        case 0x54:
            return 0x6F
        case 0x55:
            return 0x6A
        case 0x56:
            return 0x6D
        case 0x57:
            return 0x6B
        case 0x58:
            return 0x0D
        case 0x59 ... 0x61:
            return 0x61 + (usage - 0x59)
        case 0x62:
            return 0x60
        case 0x63:
            return 0x6E
        case 0x67:
            return 0x6C
        case 0x68 ... 0x73:
            return 0x7C + (usage - 0x68)
        case 0x7D:
            return 0x86
        case 0x7E:
            return 0x2F
        case 0x7F:
            return 0xAD
        case 0x80:
            return 0xAF
        case 0x81:
            return 0xAE
        case 0xE0:
            return 0xA2
        case 0xE1:
            return 0xA0
        case 0xE2:
            return 0xA4
        case 0xE3:
            return 0x5B
        case 0xE4:
            return 0xA3
        case 0xE5:
            return 0xA1
        case 0xE6:
            return 0xA5
        case 0xE7:
            return 0x5C
        default:
            return nil
        }
    }
    #endif
}
