import ShadowClientStreaming

public enum ShadowClientStreamingResolutionPreset: String, CaseIterable, Sendable {
    case p720 = "1280x720"
    case p1080 = "1920x1080"
    case p1440 = "2560x1440"
    case p2160 = "3840x2160"

    public var width: Int {
        switch self {
        case .p720:
            return 1280
        case .p1080:
            return 1920
        case .p1440:
            return 2560
        case .p2160:
            return 3840
        }
    }

    public var height: Int {
        switch self {
        case .p720:
            return 720
        case .p1080:
            return 1080
        case .p1440:
            return 1440
        case .p2160:
            return 2160
        }
    }

    public var label: String {
        switch self {
        case .p720:
            return "720p"
        case .p1080:
            return "1080p"
        case .p1440:
            return "1440p"
        case .p2160:
            return "4K"
        }
    }
}

public enum ShadowClientStreamingFrameRatePreset: Int, CaseIterable, Sendable {
    case fps30 = 30
    case fps60 = 60
    case fps90 = 90
    case fps120 = 120
}

public enum ShadowClientAudioConfiguration: String, CaseIterable, Sendable {
    case stereo
    case surround51
    case surround71

    public var label: String {
        switch self {
        case .stereo:
            return "Stereo"
        case .surround51:
            return "5.1 Surround"
        case .surround71:
            return "7.1 Surround"
        }
    }

    public var prefersSurroundAudio: Bool {
        self != .stereo
    }
}

public enum ShadowClientDisplayMode: String, CaseIterable, Sendable {
    case borderlessFullscreen
    case fullscreen
    case windowed

    public var label: String {
        switch self {
        case .borderlessFullscreen:
            return "Borderless fullscreen"
        case .fullscreen:
            return "Fullscreen"
        case .windowed:
            return "Windowed"
        }
    }
}

public enum ShadowClientVideoDecoderPreference: String, CaseIterable, Sendable {
    case forceHardware
    case automatic
    case software

    public var label: String {
        switch self {
        case .forceHardware:
            return "Force hardware decoding"
        case .automatic:
            return "Automatic"
        case .software:
            return "Prefer software decoding"
        }
    }
}

public enum ShadowClientKeyboardShortcutCaptureMode: String, CaseIterable, Sendable {
    case never
    case fullscreenOnly
    case always

    public var label: String {
        switch self {
        case .never:
            return "Never"
        case .fullscreenOnly:
            return "In fullscreen"
        case .always:
            return "Always"
        }
    }
}

public enum ShadowClientLanguagePreference: String, CaseIterable, Sendable {
    case automatic
    case english
    case korean

    public var label: String {
        switch self {
        case .automatic:
            return "Automatic"
        case .english:
            return "English"
        case .korean:
            return "Korean"
        }
    }
}

public enum ShadowClientGUIDisplayMode: String, CaseIterable, Sendable {
    case windowed
    case fullscreen

    public var label: String {
        switch self {
        case .windowed:
            return "Windowed"
        case .fullscreen:
            return "Fullscreen"
        }
    }
}

public struct ShadowClientAppSettings: Equatable, Sendable {
    public struct StorageKeys {
        public static let lowLatencyMode = "settings.lowLatencyMode"
        public static let preferHDR = "settings.preferHDR"
        public static let showDiagnosticsHUD = "settings.showDiagnosticsHUD"
        public static let connectionHost = "settings.connectionHost"
        public static let resolution = "settings.resolution"
        public static let frameRate = "settings.frameRate"
        public static let bitrateKbps = "settings.bitrateKbps"
        public static let displayMode = "settings.displayMode"
        public static let audioConfiguration = "settings.audioConfiguration"
        public static let videoCodec = "settings.videoCodec"
        public static let videoDecoder = "settings.videoDecoder"
        public static let enableVSync = "settings.enableVSync"
        public static let enableFramePacing = "settings.enableFramePacing"
        public static let enableYUV444 = "settings.enableYUV444"
        public static let unlockBitrateLimit = "settings.unlockBitrateLimit"
        public static let optimizeMouseForDesktop = "settings.optimizeMouseForDesktop"
        public static let captureSystemKeyboardShortcuts = "settings.captureSystemKeyboardShortcuts"
        public static let keyboardShortcutCaptureMode = "settings.keyboardShortcutCaptureMode"
        public static let useTouchscreenTrackpad = "settings.useTouchscreenTrackpad"
        public static let swapMouseButtons = "settings.swapMouseButtons"
        public static let reverseMouseScrollDirection = "settings.reverseMouseScrollDirection"
        public static let swapABXYButtons = "settings.swapABXYButtons"
        public static let forceGamepadOneAlwaysConnected = "settings.forceGamepadOneAlwaysConnected"
        public static let enableGamepadMouseMode = "settings.enableGamepadMouseMode"
        public static let processGamepadInputInBackground = "settings.processGamepadInputInBackground"
        public static let optimizeGameSettingsForStreaming = "settings.optimizeGameSettingsForStreaming"
        public static let quitAppOnHostAfterStream = "settings.quitAppOnHostAfterStream"
        public static let muteHostSpeakersWhileStreaming = "settings.muteHostSpeakersWhileStreaming"
        public static let muteAudioWhenInactiveWindow = "settings.muteAudioWhenInactiveWindow"
        public static let autoFindHosts = "settings.autoFindHosts"
        public static let language = "settings.language"
        public static let guiDisplayMode = "settings.guiDisplayMode"
    }

    public let lowLatencyMode: Bool
    public let preferHDR: Bool
    public let showDiagnosticsHUD: Bool
    public let resolution: ShadowClientStreamingResolutionPreset
    public let frameRate: ShadowClientStreamingFrameRatePreset
    public let bitrateKbps: Int
    public let displayMode: ShadowClientDisplayMode
    public let audioConfiguration: ShadowClientAudioConfiguration
    public let videoCodec: ShadowClientVideoCodecPreference
    public let videoDecoder: ShadowClientVideoDecoderPreference
    public let enableVSync: Bool
    public let enableFramePacing: Bool
    public let enableYUV444: Bool
    public let unlockBitrateLimit: Bool
    public let optimizeMouseForDesktop: Bool
    public let captureSystemKeyboardShortcuts: Bool
    public let keyboardShortcutCaptureMode: ShadowClientKeyboardShortcutCaptureMode
    public let useTouchscreenTrackpad: Bool
    public let swapMouseButtons: Bool
    public let reverseMouseScrollDirection: Bool
    public let swapABXYButtons: Bool
    public let forceGamepadOneAlwaysConnected: Bool
    public let enableGamepadMouseMode: Bool
    public let processGamepadInputInBackground: Bool
    public let optimizeGameSettingsForStreaming: Bool
    public let quitAppOnHostAfterStream: Bool
    public let muteHostSpeakersWhileStreaming: Bool
    public let muteAudioWhenInactiveWindow: Bool
    public let autoFindHosts: Bool
    public let language: ShadowClientLanguagePreference
    public let guiDisplayMode: ShadowClientGUIDisplayMode

    public init(
        lowLatencyMode: Bool = true,
        preferHDR: Bool = true,
        showDiagnosticsHUD: Bool = true,
        resolution: ShadowClientStreamingResolutionPreset = .p1080,
        frameRate: ShadowClientStreamingFrameRatePreset = .fps60,
        bitrateKbps: Int = 22_000,
        displayMode: ShadowClientDisplayMode = .borderlessFullscreen,
        audioConfiguration: ShadowClientAudioConfiguration = .surround71,
        videoCodec: ShadowClientVideoCodecPreference = .auto,
        videoDecoder: ShadowClientVideoDecoderPreference = .forceHardware,
        enableVSync: Bool = false,
        enableFramePacing: Bool = false,
        enableYUV444: Bool = false,
        unlockBitrateLimit: Bool = false,
        optimizeMouseForDesktop: Bool = false,
        captureSystemKeyboardShortcuts: Bool = false,
        keyboardShortcutCaptureMode: ShadowClientKeyboardShortcutCaptureMode = .fullscreenOnly,
        useTouchscreenTrackpad: Bool = false,
        swapMouseButtons: Bool = false,
        reverseMouseScrollDirection: Bool = false,
        swapABXYButtons: Bool = false,
        forceGamepadOneAlwaysConnected: Bool = false,
        enableGamepadMouseMode: Bool = true,
        processGamepadInputInBackground: Bool = false,
        optimizeGameSettingsForStreaming: Bool = true,
        quitAppOnHostAfterStream: Bool = false,
        muteHostSpeakersWhileStreaming: Bool = true,
        muteAudioWhenInactiveWindow: Bool = true,
        autoFindHosts: Bool = true,
        language: ShadowClientLanguagePreference = .automatic,
        guiDisplayMode: ShadowClientGUIDisplayMode = .windowed
    ) {
        self.lowLatencyMode = lowLatencyMode
        self.preferHDR = preferHDR
        self.showDiagnosticsHUD = showDiagnosticsHUD
        self.resolution = resolution
        self.frameRate = frameRate
        self.bitrateKbps = min(max(500, bitrateKbps), 500_000)
        self.displayMode = displayMode
        self.audioConfiguration = audioConfiguration
        self.videoCodec = videoCodec
        self.videoDecoder = videoDecoder
        self.enableVSync = enableVSync
        self.enableFramePacing = enableFramePacing
        self.enableYUV444 = enableYUV444
        self.unlockBitrateLimit = unlockBitrateLimit
        self.optimizeMouseForDesktop = optimizeMouseForDesktop
        self.captureSystemKeyboardShortcuts = captureSystemKeyboardShortcuts
        self.keyboardShortcutCaptureMode = keyboardShortcutCaptureMode
        self.useTouchscreenTrackpad = useTouchscreenTrackpad
        self.swapMouseButtons = swapMouseButtons
        self.reverseMouseScrollDirection = reverseMouseScrollDirection
        self.swapABXYButtons = swapABXYButtons
        self.forceGamepadOneAlwaysConnected = forceGamepadOneAlwaysConnected
        self.enableGamepadMouseMode = enableGamepadMouseMode
        self.processGamepadInputInBackground = processGamepadInputInBackground
        self.optimizeGameSettingsForStreaming = optimizeGameSettingsForStreaming
        self.quitAppOnHostAfterStream = quitAppOnHostAfterStream
        self.muteHostSpeakersWhileStreaming = muteHostSpeakersWhileStreaming
        self.muteAudioWhenInactiveWindow = muteAudioWhenInactiveWindow
        self.autoFindHosts = autoFindHosts
        self.language = language
        self.guiDisplayMode = guiDisplayMode
    }

    public var streamingPreferences: StreamingUserPreferences {
        StreamingUserPreferences(
            preferHDR: preferHDR,
            preferSurroundAudio: audioConfiguration.prefersSurroundAudio,
            lowLatencyMode: lowLatencyMode
        )
    }

    public func launchSettings(
        hostApp: ShadowClientRemoteAppDescriptor?
    ) -> ShadowClientGameStreamLaunchSettings {
        ShadowClientGameStreamLaunchSettings(
            width: resolution.width,
            height: resolution.height,
            fps: frameRate.rawValue,
            bitrateKbps: bitrateKbps,
            preferredCodec: videoCodec,
            enableHDR: preferHDR && (hostApp?.hdrSupported ?? true),
            enableSurroundAudio: audioConfiguration.prefersSurroundAudio,
            lowLatencyMode: lowLatencyMode,
            enableVSync: enableVSync,
            enableFramePacing: enableFramePacing,
            enableYUV444: enableYUV444,
            unlockBitrateLimit: unlockBitrateLimit,
            forceHardwareDecoding: videoDecoder != .software,
            optimizeGameSettingsForStreaming: optimizeGameSettingsForStreaming,
            quitAppOnHostAfterStreamEnds: quitAppOnHostAfterStream
        )
    }

    public var identityKey: String {
        [
            "\(lowLatencyMode)",
            "\(preferHDR)",
            "\(showDiagnosticsHUD)",
            resolution.rawValue,
            "\(frameRate.rawValue)",
            "\(bitrateKbps)",
            audioConfiguration.rawValue,
            videoCodec.rawValue,
            videoDecoder.rawValue,
            "\(enableVSync)",
            "\(enableFramePacing)",
            "\(enableYUV444)",
            "\(unlockBitrateLimit)",
            "\(autoFindHosts)",
        ].joined(separator: "-")
    }

    public var streamingIdentityKey: String {
        [
            "\(lowLatencyMode)",
            "\(preferHDR)",
            audioConfiguration.rawValue,
        ].joined(separator: "-")
    }
}

public extension ShadowClientFeatureHomeDependencies {
    func applying(settings: ShadowClientAppSettings) -> Self {
        let updatedPreferences = settings.streamingPreferences

        return .init(
            telemetryPublisher: telemetryPublisher,
            diagnosticsRuntime: HomeDiagnosticsRuntime(
                launchRuntime: AdaptiveSessionLaunchRuntime(
                    telemetryPipeline: .init(initialBufferMs: 40.0),
                    settingsMapper: settingsMapper,
                    sessionPreferences: updatedPreferences,
                    hostCapabilities: hostCapabilities
                )
            ),
            connectionRuntime: connectionRuntime,
            hostDiscoveryRuntime: hostDiscoveryRuntime,
            remoteDesktopRuntime: remoteDesktopRuntime,
            connectionBackendLabel: connectionBackendLabel,
            settingsMapper: settingsMapper,
            sessionPreferences: updatedPreferences,
            hostCapabilities: hostCapabilities
        )
    }
}
