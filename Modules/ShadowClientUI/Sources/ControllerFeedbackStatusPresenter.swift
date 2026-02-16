import ShadowClientInput

public struct ControllerFeedbackSimulationState: Equatable, Sendable {
    public let transport: DualSenseTransport
    public let supportsRumble: Bool
    public let supportsAdaptiveTriggers: Bool
    public let supportsLED: Bool

    public init(
        transport: DualSenseTransport = .usb,
        supportsRumble: Bool = true,
        supportsAdaptiveTriggers: Bool = true,
        supportsLED: Bool = true
    ) {
        self.transport = transport
        self.supportsRumble = supportsRumble
        self.supportsAdaptiveTriggers = supportsAdaptiveTriggers
        self.supportsLED = supportsLED
    }

    public var capabilities: DualSenseFeedbackCapabilities {
        .init(
            supportsRumble: supportsRumble,
            supportsAdaptiveTriggers: supportsAdaptiveTriggers,
            supportsLED: supportsLED
        )
    }
}

public struct ControllerFeedbackCapabilityRow: Equatable, Sendable {
    public let title: String
    public let passes: Bool

    public init(title: String, passes: Bool) {
        self.title = title
        self.passes = passes
    }
}

public struct ControllerFeedbackStatusModel: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let tone: HealthTone
    public let rows: [ControllerFeedbackCapabilityRow]

    public init(
        title: String,
        detail: String,
        tone: HealthTone,
        rows: [ControllerFeedbackCapabilityRow]
    ) {
        self.title = title
        self.detail = detail
        self.tone = tone
        self.rows = rows
    }
}

public struct ControllerFeedbackStatusPresenter: Sendable {
    private let contract: DualSenseFeedbackContract

    public init(contract: DualSenseFeedbackContract = .init()) {
        self.contract = contract
    }

    public func makeModel(state: ControllerFeedbackSimulationState) -> ControllerFeedbackStatusModel {
        let evaluation = contract.evaluate(
            capabilities: state.capabilities,
            transport: state.transport
        )

        let detail: String
        if evaluation.passes {
            detail = "DualSense feedback contract satisfies USB-first requirements."
        } else {
            let missing = evaluation.missingCapabilities
                .map(readableCapabilityName(_:))
                .joined(separator: ", ")
            detail = "Missing: \(missing)"
        }

        return ControllerFeedbackStatusModel(
            title: evaluation.passes ? "Controller Feedback Ready" : "Feedback Contract Warning",
            detail: detail,
            tone: evaluation.passes ? .healthy : .warning,
            rows: [
                .init(title: "USB transport enforced", passes: state.transport == .usb),
                .init(title: "Rumble requires support", passes: state.supportsRumble),
                .init(title: "Adaptive triggers", passes: state.supportsAdaptiveTriggers),
                .init(title: "LED indicator", passes: state.supportsLED),
            ]
        )
    }

    private func readableCapabilityName(_ missingCapability: String) -> String {
        switch missingCapability {
        case "usbTransport":
            return "USB transport"
        case "rumble":
            return "rumble"
        case "adaptiveTriggers":
            return "adaptive triggers"
        case "led":
            return "LED indicator"
        default:
            return missingCapability
        }
    }
}
