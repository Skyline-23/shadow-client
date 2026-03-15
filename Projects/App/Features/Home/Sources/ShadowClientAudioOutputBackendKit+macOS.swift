#if os(macOS)
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
        try ShadowClientRealtimeSampleBufferAudioOutput(
            format: format,
            maximumQueuedBufferCount: maximumQueuedBufferCount,
            nominalFramesPerBuffer: nominalFramesPerBuffer,
            maximumPendingDurationMs: maximumPendingDurationMs,
            synchronizationPolicy: synchronizationPolicy,
            prefersSpatialHeadphoneRendering: prefersSpatialHeadphoneRendering
        )
    }
}
#endif
