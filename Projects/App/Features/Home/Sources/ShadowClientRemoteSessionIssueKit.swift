import Foundation

enum ShadowClientRemoteSessionIssueKit {
    enum ClipboardOperation {
        case read
        case write
    }

    enum ClipboardIssueKind {
        case readUnavailable
        case writeUnavailable
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
                return operation == .read ? .readUnavailable : .writeUnavailable
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
        clipboardReadUnavailable: Bool,
        clipboardWriteUnavailable: Bool,
        clipboardActionRequiresActiveStream: Bool
    ) -> ShadowClientRemoteSessionIssue? {
        if clipboardReadUnavailable && clipboardWriteUnavailable {
            return .init(
                title: "Clipboard Sync Unavailable",
                message: "Lumen clipboard sync is unavailable for this paired client."
            )
        }

        if clipboardWriteUnavailable {
            return .init(
                title: "Clipboard Sync Unavailable",
                message: "Lumen clipboard write is unavailable for this paired client."
            )
        }

        if clipboardReadUnavailable {
            return .init(
                title: "Clipboard Sync Unavailable",
                message: "Lumen clipboard read is unavailable for this paired client."
            )
        }

        if clipboardActionRequiresActiveStream {
            return .init(
                title: "Clipboard Sync Unavailable",
                message: "Lumen clipboard actions require an active stream for this client."
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
