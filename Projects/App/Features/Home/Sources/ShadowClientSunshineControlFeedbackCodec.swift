import Foundation

struct ShadowClientSunshineControllerRumbleEvent: Equatable, Sendable {
    let controllerNumber: UInt16
    let lowFrequencyMotor: UInt16
    let highFrequencyMotor: UInt16
}

struct ShadowClientSunshineControllerTriggerRumbleEvent: Equatable, Sendable {
    let controllerNumber: UInt16
    let leftTriggerMotor: UInt16
    let rightTriggerMotor: UInt16
}

enum ShadowClientSunshineControllerFeedbackEvent: Equatable, Sendable {
    case rumble(ShadowClientSunshineControllerRumbleEvent)
    case triggerRumble(ShadowClientSunshineControllerTriggerRumbleEvent)
}

enum ShadowClientSunshineControlFeedbackCodec {
    static func parse(
        type: UInt16,
        payload: Data
    ) -> ShadowClientSunshineControllerFeedbackEvent? {
        if type == ShadowClientSunshineControlMessageProfile.rumbleType {
            return parseRumble(payload: payload)
        }
        if type == ShadowClientSunshineControlMessageProfile.rumbleTriggersType {
            return parseTriggerRumble(payload: payload)
        }
        return nil
    }

    private static func parseRumble(
        payload: Data
    ) -> ShadowClientSunshineControllerFeedbackEvent? {
        // Sunshine control_rumble_t packs a 4-byte reserved field before id/low/high.
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
    ) -> ShadowClientSunshineControllerFeedbackEvent? {
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

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset])
        let b1 = UInt16(data[offset + 1]) << 8
        return b0 | b1
    }
}
