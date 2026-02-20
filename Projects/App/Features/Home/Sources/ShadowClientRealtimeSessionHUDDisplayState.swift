public enum ShadowClientRealtimeSessionHUDDisplayState: Equatable, Sendable {
    case telemetry(SettingsDiagnosticsHUDModel)
    case waitingForTelemetry(controlRoundTripMs: Int?)
}

public enum ShadowClientRealtimeSessionHUDDisplayStateMapper {
    public static func make(
        showDiagnosticsHUD: Bool,
        diagnosticsModel: SettingsDiagnosticsHUDModel?,
        controlRoundTripMs: Int?
    ) -> ShadowClientRealtimeSessionHUDDisplayState? {
        guard showDiagnosticsHUD else {
            return nil
        }

        if let diagnosticsModel {
            return .telemetry(diagnosticsModel)
        }

        return .waitingForTelemetry(
            controlRoundTripMs: controlRoundTripMs.map { max(0, $0) }
        )
    }
}
