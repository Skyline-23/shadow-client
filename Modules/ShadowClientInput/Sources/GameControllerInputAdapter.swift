#if canImport(GameController)
import GameController
#endif

public protocol GameControllerStateProviding {
    var faceSouthPressed: Bool { get }
    var faceEastPressed: Bool { get }
    var faceWestPressed: Bool { get }
    var faceNorthPressed: Bool { get }
    var leftShoulderPressed: Bool { get }
    var rightShoulderPressed: Bool { get }
    var leftStickPressed: Bool { get }
    var rightStickPressed: Bool { get }
    var dpadUpPressed: Bool { get }
    var dpadDownPressed: Bool { get }
    var dpadLeftPressed: Bool { get }
    var dpadRightPressed: Bool { get }
    var menuPressed: Bool { get }
    var leftStickX: Double { get }
    var leftStickY: Double { get }
    var rightStickX: Double { get }
    var rightStickY: Double { get }
    var leftTriggerValue: Double { get }
    var rightTriggerValue: Double { get }
}

public struct GameControllerInputAdapter {
    public init() {}

    public func makeSnapshot(from state: any GameControllerStateProviding) -> ControllerInputSnapshot {
        var pressedButtons: Set<PhysicalControllerButton> = []

        if state.faceSouthPressed { pressedButtons.insert(.cross) }
        if state.faceEastPressed { pressedButtons.insert(.circle) }
        if state.faceWestPressed { pressedButtons.insert(.square) }
        if state.faceNorthPressed { pressedButtons.insert(.triangle) }
        if state.leftShoulderPressed { pressedButtons.insert(.leftShoulder) }
        if state.rightShoulderPressed { pressedButtons.insert(.rightShoulder) }
        if state.leftStickPressed { pressedButtons.insert(.leftStickClick) }
        if state.rightStickPressed { pressedButtons.insert(.rightStickClick) }
        if state.dpadUpPressed { pressedButtons.insert(.dpadUp) }
        if state.dpadDownPressed { pressedButtons.insert(.dpadDown) }
        if state.dpadLeftPressed { pressedButtons.insert(.dpadLeft) }
        if state.dpadRightPressed { pressedButtons.insert(.dpadRight) }
        if state.menuPressed { pressedButtons.insert(.options) }

        let axisValues: [PhysicalControllerAxis: Double] = [
            .leftStickX: state.leftStickX,
            .leftStickY: state.leftStickY,
            .rightStickX: state.rightStickX,
            .rightStickY: state.rightStickY,
            .leftTrigger: state.leftTriggerValue,
            .rightTrigger: state.rightTriggerValue,
        ]

        return ControllerInputSnapshot(
            pressedButtons: pressedButtons,
            axisValues: axisValues
        )
    }
}

#if canImport(GameController)
extension GCExtendedGamepad: GameControllerStateProviding {
    public var faceSouthPressed: Bool { buttonA.isPressed }
    public var faceEastPressed: Bool { buttonB.isPressed }
    public var faceWestPressed: Bool { buttonX.isPressed }
    public var faceNorthPressed: Bool { buttonY.isPressed }
    public var leftShoulderPressed: Bool { leftShoulder.isPressed }
    public var rightShoulderPressed: Bool { rightShoulder.isPressed }
    public var leftStickPressed: Bool { leftThumbstickButton?.isPressed ?? false }
    public var rightStickPressed: Bool { rightThumbstickButton?.isPressed ?? false }
    public var dpadUpPressed: Bool { dpad.up.isPressed }
    public var dpadDownPressed: Bool { dpad.down.isPressed }
    public var dpadLeftPressed: Bool { dpad.left.isPressed }
    public var dpadRightPressed: Bool { dpad.right.isPressed }
    public var menuPressed: Bool { buttonMenu.isPressed }
    public var leftStickX: Double { Double(leftThumbstick.xAxis.value) }
    public var leftStickY: Double { Double(leftThumbstick.yAxis.value) }
    public var rightStickX: Double { Double(rightThumbstick.xAxis.value) }
    public var rightStickY: Double { Double(rightThumbstick.yAxis.value) }
    public var leftTriggerValue: Double { Double(leftTrigger.value) }
    public var rightTriggerValue: Double { Double(rightTrigger.value) }
}
#endif
