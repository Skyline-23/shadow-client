import AVFAudio
import Foundation
import os

enum ShadowClientIOSAudioSessionCoordinator {
    private static let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "iOSAudioSession"
    )

    static func configurePlaybackSession() {
        if Thread.isMainThread {
            applyPlaybackSessionConfiguration()
        } else {
            DispatchQueue.main.sync {
                applyPlaybackSessionConfiguration()
            }
        }
    }

    static func ensurePlaybackSessionActive() async {
        await MainActor.run {
            applyPlaybackSessionConfiguration()
        }
    }

    private static func applyPlaybackSessionConfiguration() {
        let session = AVAudioSession.sharedInstance()

        func activate(options: AVAudioSession.CategoryOptions) throws {
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setActive(true, options: [])
        }

        do {
            try activate(options: [])
            return
        } catch {
            logger.error(
                "AVAudioSession primary activation failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        do {
            try activate(options: [.allowAirPlay])
            return
        } catch {
            logger.error(
                "AVAudioSession AirPlay fallback failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        do {
            try activate(options: [.allowBluetoothA2DP])
            return
        } catch {
            logger.error(
                "AVAudioSession Bluetooth fallback failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
