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
}
