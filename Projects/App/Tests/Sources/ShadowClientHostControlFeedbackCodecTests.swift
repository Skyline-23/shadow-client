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
    #expect(event?.message == "Lumen paused or closed the desktop session (0x80030023). This often happens when Windows shows a secure desktop, password prompt, or UAC dialog.")
}

@Test("Host control feedback codec parses Sunshine HDR metadata payload")
func hostControlFeedbackCodecParsesHDRModePayload() {
    let payload = Data([
        0x01,
        0x34, 0x12, 0x78, 0x56,
        0x9A, 0xBC, 0xDE, 0xF0,
        0x11, 0x22, 0x33, 0x44,
        0x55, 0x66, 0x77, 0x88,
        0x99, 0x00,
        0xAB, 0xCD,
        0xEF, 0x01,
        0x23, 0x45,
        0x67, 0x89,
    ])

    let event = ShadowClientHostControlFeedbackCodec.parseHDRMode(
        type: ShadowClientHostControlMessageProfile.hdrModeType,
        payload: payload
    )

    #expect(
        event ==
            .init(
                isEnabled: true,
                metadata: .init(
                    displayPrimaries: [
                        .init(x: 0x1234, y: 0x5678),
                        .init(x: 0xBC9A, y: 0xF0DE),
                        .init(x: 0x2211, y: 0x4433),
                    ],
                    whitePoint: .init(x: 0x6655, y: 0x8877),
                    maxDisplayLuminance: 0x0099,
                    minDisplayLuminance: 0xCDAB,
                    maxContentLightLevel: 0x01EF,
                    maxFrameAverageLightLevel: 0x4523,
                    maxFullFrameLuminance: 0x8967
                )
            )
    )
    #expect(event?.metadata?.hdr10DisplayInfoData == Data([
        0x12, 0x34, 0x56, 0x78,
        0xBC, 0x9A, 0xF0, 0xDE,
        0x22, 0x11, 0x44, 0x33,
        0x66, 0x55, 0x88, 0x77,
        0x00, 0x00, 0x00, 0x99,
        0x00, 0x00, 0xCD, 0xAB,
    ]))
    #expect(event?.metadata?.hdr10ContentInfoData == Data([
        0x01, 0xEF, 0x45, 0x23,
    ]))
}

@Test("Host control feedback codec parses Lumen HDR frame state payload")
func hostControlFeedbackCodecParsesHDRFrameStatePayload() {
    let payload = Data([
        0x01, // version
        0x02, // partial HDR overlay
        0x03, // static metadata + overlay regions
        0x00, // reserved
        0x78, 0x56, 0x34, 0x12, // effective frame
        0x01, 0x00, // overlay region count
        0x00, 0x00, // reserved
        // static metadata
        0x34, 0x12, 0x78, 0x56,
        0x9A, 0xBC, 0xDE, 0xF0,
        0x11, 0x22, 0x33, 0x44,
        0x55, 0x66, 0x77, 0x88,
        0x99, 0x00,
        0xAB, 0xCD,
        0xEF, 0x01,
        0x23, 0x45,
        0x67, 0x89,
        // overlay region
        0x10, 0x00, // x
        0x20, 0x00, // y
        0x30, 0x00, // width
        0x40, 0x00, // height
        0x01, // region metadata flag
        0x00, 0x00, 0x00, // reserved
        // region metadata
        0x01, 0x10, 0x02, 0x10,
        0x03, 0x10, 0x04, 0x10,
        0x05, 0x10, 0x06, 0x10,
        0x07, 0x10, 0x08, 0x10,
        0x09, 0x10,
        0x0A, 0x10,
        0x0B, 0x10,
        0x0C, 0x10,
        0x0D, 0x10,
    ])

    let frameState = ShadowClientHostControlFeedbackCodec.parseHDRFrameState(
        type: ShadowClientHostControlMessageProfile.hdrFrameStateType,
        payload: payload
    )

    #expect(frameState?.content == .partialHDROverlay)
    #expect(frameState?.effectiveFromFrameNumber == 0x12345678)
    #expect(frameState?.staticMetadata == makeTestHDRMetadata())
    #expect(frameState?.overlayRegions.count == 1)
    #expect(
        frameState?.overlayRegions.first ==
            .init(
                x: 16,
                y: 32,
                width: 48,
                height: 64,
                metadata: makeTestOverlayHDRMetadata()
            )
    )
}

private func makeTestHDRMetadata() -> ShadowClientHDRMetadata {
    ShadowClientHDRMetadata(
        displayPrimaries: [
            .init(x: 0x1234, y: 0x5678),
            .init(x: 0xBC9A, y: 0xF0DE),
            .init(x: 0x2211, y: 0x4433),
        ],
        whitePoint: .init(x: 0x6655, y: 0x8877),
        maxDisplayLuminance: 0x0099,
        minDisplayLuminance: 0xCDAB,
        maxContentLightLevel: 0x01EF,
        maxFrameAverageLightLevel: 0x4523,
        maxFullFrameLuminance: 0x8967
    )
}

private func makeTestOverlayHDRMetadata() -> ShadowClientHDRMetadata {
    ShadowClientHDRMetadata(
        displayPrimaries: [
            .init(x: 0x1001, y: 0x1002),
            .init(x: 0x1003, y: 0x1004),
            .init(x: 0x1005, y: 0x1006),
        ],
        whitePoint: .init(x: 0x1007, y: 0x1008),
        maxDisplayLuminance: 0x1009,
        minDisplayLuminance: 0x100A,
        maxContentLightLevel: 0x100B,
        maxFrameAverageLightLevel: 0x100C,
        maxFullFrameLuminance: 0x100D
    )
}
