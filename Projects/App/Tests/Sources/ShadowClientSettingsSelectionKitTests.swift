import Testing
import ShadowClientFeatureSession
@testable import ShadowClientFeatureHome

@Test("Settings selection kit resolves fallback selections from raw values")
func settingsSelectionKitFallbackSelections() {
    #expect(ShadowClientSettingsSelectionKit.resolution(rawValue: "invalid") == ShadowClientAppSettingsDefaults.defaultResolution)
    #expect(ShadowClientSettingsSelectionKit.frameRate(rawValue: -1) == ShadowClientAppSettingsDefaults.defaultFrameRate)
    #expect(ShadowClientSettingsSelectionKit.displayMode(rawValue: "invalid") == .borderlessFullscreen)
    #expect(ShadowClientSettingsSelectionKit.audioConfiguration(rawValue: "invalid") == .surround71)
    #expect(ShadowClientSettingsSelectionKit.audioSynchronizationPolicy(rawValue: "invalid") == .lowLatency)
    #expect(ShadowClientSettingsSelectionKit.videoCodec(rawValue: "invalid") == .auto)
    #expect(ShadowClientSettingsSelectionKit.videoDecoder(rawValue: "invalid") == .forceHardware)
    #expect(ShadowClientSettingsSelectionKit.keyboardShortcutCaptureMode(rawValue: "invalid") == .fullscreenOnly)
    #expect(ShadowClientSettingsSelectionKit.language(rawValue: "invalid") == .automatic)
    #expect(ShadowClientSettingsSelectionKit.guiDisplayMode(rawValue: "invalid") == .windowed)
}

@Test("Settings selection kit assembles app settings from selection input")
func settingsSelectionKitBuildsAppSettings() {
    let settings = ShadowClientSettingsSelectionKit.makeSettings(
        .init(
            lowLatencyMode: true,
            preferHDR: true,
            showDiagnosticsHUD: true,
            resolution: .retinaAuto,
            frameRate: .fps120,
            bitrateKbps: 20000,
            autoBitrate: true,
            displayMode: .windowed,
            preferVirtualDisplay: true,
            audioConfiguration: .stereo,
            audioSynchronizationPolicy: .lowLatency,
            videoCodec: .h265,
            videoDecoder: .software,
            enableVSync: false,
            enableFramePacing: false,
            enableYUV444: true,
            unlockBitrateLimit: true,
            optimizeMouseForDesktop: true,
            captureSystemKeyboardShortcuts: true,
            keyboardShortcutCaptureMode: .always,
            useTouchscreenTrackpad: true,
            swapMouseButtons: true,
            reverseMouseScrollDirection: true,
            swapABXYButtons: true,
            forceGamepadOneAlwaysConnected: true,
            enableGamepadMouseMode: true,
            processGamepadInputInBackground: true,
            optimizeGameSettingsForStreaming: true,
            quitAppOnHostAfterStream: true,
            muteHostSpeakersWhileStreaming: true,
            muteAudioWhenInactiveWindow: true,
            autoFindHosts: true,
            language: .automatic,
            guiDisplayMode: .windowed
        )
    )

    #expect(settings.lowLatencyMode)
    #expect(settings.preferHDR)
    #expect(settings.resolution == ShadowClientStreamingResolutionPreset.retinaAuto)
    #expect(settings.frameRate == ShadowClientStreamingFrameRatePreset.fps120)
    #expect(settings.audioSynchronizationPolicy == .lowLatency)
    #expect(settings.videoCodec == ShadowClientVideoCodecPreference.h265)
    #expect(settings.videoDecoder == ShadowClientVideoDecoderPreference.software)
}
