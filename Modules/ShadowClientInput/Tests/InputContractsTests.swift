import Testing
@testable import ShadowClientInput

@Test("Input analyzer computes p95 from sorted RTT samples")
func inputAnalyzerP95() {
    let analyzer = InputRoundTripAnalyzer()
    let samples = (1...20).map { InputRTTSample(milliseconds: Double($0)) }

    #expect(analyzer.p95Milliseconds(from: samples) == 19.0)
}

@Test("Input RTT gate evaluator enforces p95 <= 35ms")
func inputRTTGateEvaluatorThresholds() {
    let evaluator = InputRoundTripGateEvaluator()
    let passing = (10...30).map { InputRTTSample(milliseconds: Double($0)) }
    let failing = (10...40).map { InputRTTSample(milliseconds: Double($0)) }

    #expect(evaluator.evaluate(samples: passing).passes)
    #expect(!evaluator.evaluate(samples: failing).passes)
}

@Test("DualSense feedback contract defaults to Apple capability checks")
func dualSenseFeedbackFirstPassRequirements() {
    let contract = DualSenseFeedbackContract()
    let complete = DualSenseFeedbackCapabilities(
        supportsRumble: true,
        supportsAdaptiveTriggers: true,
        supportsLED: true
    )
    let missingLED = DualSenseFeedbackCapabilities(
        supportsRumble: true,
        supportsAdaptiveTriggers: true,
        supportsLED: false
    )

    let passing = contract.evaluate(capabilities: complete, transport: .bluetooth)
    let failingCapability = contract.evaluate(capabilities: missingLED, transport: .bluetooth)

    #expect(complete.isFirstPassComplete)
    #expect(passing.passes)
    #expect(!failingCapability.passes)
    #expect(failingCapability.missingCapabilities.contains("led"))
}

@Test("DualSense feedback contract can optionally enforce USB transport")
func dualSenseFeedbackOptionalUSBPolicy() {
    let contract = DualSenseFeedbackContract(requiresUSBTransport: true)
    let complete = DualSenseFeedbackCapabilities(
        supportsRumble: true,
        supportsAdaptiveTriggers: true,
        supportsLED: true
    )

    let passing = contract.evaluate(capabilities: complete, transport: .usb)
    let failingTransport = contract.evaluate(capabilities: complete, transport: .bluetooth)

    #expect(passing.passes)
    #expect(!failingTransport.passes)
    #expect(failingTransport.missingCapabilities.contains("usbTransport"))
}
