import SwiftUI

struct ShadowClientRemoteHostPresentationInput: Equatable {
    let host: ShadowClientRemoteHostDescriptor
    let issue: ShadowClientRemoteHostIssuePresentation?
    let alias: String
    let notes: String
}

enum ShadowClientRemoteHostPresentationKit {
    static func displayTitle(_ input: ShadowClientRemoteHostPresentationInput) -> String {
        let alias = input.alias.trimmingCharacters(in: .whitespacesAndNewlines)
        return alias.isEmpty ? input.host.displayName : alias
    }

    static func summaryText(_ input: ShadowClientRemoteHostPresentationInput) -> String {
        if let issue = input.issue {
            return issue.message
        }
        let notes = input.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            return notes
        }
        if let lastError = input.host.lastError, !lastError.isEmpty {
            return lastError
        }
        return input.host.detailLabel
    }

    static func tileActionLabel(_ input: ShadowClientRemoteHostPresentationInput) -> String {
        if input.issue != nil {
            return "Permissions"
        }
        let authState = input.host.authenticationState
        switch authState.pairing {
        case .pendingResolution:
            return "Saved"
        case .unavailable:
            return "Needs Attention"
        case .paired:
            return "Ready to Go"
        case .pairingRequired:
            return "Pair First"
        case .reachable:
            return "Inspect"
        }
    }

    static func frontHint(_ input: ShadowClientRemoteHostPresentationInput) -> String {
        if input.issue != nil {
            return "Permissions"
        }
        let authState = input.host.authenticationState
        switch authState.pairing {
        case .pendingResolution:
            return "Saved"
        case .unavailable:
            return "Connection issue"
        case .paired:
            return "Ready"
        case .pairingRequired, .reachable:
            return "Pair first"
        }
    }

    static func frontHintSymbol(_ input: ShadowClientRemoteHostPresentationInput) -> String {
        if input.issue != nil {
            return "lock.trianglebadge.exclamationmark"
        }
        let authState = input.host.authenticationState
        switch authState.pairing {
        case .pendingResolution:
            return "bookmark.circle"
        case .unavailable:
            return "exclamationmark.shield"
        case .paired:
            return "play.circle"
        case .pairingRequired, .reachable:
            return "lock.shield"
        }
    }

    static func frontHintColor(_ input: ShadowClientRemoteHostPresentationInput) -> Color {
        if input.issue != nil {
            return .yellow
        }
        switch input.host.authenticationState.hostIndicatorTone {
        case .neutral:
            return Color.white.opacity(0.84)
        case .unavailable:
            return .red.opacity(0.9)
        case .ready:
            return .mint
        case .pairingRequired:
            return .yellow
        case .streaming:
            return .orange
        }
    }

    static func frontMessage(_ input: ShadowClientRemoteHostPresentationInput) -> String {
        if let issue = input.issue {
            return issue.message
        }
        let authState = input.host.authenticationState
        switch authState.pairing {
        case .pendingResolution:
            return "This address is saved. Host details will attach when the server responds."
        case .unavailable:
            return authState.detailLabel
        case .paired:
            return "Flip the card for launch controls and a quick app library."
        case .pairingRequired, .reachable:
            return "Flip the card to pair this host before browsing or launching apps."
        }
    }

    static func spotlightAccessibilityHint(_ input: ShadowClientRemoteHostPresentationInput) -> String {
        "Opens \(displayTitle(input)) in a focused rotating card"
    }

    static func accessibilityLabel(
        _ input: ShadowClientRemoteHostPresentationInput,
        isSelected: Bool
    ) -> String {
        let selectionDetail = isSelected ? " Currently selected." : ""
        return "\(displayTitle(input)), \(input.host.statusLabel). Host: \(input.host.host).\(selectionDetail) \(summaryText(input))"
    }

    static func sanitizedIdentifier(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = raw.lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return sanitized.isEmpty ? "unknown" : sanitized
    }

    static func glyphSymbol(_ input: ShadowClientRemoteHostPresentationInput) -> String {
        if input.issue != nil {
            return "lock.trianglebadge.exclamationmark.fill"
        }
        let authState = input.host.authenticationState
        switch authState.pairing {
        case .pendingResolution:
            return "bookmark.circle.fill"
        case .unavailable:
            return "wifi.exclamationmark"
        case .paired:
            return "checkmark.circle.fill"
        case .pairingRequired, .reachable:
            return "lock.fill"
        }
    }

    static func glyphColor(_ input: ShadowClientRemoteHostPresentationInput) -> Color {
        if input.issue != nil {
            return .yellow
        }
        switch input.host.authenticationState.hostIndicatorTone {
        case .neutral:
            return Color.white.opacity(0.84)
        case .unavailable:
            return .red.opacity(0.92)
        case .ready:
            return .mint
        case .pairingRequired:
            return .yellow
        case .streaming:
            return .orange
        }
    }
}
