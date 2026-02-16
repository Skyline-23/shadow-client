import Testing
@testable import ShadowClientInput

@Test("GameController adapter maps physical controls into snapshot controls")
func gameControllerAdapterMapsPhysicalControls() {
    let state = GameControllerStateStub(
        faceSouthPressed: true,
        faceNorthPressed: true,
        leftShoulderPressed: true,
        dpadRightPressed: true,
        menuPressed: true,
        leftStickX: -0.5,
        rightStickY: 0.4,
        leftTriggerValue: 0.75
    )

    let snapshot = GameControllerInputAdapter().makeSnapshot(from: state)

    #expect(snapshot.pressedButtons.contains(.cross))
    #expect(snapshot.pressedButtons.contains(.triangle))
    #expect(snapshot.pressedButtons.contains(.leftShoulder))
    #expect(snapshot.pressedButtons.contains(.dpadRight))
    #expect(snapshot.pressedButtons.contains(.options))
    #expect(snapshot.axisValues[.leftStickX] == -0.5)
    #expect(snapshot.axisValues[.rightStickY] == 0.4)
    #expect(snapshot.axisValues[.leftTrigger] == 0.75)
}
