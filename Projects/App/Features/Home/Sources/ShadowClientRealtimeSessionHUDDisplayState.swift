public enum ShadowClientRealtimeSessionHUDDisplayState: Equatable, Sendable {
    case telemetry(SettingsDiagnosticsHUDModel)
    case waitingForTelemetry(controlRoundTripMs: Int?)
    case connectionIssue(title: String, message: String)
}

public enum ShadowClientRealtimeSessionHUDDisplayStateMapper {
    public static func make(
        showDiagnosticsHUD: Bool,
        diagnosticsModel: SettingsDiagnosticsHUDModel?,
        controlRoundTripMs: Int?,
        renderState: ShadowClientRealtimeSessionSurfaceContext.RenderState,
        audioOutputState: ShadowClientRealtimeAudioOutputState = .idle,
        sessionIssue: ShadowClientRemoteSessionIssue? = nil
    ) -> ShadowClientRealtimeSessionHUDDisplayState? {
        guard showDiagnosticsHUD else {
            return nil
        }

        switch renderState {
        case let .disconnected(message):
            let issue = normalizedIssueMessage(
                message,
                fallback: "Remote session transport closed."
            )
            return .connectionIssue(
                title: "Session Disconnected",
                message: issue
            )
        case let .failed(message):
            let issue = normalizedIssueMessage(
                message,
                fallback: "Native decoder failed."
            )
            return .connectionIssue(
                title: "Session Error",
                message: issue
            )
        case .idle, .connecting, .waitingForFirstFrame, .rendering:
            break
        }

        switch audioOutputState {
        case let .deviceUnavailable(message):
            return .connectionIssue(
                title: "Audio Device Unavailable",
                message: normalizedIssueMessage(
                    message,
                    fallback: "Could not start local audio output device."
                )
            )
        case let .decoderFailed(message):
            return .connectionIssue(
                title: "Audio Decode Error",
                message: normalizedIssueMessage(
                    message,
                    fallback: "Could not decode incoming audio stream."
                )
            )
        case let .disconnected(message):
            return .connectionIssue(
                title: "Audio Stream Disconnected",
                message: normalizedIssueMessage(
                    message,
                    fallback: "Audio transport disconnected."
                )
            )
        case .idle, .starting, .playing:
            break
        }

        if let sessionIssue {
            return .connectionIssue(
                title: sessionIssue.title,
                message: sessionIssue.message
            )
        }

        if let diagnosticsModel {
            return .telemetry(diagnosticsModel)
        }

        return .waitingForTelemetry(
            controlRoundTripMs: controlRoundTripMs.map { max(0, $0) }
        )
    }

    private static func normalizedIssueMessage(
        _ message: String,
        fallback: String
    ) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
