import AVFAudio
import Foundation
import os

private actor ShadowClientIOSAudioSessionController {
    nonisolated private static let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "iOSAudioSession"
    )

    func ensurePlaybackSessionActive() async {
        await MainActor.run {
            Self.applyPlaybackSessionConfiguration()
        }
    }

    func deactivatePlaybackSessionIfNeeded() async {
        await MainActor.run {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setActive(false, options: [.notifyOthersOnDeactivation])
            } catch {
                Self.logger.error(
                    "AVAudioSession deactivation failed: \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    @MainActor
    private static func applyPlaybackSessionConfiguration() {
        let session = AVAudioSession.sharedInstance()

        func activate(options: AVAudioSession.CategoryOptions) throws {
            try session.setPreferredSampleRate(48_000)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setCategory(.playback, mode: .default, options: options)
            try session.setSupportsMultichannelContent(true)
            try session.setActive(true, options: [])
            let routeSummary = session.currentRoute.outputs
                .map { output in
                    "\(output.portType.rawValue){name=\(output.portName),channels=\(output.channels?.count ?? 0),spatial=\(output.isSpatialAudioEnabled)}"
                }
                .joined(separator: ",")
            Self.logger.notice(
                "AVAudioSession activated multichannel=\(session.supportsMultichannelContent, privacy: .public) max-output-channels=\(session.maximumOutputNumberOfChannels, privacy: .public) output-channels=\(session.outputNumberOfChannels, privacy: .public) routes=[\(routeSummary, privacy: .public)]"
            )
        }

        do {
            try activate(options: [])
            return
        } catch {
            Self.logger.error(
                "AVAudioSession primary activation failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        do {
            try activate(options: [.allowAirPlay])
            return
        } catch {
            Self.logger.error(
                "AVAudioSession AirPlay fallback failed: \(error.localizedDescription, privacy: .public)"
            )
        }

        do {
            try activate(options: [.allowBluetoothA2DP])
            return
        } catch {
            Self.logger.error(
                "AVAudioSession Bluetooth fallback failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}

enum ShadowClientIOSAudioSessionCoordinator {
    private static let controller = ShadowClientIOSAudioSessionController()

    static func ensurePlaybackSessionActive() async {
        await controller.ensurePlaybackSessionActive()
    }

    static func deactivatePlaybackSessionIfNeeded() async {
        await controller.deactivatePlaybackSessionIfNeeded()
    }
}
