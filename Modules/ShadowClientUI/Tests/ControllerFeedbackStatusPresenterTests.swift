import ShadowClientInput
import Testing
@testable import ShadowClientUI

@Test("Controller feedback presenter emits ready state when capabilities satisfy contract")
func controllerFeedbackPresenterReadyState() {
    let presenter = ControllerFeedbackStatusPresenter()
    let state = ControllerFeedbackSimulationState(
        transport: .usb,
        supportsRumble: true,
        supportsAdaptiveTriggers: true,
        supportsLED: true
    )

    let model = presenter.makeModel(state: state)

    #expect(model.tone == .healthy)
    #expect(model.title == "Controller Feedback Ready")
    #expect(model.detail == "DualSense feedback contract satisfies Apple Game Controller capability requirements.")
    #expect(model.rows.contains(where: { !$0.passes }) == false)
}

@Test("Controller feedback presenter surfaces missing requirements with readable labels")
func controllerFeedbackPresenterMissingRequirements() {
    let presenter = ControllerFeedbackStatusPresenter()
    let state = ControllerFeedbackSimulationState(
        transport: .bluetooth,
        supportsRumble: true,
        supportsAdaptiveTriggers: false,
        supportsLED: false
    )

    let model = presenter.makeModel(state: state)

    #expect(model.tone == .warning)
    #expect(model.title == "Feedback Contract Warning")
    #expect(model.detail == "Missing: adaptive triggers, LED indicator")
    #expect(model.rows.first(where: { $0.title == "Adaptive triggers" })?.passes == false)
    #expect(model.rows.first(where: { $0.title == "LED indicator" })?.passes == false)
}

@Test("Controller feedback presenter rows mirror simulation toggles")
func controllerFeedbackPresenterRowsMirrorSimulationState() {
    let presenter = ControllerFeedbackStatusPresenter()
    let state = ControllerFeedbackSimulationState(
        transport: .usb,
        supportsRumble: false,
        supportsAdaptiveTriggers: true,
        supportsLED: true
    )

    let model = presenter.makeModel(state: state)

    #expect(model.rows.count == 3)
    #expect(model.rows.first(where: { $0.title == "Rumble requires support" })?.passes == false)
    #expect(model.rows.first(where: { $0.title == "Adaptive triggers" })?.passes == true)
}

@Test("Controller feedback presenter maps runtime evaluation into ready status model")
func controllerFeedbackPresenterMapsRuntimeEvaluationReadyState() {
    let presenter = ControllerFeedbackStatusPresenter()
    let evaluation = GameControllerFeedbackRuntime.Evaluation(
        state: .init(pressedButtons: [], axisValues: [:]),
        feedback: .init(
            passes: true,
            missingCapabilities: [],
            transport: .usb
        )
    )

    let model = presenter.makeModel(evaluation: evaluation)

    #expect(model.tone == .healthy)
    #expect(model.title == "Controller Feedback Ready")
    #expect(model.detail == "DualSense feedback contract satisfies Apple Game Controller capability requirements.")
    #expect(model.rows.first(where: { $0.title == "Rumble requires support" })?.passes == true)
    #expect(model.rows.first(where: { $0.title == "Adaptive triggers" })?.passes == true)
    #expect(model.rows.first(where: { $0.title == "LED indicator" })?.passes == true)
}

@Test("Controller feedback presenter maps runtime evaluation missing requirements")
func controllerFeedbackPresenterMapsRuntimeEvaluationMissingRequirements() {
    let presenter = ControllerFeedbackStatusPresenter()
    let evaluation = GameControllerFeedbackRuntime.Evaluation(
        state: .init(pressedButtons: [], axisValues: [:]),
        feedback: .init(
            passes: false,
            missingCapabilities: ["led"],
            transport: .bluetooth
        )
    )

    let model = presenter.makeModel(evaluation: evaluation)

    #expect(model.tone == .warning)
    #expect(model.title == "Feedback Contract Warning")
    #expect(model.detail == "Missing: LED indicator")
    #expect(model.rows.first(where: { $0.title == "Rumble requires support" })?.passes == true)
    #expect(model.rows.first(where: { $0.title == "Adaptive triggers" })?.passes == true)
    #expect(model.rows.first(where: { $0.title == "LED indicator" })?.passes == false)
}
