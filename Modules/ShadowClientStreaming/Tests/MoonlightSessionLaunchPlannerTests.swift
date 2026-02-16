import Testing
@testable import ShadowClientStreaming

@Test("Launch plan builder maps settings and quality-drop intent into launch settings")
func launchPlanBuilderMapsSettingsAndQualityDropIntent() {
    let builder = MoonlightSessionLaunchPlanBuilder()
    let configuration = StreamingSessionConfiguration(
        hdrVideoMode: .hdr10,
        audioMode: .surround51
    )
    let decision = LowLatencyStreamingDecision(
        targetBufferMs: 46.0,
        action: .requestQualityReduction,
        stabilityPasses: false,
        recoveryStableSamplesRemaining: 2
    )

    let plan = builder.makePlan(
        previousSettings: nil,
        sessionConfiguration: configuration,
        decision: decision
    )

    #expect(plan.settings.hdrVideoMode == .hdr10)
    #expect(plan.settings.audioMode == .surround51)
    #expect(plan.settings.audioChannelCount == 6)
    #expect(plan.settings.isHDREnabled)
    #expect(plan.settings.targetBufferMs == 46)
    #expect(plan.settings.qualityReductionRequested)
    #expect(plan.settings.recoveryStableSamplesRemaining == 2)
    #expect(!plan.shouldRenegotiateVideoPipeline)
    #expect(!plan.shouldRenegotiateAudioPipeline)
    #expect(plan.shouldApplyQualityDropImmediately)
}

@Test("Launch plan builder flags renegotiation when HDR and audio modes change")
func launchPlanBuilderFlagsRenegotiationOnModeChanges() {
    let builder = MoonlightSessionLaunchPlanBuilder()
    let previous = MoonlightSessionLaunchSettings(
        hdrVideoMode: .hdr10,
        audioMode: .surround51,
        targetBufferMs: 44,
        qualityReductionRequested: false,
        recoveryStableSamplesRemaining: 0
    )
    let nextConfiguration = StreamingSessionConfiguration(
        hdrVideoMode: .off,
        audioMode: .stereo
    )
    let decision = LowLatencyStreamingDecision(
        targetBufferMs: 52.0,
        action: .holdQuality,
        stabilityPasses: true,
        recoveryStableSamplesRemaining: 0
    )

    let plan = builder.makePlan(
        previousSettings: previous,
        sessionConfiguration: nextConfiguration,
        decision: decision
    )

    #expect(plan.settings.hdrVideoMode == .off)
    #expect(plan.settings.audioMode == .stereo)
    #expect(plan.settings.audioChannelCount == 2)
    #expect(!plan.settings.isHDREnabled)
    #expect(plan.shouldRenegotiateVideoPipeline)
    #expect(plan.shouldRenegotiateAudioPipeline)
    #expect(!plan.shouldApplyQualityDropImmediately)
}

@Test("Adaptive session launch runtime emits renegotiation plan across healthy to degraded transition")
func adaptiveSessionLaunchRuntimeEmitsRenegotiationPlanAcrossTransition() async {
    let runtime = AdaptiveSessionLaunchRuntime(
        sessionPreferences: .init(
            preferHDR: true,
            preferSurroundAudio: true,
            lowLatencyMode: false
        ),
        hostCapabilities: .init(
            supportsHDR10: true,
            supportsSurround51: true
        )
    )
    let healthySnapshot = StreamingTelemetrySnapshot(
        stats: StreamingStats(
            renderedFrames: 995,
            droppedFrames: 5,
            avSyncOffsetMilliseconds: 8.0
        ),
        signal: StreamingNetworkSignal(jitterMs: 3.0, packetLossPercent: 0.2),
        timestampMs: 1_000
    )
    let degradedSnapshot = StreamingTelemetrySnapshot(
        stats: StreamingStats(
            renderedFrames: 960,
            droppedFrames: 40,
            avSyncOffsetMilliseconds: 55.0
        ),
        signal: StreamingNetworkSignal(jitterMs: 80.0, packetLossPercent: 3.0),
        timestampMs: 1_016
    )

    let firstPlan = await runtime.ingest(healthySnapshot)
    let secondPlan = await runtime.ingest(degradedSnapshot)

    #expect(firstPlan.settings.hdrVideoMode == .hdr10)
    #expect(firstPlan.settings.audioMode == .surround51)
    #expect(firstPlan.settings.targetBufferMs == 38)
    #expect(!firstPlan.shouldRenegotiateVideoPipeline)
    #expect(!firstPlan.shouldRenegotiateAudioPipeline)
    #expect(!firstPlan.shouldApplyQualityDropImmediately)

    #expect(secondPlan.settings.hdrVideoMode == .off)
    #expect(secondPlan.settings.audioMode == .stereo)
    #expect(secondPlan.settings.targetBufferMs == 46)
    #expect(secondPlan.settings.qualityReductionRequested)
    #expect(secondPlan.settings.recoveryStableSamplesRemaining == 2)
    #expect(secondPlan.shouldRenegotiateVideoPipeline)
    #expect(secondPlan.shouldRenegotiateAudioPipeline)
    #expect(secondPlan.shouldApplyQualityDropImmediately)
}
