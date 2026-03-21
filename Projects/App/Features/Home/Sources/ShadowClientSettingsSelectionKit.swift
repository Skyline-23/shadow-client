import Foundation
import ShadowClientFeatureSession

struct ShadowClientSettingsSelectionInput {
    let lowLatencyMode: Bool
    let preferHDR: Bool
    let showDiagnosticsHUD: Bool
    let resolution: ShadowClientStreamingResolutionPreset
    let frameRate: ShadowClientStreamingFrameRatePreset
    let bitrateKbps: Int
    let autoBitrate: Bool
    let displayMode: ShadowClientDisplayMode
    let preferVirtualDisplay: Bool
    let audioConfiguration: ShadowClientAudioConfiguration
    let videoCodec: ShadowClientVideoCodecPreference
    let videoDecoder: ShadowClientVideoDecoderPreference
    let enableVSync: Bool
    let enableFramePacing: Bool
    let enableYUV444: Bool
    let unlockBitrateLimit: Bool
    let prioritizeStreamingTraffic: Bool
    let optimizeMouseForDesktop: Bool
    let captureSystemKeyboardShortcuts: Bool
    let keyboardShortcutCaptureMode: ShadowClientKeyboardShortcutCaptureMode
    let useTouchscreenTrackpad: Bool
    let swapMouseButtons: Bool
    let reverseMouseScrollDirection: Bool
    let swapABXYButtons: Bool
    let forceGamepadOneAlwaysConnected: Bool
    let enableGamepadMouseMode: Bool
    let processGamepadInputInBackground: Bool
    let optimizeGameSettingsForStreaming: Bool
    let quitAppOnHostAfterStream: Bool
    let muteHostSpeakersWhileStreaming: Bool
    let muteAudioWhenInactiveWindow: Bool
    let autoFindHosts: Bool
    let language: ShadowClientLanguagePreference
    let guiDisplayMode: ShadowClientGUIDisplayMode

    init(
        lowLatencyMode: Bool,
        preferHDR: Bool,
        showDiagnosticsHUD: Bool,
        resolution: ShadowClientStreamingResolutionPreset,
        frameRate: ShadowClientStreamingFrameRatePreset,
        bitrateKbps: Int,
        autoBitrate: Bool,
        displayMode: ShadowClientDisplayMode,
        preferVirtualDisplay: Bool,
        audioConfiguration: ShadowClientAudioConfiguration,
        videoCodec: ShadowClientVideoCodecPreference,
        videoDecoder: ShadowClientVideoDecoderPreference,
        enableVSync: Bool,
        enableFramePacing: Bool,
        enableYUV444: Bool,
        unlockBitrateLimit: Bool,
        prioritizeStreamingTraffic: Bool,
        optimizeMouseForDesktop: Bool,
        captureSystemKeyboardShortcuts: Bool,
        keyboardShortcutCaptureMode: ShadowClientKeyboardShortcutCaptureMode,
        useTouchscreenTrackpad: Bool,
        swapMouseButtons: Bool,
        reverseMouseScrollDirection: Bool,
        swapABXYButtons: Bool,
        forceGamepadOneAlwaysConnected: Bool,
        enableGamepadMouseMode: Bool,
        processGamepadInputInBackground: Bool,
        optimizeGameSettingsForStreaming: Bool,
        quitAppOnHostAfterStream: Bool,
        muteHostSpeakersWhileStreaming: Bool,
        muteAudioWhenInactiveWindow: Bool,
        autoFindHosts: Bool,
        language: ShadowClientLanguagePreference,
        guiDisplayMode: ShadowClientGUIDisplayMode
    ) {
        self.lowLatencyMode = lowLatencyMode
        self.preferHDR = preferHDR
        self.showDiagnosticsHUD = showDiagnosticsHUD
        self.resolution = resolution
        self.frameRate = frameRate
        self.bitrateKbps = bitrateKbps
        self.autoBitrate = autoBitrate
        self.displayMode = displayMode
        self.preferVirtualDisplay = preferVirtualDisplay
        self.audioConfiguration = audioConfiguration
        self.videoCodec = videoCodec
        self.videoDecoder = videoDecoder
        self.enableVSync = enableVSync
        self.enableFramePacing = enableFramePacing
        self.enableYUV444 = enableYUV444
        self.unlockBitrateLimit = unlockBitrateLimit
        self.prioritizeStreamingTraffic = prioritizeStreamingTraffic
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
}

enum ShadowClientSettingsSelectionKit {
    static func makeSettings(_ input: ShadowClientSettingsSelectionInput) -> ShadowClientAppSettings {
        ShadowClientAppSettings(
            lowLatencyMode: input.lowLatencyMode,
            preferHDR: input.preferHDR,
            showDiagnosticsHUD: input.showDiagnosticsHUD,
            resolution: input.resolution,
            frameRate: input.frameRate,
            bitrateKbps: input.bitrateKbps,
            autoBitrate: input.autoBitrate,
            displayMode: input.displayMode,
            preferVirtualDisplay: input.preferVirtualDisplay,
            audioConfiguration: input.audioConfiguration,
            videoCodec: input.videoCodec,
            videoDecoder: input.videoDecoder,
            enableVSync: input.enableVSync,
            enableFramePacing: input.enableFramePacing,
            enableYUV444: input.enableYUV444,
            unlockBitrateLimit: input.unlockBitrateLimit,
            prioritizeStreamingTraffic: input.prioritizeStreamingTraffic,
            optimizeMouseForDesktop: input.optimizeMouseForDesktop,
            captureSystemKeyboardShortcuts: input.captureSystemKeyboardShortcuts,
            keyboardShortcutCaptureMode: input.keyboardShortcutCaptureMode,
            useTouchscreenTrackpad: input.useTouchscreenTrackpad,
            swapMouseButtons: input.swapMouseButtons,
            reverseMouseScrollDirection: input.reverseMouseScrollDirection,
            swapABXYButtons: input.swapABXYButtons,
            forceGamepadOneAlwaysConnected: input.forceGamepadOneAlwaysConnected,
            enableGamepadMouseMode: input.enableGamepadMouseMode,
            processGamepadInputInBackground: input.processGamepadInputInBackground,
            optimizeGameSettingsForStreaming: input.optimizeGameSettingsForStreaming,
            quitAppOnHostAfterStream: input.quitAppOnHostAfterStream,
            muteHostSpeakersWhileStreaming: input.muteHostSpeakersWhileStreaming,
            muteAudioWhenInactiveWindow: input.muteAudioWhenInactiveWindow,
            autoFindHosts: input.autoFindHosts,
            language: input.language,
            guiDisplayMode: input.guiDisplayMode
        )
    }

    static func resolution(rawValue: String) -> ShadowClientStreamingResolutionPreset {
        ShadowClientStreamingResolutionPreset(rawValue: rawValue) ?? ShadowClientAppSettingsDefaults.defaultResolution
    }

    static func frameRate(rawValue: Int) -> ShadowClientStreamingFrameRatePreset {
        ShadowClientStreamingFrameRatePreset(rawValue: rawValue) ?? ShadowClientAppSettingsDefaults.defaultFrameRate
    }

    static func displayMode(rawValue: String) -> ShadowClientDisplayMode {
        ShadowClientDisplayMode(rawValue: rawValue) ?? .borderlessFullscreen
    }

    static func audioConfiguration(rawValue: String) -> ShadowClientAudioConfiguration {
        ShadowClientAudioConfiguration(rawValue: rawValue) ?? .surround71
    }

    static func videoCodec(rawValue: String) -> ShadowClientVideoCodecPreference {
        ShadowClientVideoCodecPreference(rawValue: rawValue) ?? .auto
    }

    static func videoDecoder(rawValue: String) -> ShadowClientVideoDecoderPreference {
        ShadowClientVideoDecoderPreference(rawValue: rawValue) ?? .forceHardware
    }

    static func keyboardShortcutCaptureMode(rawValue: String) -> ShadowClientKeyboardShortcutCaptureMode {
        ShadowClientKeyboardShortcutCaptureMode(rawValue: rawValue) ?? .fullscreenOnly
    }

    static func language(rawValue: String) -> ShadowClientLanguagePreference {
        ShadowClientLanguagePreference(rawValue: rawValue) ?? .automatic
    }

    static func guiDisplayMode(rawValue: String) -> ShadowClientGUIDisplayMode {
        ShadowClientGUIDisplayMode(rawValue: rawValue) ?? .windowed
    }
}
