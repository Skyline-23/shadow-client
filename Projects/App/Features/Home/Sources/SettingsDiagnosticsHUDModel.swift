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
    public let targetBufferMs: Int
    public let jitterMs: Int
    public let packetLossPercent: Double
    public let frameDropPercent: Double
    public let avSyncOffsetMs: Int
    public let networkDroppedFrames: Int
    public let pacerDroppedFrames: Int
    public let timestampMs: Int
    public let sampleIntervalMs: Int?
    public let receivedOutOfOrderSample: Bool

    public init(
        tick: HomeDiagnosticsTick,
        sampleIntervalMs: Int? = nil,
        receivedOutOfOrderSample: Bool = false
    ) {
        tone = tick.model.tone
        hdrVideoMode = tick.sessionPlan.settings.hdrVideoMode
        audioMode = tick.sessionPlan.settings.audioMode
        shouldRenegotiateVideoPipeline = tick.sessionPlan.shouldRenegotiateVideoPipeline
        shouldRenegotiateAudioPipeline = tick.sessionPlan.shouldRenegotiateAudioPipeline
        shouldApplyQualityDropImmediately = tick.sessionPlan.shouldApplyQualityDropImmediately
        recoveryStableSamplesRemaining = tick.model.recoveryStableSamplesRemaining
        targetBufferMs = tick.sessionPlan.settings.targetBufferMs
        jitterMs = tick.model.jitterMs
        packetLossPercent = tick.model.packetLossPercent
        frameDropPercent = tick.model.frameDropPercent
        avSyncOffsetMs = tick.model.avSyncOffsetMs
        networkDroppedFrames = tick.model.networkDroppedFrames
        pacerDroppedFrames = tick.model.pacerDroppedFrames
        timestampMs = tick.timestampMs
        self.sampleIntervalMs = sampleIntervalMs
        self.receivedOutOfOrderSample = receivedOutOfOrderSample
    }
}
