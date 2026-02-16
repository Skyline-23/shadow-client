import ShadowClientInput
import ShadowClientStreaming
import ShadowClientUI

public struct HomeFeatureSnapshot: Equatable, Sendable {
    public let streamHealthy: Bool
    public let inputHealthy: Bool
    public let feedbackReady: Bool
    public let badge: StreamHealthBadgeModel

    public init(
        streamHealthy: Bool,
        inputHealthy: Bool,
        feedbackReady: Bool,
        badge: StreamHealthBadgeModel
    ) {
        self.streamHealthy = streamHealthy
        self.inputHealthy = inputHealthy
        self.feedbackReady = feedbackReady
        self.badge = badge
    }
}

public struct HomeFeatureBuilder: Sendable {
    public let streamChecker: StreamingStabilityChecker
    public let inputEvaluator: InputRoundTripGateEvaluator
    public let feedbackContract: DualSenseFeedbackContract
    public let presenter: StreamHealthPresenter

    public init(
        streamChecker: StreamingStabilityChecker = .init(),
        inputEvaluator: InputRoundTripGateEvaluator = .init(),
        feedbackContract: DualSenseFeedbackContract = .init(),
        presenter: StreamHealthPresenter = .init()
    ) {
        self.streamChecker = streamChecker
        self.inputEvaluator = inputEvaluator
        self.feedbackContract = feedbackContract
        self.presenter = presenter
    }

    public func makeSnapshot(
        streamingStats: StreamingStats,
        inputSamples: [InputRTTSample],
        feedbackCapabilities: DualSenseFeedbackCapabilities,
        transport: DualSenseTransport = .usb
    ) -> HomeFeatureSnapshot {
        let streaming = streamChecker.evaluate(streamingStats)
        let input = inputEvaluator.evaluate(samples: inputSamples)
        let feedback = feedbackContract.evaluate(
            capabilities: feedbackCapabilities,
            transport: transport
        )

        return HomeFeatureSnapshot(
            streamHealthy: streaming.passes,
            inputHealthy: input.passes,
            feedbackReady: feedback.passes,
            badge: presenter.makeBadge(streaming: streaming, inputLatency: input, feedback: feedback)
        )
    }
}
