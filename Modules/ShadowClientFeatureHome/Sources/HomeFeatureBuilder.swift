import ShadowClientInput
import ShadowClientStreaming
import ShadowClientUI

public struct HomeFeatureSnapshot: Equatable, Sendable {
    public let streamHealthy: Bool
    public let inputHealthy: Bool
    public let feedbackReady: Bool
    public let sessionConfiguration: StreamingSessionConfiguration
    public let badge: StreamHealthBadgeModel

    public init(
        streamHealthy: Bool,
        inputHealthy: Bool,
        feedbackReady: Bool,
        sessionConfiguration: StreamingSessionConfiguration,
        badge: StreamHealthBadgeModel
    ) {
        self.streamHealthy = streamHealthy
        self.inputHealthy = inputHealthy
        self.feedbackReady = feedbackReady
        self.sessionConfiguration = sessionConfiguration
        self.badge = badge
    }
}

public struct HomeFeatureBuilder: Sendable {
    public let streamChecker: StreamingStabilityChecker
    public let inputEvaluator: InputRoundTripGateEvaluator
    public let feedbackContract: DualSenseFeedbackContract
    public let settingsMapper: StreamingSessionSettingsMapper
    public let sessionPreferences: StreamingUserPreferences
    public let hostCapabilities: HostStreamingCapabilities
    public let presenter: StreamHealthPresenter

    public init(
        streamChecker: StreamingStabilityChecker = .init(),
        inputEvaluator: InputRoundTripGateEvaluator = .init(),
        feedbackContract: DualSenseFeedbackContract = .init(),
        settingsMapper: StreamingSessionSettingsMapper = .init(),
        sessionPreferences: StreamingUserPreferences = .init(
            preferHDR: true,
            preferSurroundAudio: true,
            lowLatencyMode: true
        ),
        hostCapabilities: HostStreamingCapabilities = .init(
            supportsHDR10: true,
            supportsSurround51: true
        ),
        presenter: StreamHealthPresenter = .init()
    ) {
        self.streamChecker = streamChecker
        self.inputEvaluator = inputEvaluator
        self.feedbackContract = feedbackContract
        self.settingsMapper = settingsMapper
        self.sessionPreferences = sessionPreferences
        self.hostCapabilities = hostCapabilities
        self.presenter = presenter
    }

    public func makeSnapshot(
        streamingStats: StreamingStats,
        networkSignal: StreamingNetworkSignal = .init(jitterMs: 0.0, packetLossPercent: 0.0),
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
        let sessionConfiguration = settingsMapper.map(
            preferences: sessionPreferences,
            capabilities: hostCapabilities,
            signal: networkSignal
        )

        return HomeFeatureSnapshot(
            streamHealthy: streaming.passes,
            inputHealthy: input.passes,
            feedbackReady: feedback.passes,
            sessionConfiguration: sessionConfiguration,
            badge: presenter.makeBadge(streaming: streaming, inputLatency: input, feedback: feedback)
        )
    }
}
