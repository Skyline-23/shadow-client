public struct MoonlightSessionLaunchSettings: Equatable, Sendable {
    public let hdrVideoMode: HDRVideoMode
    public let audioMode: StreamAudioMode
    public let targetBufferMs: Int
    public let qualityReductionRequested: Bool
    public let recoveryStableSamplesRemaining: Int

    public init(
        hdrVideoMode: HDRVideoMode,
        audioMode: StreamAudioMode,
        targetBufferMs: Int,
        qualityReductionRequested: Bool,
        recoveryStableSamplesRemaining: Int
    ) {
        self.hdrVideoMode = hdrVideoMode
        self.audioMode = audioMode
        self.targetBufferMs = max(0, targetBufferMs)
        self.qualityReductionRequested = qualityReductionRequested
        self.recoveryStableSamplesRemaining = max(0, recoveryStableSamplesRemaining)
    }

    public var isHDREnabled: Bool {
        hdrVideoMode == .hdr10
    }

    public var audioChannelCount: Int {
        switch audioMode {
        case .stereo:
            return 2
        case .surround51:
            return 6
        }
    }
}

public struct MoonlightSessionReconfigurationPlan: Equatable, Sendable {
    public let settings: MoonlightSessionLaunchSettings
    public let shouldRenegotiateVideoPipeline: Bool
    public let shouldRenegotiateAudioPipeline: Bool
    public let shouldApplyQualityDropImmediately: Bool

    public init(
        settings: MoonlightSessionLaunchSettings,
        shouldRenegotiateVideoPipeline: Bool,
        shouldRenegotiateAudioPipeline: Bool,
        shouldApplyQualityDropImmediately: Bool
    ) {
        self.settings = settings
        self.shouldRenegotiateVideoPipeline = shouldRenegotiateVideoPipeline
        self.shouldRenegotiateAudioPipeline = shouldRenegotiateAudioPipeline
        self.shouldApplyQualityDropImmediately = shouldApplyQualityDropImmediately
    }
}

public struct MoonlightSessionLaunchPlanBuilder: Sendable {
    public init() {}

    public func makeSettings(
        sessionConfiguration: StreamingSessionConfiguration,
        decision: LowLatencyStreamingDecision
    ) -> MoonlightSessionLaunchSettings {
        MoonlightSessionLaunchSettings(
            hdrVideoMode: sessionConfiguration.hdrVideoMode,
            audioMode: sessionConfiguration.audioMode,
            targetBufferMs: Int(decision.targetBufferMs.rounded()),
            qualityReductionRequested: decision.action == .requestQualityReduction,
            recoveryStableSamplesRemaining: decision.recoveryStableSamplesRemaining
        )
    }

    public func makePlan(
        previousSettings: MoonlightSessionLaunchSettings?,
        sessionConfiguration: StreamingSessionConfiguration,
        decision: LowLatencyStreamingDecision
    ) -> MoonlightSessionReconfigurationPlan {
        let settings = makeSettings(
            sessionConfiguration: sessionConfiguration,
            decision: decision
        )

        let shouldRenegotiateVideoPipeline: Bool
        let shouldRenegotiateAudioPipeline: Bool
        if let previousSettings {
            shouldRenegotiateVideoPipeline = previousSettings.hdrVideoMode != settings.hdrVideoMode
            shouldRenegotiateAudioPipeline = previousSettings.audioMode != settings.audioMode
        } else {
            shouldRenegotiateVideoPipeline = false
            shouldRenegotiateAudioPipeline = false
        }

        return MoonlightSessionReconfigurationPlan(
            settings: settings,
            shouldRenegotiateVideoPipeline: shouldRenegotiateVideoPipeline,
            shouldRenegotiateAudioPipeline: shouldRenegotiateAudioPipeline,
            shouldApplyQualityDropImmediately: settings.qualityReductionRequested
        )
    }
}

public actor AdaptiveSessionLaunchRuntime {
    public struct IngestResult: Equatable, Sendable {
        public let decision: LowLatencyStreamingDecision
        public let plan: MoonlightSessionReconfigurationPlan

        public init(
            decision: LowLatencyStreamingDecision,
            plan: MoonlightSessionReconfigurationPlan
        ) {
            self.decision = decision
            self.plan = plan
        }
    }

    private let telemetryPipeline: LowLatencyTelemetryPipeline
    private let settingsMapper: StreamingSessionSettingsMapper
    private let launchPlanBuilder: MoonlightSessionLaunchPlanBuilder
    private let sessionPreferences: StreamingUserPreferences
    private let hostCapabilities: HostStreamingCapabilities
    private var previousSettings: MoonlightSessionLaunchSettings?

    public init(
        telemetryPipeline: LowLatencyTelemetryPipeline = .init(),
        settingsMapper: StreamingSessionSettingsMapper = .init(),
        launchPlanBuilder: MoonlightSessionLaunchPlanBuilder = .init(),
        sessionPreferences: StreamingUserPreferences = .init(
            preferHDR: true,
            preferSurroundAudio: true,
            lowLatencyMode: true
        ),
        hostCapabilities: HostStreamingCapabilities = .init(
            supportsHDR10: true,
            supportsSurround51: true
        )
    ) {
        self.telemetryPipeline = telemetryPipeline
        self.settingsMapper = settingsMapper
        self.launchPlanBuilder = launchPlanBuilder
        self.sessionPreferences = sessionPreferences
        self.hostCapabilities = hostCapabilities
        self.previousSettings = nil
    }

    public func ingest(_ snapshot: StreamingTelemetrySnapshot) async -> IngestResult {
        let decision = await telemetryPipeline.ingest(snapshot)
        let sessionConfiguration = settingsMapper.map(
            preferences: sessionPreferences,
            capabilities: hostCapabilities,
            signal: snapshot.signal
        )
        let plan = launchPlanBuilder.makePlan(
            previousSettings: previousSettings,
            sessionConfiguration: sessionConfiguration,
            decision: decision
        )
        previousSettings = plan.settings
        return IngestResult(decision: decision, plan: plan)
    }

    public func currentSettings() -> MoonlightSessionLaunchSettings? {
        previousSettings
    }
}
