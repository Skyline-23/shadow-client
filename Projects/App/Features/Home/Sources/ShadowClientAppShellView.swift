import Combine
import ShadowClientUI
import AVKit
import SwiftUI

public struct ShadowClientAppShellView: View {
    private enum AppTab: Hashable {
        case home
        case settings
    }

    private let platformName: String
    private let baseDependencies: ShadowClientFeatureHomeDependencies
    private let settingsTelemetryRuntime: SettingsDiagnosticsTelemetryRuntime

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: AppTab = .home
    @AppStorage(ShadowClientAppSettings.StorageKeys.lowLatencyMode) private var lowLatencyMode = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.preferHDR) private var preferHDR = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.showDiagnosticsHUD) private var showDiagnosticsHUD = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.connectionHost) private var connectionHost = ""
    @AppStorage(ShadowClientAppSettings.StorageKeys.resolution) private var resolutionRawValue = ShadowClientStreamingResolutionPreset.p1080.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.frameRate) private var frameRateRawValue = ShadowClientStreamingFrameRatePreset.fps60.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.bitrateKbps) private var bitrateKbps = 22_000
    @AppStorage(ShadowClientAppSettings.StorageKeys.displayMode) private var displayModeRawValue = ShadowClientDisplayMode.borderlessFullscreen.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.audioConfiguration) private var audioConfigurationRawValue = ShadowClientAudioConfiguration.surround71.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.videoCodec) private var videoCodecRawValue = ShadowClientVideoCodecPreference.auto.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.videoDecoder) private var videoDecoderRawValue = ShadowClientVideoDecoderPreference.forceHardware.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.enableVSync) private var enableVSync = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.enableFramePacing) private var enableFramePacing = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.enableYUV444) private var enableYUV444 = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.unlockBitrateLimit) private var unlockBitrateLimit = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.optimizeMouseForDesktop) private var optimizeMouseForDesktop = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.captureSystemKeyboardShortcuts) private var captureSystemKeyboardShortcuts = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.keyboardShortcutCaptureMode) private var keyboardShortcutCaptureModeRawValue = ShadowClientKeyboardShortcutCaptureMode.fullscreenOnly.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.useTouchscreenTrackpad) private var useTouchscreenTrackpad = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.swapMouseButtons) private var swapMouseButtons = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.reverseMouseScrollDirection) private var reverseMouseScrollDirection = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.swapABXYButtons) private var swapABXYButtons = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.forceGamepadOneAlwaysConnected) private var forceGamepadOneAlwaysConnected = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.enableGamepadMouseMode) private var enableGamepadMouseMode = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.processGamepadInputInBackground) private var processGamepadInputInBackground = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.optimizeGameSettingsForStreaming) private var optimizeGameSettingsForStreaming = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.quitAppOnHostAfterStream) private var quitAppOnHostAfterStream = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.muteHostSpeakersWhileStreaming) private var muteHostSpeakersWhileStreaming = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.muteAudioWhenInactiveWindow) private var muteAudioWhenInactiveWindow = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.autoFindHosts) private var autoFindHosts = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.language) private var languageRawValue = ShadowClientLanguagePreference.automatic.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.guiDisplayMode) private var guiDisplayModeRawValue = ShadowClientGUIDisplayMode.windowed.rawValue
    @ObservedObject private var hostDiscoveryRuntime: ShadowClientHostDiscoveryRuntime
    @ObservedObject private var remoteDesktopRuntime: ShadowClientRemoteDesktopRuntime
    @StateObject private var sessionPlaybackRuntime = ShadowClientSessionPlaybackRuntime()
    @State private var connectionState: ShadowClientConnectionState = .disconnected
    @State private var settingsTelemetryCancellable: AnyCancellable?
    @State private var settingsDiagnosticsModel: SettingsDiagnosticsHUDModel?

    public init(platformName: String, dependencies: ShadowClientFeatureHomeDependencies) {
        self.platformName = platformName
        self.baseDependencies = dependencies
        _hostDiscoveryRuntime = ObservedObject(wrappedValue: dependencies.hostDiscoveryRuntime)
        _remoteDesktopRuntime = ObservedObject(wrappedValue: dependencies.remoteDesktopRuntime)
        self.settingsTelemetryRuntime = SettingsDiagnosticsTelemetryRuntime(
            baseDependencies: dependencies
        )
    }

    public var body: some View {
        ZStack {
            backgroundGradient
            if remoteDesktopRuntime.activeSession == nil {
                TabView(selection: $selectedTab) {
                    homeTab
                    settingsTab
                }
            } else {
                remoteSessionFlowView
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .tint(accentColor)
        .preferredColorScheme(.dark)
        .task {
            await syncConnectionStateFromRuntime()
            startHostDiscovery()
            refreshRemoteDesktopCatalog()
        }
        .task(id: currentSettings.streamingIdentityKey) {
            restartSettingsTelemetrySubscription(for: currentSettings)
        }
        .onChange(of: hostDiscoveryRuntime.hosts, initial: false) { _, _ in
            refreshRemoteDesktopCatalog()
        }
        .onChange(of: connectionHost, initial: false) { _, _ in
            refreshRemoteDesktopCatalog()
        }
        .onChange(of: autoFindHosts, initial: false) { _, _ in
            if autoFindHosts {
                startHostDiscovery()
            } else {
                stopHostDiscovery()
            }
            refreshRemoteDesktopCatalog()
        }
        .onChange(of: unlockBitrateLimit, initial: false) { _, unlocked in
            if !unlocked && bitrateKbps > 150_000 {
                bitrateKbps = 150_000
            }
        }
        .onDisappear {
            stopSettingsTelemetrySubscription()
            stopHostDiscovery()
            sessionPlaybackRuntime.stop()
        }
        .onChange(of: activeSessionPlaybackURL, initial: true) { _, sessionURL in
            if sessionURL.isEmpty {
                sessionPlaybackRuntime.stop()
            } else {
                sessionPlaybackRuntime.start(sessionURL: sessionURL)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: remoteDesktopRuntime.activeSession != nil)
    }

    private var currentSettings: ShadowClientAppSettings {
        ShadowClientAppSettings(
            lowLatencyMode: lowLatencyMode,
            preferHDR: preferHDR,
            showDiagnosticsHUD: showDiagnosticsHUD,
            resolution: selectedResolution,
            frameRate: selectedFrameRate,
            bitrateKbps: bitrateKbps,
            displayMode: selectedDisplayMode,
            audioConfiguration: selectedAudioConfiguration,
            videoCodec: selectedVideoCodec,
            videoDecoder: selectedVideoDecoder,
            enableVSync: enableVSync,
            enableFramePacing: enableFramePacing,
            enableYUV444: enableYUV444,
            unlockBitrateLimit: unlockBitrateLimit,
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
    }

    private var selectedResolution: ShadowClientStreamingResolutionPreset {
        get { ShadowClientStreamingResolutionPreset(rawValue: resolutionRawValue) ?? .p1080 }
        nonmutating set { resolutionRawValue = newValue.rawValue }
    }

    private var selectedFrameRate: ShadowClientStreamingFrameRatePreset {
        get { ShadowClientStreamingFrameRatePreset(rawValue: frameRateRawValue) ?? .fps60 }
        nonmutating set { frameRateRawValue = newValue.rawValue }
    }

    private var selectedDisplayMode: ShadowClientDisplayMode {
        get { ShadowClientDisplayMode(rawValue: displayModeRawValue) ?? .borderlessFullscreen }
        nonmutating set { displayModeRawValue = newValue.rawValue }
    }

    private var selectedAudioConfiguration: ShadowClientAudioConfiguration {
        get { ShadowClientAudioConfiguration(rawValue: audioConfigurationRawValue) ?? .surround71 }
        nonmutating set { audioConfigurationRawValue = newValue.rawValue }
    }

    private var selectedVideoCodec: ShadowClientVideoCodecPreference {
        get { ShadowClientVideoCodecPreference(rawValue: videoCodecRawValue) ?? .auto }
        nonmutating set { videoCodecRawValue = newValue.rawValue }
    }

    private var selectedVideoDecoder: ShadowClientVideoDecoderPreference {
        get { ShadowClientVideoDecoderPreference(rawValue: videoDecoderRawValue) ?? .forceHardware }
        nonmutating set { videoDecoderRawValue = newValue.rawValue }
    }

    private var selectedKeyboardShortcutCaptureMode: ShadowClientKeyboardShortcutCaptureMode {
        get { ShadowClientKeyboardShortcutCaptureMode(rawValue: keyboardShortcutCaptureModeRawValue) ?? .fullscreenOnly }
        nonmutating set { keyboardShortcutCaptureModeRawValue = newValue.rawValue }
    }

    private var selectedLanguage: ShadowClientLanguagePreference {
        get { ShadowClientLanguagePreference(rawValue: languageRawValue) ?? .automatic }
        nonmutating set { languageRawValue = newValue.rawValue }
    }

    private var selectedGUIDisplayMode: ShadowClientGUIDisplayMode {
        get { ShadowClientGUIDisplayMode(rawValue: guiDisplayModeRawValue) ?? .windowed }
        nonmutating set { guiDisplayModeRawValue = newValue.rawValue }
    }

    private var activeSessionPlaybackURL: String {
        remoteDesktopRuntime.activeSession?.sessionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var sessionPlaybackStatusText: String {
        if activeSessionPlaybackURL.isEmpty {
            return "Session opened. Launch desktop/game on host to start remote stream."
        }

        switch sessionPlaybackRuntime.state {
        case .idle:
            return "Connecting to remote stream..."
        case .playing:
            return "Remote stream is active."
        case let .failed(message):
            return message
        }
    }

    private var sessionPlaybackOverlay: (title: String, symbol: String)? {
        if activeSessionPlaybackURL.isEmpty {
            return (
                title: "Waiting for remote desktop stream...",
                symbol: "desktopcomputer"
            )
        }

        switch sessionPlaybackRuntime.state {
        case .idle:
            return (
                title: "Connecting to remote desktop stream...",
                symbol: "antenna.radiowaves.left.and.right"
            )
        case .playing:
            return nil
        case .failed:
            return (
                title: "Remote desktop stream failed to start.",
                symbol: "exclamationmark.triangle"
            )
        }
    }

    private var homeTab: some View {
        ZStack {
            backgroundGradient
            ScrollView {
                VStack(spacing: 28) {
                    remoteDesktopHostCard
                    connectionStatusCard

                    ShadowClientFeatureHomeView(
                        platformName: platformName,
                        dependencies: baseDependencies.applying(settings: currentSettings),
                        connectionState: connectionState,
                        showsDiagnosticsHUD: currentSettings.showDiagnosticsHUD
                    )
                    .id(currentSettings.streamingIdentityKey)
                    .frame(maxWidth: .infinity, alignment: .top)

                    ControllerFeedbackStatusPanel()
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, topContentPadding)
                .padding(.horizontal, horizontalContentPadding)
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
        }
        .tabItem { Label("Home", systemImage: "house.fill") }
        .tag(AppTab.home)
    }

    private var settingsTab: some View {
        ZStack(alignment: .top) {
            backgroundGradient
            ScrollView {
                VStack(spacing: 18) {
                    settingsSection(title: "Client Connection") {
                        TextField("Host (IP or hostname)", text: $connectionHost)
                            .font(.body.weight(.semibold))
                            .textFieldStyle(.plain)
                            .foregroundStyle(.white)
                            .autocorrectionDisabled()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(rowSurface(cornerRadius: 10))
                            .onSubmit {
                                if canConnect {
                                    connectToHost()
                                }
                            }

                        settingsRow {
                            Label("Backend: \(baseDependencies.connectionBackendLabel)", systemImage: "bolt.horizontal.circle")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.9))
                            Spacer(minLength: 0)
                        }

                        settingsRow {
                            Label(
                                "Auto Discovery: \(autoFindHosts ? hostDiscoveryRuntime.state.label : "Disabled")",
                                systemImage: "dot.radiowaves.left.and.right"
                            )
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.9))
                            Spacer(minLength: 0)
                            Button {
                                hostDiscoveryRuntime.refresh()
                                refreshRemoteDesktopCatalog()
                            } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .disabled(!autoFindHosts)
                        }

                        if hostDiscoveryRuntime.hosts.isEmpty {
                            settingsRow {
                                Text("No hosts discovered yet. Keep this view open or enter host manually.")
                                    .font(.callout.weight(.medium))
                                    .foregroundStyle(Color.white.opacity(0.82))
                                Spacer(minLength: 0)
                            }
                        } else {
                            ForEach(hostDiscoveryRuntime.hosts.prefix(8)) { discoveredHost in
                                discoveredHostRow(discoveredHost)
                            }
                        }

                        HStack(spacing: 10) {
                            Button("Connect") {
                                connectToHost()
                            }
                            .disabled(!canConnect)
                            .buttonStyle(.borderedProminent)

                            Button("Disconnect") {
                                disconnectFromHost()
                            }
                            .disabled(!canDisconnect)
                            .buttonStyle(.bordered)

                            Spacer(minLength: 0)
                        }

                        settingsRow {
                            Label(connectionStatusText, systemImage: connectionStatusSymbol)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(connectionStatusColor)
                            Spacer(minLength: 0)
                        }
                    }

                    settingsSection(title: "Basic Settings") {
                        settingsPickerRow(
                            title: "Resolution",
                            symbol: "rectangle.expand.vertical",
                            selection: Binding(
                                get: { selectedResolution },
                                set: { selectedResolution = $0 }
                            )
                        ) {
                            ForEach(ShadowClientStreamingResolutionPreset.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }

                        settingsPickerRow(
                            title: "Frame Rate",
                            symbol: "film.stack",
                            selection: Binding(
                                get: { selectedFrameRate },
                                set: { selectedFrameRate = $0 }
                            )
                        ) {
                            ForEach(ShadowClientStreamingFrameRatePreset.allCases, id: \.self) { option in
                                Text("\(option.rawValue) FPS").tag(option)
                            }
                        }

                        settingsRow {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label("Video bitrate", systemImage: "dial.medium")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.white)
                                    Spacer(minLength: 8)
                                    Text("\(bitrateKbps) Kbps")
                                        .font(.footnote.monospacedDigit().weight(.bold))
                                        .foregroundStyle(.mint)
                                }
                                Slider(
                                    value: bitrateSliderBinding,
                                    in: 500...maxBitrateKbps,
                                    step: 500
                                )
                                .tint(.mint)
                            }
                        }

                        settingsPickerRow(
                            title: "Display mode",
                            symbol: "macwindow",
                            selection: Binding(
                                get: { selectedDisplayMode },
                                set: { selectedDisplayMode = $0 }
                            )
                        ) {
                            ForEach(ShadowClientDisplayMode.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }

                        settingsRow {
                            Toggle(isOn: $lowLatencyMode) {
                                Label("Low-Latency Mode", systemImage: "speedometer")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $preferHDR) {
                                Label("Enable HDR (Experimental)", systemImage: "sparkles.tv")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $enableVSync) {
                                Label("V-Sync", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $enableFramePacing) {
                                Label("Frame pacing", systemImage: "waveform.path")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "Audio Settings") {
                        settingsPickerRow(
                            title: "Audio configuration",
                            symbol: "hifispeaker.and.homepod.fill",
                            selection: Binding(
                                get: { selectedAudioConfiguration },
                                set: { selectedAudioConfiguration = $0 }
                            )
                        ) {
                            ForEach(ShadowClientAudioConfiguration.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }

                        settingsRow {
                            Toggle(isOn: $muteHostSpeakersWhileStreaming) {
                                Text("Mute host PC speakers while streaming")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $muteAudioWhenInactiveWindow) {
                                Text("Mute audio stream when app is not active")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "Input Settings") {
                        settingsRow {
                            Toggle(isOn: $optimizeMouseForDesktop) {
                                Text("Optimize mouse for remote desktop instead of games")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $captureSystemKeyboardShortcuts) {
                                Text("Capture system keyboard shortcuts")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        if captureSystemKeyboardShortcuts {
                            settingsPickerRow(
                                title: "Shortcut capture mode",
                                symbol: "command",
                                selection: Binding(
                                    get: { selectedKeyboardShortcutCaptureMode },
                                    set: { selectedKeyboardShortcutCaptureMode = $0 }
                                )
                            ) {
                                ForEach(ShadowClientKeyboardShortcutCaptureMode.allCases, id: \.self) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                        }

                        settingsRow {
                            Toggle(isOn: $useTouchscreenTrackpad) {
                                Text("Use touchscreen as virtual trackpad")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $swapMouseButtons) {
                                Text("Swap left and right mouse buttons")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $reverseMouseScrollDirection) {
                                Text("Reverse mouse scrolling direction")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "Gamepad Settings") {
                        settingsRow {
                            Toggle(isOn: $swapABXYButtons) {
                                Text("Swap A/B and X/Y gamepad buttons")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $forceGamepadOneAlwaysConnected) {
                                Text("Force gamepad #1 always connected")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $enableGamepadMouseMode) {
                                Text("Enable mouse control with gamepads by holding Start")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $processGamepadInputInBackground) {
                                Text("Process gamepad input while app is in background")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "Advanced Settings") {
                        settingsPickerRow(
                            title: "Video decoder",
                            symbol: "cpu",
                            selection: Binding(
                                get: { selectedVideoDecoder },
                                set: { selectedVideoDecoder = $0 }
                            )
                        ) {
                            ForEach(ShadowClientVideoDecoderPreference.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }

                        settingsPickerRow(
                            title: "Video codec",
                            symbol: "film",
                            selection: Binding(
                                get: { selectedVideoCodec },
                                set: { selectedVideoCodec = $0 }
                            )
                        ) {
                            ForEach(ShadowClientVideoCodecPreference.allCases, id: \.self) { option in
                                Text(videoCodecLabel(option)).tag(option)
                            }
                        }

                        settingsRow {
                            Toggle(isOn: $enableYUV444) {
                                Text("Enable YUV 4:4:4 (Experimental)")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $unlockBitrateLimit) {
                                Text("Unlock bitrate limit (Experimental)")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $autoFindHosts) {
                                Text("Automatically find PCs on local network")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "Host Settings") {
                        settingsRow {
                            Toggle(isOn: $optimizeGameSettingsForStreaming) {
                                Text("Optimize game settings for streaming")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }

                        settingsRow {
                            Toggle(isOn: $quitAppOnHostAfterStream) {
                                Text("Quit app on host after ending stream")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "UI Settings") {
                        settingsPickerRow(
                            title: "Language",
                            symbol: "globe",
                            selection: Binding(
                                get: { selectedLanguage },
                                set: { selectedLanguage = $0 }
                            )
                        ) {
                            ForEach(ShadowClientLanguagePreference.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }

                        settingsPickerRow(
                            title: "GUI display mode",
                            symbol: "rectangle.3.group",
                            selection: Binding(
                                get: { selectedGUIDisplayMode },
                                set: { selectedGUIDisplayMode = $0 }
                            )
                        ) {
                            ForEach(ShadowClientGUIDisplayMode.allCases, id: \.self) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    }

                    settingsSection(title: "Diagnostics") {
                        settingsRow {
                            Toggle(isOn: $showDiagnosticsHUD) {
                                Label("Show Debug HUD", systemImage: "waveform.path.ecg.rectangle")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)
                        }
                    }

                    settingsSection(title: "Session Launch Plan") {
                        if let settingsDiagnosticsModel {
                            diagnosticsRow(
                                label: "Tone",
                                value: settingsDiagnosticsModel.tone.rawValue.uppercased(),
                                valueColor: toneColor(for: settingsDiagnosticsModel.tone)
                            )
                            diagnosticsRow(
                                label: "Target Buffer",
                                value: "\(settingsDiagnosticsModel.targetBufferMs) ms"
                            )
                            diagnosticsRow(
                                label: "Jitter / Packet Loss",
                                value: "\(settingsDiagnosticsModel.jitterMs) ms / \(String(format: "%.1f", settingsDiagnosticsModel.packetLossPercent))%"
                            )
                            diagnosticsRow(
                                label: "Frame Drop / AV Sync",
                                value: "\(String(format: "%.1f", settingsDiagnosticsModel.frameDropPercent))% / \(settingsDiagnosticsModel.avSyncOffsetMs) ms"
                            )
                            diagnosticsRow(
                                label: "Drop Origin",
                                value: "NET \(settingsDiagnosticsModel.networkDroppedFrames) / PACER \(settingsDiagnosticsModel.pacerDroppedFrames)"
                            )
                            diagnosticsRow(
                                label: "Telemetry Timestamp",
                                value: "\(settingsDiagnosticsModel.timestampMs) ms",
                                valueColor: Color.white.opacity(0.78)
                            )
                            if let sampleIntervalMs = settingsDiagnosticsModel.sampleIntervalMs {
                                diagnosticsRow(
                                    label: "Sample Interval",
                                    value: "\(sampleIntervalMs) ms",
                                    valueColor: Color.white.opacity(0.78)
                                )
                            } else {
                                diagnosticsRow(
                                    label: "Sample Interval",
                                    value: "--",
                                    valueColor: Color.white.opacity(0.78)
                                )
                            }
                            if settingsDiagnosticsModel.receivedOutOfOrderSample {
                                diagnosticsRow(
                                    label: "Sample Order",
                                    value: "Out-of-order telemetry sample ignored",
                                    valueColor: .orange
                                )
                            }
                            diagnosticsRow(
                                label: "Session Video / Audio",
                                value: "\(settingsDiagnosticsModel.hdrVideoMode.rawValue.uppercased()) / \(settingsDiagnosticsModel.audioMode.rawValue.uppercased())"
                            )
                            diagnosticsRow(
                                label: "Reconfigure",
                                value: "V:\(settingsDiagnosticsModel.shouldRenegotiateVideoPipeline ? "Y" : "N") A:\(settingsDiagnosticsModel.shouldRenegotiateAudioPipeline ? "Y" : "N") QDrop:\(settingsDiagnosticsModel.shouldApplyQualityDropImmediately ? "Y" : "N")",
                                valueColor: Color.white.opacity(0.78)
                            )
                            if settingsDiagnosticsModel.recoveryStableSamplesRemaining > 0 {
                                diagnosticsRow(
                                    label: "Recovery Hold",
                                    value: "\(settingsDiagnosticsModel.recoveryStableSamplesRemaining) stable sample(s) remaining",
                                    valueColor: .orange
                                )
                            }
                        } else {
                            settingsRow {
                                Label("Awaiting telemetry samples from active session.", systemImage: "antenna.radiowaves.left.and.right")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.82))
                                Spacer(minLength: 0)
                            }
                        }
                    }

                    settingsSection(title: "Controller") {
                        settingsRow {
                            Label("USB-first DualSense feedback contract remains enabled.", systemImage: "gamecontroller.fill")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.82))
                            Spacer(minLength: 0)
                        }
                    }
                }
                .frame(maxWidth: contentMaxWidth)
                .frame(maxWidth: .infinity)
                .padding(.top, topContentPadding)
                .padding(.horizontal, horizontalContentPadding)
                .padding(.bottom, 40)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        .tag(AppTab.settings)
    }

    private var remoteDesktopHostCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Remote Desktop Hosts", systemImage: "desktopcomputer")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Label(remoteDesktopRuntime.hostState.label, systemImage: "dot.radiowaves.left.and.right")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .foregroundStyle(Color.white.opacity(0.9))
                    .background(Color.white.opacity(0.12), in: Capsule())
                Button {
                    refreshRemoteDesktopCatalog()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            if remoteDesktopRuntime.hosts.isEmpty {
                settingsRow {
                    Text("No hosts in catalog yet. Keep Settings > Client Connection open for discovery or set host manually.")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.88))
                    Spacer(minLength: 0)
                }
            } else {
                ForEach(remoteDesktopRuntime.hosts.prefix(6)) { host in
                    remoteDesktopHostRow(host)
                }
            }

            settingsRow {
                Button {
                    remoteDesktopRuntime.pairSelectedHost()
                } label: {
                    if case .pairing = remoteDesktopRuntime.pairingState {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Start Pairing")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(remoteDesktopRuntime.selectedHost == nil)
                Spacer(minLength: 0)
            }

            if let pairingPIN = remoteDesktopRuntime.activePairingPIN {
                settingsRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pair PIN: \(pairingPIN)")
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundStyle(.mint)
                        Text("Enter this PIN in Sunshine Web UI.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.82))
                    }
                    Spacer(minLength: 0)
                }
            }

            settingsRow {
                Label(remoteDesktopRuntime.pairingState.label, systemImage: "number.square")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(pairingStateColor)
                Spacer(minLength: 0)
            }

            remoteDesktopAppListSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelSurface(cornerRadius: 14))
    }

    private func remoteDesktopHostRow(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        let isSelected = remoteDesktopRuntime.selectedHostID == host.id

        return settingsRow {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(host.displayName)
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.85)

                        Text(host.host)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Color.white.opacity(0.86))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .minimumScaleFactor(0.8)

                        Text(host.statusLabel)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(remoteHostStatusColor(host))

                        Text(host.detailLabel)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .lineLimit(3)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 8)

                    if isSelected {
                        Label("Selected", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accentColor)
                    }
                }

                if isCompactLayout {
                    HStack(spacing: 8) {
                        Button("Use") {
                            connectionHost = host.host
                            remoteDesktopRuntime.selectHost(host.id)
                        }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("Connect") {
                            connectionHost = host.host
                            connectToHost(autoLaunchAfterConnect: true, preferredHostID: host.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canStartConnection || !host.isReachable)
                        .frame(maxWidth: .infinity)
                    }

                    if !isSelected {
                        Button("Select") {
                            remoteDesktopRuntime.selectHost(host.id)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button("Use") {
                            connectionHost = host.host
                            remoteDesktopRuntime.selectHost(host.id)
                        }
                        .buttonStyle(.bordered)

                        Button("Connect") {
                            connectionHost = host.host
                            connectToHost(autoLaunchAfterConnect: true, preferredHostID: host.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canStartConnection || !host.isReachable)

                        Button(isSelected ? "Selected" : "Select") {
                            remoteDesktopRuntime.selectHost(host.id)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isSelected)
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.mint.opacity(0.9) : Color.clear, lineWidth: 1.5)
        )
    }

    private var remoteDesktopAppListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isCompactLayout {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Host App Library")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
                        Button {
                            remoteDesktopRuntime.refreshSelectedHostApps()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                    }

                    Label(remoteDesktopRuntime.appState.label, systemImage: "gamecontroller.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.84))
                }
            } else {
                HStack {
                    Text("Host App Library")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    Label(remoteDesktopRuntime.appState.label, systemImage: "gamecontroller.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.84))
                    Button {
                        remoteDesktopRuntime.refreshSelectedHostApps()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                }
            }

            if let selectedHost = remoteDesktopRuntime.selectedHost {
                Text("Selected Host: \(selectedHost.displayName) (\(selectedHost.host))")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
            } else {
                Text("Select a host to inspect available desktop/game apps.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
            }

            if remoteDesktopRuntime.apps.isEmpty {
                settingsRow {
                    Text("No app metadata loaded yet. The host may require pairing before app list queries.")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.82))
                    Spacer(minLength: 0)
                }
            } else {
                ForEach(remoteDesktopRuntime.apps.prefix(8)) { app in
                    settingsRow {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.title)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.white)
                            Text("App ID: \(app.id) · HDR: \(app.hdrSupported ? "Y" : "N")")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                        Spacer(minLength: 8)
                        Button("Launch") {
                            launchRemoteApp(app)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(remoteDesktopRuntime.launchState == .launching)
                    }
                }
            }

            settingsRow {
                Label(remoteDesktopRuntime.launchState.label, systemImage: "play.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(launchStateColor)
                Spacer(minLength: 0)
            }
        }
    }

    private var connectionStatusCard: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text("Client Connection")
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(connectionStatusText)
                    .font(.footnote)
                    .foregroundStyle(Color.white.opacity(0.82))
            }

            Spacer()
        }
        .padding(14)
        .background(panelSurface(cornerRadius: 12))
    }

    private func remoteHostStatusColor(_ host: ShadowClientRemoteHostDescriptor) -> Color {
        if host.lastError != nil {
            return .red
        }

        if host.currentGameID > 0 {
            return .orange
        }

        switch host.pairStatus {
        case .paired:
            return .green
        case .notPaired:
            return .yellow
        case .unknown:
            return Color.white.opacity(0.78)
        }
    }

    private var pairingStateColor: Color {
        switch remoteDesktopRuntime.pairingState {
        case .idle:
            return Color.white.opacity(0.74)
        case .pairing:
            return .orange
        case .paired:
            return .green
        case .failed:
            return .red
        }
    }

    private var launchStateColor: Color {
        switch remoteDesktopRuntime.launchState {
        case .idle:
            return Color.white.opacity(0.74)
        case .launching:
            return .orange
        case .launched:
            return .green
        case .failed:
            return .red
        }
    }

    @ViewBuilder
    private var remoteSessionFlowView: some View {
        if let activeSession = remoteDesktopRuntime.activeSession {
            ZStack {
                backgroundGradient

                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Remote Session")
                                .font(.system(.title2, design: .rounded).weight(.bold))
                                .foregroundStyle(.white)
                            Text("\(activeSession.appTitle) · \(activeSession.host)")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.82))
                        }

                        Spacer(minLength: 8)

                        Button("End Session") {
                            remoteDesktopRuntime.clearActiveSession()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        ZStack {
#if os(macOS)
                            ShadowClientMacOSSessionPlayerView(player: sessionPlaybackRuntime.player)
#else
                            VideoPlayer(player: sessionPlaybackRuntime.player)
#endif

                            if let overlay = sessionPlaybackOverlay {
                                playbackOverlayLabel(
                                    overlay.title,
                                    symbol: overlay.symbol
                                )
                            }

#if os(macOS)
                            ShadowClientMacOSSessionInputCaptureView { event in
                                remoteDesktopRuntime.sendInput(event)
                            }
                            .background(Color.clear)
#endif
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: horizontalSizeClass == .compact ? 220 : 360)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Text(sessionPlaybackStatusText)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.90))

                        if let sessionURL = activeSession.sessionURL, !sessionURL.isEmpty {
                            Text(sessionURL)
                                .font(.footnote.monospaced())
                                .foregroundStyle(Color.white.opacity(0.72))
                                .textSelection(.enabled)
                        }

                        Label(remoteDesktopRuntime.launchState.label, systemImage: "play.circle.fill")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(launchStateColor)
                    }
                    .padding(14)
                    .background(panelSurface(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Input Capture")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Text("Click the stream surface to focus, then use keyboard and mouse for remote desktop input.")
                            .font(.body)
                            .foregroundStyle(Color.white.opacity(0.86))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(rowSurface(cornerRadius: 10))
                    }
                    .padding(14)
                    .background(panelSurface(cornerRadius: 14))

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: contentMaxWidth)
                .padding(.horizontal, horizontalContentPadding)
                .padding(.top, topContentPadding)
                .padding(.bottom, 24)
            }
        }
    }

    private var backgroundGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.08, blue: 0.15),
                    Color(red: 0.06, green: 0.16, blue: 0.20),
                    Color(red: 0.13, green: 0.14, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    accentColor.opacity(0.26),
                    .clear,
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    Color(red: 0.35, green: 0.45, blue: 0.95).opacity(0.18),
                    .clear,
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

    private var accentColor: Color {
        Color(red: 0.34, green: 0.88, blue: 0.82)
    }

    private var contentMaxWidth: CGFloat {
        horizontalSizeClass == .compact ? 380 : 920
    }

    private var isCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

    private var horizontalContentPadding: CGFloat {
        horizontalSizeClass == .compact ? 14 : 20
    }

    private var topContentPadding: CGFloat {
        horizontalSizeClass == .compact ? 20 : 28
    }

    private func panelSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.06),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 10)
    }

    private func rowSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.30),
                        Color.black.opacity(0.22),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            )
    }

    private func playbackOverlayLabel(_ title: String, symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black.opacity(0.45))
            .overlay {
                Label(title, systemImage: symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
            }
    }

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelSurface(cornerRadius: 14))
    }

    private func settingsRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
            .background(rowSurface(cornerRadius: 10))
    }

    private func settingsPickerRow<Value: Hashable, Content: View>(
        title: String,
        symbol: String,
        selection: Binding<Value>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsRow {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)

                Picker(title, selection: selection) {
                    content()
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            Spacer(minLength: 0)
        }
    }

    private func diagnosticsRow(
        label: String,
        value: String,
        valueColor: Color = Color.white.opacity(0.92)
    ) -> some View {
        settingsRow {
            Text(label)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.75))
            Spacer(minLength: 8)
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

    private func discoveredHostRow(_ discoveredHost: ShadowClientDiscoveredHost) -> some View {
        settingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(discoveredHost.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(discoveredHost.host):\(discoveredHost.port) · \(discoveredHost.serviceType)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.74))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button("Use") {
                connectionHost = discoveredHost.host
                refreshRemoteDesktopCatalog()
            }
            .buttonStyle(.bordered)
            Button("Connect") {
                connectToDiscoveredHost(discoveredHost)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStartConnection)
        }
    }

    private func toneColor(for tone: HealthTone) -> Color {
        switch tone {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    private func videoCodecLabel(_ codec: ShadowClientVideoCodecPreference) -> String {
        switch codec {
        case .auto:
            return "Auto"
        case .av1:
            return "AV1"
        case .h265:
            return "H.265"
        case .h264:
            return "H.264"
        }
    }

    private var maxBitrateKbps: Double {
        unlockBitrateLimit ? 500_000 : 150_000
    }

    private var bitrateSliderBinding: Binding<Double> {
        Binding(
            get: { Double(bitrateKbps) },
            set: { newValue in
                let clamped = min(max(500, Int(newValue.rounded() / 500) * 500), Int(maxBitrateKbps))
                bitrateKbps = clamped
            }
        )
    }

    private var normalizedConnectionHost: String {
        connectionHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canConnect: Bool {
        guard !normalizedConnectionHost.isEmpty else {
            return false
        }

        return canStartConnection
    }

    private var canStartConnection: Bool {
        switch connectionState {
        case .connected, .connecting, .disconnecting:
            return false
        case .disconnected, .failed:
            return true
        }
    }

    private var canDisconnect: Bool {
        switch connectionState {
        case .connected, .connecting, .failed:
            return true
        case .disconnected, .disconnecting:
            return false
        }
    }

    private var connectionStatusText: String {
        switch connectionState {
        case .disconnected:
            return "Status: Disconnected"
        case let .connecting(host):
            return "Status: Connecting to \(host)..."
        case let .connected(host):
            return "Status: Connected to \(host)"
        case .disconnecting:
            return "Status: Disconnecting..."
        case let .failed(_, message):
            return "Status: Connection Failed - \(message)"
        }
    }

    private var connectionStatusColor: Color {
        switch connectionState {
        case .connected:
            return .green
        case .failed:
            return .red
        case .connecting, .disconnecting:
            return .orange
        case .disconnected:
            return .secondary
        }
    }

    private var connectionStatusSymbol: String {
        switch connectionState {
        case .connected:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .connecting, .disconnecting:
            return "clock.fill"
        case .disconnected:
            return "bolt.slash.fill"
        }
    }

    @MainActor
    private func restartSettingsTelemetrySubscription(for settings: ShadowClientAppSettings) {
        settingsTelemetryCancellable?.cancel()
        settingsTelemetryCancellable = baseDependencies.telemetryPublisher.sink { snapshot in
            Task {
                let model = await settingsTelemetryRuntime.ingest(
                    snapshot: snapshot,
                    settings: settings
                )

                await MainActor.run {
                    settingsDiagnosticsModel = model
                }
            }
        }
    }

    @MainActor
    private func stopSettingsTelemetrySubscription() {
        settingsTelemetryCancellable?.cancel()
        settingsTelemetryCancellable = nil
    }

    @MainActor
    private func syncConnectionStateFromRuntime() async {
        connectionState = await baseDependencies.connectionRuntime.currentState()
        if connectionHost.isEmpty, let host = connectionState.host, !host.isEmpty {
            connectionHost = host
        }
    }

    @MainActor
    private func startHostDiscovery() {
        guard autoFindHosts else {
            hostDiscoveryRuntime.stop()
            return
        }
        hostDiscoveryRuntime.start()
    }

    @MainActor
    private func refreshRemoteDesktopCatalog() {
        var candidates: [String] = autoFindHosts ? hostDiscoveryRuntime.hosts.map(\.host) : []
        if !normalizedConnectionHost.isEmpty {
            candidates.append(normalizedConnectionHost)
        }

        remoteDesktopRuntime.refreshHosts(
            candidates: candidates,
            preferredHost: normalizedConnectionHost.isEmpty ? nil : normalizedConnectionHost
        )
    }

    @MainActor
    private func stopHostDiscovery() {
        hostDiscoveryRuntime.stop()
    }

    @MainActor
    private func connectToHost(
        autoLaunchAfterConnect: Bool = false,
        preferredHostID: String? = nil
    ) {
        let host = normalizedConnectionHost
        guard !host.isEmpty else {
            return
        }

        refreshRemoteDesktopCatalog()

        Task {
            let state = await baseDependencies.connectionRuntime.connect(to: host)
            await MainActor.run {
                connectionState = state
                if let connectedHost = state.host, !connectedHost.isEmpty {
                    connectionHost = connectedHost
                    refreshRemoteDesktopCatalog()
                }
            }

            if autoLaunchAfterConnect, state.isConnected {
                await MainActor.run {
                    remoteDesktopRuntime.openSessionFlow(
                        host: state.host ?? host,
                        appTitle: "Remote Desktop"
                    )
                }
                await autoLaunchPreferredRemoteApp(preferredHostID: preferredHostID)
            }
        }
    }

    @MainActor
    private func connectToDiscoveredHost(_ discoveredHost: ShadowClientDiscoveredHost) {
        connectionHost = discoveredHost.host
        connectToHost()
    }

    @MainActor
    private func autoLaunchPreferredRemoteApp(preferredHostID: String?) async {
        if let preferredHostID {
            remoteDesktopRuntime.selectHost(preferredHostID)
        }

        remoteDesktopRuntime.refreshSelectedHostApps()

        for _ in 0..<25 {
            if case .loaded = remoteDesktopRuntime.appState {
                if let preferred = preferredLaunchApp(from: remoteDesktopRuntime.apps) {
                    launchRemoteApp(preferred)
                }
                return
            }

            if case .failed = remoteDesktopRuntime.appState {
                await launchDesktopFallbackIfNeeded()
                return
            }

            try? await Task.sleep(for: .milliseconds(200))
        }

        if let preferred = preferredLaunchApp(from: remoteDesktopRuntime.apps) {
            launchRemoteApp(preferred)
            return
        }

        await launchDesktopFallbackIfNeeded()
    }

    private func preferredLaunchApp(from apps: [ShadowClientRemoteAppDescriptor]) -> ShadowClientRemoteAppDescriptor? {
        if let desktop = apps.first(where: { $0.title.localizedCaseInsensitiveContains("desktop") }) {
            return desktop
        }
        return apps.first
    }

    @MainActor
    private func launchRemoteApp(_ app: ShadowClientRemoteAppDescriptor) {
        let settings = currentSettings.launchSettings(hostApp: app)

        remoteDesktopRuntime.launchSelectedApp(
            appID: app.id,
            appTitle: app.title,
            settings: settings
        )
    }

    @MainActor
    private func launchDesktopFallbackIfNeeded() async {
        guard let selectedHost = remoteDesktopRuntime.selectedHost else {
            return
        }
        guard selectedHost.pairStatus == .paired else {
            return
        }
        guard remoteDesktopRuntime.launchState != .launching else {
            return
        }

        let settings = currentSettings.launchSettings(hostApp: nil)

        remoteDesktopRuntime.launchSelectedApp(
            appID: 881_448_767,
            appTitle: "Desktop",
            settings: settings
        )

        for _ in 0..<15 {
            if case .launched = remoteDesktopRuntime.launchState {
                return
            }
            if case .failed = remoteDesktopRuntime.launchState {
                break
            }
            try? await Task.sleep(for: .milliseconds(200))
        }

        if case .failed = remoteDesktopRuntime.launchState {
            remoteDesktopRuntime.launchSelectedApp(
                appID: 1,
                appTitle: "Desktop",
                settings: settings
            )
        }
    }

    @MainActor
    private func disconnectFromHost() {
        Task {
            let state = await baseDependencies.connectionRuntime.disconnect()
            await MainActor.run {
                connectionState = state
                settingsDiagnosticsModel = nil
                refreshRemoteDesktopCatalog()
            }
        }
    }
}
