import Foundation

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
