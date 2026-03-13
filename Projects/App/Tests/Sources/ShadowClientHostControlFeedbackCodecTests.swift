import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Host control feedback codec parses rumble payload with reserved prefix")
func hostControlFeedbackCodecParsesRumblePayload() {
    let payload = Data([
        0xEE, 0xFF, 0xC0, 0x00, // reserved prefix (ignored)
        0x02, 0x00, // controller id
        0x34, 0x12, // low motor
        0x78, 0x56, // high motor
    ])

    let event = ShadowClientHostControlFeedbackCodec.parse(
        type: ShadowClientHostControlMessageProfile.rumbleType,
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

@Test("Host control feedback codec parses trigger rumble payload")
func hostControlFeedbackCodecParsesTriggerRumblePayload() {
    let payload = Data([
        0x01, 0x00, // controller id
        0xAA, 0x00, // left trigger
        0x55, 0x01, // right trigger
    ])

    let event = ShadowClientHostControlFeedbackCodec.parse(
        type: ShadowClientHostControlMessageProfile.rumbleTriggersType,
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

@Test("Host control feedback codec maps adaptive trigger payload to trigger rumble")
func hostControlFeedbackCodecParsesAdaptiveTriggerPayload() {
    let payload = Data([
        0x03, 0x00, // controller id
        0x0C, // event flags (left + right)
        0x02, // left trigger type
        0x03, // right trigger type
        // left effect payload (peak=0x80)
        0x10, 0x20, 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01,
        // right effect payload (peak=0x40)
        0x04, 0x08, 0x10, 0x20, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02,
    ])

    let event = ShadowClientHostControlFeedbackCodec.parse(
        type: ShadowClientHostControlMessageProfile.adaptiveTriggersType,
        payload: payload
    )

    #expect(
        event ==
            .triggerRumble(
                .init(
                    controllerNumber: 3,
                    leftTriggerMotor: 0x8080,
                    rightTriggerMotor: 0x4040
                )
            )
    )
}

@Test("Host control feedback codec returns nil for unsupported control type")
func hostControlFeedbackCodecIgnoresUnsupportedType() {
    let event = ShadowClientHostControlFeedbackCodec.parse(
        type: 0x0206,
        payload: Data([0x00, 0x01])
    )

    #expect(event == nil)
}

@Test("Host control feedback codec parses termination payload")
func hostControlFeedbackCodecParsesTerminationPayload() {
    let payload = Data([0x80, 0x03, 0x00, 0x23])

    let event = ShadowClientHostControlFeedbackCodec.parseTermination(
        type: ShadowClientHostControlMessageProfile.terminationType,
        payload: payload
    )

    #expect(event == .init(reasonCode: 0x80030023))
    #expect(event?.message == "Host terminated the session gracefully (0x80030023).")
}
