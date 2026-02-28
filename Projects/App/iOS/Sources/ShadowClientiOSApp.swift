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
        func activate(options: AVAudioSession.CategoryOptions) throws {
            try session.setCategory(
                .playback,
                mode: .default,
                options: options
            )
            try session.setActive(true, options: [])
        }

        do {
            try activate(options: [])
            return
        } catch {
            logger.error("AVAudioSession bootstrap primary path failed: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try activate(options: [.allowAirPlay])
            return
        } catch {
            logger.error("AVAudioSession bootstrap AirPlay fallback failed: \(error.localizedDescription, privacy: .public)")
        }

        do {
            try activate(options: [.allowBluetoothA2DP])
            return
        } catch {
            logger.error("AVAudioSession bootstrap Bluetooth fallback failed: \(error.localizedDescription, privacy: .public)")
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
