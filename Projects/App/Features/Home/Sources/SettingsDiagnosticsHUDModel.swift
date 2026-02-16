import ShadowClientStreaming
import ShadowClientUI

public struct SettingsDiagnosticsHUDModel: Equatable, Sendable {
    public let tone: HealthTone
    public let hdrVideoMode: HDRVideoMode
    public let audioMode: StreamAudioMode
    public let shouldRenegotiateVideoPipeline: Bool
    public let shouldRenegotiateAudioPipeline: Bool
    public let shouldApplyQualityDropImmediately: Bool
    public let recoveryStableSamplesRemaining: Int

    public init(tick: HomeDiagnosticsTick) {
        tone = tick.model.tone
        hdrVideoMode = tick.sessionPlan.settings.hdrVideoMode
        audioMode = tick.sessionPlan.settings.audioMode
        shouldRenegotiateVideoPipeline = tick.sessionPlan.shouldRenegotiateVideoPipeline
        shouldRenegotiateAudioPipeline = tick.sessionPlan.shouldRenegotiateAudioPipeline
        shouldApplyQualityDropImmediately = tick.sessionPlan.shouldApplyQualityDropImmediately
        recoveryStableSamplesRemaining = tick.model.recoveryStableSamplesRemaining
    }
}
