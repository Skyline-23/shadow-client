import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Sunshine control feedback codec parses rumble payload with reserved prefix")
func sunshineControlFeedbackCodecParsesRumblePayload() {
    let payload = Data([
        0xEE, 0xFF, 0xC0, 0x00, // reserved prefix (ignored)
        0x02, 0x00, // controller id
        0x34, 0x12, // low motor
        0x78, 0x56, // high motor
    ])

    let event = ShadowClientSunshineControlFeedbackCodec.parse(
        type: ShadowClientSunshineControlMessageProfile.rumbleType,
        payload: payload
    )

    #expect(
        event ==
            .rumble(
                .init(
                    controllerNumber: 2,
                    lowFrequencyMotor: 0x1234,
                    highFrequencyMotor: 0x5678
                )
            )
    )
}

@Test("Sunshine control feedback codec parses trigger rumble payload")
func sunshineControlFeedbackCodecParsesTriggerRumblePayload() {
    let payload = Data([
        0x01, 0x00, // controller id
        0xAA, 0x00, // left trigger
        0x55, 0x01, // right trigger
    ])

    let event = ShadowClientSunshineControlFeedbackCodec.parse(
        type: ShadowClientSunshineControlMessageProfile.rumbleTriggersType,
        payload: payload
    )

    #expect(
        event ==
            .triggerRumble(
                .init(
                    controllerNumber: 1,
                    leftTriggerMotor: 0x00AA,
                    rightTriggerMotor: 0x0155
                )
            )
    )
}

@Test("Sunshine control feedback codec returns nil for unsupported control type")
func sunshineControlFeedbackCodecIgnoresUnsupportedType() {
    let event = ShadowClientSunshineControlFeedbackCodec.parse(
        type: 0x0206,
        payload: Data([0x00, 0x01])
    )

    #expect(event == nil)
}

