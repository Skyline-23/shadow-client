#if os(iOS) || os(tvOS)
@preconcurrency import AVFoundation
import ShadowClientFeatureSession

enum ShadowClientAudioOutputBackendPlatformKit {
    static func make(
        format: AVAudioFormat,
        maximumQueuedBufferCount: Int,
        nominalFramesPerBuffer: AVAudioFrameCount,
        maximumPendingDurationMs: Double,
        prefersSpatialHeadphoneRendering: Bool
    ) throws -> any ShadowClientRealtimeAudioOutput {
        try ShadowClientRealtimeSampleBufferAudioOutput(
            format: format,
            maximumQueuedBufferCount: maximumQueuedBufferCount,
            nominalFramesPerBuffer: nominalFramesPerBuffer,
            maximumPendingDurationMs: maximumPendingDurationMs,
            prefersSpatialHeadphoneRendering: prefersSpatialHeadphoneRendering
        )
    }
}
#endif
