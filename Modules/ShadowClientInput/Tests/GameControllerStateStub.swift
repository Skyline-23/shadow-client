@testable import ShadowClientInput

struct GameControllerStateStub: GameControllerStateProviding {
    var faceSouthPressed: Bool
    var faceEastPressed: Bool
    var faceWestPressed: Bool
    var faceNorthPressed: Bool
    var leftShoulderPressed: Bool
    var rightShoulderPressed: Bool
    var leftStickPressed: Bool
    var rightStickPressed: Bool
    var dpadUpPressed: Bool
    var dpadDownPressed: Bool
    var dpadLeftPressed: Bool
    var dpadRightPressed: Bool
    var menuPressed: Bool
    var leftStickX: Double
    var leftStickY: Double
    var rightStickX: Double
    var rightStickY: Double
    var leftTriggerValue: Double
    var rightTriggerValue: Double

    init(
        faceSouthPressed: Bool = false,
        faceEastPressed: Bool = false,
        faceWestPressed: Bool = false,
        faceNorthPressed: Bool = false,
        leftShoulderPressed: Bool = false,
        rightShoulderPressed: Bool = false,
        leftStickPressed: Bool = false,
        rightStickPressed: Bool = false,
        dpadUpPressed: Bool = false,
        dpadDownPressed: Bool = false,
        dpadLeftPressed: Bool = false,
        dpadRightPressed: Bool = false,
        menuPressed: Bool = false,
        leftStickX: Double = 0.0,
        leftStickY: Double = 0.0,
        rightStickX: Double = 0.0,
        rightStickY: Double = 0.0,
        leftTriggerValue: Double = 0.0,
        rightTriggerValue: Double = 0.0
    ) {
        self.faceSouthPressed = faceSouthPressed
        self.faceEastPressed = faceEastPressed
        self.faceWestPressed = faceWestPressed
        self.faceNorthPressed = faceNorthPressed
        self.leftShoulderPressed = leftShoulderPressed
        self.rightShoulderPressed = rightShoulderPressed
        self.leftStickPressed = leftStickPressed
        self.rightStickPressed = rightStickPressed
        self.dpadUpPressed = dpadUpPressed
        self.dpadDownPressed = dpadDownPressed
        self.dpadLeftPressed = dpadLeftPressed
        self.dpadRightPressed = dpadRightPressed
        self.menuPressed = menuPressed
        self.leftStickX = leftStickX
        self.leftStickY = leftStickY
        self.rightStickX = rightStickX
        self.rightStickY = rightStickY
        self.leftTriggerValue = leftTriggerValue
        self.rightTriggerValue = rightTriggerValue
    }
}
