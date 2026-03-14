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
        self.container = .live(
            bridge: bridge,
            remoteDesktopDependencies: .live(
                prepareAudioDecoders: {
                    await ShadowClientNativeAudioDecodingPlugin.ensureDefaultDecodersRegistered()
                },
                audioSessionActivation: {
                    await ShadowClientIOSAudioSessionCoordinator.ensurePlaybackSessionActive()
                },
                audioSessionDeactivation: {
                    await ShadowClientIOSAudioSessionCoordinator.deactivatePlaybackSessionIfNeeded()
                }
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                dependencies: container.dependencies
            )
            .onOpenURL { url in
                NotificationCenter.default.post(
                    name: .shadowClientApolloPairingLinkReceived,
                    object: url
                )
            }
        }
    }
}
