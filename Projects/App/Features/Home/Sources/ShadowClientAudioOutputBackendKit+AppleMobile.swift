#if os(iOS) || os(tvOS)
@preconcurrency import AVFoundation
import ShadowClientFeatureSession

enum ShadowClientAudioOutputBackendPlatformKit {
    static func make(
        format: AVAudioFormat,
        maximumQueuedBufferCount: Int,
        nominalFramesPerBuffer: AVAudioFrameCount,
        maximumPendingDurationMs: Double,
        synchronizationPolicy: ShadowClientAudioSynchronizationPolicy,
        prefersSpatialHeadphoneRendering: Bool
    ) throws -> any ShadowClientRealtimeAudioOutput {
        switch ShadowClientAudioOutputBackendKit.preferredBackend(
            format: format,
            synchronizationPolicy: synchronizationPolicy
        ) {
        case .sampleBufferRenderer:
            return try ShadowClientRealtimeSampleBufferAudioOutput(
                format: format,
                maximumQueuedBufferCount: maximumQueuedBufferCount,
                nominalFramesPerBuffer: nominalFramesPerBuffer,
                maximumPendingDurationMs: maximumPendingDurationMs,
                synchronizationPolicy: synchronizationPolicy,
                prefersSpatialHeadphoneRendering: prefersSpatialHeadphoneRendering
            )
        case .audioEngine:
            return try ShadowClientRealtimeAudioEngineOutput(
                format: format,
                maximumQueuedBufferCount: maximumQueuedBufferCount,
                nominalFramesPerBuffer: nominalFramesPerBuffer,
                maximumPendingDurationMs: maximumPendingDurationMs,
                prefersSpatialHeadphoneRendering: prefersSpatialHeadphoneRendering
            )
        }
    }
}
#endif
