import ShadowClientStreaming

public struct ShadowClientAppSettings: Equatable, Sendable {
    public struct StorageKeys {
        public static let lowLatencyMode = "settings.lowLatencyMode"
        public static let preferHDR = "settings.preferHDR"
        public static let preferSurroundAudio = "settings.preferSurroundAudio"
        public static let showDiagnosticsHUD = "settings.showDiagnosticsHUD"
    }

    public let lowLatencyMode: Bool
    public let preferHDR: Bool
    public let preferSurroundAudio: Bool
    public let showDiagnosticsHUD: Bool

    public init(
        lowLatencyMode: Bool = true,
        preferHDR: Bool = true,
        preferSurroundAudio: Bool = true,
        showDiagnosticsHUD: Bool = true
    ) {
        self.lowLatencyMode = lowLatencyMode
        self.preferHDR = preferHDR
        self.preferSurroundAudio = preferSurroundAudio
        self.showDiagnosticsHUD = showDiagnosticsHUD
    }

    public var streamingPreferences: StreamingUserPreferences {
        StreamingUserPreferences(
            preferHDR: preferHDR,
            preferSurroundAudio: preferSurroundAudio,
            lowLatencyMode: lowLatencyMode
        )
    }

    public var identityKey: String {
        "\(lowLatencyMode)-\(preferHDR)-\(preferSurroundAudio)-\(showDiagnosticsHUD)"
    }
}

public extension ShadowClientFeatureHomeDependencies {
    func applying(settings: ShadowClientAppSettings) -> Self {
        .init(
            telemetryPublisher: telemetryPublisher,
            pipeline: pipeline,
            diagnosticsPresenter: diagnosticsPresenter,
            settingsMapper: settingsMapper,
            launchPlanBuilder: launchPlanBuilder,
            sessionPreferences: settings.streamingPreferences,
            hostCapabilities: hostCapabilities
        )
    }
}
