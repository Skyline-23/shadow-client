import ShadowClientFeatureHome
import ShadowClientStreaming
import ShadowClientUI
import Testing

@Test("Settings diagnostics HUD model maps launch plan and tone from diagnostics tick")
func settingsDiagnosticsHUDModelMapsTick() {
    let tick = makeTick(
        tone: .critical,
        hdrVideoMode: .hdr10,
        audioMode: .surround51,
        shouldRenegotiateVideoPipeline: true,
        shouldRenegotiateAudioPipeline: false,
        shouldApplyQualityDropImmediately: true,
        recoveryStableSamplesRemaining: 3
    )

    let model = SettingsDiagnosticsHUDModel(tick: tick)

    #expect(model.tone == .critical)
    #expect(model.hdrVideoMode == .hdr10)
    #expect(model.audioMode == .surround51)
    #expect(model.shouldRenegotiateVideoPipeline)
    #expect(!model.shouldRenegotiateAudioPipeline)
    #expect(model.shouldApplyQualityDropImmediately)
    #expect(model.recoveryStableSamplesRemaining == 3)
    #expect(model.targetBufferMs == 48)
    #expect(model.jitterMs == 24)
    #expect(model.packetLossPercent == 2.0)
    #expect(model.frameDropPercent == 1.4)
    #expect(model.avSyncOffsetMs == 6)
    #expect(model.networkDroppedFrames == 12)
    #expect(model.pacerDroppedFrames == 2)
    #expect(model.timestampMs == 1_024)
    #expect(model.sampleIntervalMs == nil)
}

@Test("Settings diagnostics HUD model preserves zero recovery hold")
func settingsDiagnosticsHUDModelZeroRecoveryHold() {
    let tick = makeTick(
        tone: .healthy,
        hdrVideoMode: .off,
        audioMode: .stereo,
        shouldRenegotiateVideoPipeline: false,
        shouldRenegotiateAudioPipeline: false,
        shouldApplyQualityDropImmediately: false,
        recoveryStableSamplesRemaining: 0
    )

    let model = SettingsDiagnosticsHUDModel(tick: tick)

    #expect(model.tone == .healthy)
    #expect(model.hdrVideoMode == .off)
    #expect(model.audioMode == .stereo)
    #expect(model.recoveryStableSamplesRemaining == 0)
    #expect(model.targetBufferMs == 48)
    #expect(model.timestampMs == 1_024)
    #expect(model.sampleIntervalMs == nil)
}

private func makeTick(
    tone: HealthTone,
    hdrVideoMode: HDRVideoMode,
    audioMode: StreamAudioMode,
    shouldRenegotiateVideoPipeline: Bool,
    shouldRenegotiateAudioPipeline: Bool,
    shouldApplyQualityDropImmediately: Bool,
    recoveryStableSamplesRemaining: Int
) -> HomeDiagnosticsTick {
    HomeDiagnosticsTick(
        model: .init(
            bufferMs: 48,
            jitterMs: 24,
            packetLossPercent: 2.0,
            frameDropPercent: 1.4,
            avSyncOffsetMs: 6,
            networkDroppedFrames: 12,
            pacerDroppedFrames: 2,
            recoveryStableSamplesRemaining: recoveryStableSamplesRemaining,
            tone: tone
        ),
        sessionPlan: .init(
            settings: .init(
                hdrVideoMode: hdrVideoMode,
                audioMode: audioMode,
                targetBufferMs: 48,
                qualityReductionRequested: shouldApplyQualityDropImmediately,
                recoveryStableSamplesRemaining: recoveryStableSamplesRemaining
            ),
            shouldRenegotiateVideoPipeline: shouldRenegotiateVideoPipeline,
            shouldRenegotiateAudioPipeline: shouldRenegotiateAudioPipeline,
            shouldApplyQualityDropImmediately: shouldApplyQualityDropImmediately
        ),
        timestampMs: 1_024
    )
}
