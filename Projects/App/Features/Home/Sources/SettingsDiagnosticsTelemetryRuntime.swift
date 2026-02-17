import ShadowClientStreaming

actor SettingsDiagnosticsTelemetryRuntime {
    private let baseDependencies: ShadowClientFeatureHomeDependencies
    private var cachedSettingsIdentityKey: String?
    private var cachedDiagnosticsRuntime: HomeDiagnosticsRuntime?
    private var cachedLastTimestampMs: Int?

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
            cachedLastTimestampMs = nil
        }

        let tick = await runtime.ingest(snapshot: snapshot)
        let sampleIntervalMs: Int?
        if let cachedLastTimestampMs,
           tick.timestampMs > cachedLastTimestampMs {
            sampleIntervalMs = tick.timestampMs - cachedLastTimestampMs
        } else {
            sampleIntervalMs = nil
        }

        if let cachedLastTimestampMs {
            self.cachedLastTimestampMs = max(cachedLastTimestampMs, tick.timestampMs)
        } else {
            self.cachedLastTimestampMs = tick.timestampMs
        }

        return SettingsDiagnosticsHUDModel(
            tick: tick,
            sampleIntervalMs: sampleIntervalMs
        )
    }
}
