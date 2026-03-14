import Foundation

enum ShadowClientApolloAdminPresentationKit {
    static func stateLabel(
        state: ShadowClientApolloAdminClientState,
        selectedProfile: ShadowClientApolloAdminClientProfile?
    ) -> String {
        switch state {
        case .idle:
            return "Not synced"
        case .loading:
            return "Loading…"
        case .saving:
            return "Saving…"
        case .loaded:
            return selectedProfile == nil ? "Client not found" : "Loaded"
        case let .failed(message):
            return message
        }
    }

    static func summary(_ profile: ShadowClientApolloAdminClientProfile) -> String {
        let displayMode = profile.displayModeOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayDescription = displayMode.isEmpty ? "Display mode override: automatic" : "Display mode override: \(displayMode)"
        let virtualDisplayDescription = profile.alwaysUseVirtualDisplay
            ? "Always use virtual display: ON"
            : "Always use virtual display: OFF"
        let connectedDescription = profile.connected ? "Connected" : "Not connected"
        let permissionsDescription = ShadowClientApolloPermission.summary(for: profile.permissions)
        return [displayDescription, virtualDisplayDescription, permissionsDescription, connectedDescription].joined(separator: "\n")
    }

    static func displayModeDraft(
        hostID: String,
        drafts: [String: String],
        profile: ShadowClientApolloAdminClientProfile?
    ) -> String {
        if let draft = drafts[hostID] {
            return draft
        }
        return profile?.displayModeOverride ?? ""
    }

    static func alwaysUseVirtualDisplayDraft(
        hostID: String,
        drafts: [String: Bool],
        profile: ShadowClientApolloAdminClientProfile?
    ) -> Bool {
        if let draft = drafts[hostID] {
            return draft
        }
        return profile?.alwaysUseVirtualDisplay ?? false
    }

    static func permissionDraft(
        hostID: String,
        drafts: [String: UInt32],
        profile: ShadowClientApolloAdminClientProfile?
    ) -> UInt32 {
        if let draft = drafts[hostID] {
            return draft
        }
        return profile?.permissions ?? 0
    }
}
