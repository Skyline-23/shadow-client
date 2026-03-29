import SwiftUI

struct ShadowClientHostSpotlightCallout: Equatable {
    enum Tone: Equatable {
        case warning
        case destructive
        case success
        case info
    }

    let title: String
    let message: String
    let tone: Tone
}

enum ShadowClientHostSpotlightPresentationKit {
    static func statusCallouts(
        host: ShadowClientRemoteHostDescriptor,
        issue: ShadowClientRemoteHostIssuePresentation?,
        lumenSummary: String?
    ) -> [ShadowClientHostSpotlightCallout] {
        if let issue {
            return [.init(title: issue.title, message: issue.message, tone: .warning)]
        }

        let authState = host.authenticationState

        switch authState.pairing {
        case .unavailable:
            return [.init(title: "Connection Issue", message: authState.detailLabel, tone: .destructive)]
        case .paired:
            var callouts: [ShadowClientHostSpotlightCallout] = [
                .init(
                    title: "Ready",
                    message: "This device is paired and ready to launch a remote desktop session.",
                    tone: .success
                )
            ]
            if let lumenSummary, !lumenSummary.isEmpty {
                callouts.append(
                    .init(
                        title: "Lumen Device Overrides",
                        message: lumenSummary,
                        tone: .info
                    )
                )
            }
            return callouts
        case .pendingResolution:
            return [
                .init(
                    title: "Saved",
                    message: authState.detailLabel,
                    tone: .info
                )
            ]
        case .pairingRequired, .reachable:
            return [
                .init(
                    title: "Pairing Required",
                    message: "This device is reachable, but you need to pair it before browsing apps or launching a session.",
                    tone: .warning
                )
            ]
        }
    }

    static func accentColor(for tone: ShadowClientHostSpotlightCallout.Tone) -> Color {
        switch tone {
        case .warning:
            return .yellow
        case .destructive:
            return .red
        case .success:
            return .mint
        case .info:
            return .cyan
        }
    }
}
