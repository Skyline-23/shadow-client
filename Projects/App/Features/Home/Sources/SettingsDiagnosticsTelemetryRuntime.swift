import ShadowClientStreaming

actor SettingsDiagnosticsTelemetryRuntime {
    private let settingsMapper: StreamingSessionSettingsMapper
    private let hostCapabilities: HostStreamingCapabilities
    private var cachedSettingsIdentityKey: String?
    private var cachedDiagnosticsRuntime: HomeDiagnosticsRuntime?
    private var cachedLastTimestampMs: Int?

    init(
        settingsMapper: StreamingSessionSettingsMapper,
        hostCapabilities: HostStreamingCapabilities
    ) {
        self.settingsMapper = settingsMapper
        self.hostCapabilities = hostCapabilities
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
            runtime = makeDiagnosticsRuntime(for: settings)
            cachedDiagnosticsRuntime = runtime
            cachedSettingsIdentityKey = settings.streamingIdentityKey
            cachedLastTimestampMs = nil
        }

        let tick = await runtime.ingest(snapshot: snapshot)
        let sampleIntervalMs: Int?
        let receivedOutOfOrderSample: Bool
        if let cachedLastTimestampMs,
           tick.timestampMs > cachedLastTimestampMs {
            sampleIntervalMs = tick.timestampMs - cachedLastTimestampMs
            receivedOutOfOrderSample = false
        } else if let cachedLastTimestampMs,
                  tick.timestampMs <= cachedLastTimestampMs {
            sampleIntervalMs = nil
            receivedOutOfOrderSample = true
        } else {
            sampleIntervalMs = nil
            receivedOutOfOrderSample = false
        }

        if let cachedLastTimestampMs {
            self.cachedLastTimestampMs = max(cachedLastTimestampMs, tick.timestampMs)
        } else {
            self.cachedLastTimestampMs = tick.timestampMs
        }

        return SettingsDiagnosticsHUDModel(
            tick: tick,
            sampleIntervalMs: sampleIntervalMs,
            receivedOutOfOrderSample: receivedOutOfOrderSample
        )
    }

    private func makeDiagnosticsRuntime(for settings: ShadowClientAppSettings) -> HomeDiagnosticsRuntime {
        HomeDiagnosticsRuntime(
            launchRuntime: AdaptiveSessionLaunchRuntime(
                telemetryPipeline: .init(initialBufferMs: 40.0),
                settingsMapper: settingsMapper,
                sessionPreferences: settings.streamingPreferences,
                hostCapabilities: hostCapabilities
            )
        )
    }
}
