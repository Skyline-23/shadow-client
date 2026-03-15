import Foundation

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
}
