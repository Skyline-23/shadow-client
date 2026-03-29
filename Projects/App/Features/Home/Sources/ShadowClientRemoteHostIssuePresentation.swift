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

        return nil
    }
}
