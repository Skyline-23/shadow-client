@preconcurrency import AVFoundation
import Foundation
import ShadowClientFeatureSession

enum ShadowClientAudioOutputBackendKind: Equatable {
    case sampleBufferRenderer
    case audioEngine
}

enum ShadowClientAudioOutputBackendKit {
    static func preferredBackend(
        format: AVAudioFormat,
        synchronizationPolicy: ShadowClientAudioSynchronizationPolicy
    ) -> ShadowClientAudioOutputBackendKind {
        if synchronizationPolicy == .lowLatency, format.channelCount <= 2 {
            return .audioEngine
        }
        return .sampleBufferRenderer
    }

    static func make(
        format: AVAudioFormat,
        maximumQueuedBufferCount: Int,
        nominalFramesPerBuffer: AVAudioFrameCount,
        maximumPendingDurationMs: Double,
        synchronizationPolicy: ShadowClientAudioSynchronizationPolicy,
        prefersSpatialHeadphoneRendering: Bool
    ) throws -> any ShadowClientRealtimeAudioOutput {
        try ShadowClientAudioOutputBackendPlatformKit.make(
            format: format,
            maximumQueuedBufferCount: maximumQueuedBufferCount,
            nominalFramesPerBuffer: nominalFramesPerBuffer,
            maximumPendingDurationMs: maximumPendingDurationMs,
            synchronizationPolicy: synchronizationPolicy,
            prefersSpatialHeadphoneRendering: prefersSpatialHeadphoneRendering
        )
    }
}
