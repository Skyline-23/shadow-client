import Testing
@testable import ShadowClientInput

@Test("DualSense default profile maps face buttons and menu buttons to logical controls")
func dualSenseDefaultProfileMapsButtons() {
    let mapper = NativeControllerInputMapper()
    let snapshot = ControllerInputSnapshot(
        pressedButtons: [.cross, .circle, .options, .create, .ps],
        axisValues: [:]
    )

    let mapped = mapper.map(snapshot)

    #expect(mapped.pressedButtons.contains(.actionSouth))
    #expect(mapped.pressedButtons.contains(.actionEast))
    #expect(mapped.pressedButtons.contains(.menu))
    #expect(mapped.pressedButtons.contains(.view))
    #expect(mapped.pressedButtons.contains(.guide))
}

@Test("DualSense default profile maps stick and trigger axes to logical controls")
func dualSenseDefaultProfileMapsAxes() {
    let mapper = NativeControllerInputMapper()
    let snapshot = ControllerInputSnapshot(
        pressedButtons: [],
        axisValues: [
            .leftStickX: -0.7,
            .leftStickY: 0.2,
            .rightStickX: 0.9,
            .rightStickY: -0.4,
            .leftTrigger: 0.8,
            .rightTrigger: 1.0,
        ]
    )

    let mapped = mapper.map(snapshot)

    #expect(mapped.axisValues[.moveX] == -0.7)
    #expect(mapped.axisValues[.moveY] == 0.2)
    #expect(mapped.axisValues[.cameraX] == 0.9)
    #expect(mapped.axisValues[.cameraY] == -0.4)
    #expect(mapped.axisValues[.leftTrigger] == 0.8)
    #expect(mapped.axisValues[.rightTrigger] == 1.0)
}

@Test("Input mapper clamps invalid axis ranges and resets non-finite values")
func inputMapperClampsAxisRanges() {
    let mapper = NativeControllerInputMapper()
    let snapshot = ControllerInputSnapshot(
        pressedButtons: [],
        axisValues: [
            .leftStickX: -2.5,
            .rightStickX: 3.2,
            .leftTrigger: .infinity,
            .rightTrigger: -.infinity,
        ]
    )

    let mapped = mapper.map(snapshot)

    #expect(mapped.axisValues[.moveX] == -1.0)
    #expect(mapped.axisValues[.cameraX] == 1.0)
    #expect(mapped.axisValues[.leftTrigger] == 0.0)
    #expect(mapped.axisValues[.rightTrigger] == 0.0)
}

@Test("Custom mapping profile can disable unmapped buttons while preserving mapped buttons")
func customProfileDisablesUnmappedButtons() {
    let profile = NativeControllerMappingProfile(
        buttonMap: [.cross: .actionSouth],
        axisMap: [:]
    )
    let mapper = NativeControllerInputMapper(profile: profile)
    let snapshot = ControllerInputSnapshot(
        pressedButtons: [.cross, .circle, .triangle],
        axisValues: [:]
    )

    let mapped = mapper.map(snapshot)

    #expect(mapped.pressedButtons == [.actionSouth])
}
