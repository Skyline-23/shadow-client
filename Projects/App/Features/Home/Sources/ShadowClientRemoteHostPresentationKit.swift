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
        if input.host.isPendingResolution {
            return "Saved"
        }
        if !input.host.isReachable {
            return "Needs Attention"
        }
        switch input.host.pairStatus {
        case .paired:
            return "Ready to Go"
        case .notPaired:
            return "Pair First"
        case .unknown:
            return "Inspect"
        }
    }

    static func frontHint(_ input: ShadowClientRemoteHostPresentationInput) -> String {
        if input.issue != nil {
            return "Permissions"
        }
        if input.host.isPendingResolution {
            return "Saved"
        }
        if !input.host.isReachable {
            return "Connection issue"
        }
        if input.host.pairStatus == .paired {
            return "Ready"
        }
        return "Pair first"
    }

    static func frontHintSymbol(_ input: ShadowClientRemoteHostPresentationInput) -> String {
        if input.issue != nil {
            return "lock.trianglebadge.exclamationmark"
        }
        if input.host.isPendingResolution {
            return "bookmark.circle"
        }
        if !input.host.isReachable {
            return "exclamationmark.shield"
        }
        if input.host.pairStatus == .paired {
            return "play.circle"
        }
        return "lock.shield"
    }

    static func frontHintColor(_ input: ShadowClientRemoteHostPresentationInput) -> Color {
        if input.issue != nil {
            return .yellow
        }
        if input.host.isPendingResolution {
            return Color.white.opacity(0.84)
        }
        if !input.host.isReachable {
            return .red.opacity(0.9)
        }
        if input.host.pairStatus == .paired {
            return .mint
        }
        return .yellow
    }

    static func frontMessage(_ input: ShadowClientRemoteHostPresentationInput) -> String {
        if let issue = input.issue {
            return issue.message
        }
        if input.host.isPendingResolution {
            return "This address is saved. Host details will attach when the server responds."
        }
        if let lastError = input.host.lastError, !lastError.isEmpty {
            return lastError
        }
        if input.host.pairStatus == .paired {
            return "Flip the card for launch controls and a quick app library."
        }
        return "Flip the card to pair this host before browsing or launching apps."
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
        if input.host.isPendingResolution {
            return "bookmark.circle.fill"
        }
        if !input.host.isReachable {
            return "wifi.exclamationmark"
        }
        if input.host.pairStatus == .paired {
            return "checkmark.circle.fill"
        }
        return "lock.fill"
    }

    static func glyphColor(_ input: ShadowClientRemoteHostPresentationInput) -> Color {
        if input.issue != nil {
            return .yellow
        }
        if input.host.isPendingResolution {
            return Color.white.opacity(0.84)
        }
        if !input.host.isReachable {
            return .red.opacity(0.92)
        }
        if input.host.pairStatus == .paired {
            return .mint
        }
        return .yellow
    }
}
