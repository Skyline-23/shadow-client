import Foundation

struct ShadowClientHostControllerRumbleEvent: Equatable, Sendable {
    let controllerNumber: UInt16
    let lowFrequencyMotor: UInt16
    let highFrequencyMotor: UInt16
}

struct ShadowClientHostControllerTriggerRumbleEvent: Equatable, Sendable {
    let controllerNumber: UInt16
    let leftTriggerMotor: UInt16
    let rightTriggerMotor: UInt16
}

public struct ShadowClientHDRMetadataChromaticity: Equatable, Sendable {
    public let x: UInt16
    public let y: UInt16
}

public struct ShadowClientHDRMetadata: Equatable, Sendable {
    public let displayPrimaries: [ShadowClientHDRMetadataChromaticity]
    public let whitePoint: ShadowClientHDRMetadataChromaticity
    public let maxDisplayLuminance: UInt16
    public let minDisplayLuminance: UInt16
    public let maxContentLightLevel: UInt16
    public let maxFrameAverageLightLevel: UInt16
    public let maxFullFrameLuminance: UInt16

    var debugSummary: String {
        let primariesSummary = displayPrimaries
            .map { "[\($0.x),\($0.y)]" }
            .joined(separator: ",")
        return "primaries=\(primariesSummary) white-point=[\(whitePoint.x),\(whitePoint.y)] max-display=\(maxDisplayLuminance) min-display=\(minDisplayLuminance) max-cll=\(maxContentLightLevel) max-fall=\(maxFrameAverageLightLevel) max-ffl=\(maxFullFrameLuminance)"
    }

    var hasHDR10DisplayInfo: Bool {
        !(displayPrimaries.allSatisfy { $0.x == 0 && $0.y == 0 } &&
            whitePoint.x == 0 &&
            whitePoint.y == 0 &&
            maxDisplayLuminance == 0 &&
            minDisplayLuminance == 0)
    }

    var hasHDR10ContentInfo: Bool {
        maxContentLightLevel != 0 || maxFrameAverageLightLevel != 0
    }

    var hdr10DisplayInfoData: Data {
        var data = Data()
        data.reserveCapacity(24)
        for primary in displayPrimaries {
            Self.appendUInt16BE(primary.x, to: &data)
            Self.appendUInt16BE(primary.y, to: &data)
        }
        Self.appendUInt16BE(whitePoint.x, to: &data)
        Self.appendUInt16BE(whitePoint.y, to: &data)
        Self.appendUInt32BE(UInt32(maxDisplayLuminance), to: &data)
        Self.appendUInt32BE(UInt32(minDisplayLuminance), to: &data)
        return data
    }

    var hdr10ContentInfoData: Data {
        var data = Data()
        data.reserveCapacity(4)
        Self.appendUInt16BE(maxContentLightLevel, to: &data)
        Self.appendUInt16BE(maxFrameAverageLightLevel, to: &data)
        return data
    }

    private static func appendUInt16BE(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }

    private static func appendUInt32BE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: value >> 24))
        data.append(UInt8(truncatingIfNeeded: value >> 16))
        data.append(UInt8(truncatingIfNeeded: value >> 8))
        data.append(UInt8(truncatingIfNeeded: value))
    }
}

struct ShadowClientHostHDRModeEvent: Equatable, Sendable {
    let isEnabled: Bool
    let metadata: ShadowClientHDRMetadata?

    var debugSummary: String {
        "enabled=\(isEnabled) metadata=\(metadata?.debugSummary ?? "nil")"
    }
}

enum ShadowClientHostControllerFeedbackEvent: Equatable, Sendable {
    case rumble(ShadowClientHostControllerRumbleEvent)
    case triggerRumble(ShadowClientHostControllerTriggerRumbleEvent)
}

struct ShadowClientHostTerminationEvent: Equatable, Sendable {
    let reasonCode: UInt32

    var message: String {
        switch reasonCode {
        case 0x80030023:
            return "Apollo paused or closed the desktop session (0x80030023). This often happens when Windows shows a secure desktop, password prompt, or UAC dialog."
        default:
            return String(format: "Apollo terminated the session (0x%08X).", reasonCode)
        }
    }
}

enum ShadowClientHostControlFeedbackCodec {
    static func parse(
        type: UInt16,
        payload: Data
    ) -> ShadowClientHostControllerFeedbackEvent? {
        if type == ShadowClientHostControlMessageProfile.rumbleType {
            return parseRumble(payload: payload)
        }
        if type == ShadowClientHostControlMessageProfile.rumbleTriggersType {
            return parseTriggerRumble(payload: payload)
        }
        if type == ShadowClientHostControlMessageProfile.adaptiveTriggersType {
            return parseAdaptiveTriggers(payload: payload)
        }
        return nil
    }

    static func parseTermination(
        type: UInt16,
        payload: Data
    ) -> ShadowClientHostTerminationEvent? {
        guard type == ShadowClientHostControlMessageProfile.terminationType,
              payload.count >= 4
        else {
            return nil
        }

        let reasonCode = readUInt32BE(payload, at: 0)
        return .init(reasonCode: reasonCode)
    }

    static func parseHDRMode(
        type: UInt16,
        payload: Data
    ) -> ShadowClientHostHDRModeEvent? {
        guard type == ShadowClientHostControlMessageProfile.hdrModeType,
              payload.count >= 1
        else {
            return nil
        }

        let isEnabled = payload[0] != 0
        guard payload.count >= 27 else {
            return .init(isEnabled: isEnabled, metadata: nil)
        }

        var offset = 1
        var primaries: [ShadowClientHDRMetadataChromaticity] = []
        primaries.reserveCapacity(3)
        for _ in 0 ..< 3 {
            primaries.append(
                .init(
                    x: readUInt16LE(payload, at: offset),
                    y: readUInt16LE(payload, at: offset + 2)
                )
            )
            offset += 4
        }

        let metadata = ShadowClientHDRMetadata(
            displayPrimaries: primaries,
            whitePoint: .init(
                x: readUInt16LE(payload, at: offset),
                y: readUInt16LE(payload, at: offset + 2)
            ),
            maxDisplayLuminance: readUInt16LE(payload, at: offset + 4),
            minDisplayLuminance: readUInt16LE(payload, at: offset + 6),
            maxContentLightLevel: readUInt16LE(payload, at: offset + 8),
            maxFrameAverageLightLevel: readUInt16LE(payload, at: offset + 10),
            maxFullFrameLuminance: readUInt16LE(payload, at: offset + 12)
        )
        return .init(isEnabled: isEnabled, metadata: metadata)
    }

    private static func parseRumble(
        payload: Data
    ) -> ShadowClientHostControllerFeedbackEvent? {
        // Apollo-host control_rumble_t packs a 4-byte reserved field before id/low/high.
        guard payload.count >= 10 else {
            return nil
        }
        let controllerNumber = readUInt16LE(payload, at: 4)
        let lowFrequencyMotor = readUInt16LE(payload, at: 6)
        let highFrequencyMotor = readUInt16LE(payload, at: 8)
        return .rumble(
            .init(
                controllerNumber: controllerNumber,
                lowFrequencyMotor: lowFrequencyMotor,
                highFrequencyMotor: highFrequencyMotor
            )
        )
    }

    private static func parseTriggerRumble(
        payload: Data
    ) -> ShadowClientHostControllerFeedbackEvent? {
        guard payload.count >= 6 else {
            return nil
        }
        let controllerNumber = readUInt16LE(payload, at: 0)
        let leftTriggerMotor = readUInt16LE(payload, at: 2)
        let rightTriggerMotor = readUInt16LE(payload, at: 4)
        return .triggerRumble(
            .init(
                controllerNumber: controllerNumber,
                leftTriggerMotor: leftTriggerMotor,
                rightTriggerMotor: rightTriggerMotor
            )
        )
    }

    private static func parseAdaptiveTriggers(
        payload: Data
    ) -> ShadowClientHostControllerFeedbackEvent? {
        // Apollo-host control_adaptive_triggers_t:
        // id(2) + event_flags(1) + type_left(1) + type_right(1) + left[10] + right[10]
        guard payload.count >= 25 else {
            return nil
        }

        let controllerNumber = readUInt16LE(payload, at: 0)
        let eventFlags = payload[2]
        let leftType = payload[3]
        let rightType = payload[4]
        let leftPayload = payload.subdata(in: 5 ..< 15)
        let rightPayload = payload.subdata(in: 15 ..< 25)

        let leftTriggerMotor = adaptiveTriggerMotorValue(
            eventFlags: eventFlags,
            triggerType: leftType,
            triggerPayload: leftPayload,
            eventMask: 0x08
        )
        let rightTriggerMotor = adaptiveTriggerMotorValue(
            eventFlags: eventFlags,
            triggerType: rightType,
            triggerPayload: rightPayload,
            eventMask: 0x04
        )

        return .triggerRumble(
            .init(
                controllerNumber: controllerNumber,
                leftTriggerMotor: leftTriggerMotor,
                rightTriggerMotor: rightTriggerMotor
            )
        )
    }

    private static func adaptiveTriggerMotorValue(
        eventFlags: UInt8,
        triggerType: UInt8,
        triggerPayload: Data,
        eventMask: UInt8
    ) -> UInt16 {
        // Disabled trigger effects should not generate a haptic pulse.
        guard (eventFlags & eventMask) != 0, triggerType != 0 else {
            return 0
        }

        let peak = triggerPayload.max() ?? 0
        return UInt16(peak) * 257
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1]) << 8
        return b0 | b1
    }

    private static func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset]) << 24
        let b1 = UInt32(data[offset + 1]) << 16
        let b2 = UInt32(data[offset + 2]) << 8
        let b3 = UInt32(data[offset + 3])
        return b0 | b1 | b2 | b3
    }
}
