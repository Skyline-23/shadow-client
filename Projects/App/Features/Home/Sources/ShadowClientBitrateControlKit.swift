import Foundation
import ShadowClientStreaming
import ShadowClientFeatureSession

struct ShadowClientBitrateControlKit {
    static func effectiveBitrateKbps(
        settings: ShadowClientAppSettings,
        networkSignal: StreamingNetworkSignal?
    ) -> Int {
        settings.resolvedBitrateKbps(networkSignal: networkSignal)
    }

    static func clampedBitrateKbps(
        sliderValue: Double,
        maxBitrateKbps: Double
    ) -> Int {
        let rounded = Int(sliderValue.rounded() / Double(ShadowClientAppSettingsDefaults.bitrateStepKbps)) * ShadowClientAppSettingsDefaults.bitrateStepKbps
        return min(
            max(ShadowClientStreamingLaunchBounds.minimumBitrateKbps, rounded),
            Int(maxBitrateKbps)
        )
    }
}
