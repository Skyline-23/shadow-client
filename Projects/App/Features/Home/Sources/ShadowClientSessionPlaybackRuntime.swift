import AVFoundation
import Foundation

public enum ShadowClientSessionPlaybackState: Equatable, Sendable {
    case idle
    case playing(sessionURL: String)
    case failed(message: String)
}

@MainActor
public final class ShadowClientSessionPlaybackRuntime: ObservableObject {
    @Published public private(set) var player: AVPlayer
    @Published public private(set) var state: ShadowClientSessionPlaybackState = .idle
    private var currentSessionURL: String?

    public init() {
        let player = AVPlayer()
        player.automaticallyWaitsToMinimizeStalling = false
        self.player = player
        self.currentSessionURL = nil
    }

    public func start(sessionURL: String) {
        guard let resolvedURL = Self.resolveSessionURL(sessionURL) else {
            currentSessionURL = nil
            player.pause()
            player.replaceCurrentItem(with: nil)
            state = .failed(message: "Invalid video session URL.")
            return
        }

        let normalizedURL = resolvedURL.absoluteString
        if currentSessionURL == normalizedURL {
            if case .playing = state {
                player.play()
                return
            }
        }

        currentSessionURL = normalizedURL
        let item = AVPlayerItem(url: resolvedURL)
        player.replaceCurrentItem(with: item)

        state = .playing(sessionURL: normalizedURL)
        player.play()
    }

    public func stop() {
        currentSessionURL = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        state = .idle
    }

    static func resolveSessionURL(_ rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let candidate = trimmed.contains("://") ? trimmed : "rtsp://\(trimmed)"
        guard let url = URL(string: candidate),
              let scheme = url.scheme,
              !scheme.isEmpty,
              let host = url.host,
              !host.isEmpty
        else {
            return nil
        }

        return url
    }
}
