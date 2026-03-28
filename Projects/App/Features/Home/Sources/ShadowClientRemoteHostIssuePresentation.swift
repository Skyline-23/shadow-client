import SwiftUI
import ShadowClientFeatureSession

struct ShadowClientRemoteHostIssuePresentation: Equatable, Sendable {
    let title: String
    let message: String
}

enum ShadowClientRemoteHostIssueMapper {
    static func issue(
        for host: ShadowClientRemoteHostDescriptor,
        selectedHostID: String?,
        appState: ShadowClientRemoteAppCatalogState,
        launchState: ShadowClientRemoteLaunchState,
        sessionIssue: ShadowClientRemoteSessionIssue?
    ) -> ShadowClientRemoteHostIssuePresentation? {
        guard host.id == selectedHostID else {
            return nil
        }

        if let sessionIssue {
            return .init(title: sessionIssue.title, message: sessionIssue.message)
        }

        if case let .failed(message) = launchState,
           isLumenPermissionMessage(message)
        {
            return .init(
                title: "Lumen Permissions",
                message: message
            )
        }

        if case let .failed(message) = appState,
           isLumenPermissionMessage(message)
        {
            return .init(
                title: "Lumen Permissions",
                message: message
            )
        }

        return nil
    }

    private static func isLumenPermissionMessage(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("lumen denied")
            || message.localizedCaseInsensitiveContains("permission required")
            || message.localizedCaseInsensitiveContains("clipboard sync unavailable")
    }
}
