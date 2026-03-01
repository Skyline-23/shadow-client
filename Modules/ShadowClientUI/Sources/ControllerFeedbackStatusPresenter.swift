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

        return makeModel(
            feedback: evaluation,
            rumblePasses: state.supportsRumble,
            adaptiveTriggerPasses: state.supportsAdaptiveTriggers,
            ledPasses: state.supportsLED
        )
    }

    public func makeModel(
        evaluation: GameControllerFeedbackRuntime.Evaluation
    ) -> ControllerFeedbackStatusModel {
        makeModel(
            feedback: evaluation.feedback,
            rumblePasses: !evaluation.feedback.missingCapabilities.contains("rumble"),
            adaptiveTriggerPasses: !evaluation.feedback.missingCapabilities.contains("adaptiveTriggers"),
            ledPasses: !evaluation.feedback.missingCapabilities.contains("led")
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

    private func makeModel(
        feedback: DualSenseFeedbackResult,
        rumblePasses: Bool,
        adaptiveTriggerPasses: Bool,
        ledPasses: Bool
    ) -> ControllerFeedbackStatusModel {
        let detail: String
        if feedback.passes {
            detail = "DualSense feedback contract satisfies Apple Game Controller capability requirements."
        } else {
            let missing = feedback.missingCapabilities
                .map(readableCapabilityName(_:))
                .joined(separator: ", ")
            detail = "Missing: \(missing)"
        }

        return ControllerFeedbackStatusModel(
            title: feedback.passes ? "Controller Feedback Ready" : "Feedback Contract Warning",
            detail: detail,
            tone: feedback.passes ? .healthy : .warning,
            rows: [
                .init(title: "Rumble requires support", passes: rumblePasses),
                .init(title: "Adaptive triggers", passes: adaptiveTriggerPasses),
                .init(title: "LED indicator", passes: ledPasses),
            ]
        )
    }
}
