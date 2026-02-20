import Foundation

public enum ShadowClientRemoteSessionLaunchTone: Equatable, Sendable {
    case idle
    case launching
    case launched
    case failed
}

public struct ShadowClientRemoteSessionOverlayModel: Equatable, Sendable {
    public let title: String
    public let symbol: String

    public init(title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }
}

public struct ShadowClientRemoteSessionPresentationModel: Equatable, Sendable {
    public let statusText: String
    public let overlay: ShadowClientRemoteSessionOverlayModel?
    public let launchTone: ShadowClientRemoteSessionLaunchTone

    public init(
        statusText: String,
        overlay: ShadowClientRemoteSessionOverlayModel?,
        launchTone: ShadowClientRemoteSessionLaunchTone
    ) {
        self.statusText = statusText
        self.overlay = overlay
        self.launchTone = launchTone
    }
}

public enum ShadowClientRemoteSessionPresentationMapper {
    public static func make(
        activeSessionEndpoint: String,
        launchState: ShadowClientRemoteLaunchState,
        renderState: ShadowClientRealtimeSessionSurfaceContext.RenderState = .idle
    ) -> ShadowClientRemoteSessionPresentationModel {
        let hasEndpoint = !activeSessionEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return make(
            hasSessionEndpoint: hasEndpoint,
            launchState: launchState,
            renderState: renderState
        )
    }

    static func make(
        hasSessionEndpoint: Bool,
        launchState: ShadowClientRemoteLaunchState,
        renderState: ShadowClientRealtimeSessionSurfaceContext.RenderState
    ) -> ShadowClientRemoteSessionPresentationModel {
        if !hasSessionEndpoint {
            return .init(
                statusText: "Session opened. Launch desktop/game on host to start remote stream.",
                overlay: .init(
                    title: "Waiting for remote desktop stream...",
                    symbol: "desktopcomputer"
                ),
                launchTone: .idle
            )
        }

        switch launchState {
        case .idle:
            return .init(
                statusText: "Session opened. Launch desktop/game on host to start remote stream.",
                overlay: .init(
                    title: "Connecting to remote desktop stream...",
                    symbol: "antenna.radiowaves.left.and.right"
                ),
                launchTone: .idle
            )
        case .launching:
            return .init(
                statusText: "Connecting to remote stream...",
                overlay: .init(
                    title: "Connecting to remote desktop stream...",
                    symbol: "antenna.radiowaves.left.and.right"
                ),
                launchTone: .launching
            )
        case .launched:
            switch renderState {
            case .rendering:
                return .init(
                    statusText: "Remote desktop session is live. Input and output are active.",
                    overlay: nil,
                    launchTone: .launched
                )
            case let .disconnected(message):
                return .init(
                    statusText: "Remote session disconnected: \(message)",
                    overlay: .init(
                        title: "Remote session disconnected. Reconnect to resume input/output.",
                        symbol: "wifi.slash"
                    ),
                    launchTone: .failed
                )
            case let .failed(message):
                return .init(
                    statusText: "Native decoder failed: \(message)",
                    overlay: .init(
                        title: "Native decoder failed. Check stream codec/session state.",
                        symbol: "exclamationmark.triangle"
                    ),
                    launchTone: .failed
                )
            case .connecting:
                return .init(
                    statusText: "Connecting to remote stream...",
                    overlay: .init(
                        title: "Connecting to remote desktop stream...",
                        symbol: "antenna.radiowaves.left.and.right"
                    ),
                    launchTone: .launching
                )
            case .waitingForFirstFrame, .idle:
                break
            }
            return .init(
                statusText: "Remote session transport connected. Waiting for native frame decoder.",
                overlay: .init(
                    title: "Waiting for native frame decoder...",
                    symbol: "hourglass"
                ),
                launchTone: .launched
            )
        case let .failed(message):
            return .init(
                statusText: message,
                overlay: .init(
                    title: "Remote desktop stream failed to start.",
                    symbol: "exclamationmark.triangle"
                ),
                launchTone: .failed
            )
        }
    }
}
