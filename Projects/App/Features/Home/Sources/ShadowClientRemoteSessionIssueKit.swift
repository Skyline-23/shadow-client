import Foundation

enum ShadowClientRemoteSessionIssueKit {
    enum ClipboardOperation {
        case read
        case write
    }

    enum ClipboardIssueKind {
        case readPermissionDenied
        case writePermissionDenied
        case requiresActiveStream
    }

    static func classifyClipboardIssue(
        _ error: Error,
        operation: ClipboardOperation
    ) -> ClipboardIssueKind? {
        guard let streamError = error as? ShadowClientGameStreamError else {
            return nil
        }

        switch streamError {
        case let .responseRejected(code, _):
            switch code {
            case 401:
                return operation == .read ? .readPermissionDenied : .writePermissionDenied
            case 403:
                return .requiresActiveStream
            default:
                return nil
            }
        default:
            return nil
        }
    }

    static func sessionIssue(
        clipboardReadPermissionDenied: Bool,
        clipboardWritePermissionDenied: Bool,
        clipboardActionRequiresActiveStream: Bool
    ) -> ShadowClientRemoteSessionIssue? {
        if clipboardReadPermissionDenied && clipboardWritePermissionDenied {
            return .init(
                title: "Clipboard Permission Required",
                message: "Grant Clipboard Read and Clipboard Set permissions for this paired Apollo client."
            )
        }

        if clipboardWritePermissionDenied {
            return .init(
                title: "Clipboard Permission Required",
                message: "Grant Clipboard Set permission for this paired Apollo client."
            )
        }

        if clipboardReadPermissionDenied {
            return .init(
                title: "Clipboard Permission Required",
                message: "Grant Clipboard Read permission for this paired Apollo client."
            )
        }

        if clipboardActionRequiresActiveStream {
            return .init(
                title: "Clipboard Sync Unavailable",
                message: "Apollo clipboard actions require an active stream for this client."
            )
        }

        return nil
    }

    static func hostTerminationSessionIssue(message: String) -> ShadowClientRemoteSessionIssue? {
        let normalized = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            return nil
        }

        if normalized.localizedCaseInsensitiveContains("0x80030023") {
            return .init(
                title: "Host Desktop Paused",
                message: "\(normalized)\nReturn to the normal Windows desktop, dismiss the secure prompt or popup, then launch the session again."
            )
        }

        return nil
    }
}
