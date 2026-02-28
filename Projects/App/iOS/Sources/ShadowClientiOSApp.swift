import ShadowClientStreaming
import SwiftUI
import ShadowClientFeatureHome
import ShadowClientNativeAudioDecoding
import AVFAudio
import os

private enum ShadowClientiOSAudioSessionBootstrap {
    private static let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "iOSAudioSession"
    )

    static func configurePlaybackSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.allowBluetoothA2DP, .allowAirPlay]
            )
            try session.setActive(true, options: [])
        } catch {
            logger.error("Failed to configure AVAudioSession: \(error.localizedDescription, privacy: .public)")
        }
    }
}

@main
struct ShadowClientiOSApp: App {
    private let container: ShadowClientFeatureHomeContainer

    init() {
        let bridge = MoonlightSessionTelemetryBridge()
        MoonlightSessionTelemetryIngress.configure(bridge: bridge)
        ShadowClientiOSAudioSessionBootstrap.configurePlaybackSession()
        ShadowClientNativeAudioDecodingPlugin.registerDefaultDecoders()
        self.container = .live(bridge: bridge)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                dependencies: container.dependencies
            )
        }
    }
}
