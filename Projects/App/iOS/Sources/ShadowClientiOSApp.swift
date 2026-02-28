import ShadowClientStreaming
import SwiftUI
import ShadowClientFeatureHome
import ShadowClientNativeAudioDecoding

@main
struct ShadowClientiOSApp: App {
    private let container: ShadowClientFeatureHomeContainer

    init() {
        let bridge = MoonlightSessionTelemetryBridge()
        MoonlightSessionTelemetryIngress.configure(bridge: bridge)
        ShadowClientIOSAudioSessionCoordinator.configurePlaybackSession()
        ShadowClientNativeAudioDecodingPlugin.registerDefaultDecoders()
        self.container = .live(
            bridge: bridge,
            remoteDesktopDependencies: .live(
                audioSessionActivation: {
                    await ShadowClientIOSAudioSessionCoordinator.ensurePlaybackSessionActive()
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
