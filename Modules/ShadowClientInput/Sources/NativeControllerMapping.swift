public enum PhysicalControllerButton: String, CaseIterable, Sendable {
    case cross
    case circle
    case square
    case triangle
    case leftShoulder
    case rightShoulder
    case leftStickClick
    case rightStickClick
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case options
    case create
    case ps
    case touchpadClick
}

public enum LogicalControllerButton: String, CaseIterable, Sendable {
    case actionSouth
    case actionEast
    case actionWest
    case actionNorth
    case leftShoulder
    case rightShoulder
    case leftStickClick
    case rightStickClick
    case dpadUp
    case dpadDown
    case dpadLeft
    case dpadRight
    case menu
    case view
    case guide
}

public enum PhysicalControllerAxis: String, CaseIterable, Sendable {
    case leftStickX
    case leftStickY
    case rightStickX
    case rightStickY
    case leftTrigger
    case rightTrigger
}

public enum LogicalControllerAxis: String, CaseIterable, Sendable {
    case moveX
    case moveY
    case cameraX
    case cameraY
    case leftTrigger
    case rightTrigger
}

public struct ControllerInputSnapshot: Equatable, Sendable {
    public let pressedButtons: Set<PhysicalControllerButton>
    public let axisValues: [PhysicalControllerAxis: Double]

    public init(
        pressedButtons: Set<PhysicalControllerButton>,
        axisValues: [PhysicalControllerAxis: Double]
    ) {
        self.pressedButtons = pressedButtons
        self.axisValues = axisValues
    }
}

public struct MappedControllerState: Equatable, Sendable {
    public let pressedButtons: Set<LogicalControllerButton>
    public let axisValues: [LogicalControllerAxis: Double]

    public init(
        pressedButtons: Set<LogicalControllerButton>,
        axisValues: [LogicalControllerAxis: Double]
    ) {
        self.pressedButtons = pressedButtons
        self.axisValues = axisValues
    }
}

public struct NativeControllerMappingProfile: Equatable, Sendable {
    public let buttonMap: [PhysicalControllerButton: LogicalControllerButton]
    public let axisMap: [PhysicalControllerAxis: LogicalControllerAxis]

    public init(
        buttonMap: [PhysicalControllerButton: LogicalControllerButton],
        axisMap: [PhysicalControllerAxis: LogicalControllerAxis]
    ) {
        self.buttonMap = buttonMap
        self.axisMap = axisMap
    }
}

public extension NativeControllerMappingProfile {
    static let dualSenseDefault = NativeControllerMappingProfile(
        buttonMap: [
            .cross: .actionSouth,
            .circle: .actionEast,
            .square: .actionWest,
            .triangle: .actionNorth,
            .leftShoulder: .leftShoulder,
            .rightShoulder: .rightShoulder,
            .leftStickClick: .leftStickClick,
            .rightStickClick: .rightStickClick,
            .dpadUp: .dpadUp,
            .dpadDown: .dpadDown,
            .dpadLeft: .dpadLeft,
            .dpadRight: .dpadRight,
            .options: .menu,
            .create: .view,
            .ps: .guide,
        ],
        axisMap: [
            .leftStickX: .moveX,
            .leftStickY: .moveY,
            .rightStickX: .cameraX,
            .rightStickY: .cameraY,
            .leftTrigger: .leftTrigger,
            .rightTrigger: .rightTrigger,
        ]
    )
}

public struct NativeControllerInputMapper: Sendable {
    public let profile: NativeControllerMappingProfile

    public init(profile: NativeControllerMappingProfile = .dualSenseDefault) {
        self.profile = profile
    }

    public func map(_ snapshot: ControllerInputSnapshot) -> MappedControllerState {
        var mappedButtons: Set<LogicalControllerButton> = []
        for button in snapshot.pressedButtons {
            guard let mapped = profile.buttonMap[button] else { continue }
            mappedButtons.insert(mapped)
        }

        var mappedAxes: [LogicalControllerAxis: Double] = [:]
        for (physicalAxis, rawValue) in snapshot.axisValues {
            guard let mappedAxis = profile.axisMap[physicalAxis] else { continue }
            mappedAxes[mappedAxis] = clampedAxisValue(rawValue)
        }

        return MappedControllerState(
            pressedButtons: mappedButtons,
            axisValues: mappedAxes
        )
    }

    private func clampedAxisValue(_ value: Double) -> Double {
        guard value.isFinite else { return 0.0 }
        return min(max(value, -1.0), 1.0)
    }
}
