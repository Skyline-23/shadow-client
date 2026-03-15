import Foundation

struct ShadowClientAudioOutputTimingBudget: Sendable {
    let outputLatencySeconds: Double
    let ioBufferDurationSeconds: Double

    var drainDurationSeconds: Double {
        max(0, outputLatencySeconds) + max(0, ioBufferDurationSeconds)
    }

    var rendererLeadDurationSeconds: Double {
        max(0, ioBufferDurationSeconds)
    }

    func startupPrerollDurationSeconds(packetDurationSeconds: Double) -> Double {
        let normalizedPacketDurationSeconds = max(0, packetDurationSeconds)
        return max(
            normalizedPacketDurationSeconds,
            rendererLeadDurationSeconds + normalizedPacketDurationSeconds
        )
    }

    func steadyStateBufferedDurationSeconds(packetDurationSeconds: Double) -> Double {
        let normalizedPacketDurationSeconds = max(0, packetDurationSeconds)
        return max(
            normalizedPacketDurationSeconds * 2,
            rendererLeadDurationSeconds + normalizedPacketDurationSeconds
        )
    }

    func lateTrimDurationSeconds(packetDurationSeconds: Double) -> Double {
        let normalizedPacketDurationSeconds = max(0, packetDurationSeconds)
        return max(
            normalizedPacketDurationSeconds * 3,
            steadyStateBufferedDurationSeconds(packetDurationSeconds: normalizedPacketDurationSeconds) + normalizedPacketDurationSeconds
        )
    }
}

enum ShadowClientAudioOutputCapabilityKit {
    static func supportsHeadTrackedRoute() -> Bool {
        ShadowClientAudioOutputCapabilityPlatformKit.supportsHeadTrackedRoute()
    }

    static func prefersSpatialHeadphoneRendering(channels: Int) async -> Bool {
        await ShadowClientAudioOutputCapabilityPlatformKit.prefersSpatialHeadphoneRendering(
            channels: channels
        )
    }

    static func maximumOutputChannels() async -> Int {
        await ShadowClientAudioOutputCapabilityPlatformKit.maximumOutputChannels()
    }

    @MainActor
    static func currentMaximumOutputChannels() -> Int {
        ShadowClientAudioOutputCapabilityPlatformKit.currentMaximumOutputChannels()
    }

    static func currentRouteSummary() -> String {
        ShadowClientAudioOutputCapabilityPlatformKit.currentRouteSummary()
    }

    static func currentRenderingSummary() -> String {
        ShadowClientAudioOutputCapabilityPlatformKit.currentRenderingSummary()
    }

    static func currentTimingBudget() -> ShadowClientAudioOutputTimingBudget {
        ShadowClientAudioOutputCapabilityPlatformKit.currentTimingBudget()
    }
}
