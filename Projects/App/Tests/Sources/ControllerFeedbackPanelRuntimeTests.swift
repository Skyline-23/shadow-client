import Testing
@testable import ShadowClientFeatureHome

@Test("Controller feedback panel runtime returns ready status with mapped input counts")
func controllerFeedbackPanelRuntimeReadySnapshot() async {
    let runtime = ControllerFeedbackPanelRuntime()
    let inputPlan = ControllerFeedbackSimulationInputPlan(
        crossPressed: true,
        menuPressed: true,
        leftTriggerValue: 0.75
    )

    let snapshot = await runtime.makeSnapshot(
        state: .init(
            transport: .usb,
            supportsRumble: true,
            supportsAdaptiveTriggers: true,
            supportsLED: true
        ),
        inputPlan: inputPlan
    )

    #expect(snapshot.statusModel.title == "Controller Feedback Ready")
    #expect(snapshot.statusModel.detail == "DualSense feedback contract satisfies USB-first requirements.")
    #expect(snapshot.mappedButtonCount == 2)
    #expect(snapshot.mappedAxisCount == 6)
    #expect(snapshot.mappedButtonNames == ["actionSouth", "menu"])
    #expect(snapshot.leftTriggerValue == 0.75)
}

@Test("Controller feedback panel runtime returns warning when USB-first requirements fail")
func controllerFeedbackPanelRuntimeWarningSnapshot() async {
    let runtime = ControllerFeedbackPanelRuntime()
    let inputPlan = ControllerFeedbackSimulationInputPlan(
        crossPressed: false,
        menuPressed: false,
        leftTriggerValue: 1.8
    )

    let snapshot = await runtime.makeSnapshot(
        state: .init(
            transport: .bluetooth,
            supportsRumble: true,
            supportsAdaptiveTriggers: true,
            supportsLED: false
        ),
        inputPlan: inputPlan
    )

    #expect(snapshot.statusModel.title == "Feedback Contract Warning")
    #expect(snapshot.statusModel.detail == "Missing: USB transport, LED indicator")
    #expect(snapshot.statusModel.rows.first(where: { $0.title == "USB transport enforced" })?.passes == false)
    #expect(snapshot.statusModel.rows.first(where: { $0.title == "LED indicator" })?.passes == false)
    #expect(snapshot.mappedButtonCount == 0)
    #expect(snapshot.mappedAxisCount == 6)
    #expect(snapshot.mappedButtonNames == [])
    #expect(snapshot.leftTriggerValue == 1.0)
}
