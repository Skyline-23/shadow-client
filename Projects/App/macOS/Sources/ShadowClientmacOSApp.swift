import ShadowClientStreaming
import SwiftUI
import ShadowClientFeatureHome
import ShadowClientNativeAudioDecoding

@main
struct ShadowClientmacOSApp: App {
    private let container: ShadowClientFeatureHomeContainer

    init() {
        let bridge = MoonlightSessionTelemetryBridge()
        MoonlightSessionTelemetryIngress.configure(bridge: bridge)
        self.container = .live(
            bridge: bridge,
            remoteDesktopDependencies: .live(
                prepareAudioDecoders: {
                    await ShadowClientNativeAudioDecodingPlugin.ensureDefaultDecodersRegistered()
                }
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                dependencies: container.dependencies
            )
        }
    }
}
