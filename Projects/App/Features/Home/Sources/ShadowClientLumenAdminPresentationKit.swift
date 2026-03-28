import Foundation

enum ShadowClientLumenAdminPresentationKit {
    static func stateLabel(
        state: ShadowClientLumenAdminClientState,
        selectedProfile: ShadowClientLumenAdminClientProfile?
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

    static func summary(_ profile: ShadowClientLumenAdminClientProfile) -> String {
        let displayMode = profile.displayModeOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayDescription = displayMode.isEmpty ? "Display mode override: automatic" : "Display mode override: \(displayMode)"
        let virtualDisplayDescription = profile.alwaysUseVirtualDisplay
            ? "Always use virtual display: ON"
            : "Always use virtual display: OFF"
        let connectedDescription = profile.connected ? "Connected" : "Not connected"
        let permissionsDescription = ShadowClientLumenPermission.summary(for: profile.permissions)
        return [displayDescription, virtualDisplayDescription, permissionsDescription, connectedDescription].joined(separator: "\n")
    }

    static func displayModeDraft(
        hostID: String,
        drafts: [String: String],
        profile: ShadowClientLumenAdminClientProfile?
    ) -> String {
        if let draft = drafts[hostID] {
            return draft
        }
        return profile?.displayModeOverride ?? ""
    }

    static func alwaysUseVirtualDisplayDraft(
        hostID: String,
        drafts: [String: Bool],
        profile: ShadowClientLumenAdminClientProfile?
    ) -> Bool {
        if let draft = drafts[hostID] {
            return draft
        }
        return profile?.alwaysUseVirtualDisplay ?? false
    }

    static func permissionDraft(
        hostID: String,
        drafts: [String: UInt32],
        profile: ShadowClientLumenAdminClientProfile?
    ) -> UInt32 {
        if let draft = drafts[hostID] {
            return draft
        }
        return profile?.permissions ?? 0
    }
}
