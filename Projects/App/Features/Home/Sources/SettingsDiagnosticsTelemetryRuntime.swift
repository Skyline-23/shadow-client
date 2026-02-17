import ShadowClientStreaming

actor SettingsDiagnosticsTelemetryRuntime {
    private let baseDependencies: ShadowClientFeatureHomeDependencies
    private var cachedSettingsIdentityKey: String?
    private var cachedDiagnosticsRuntime: HomeDiagnosticsRuntime?

    init(baseDependencies: ShadowClientFeatureHomeDependencies) {
        self.baseDependencies = baseDependencies
    }

    func ingest(
        snapshot: StreamingTelemetrySnapshot,
        settings: ShadowClientAppSettings
    ) async -> SettingsDiagnosticsHUDModel {
        let runtime: HomeDiagnosticsRuntime
        if let cachedDiagnosticsRuntime,
           cachedSettingsIdentityKey == settings.streamingIdentityKey {
            runtime = cachedDiagnosticsRuntime
        } else {
            let updatedDependencies = baseDependencies.applying(settings: settings)
            runtime = updatedDependencies.diagnosticsRuntime
            cachedDiagnosticsRuntime = runtime
            cachedSettingsIdentityKey = settings.streamingIdentityKey
        }

        let tick = await runtime.ingest(snapshot: snapshot)
        return SettingsDiagnosticsHUDModel(tick: tick)
    }
}
