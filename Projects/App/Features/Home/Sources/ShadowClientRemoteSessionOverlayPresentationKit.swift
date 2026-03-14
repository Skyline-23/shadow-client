import SwiftUI

struct ShadowClientRemoteSessionOverlayPresentationStyle {
    let backgroundOpacity: Double
    let strokeOpacity: Double
    let textColor: Color
}

struct ShadowClientRemoteSessionOverlayPresentationKit {
    static func overlayStyle(for tone: ShadowClientRemoteSessionLaunchTone) -> ShadowClientRemoteSessionOverlayPresentationStyle {
        switch tone {
        case .failed:
            return .init(
                backgroundOpacity: 0.66,
                strokeOpacity: 0.78,
                textColor: Color.red.opacity(0.95)
            )
        case .launching:
            return .init(
                backgroundOpacity: 0.56,
                strokeOpacity: 0.42,
                textColor: Color.orange.opacity(0.95)
            )
        case .idle, .launched:
            return .init(
                backgroundOpacity: 0.45,
                strokeOpacity: 0.18,
                textColor: Color.white.opacity(0.88)
            )
        }
    }

    static func dimOpacity(for tone: ShadowClientRemoteSessionLaunchTone) -> Double {
        switch tone {
        case .failed:
            return 0.58
        case .launching:
            return 0.46
        case .idle, .launched:
            return 0.34
        }
    }

    static func diagnosticsSummary(
        codecLabel: String,
        resolutionValue: String,
        audioChannelValue: String
    ) -> String {
        "Codec \(codecLabel) · Resolution \(resolutionValue) · Audio \(audioChannelValue)"
    }

    static func bootstrapDescription() -> String {
        "Telemetry stream pending. Showing connection health baseline."
    }

    static func connectionIssueFootnote() -> String {
        "Remote input is paused until stream reconnects."
    }

    static func connectionIssueBadgeText() -> String {
        "OFFLINE"
    }

    static func hudTitle() -> String {
        "Realtime HUD"
    }

    static func bootstrapBadgeText() -> String {
        "BOOTSTRAP"
    }
}
