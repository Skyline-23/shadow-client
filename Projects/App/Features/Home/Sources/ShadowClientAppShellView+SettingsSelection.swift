import ShadowClientStreaming
import ShadowClientUI
import SwiftUI
import ShadowClientFeatureConnection
import ShadowClientFeatureSession

extension ShadowClientAppShellView {
    var currentSettings: ShadowClientAppSettings {
        ShadowClientSettingsSelectionKit.makeSettings(
            .init(
                lowLatencyMode: lowLatencyMode,
                preferHDR: preferHDR,
                showDiagnosticsHUD: showDiagnosticsHUD,
                resolution: selectedResolution,
                frameRate: selectedFrameRate,
                bitrateKbps: bitrateKbps,
                autoBitrate: autoBitrate,
                displayMode: selectedDisplayMode,
                preferVirtualDisplay: preferVirtualDisplay,
                audioConfiguration: selectedAudioConfiguration,
                videoCodec: selectedVideoCodec,
                videoDecoder: selectedVideoDecoder,
                enableVSync: enableVSync,
                enableFramePacing: enableFramePacing,
                enableYUV444: enableYUV444,
                unlockBitrateLimit: unlockBitrateLimit,
                prioritizeStreamingTraffic: prioritizeStreamingTraffic,
                optimizeMouseForDesktop: optimizeMouseForDesktop,
                captureSystemKeyboardShortcuts: captureSystemKeyboardShortcuts,
                keyboardShortcutCaptureMode: selectedKeyboardShortcutCaptureMode,
                useTouchscreenTrackpad: useTouchscreenTrackpad,
                swapMouseButtons: swapMouseButtons,
                reverseMouseScrollDirection: reverseMouseScrollDirection,
                swapABXYButtons: swapABXYButtons,
                forceGamepadOneAlwaysConnected: forceGamepadOneAlwaysConnected,
                enableGamepadMouseMode: enableGamepadMouseMode,
                processGamepadInputInBackground: processGamepadInputInBackground,
                optimizeGameSettingsForStreaming: optimizeGameSettingsForStreaming,
                quitAppOnHostAfterStream: quitAppOnHostAfterStream,
                muteHostSpeakersWhileStreaming: muteHostSpeakersWhileStreaming,
                muteAudioWhenInactiveWindow: muteAudioWhenInactiveWindow,
                autoFindHosts: autoFindHosts,
                language: selectedLanguage,
                guiDisplayMode: selectedGUIDisplayMode
            )
        )
    }

    var gamepadInputConfiguration: ShadowClientGamepadInputPassthroughRuntime.Configuration {
        .init(
            swapABXYButtons: swapABXYButtons,
            forceGamepadOneAlwaysConnected: forceGamepadOneAlwaysConnected,
            processInputInBackground: processGamepadInputInBackground
        )
    }

    var selectedResolution: ShadowClientStreamingResolutionPreset {
        get { ShadowClientSettingsSelectionKit.resolution(rawValue: resolutionRawValue) }
        nonmutating set { resolutionRawValue = newValue.rawValue }
    }

    var selectedFrameRate: ShadowClientStreamingFrameRatePreset {
        get { ShadowClientSettingsSelectionKit.frameRate(rawValue: frameRateRawValue) }
        nonmutating set { frameRateRawValue = newValue.rawValue }
    }

    var selectedDisplayMode: ShadowClientDisplayMode {
        get { ShadowClientSettingsSelectionKit.displayMode(rawValue: displayModeRawValue) }
        nonmutating set { displayModeRawValue = newValue.rawValue }
    }

    var selectedAudioConfiguration: ShadowClientAudioConfiguration {
        get { ShadowClientSettingsSelectionKit.audioConfiguration(rawValue: audioConfigurationRawValue) }
        nonmutating set { audioConfigurationRawValue = newValue.rawValue }
    }

    var selectedVideoCodec: ShadowClientVideoCodecPreference {
        get { ShadowClientSettingsSelectionKit.videoCodec(rawValue: videoCodecRawValue) }
        nonmutating set { videoCodecRawValue = newValue.rawValue }
    }

    var selectedVideoDecoder: ShadowClientVideoDecoderPreference {
        get { ShadowClientSettingsSelectionKit.videoDecoder(rawValue: videoDecoderRawValue) }
        nonmutating set { videoDecoderRawValue = newValue.rawValue }
    }

    var selectedKeyboardShortcutCaptureMode: ShadowClientKeyboardShortcutCaptureMode {
        get { ShadowClientSettingsSelectionKit.keyboardShortcutCaptureMode(rawValue: keyboardShortcutCaptureModeRawValue) }
        nonmutating set { keyboardShortcutCaptureModeRawValue = newValue.rawValue }
    }

    var selectedLanguage: ShadowClientLanguagePreference {
        get { ShadowClientSettingsSelectionKit.language(rawValue: languageRawValue) }
        nonmutating set { languageRawValue = newValue.rawValue }
    }

    var selectedGUIDisplayMode: ShadowClientGUIDisplayMode {
        get { ShadowClientSettingsSelectionKit.guiDisplayMode(rawValue: guiDisplayModeRawValue) }
        nonmutating set { guiDisplayModeRawValue = newValue.rawValue }
    }

    var activeSessionEndpoint: String {
        remoteDesktopRuntime.activeSession?.sessionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    var sessionPresentationModel: ShadowClientRemoteSessionPresentationModel {
        ShadowClientRemoteSessionPresentationKit.make(
            activeSessionEndpoint: activeSessionEndpoint,
            launchState: remoteDesktopRuntime.launchState,
            renderState: sessionSurfaceContext.renderState
        )
    }

    var normalizedConnectionHost: String {
        connectionHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var manualSubmissionHostCandidate: String {
        ShadowClientManualHostEntryKit.submissionCandidate(
            manualHostDraft,
            portDraft: manualHostPortDraft
        )
    }

    var canConnect: Bool {
        ShadowClientConnectionPresentationKit.canConnect(
            normalizedHost: normalizedConnectionHost,
            state: connectionState
        )
    }

    var canInitiateSessionConnection: Bool {
        ShadowClientConnectionPresentationKit.canInitiateSessionConnection(
            state: connectionState
        )
    }

    var canDisconnect: Bool {
        ShadowClientConnectionPresentationKit.canDisconnect(state: connectionState)
    }

    var connectionStatusText: String {
        ShadowClientConnectionPresentationKit.statusText(state: connectionState)
    }

    var connectionStatusColor: Color {
        ShadowClientConnectionPresentationKit.statusColor(state: connectionState)
    }

    var connectionStatusSymbol: String {
        ShadowClientConnectionPresentationKit.statusSymbol(state: connectionState)
    }
}
