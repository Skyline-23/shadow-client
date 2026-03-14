import SwiftUI

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
           isApolloPermissionMessage(message)
        {
            return .init(
                title: "Apollo Permissions",
                message: message
            )
        }

        if case let .failed(message) = appState,
           isApolloPermissionMessage(message)
        {
            return .init(
                title: "Apollo Permissions",
                message: message
            )
        }

        return nil
    }

    private static func isApolloPermissionMessage(_ message: String) -> Bool {
        message.localizedCaseInsensitiveContains("apollo denied")
            || message.localizedCaseInsensitiveContains("permission required")
            || message.localizedCaseInsensitiveContains("clipboard sync unavailable")
    }
}
