import ShadowClientCore
import ShadowClientInput
import ShadowClientStreaming
import Testing
@testable import ShadowClientUI

@Test("Presenter emits healthy badge when all contracts pass")
func presenterHealthyState() {
    let checker = StreamingStabilityChecker()
    let report = checker.evaluate(
        .init(renderedFrames: 990, droppedFrames: 10, avSyncOffsetMilliseconds: 20.0)
    )
    let inputGate = InputRTTP95Gate().evaluate(p95Milliseconds: 30.0)
    let feedback = DualSenseFeedbackContract().evaluate(
        capabilities: .init(
            supportsRumble: true,
            supportsAdaptiveTriggers: true,
            supportsLED: true
        ),
        transport: .usb
    )

    let badge = StreamHealthPresenter().makeBadge(
        streaming: report,
        inputLatency: inputGate,
        feedback: feedback
    )

    #expect(badge.tone == .healthy)
}

@Test("Presenter emits critical badge when streaming gate fails")
func presenterCriticalState() {
    let checker = StreamingStabilityChecker()
    let report = checker.evaluate(
        .init(renderedFrames: 950, droppedFrames: 50, avSyncOffsetMilliseconds: 10.0)
    )
    let inputGate = InputRTTP95Gate().evaluate(p95Milliseconds: 30.0)
    let feedback = DualSenseFeedbackContract().evaluate(
        capabilities: .init(
            supportsRumble: true,
            supportsAdaptiveTriggers: true,
            supportsLED: true
        ),
        transport: .usb
    )

    let badge = StreamHealthPresenter().makeBadge(
        streaming: report,
        inputLatency: inputGate,
        feedback: feedback
    )

    #expect(badge.tone == .critical)
}
