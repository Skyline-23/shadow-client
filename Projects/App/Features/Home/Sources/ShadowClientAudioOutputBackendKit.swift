@preconcurrency import AVFoundation
import Foundation

enum ShadowClientAudioOutputBackendKit {
    static func make(
        format: AVAudioFormat,
        maximumQueuedBufferCount: Int,
        nominalFramesPerBuffer: AVAudioFrameCount,
        maximumPendingDurationMs: Double,
        prefersSpatialHeadphoneRendering: Bool
    ) throws -> any ShadowClientRealtimeAudioOutput {
        try ShadowClientAudioOutputBackendPlatformKit.make(
            format: format,
            maximumQueuedBufferCount: maximumQueuedBufferCount,
            nominalFramesPerBuffer: nominalFramesPerBuffer,
            maximumPendingDurationMs: maximumPendingDurationMs,
            prefersSpatialHeadphoneRendering: prefersSpatialHeadphoneRendering
        )
    }
}
