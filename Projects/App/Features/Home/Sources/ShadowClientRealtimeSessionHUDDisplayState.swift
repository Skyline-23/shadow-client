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
        renderState: ShadowClientRealtimeSessionSurfaceContext.RenderState
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
