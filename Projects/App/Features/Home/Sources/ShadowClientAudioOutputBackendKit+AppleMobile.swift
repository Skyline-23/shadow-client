#if os(iOS) || os(tvOS)
@preconcurrency import AVFoundation

enum ShadowClientAudioOutputBackendPlatformKit {
    static func make(
        format: AVAudioFormat,
        maximumQueuedBufferCount: Int,
        nominalFramesPerBuffer: AVAudioFrameCount,
        maximumPendingDurationMs: Double,
        prefersSpatialHeadphoneRendering: Bool
    ) throws -> any ShadowClientRealtimeAudioOutput {
        if prefersSpatialHeadphoneRendering || format.channelCount > 2 {
            try ShadowClientRealtimeSampleBufferAudioOutput(
                format: format,
                maximumQueuedBufferCount: maximumQueuedBufferCount,
                nominalFramesPerBuffer: nominalFramesPerBuffer,
                maximumPendingDurationMs: maximumPendingDurationMs,
                prefersSpatialHeadphoneRendering: prefersSpatialHeadphoneRendering
            )
        } else {
            try ShadowClientRealtimeAudioEngineOutput(
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
