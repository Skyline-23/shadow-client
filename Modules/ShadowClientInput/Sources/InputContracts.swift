import Foundation
import ShadowClientCore

public struct InputRTTSample: Equatable, Sendable {
    public let milliseconds: Double

    public init(milliseconds: Double) {
        self.milliseconds = milliseconds
    }
}

public struct InputRoundTripAnalyzer: Sendable {
    public init() {}

    public func p95Milliseconds(from samples: [InputRTTSample]) -> Double {
        guard !samples.isEmpty else { return .infinity }
        let sorted = samples.map(\.milliseconds).sorted()
        let index = Int(ceil(Double(sorted.count) * 0.95)) - 1
        let clampedIndex = min(max(index, 0), sorted.count - 1)
        return sorted[clampedIndex]
    }
}

public struct InputRoundTripGateEvaluator: Sendable {
    public let analyzer: InputRoundTripAnalyzer
    public let gate: InputRTTP95Gate

    public init(
        analyzer: InputRoundTripAnalyzer = .init(),
        gate: InputRTTP95Gate = .init()
    ) {
        self.analyzer = analyzer
        self.gate = gate
    }

    public func evaluate(samples: [InputRTTSample]) -> GateEvaluation {
        let p95 = analyzer.p95Milliseconds(from: samples)
        return gate.evaluate(p95Milliseconds: p95)
    }
}

public enum DualSenseTransport: String, Sendable {
    case usb
    case bluetooth
}

public struct DualSenseFeedbackCapabilities: Equatable, Sendable {
    public let supportsRumble: Bool
    public let supportsAdaptiveTriggers: Bool
    public let supportsLED: Bool

    public init(
        supportsRumble: Bool,
        supportsAdaptiveTriggers: Bool,
        supportsLED: Bool
    ) {
        self.supportsRumble = supportsRumble
        self.supportsAdaptiveTriggers = supportsAdaptiveTriggers
        self.supportsLED = supportsLED
    }

    public var isFirstPassComplete: Bool {
        supportsRumble && supportsAdaptiveTriggers && supportsLED
    }
}

public protocol DualSenseFeedbackDevice: Sendable {
    var transport: DualSenseTransport { get }
    var capabilities: DualSenseFeedbackCapabilities { get }
}

public struct DualSenseFeedbackResult: Equatable, Sendable {
    public let passes: Bool
    public let missingCapabilities: [String]
    public let transport: DualSenseTransport

    public init(passes: Bool, missingCapabilities: [String], transport: DualSenseTransport) {
        self.passes = passes
        self.missingCapabilities = missingCapabilities
        self.transport = transport
    }
}

public struct DualSenseFeedbackContract: Sendable {
    public let requiresUSBTransport: Bool

    public init(requiresUSBTransport: Bool = true) {
        self.requiresUSBTransport = requiresUSBTransport
    }

    public func evaluate(
        capabilities: DualSenseFeedbackCapabilities,
        transport: DualSenseTransport
    ) -> DualSenseFeedbackResult {
        var missing: [String] = []

        if requiresUSBTransport, transport != .usb {
            missing.append("usbTransport")
        }
        if !capabilities.supportsRumble {
            missing.append("rumble")
        }
        if !capabilities.supportsAdaptiveTriggers {
            missing.append("adaptiveTriggers")
        }
        if !capabilities.supportsLED {
            missing.append("led")
        }

        return DualSenseFeedbackResult(
            passes: missing.isEmpty,
            missingCapabilities: missing,
            transport: transport
        )
    }

    public func evaluate(device: any DualSenseFeedbackDevice) -> DualSenseFeedbackResult {
        evaluate(capabilities: device.capabilities, transport: device.transport)
    }
}
