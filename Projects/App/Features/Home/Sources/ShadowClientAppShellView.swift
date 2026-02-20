import Combine
import ShadowClientUI
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
    @AppStorage(ShadowClientAppSettings.StorageKeys.resolution) private var resolutionRawValue =
        ShadowClientAppSettingsDefaults.defaultResolution.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.frameRate) private var frameRateRawValue =
        ShadowClientAppSettingsDefaults.defaultFrameRate.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.bitrateKbps) private var bitrateKbps = ShadowClientAppSettingsDefaults.defaultBitrateKbps
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
    @ObservedObject private var sessionSurfaceContext: ShadowClientRealtimeSessionSurfaceContext
    @State private var connectionState: ShadowClientConnectionState = .disconnected
    @State private var settingsTelemetryCancellable: AnyCancellable?
    @State private var settingsDiagnosticsModel: SettingsDiagnosticsHUDModel?
    @State private var sessionDiagnosticsHistory = ShadowClientSessionDiagnosticsHistory(
        maxSamples: ShadowClientUIRuntimeDefaults.diagnosticsHUDSampleHistoryLimit
    )
    @State private var sessionControlsVisible = true
    @State private var launchFailureAlertMessage = ""
    @State private var isLaunchFailureAlertPresented = false

    public init(platformName: String, dependencies: ShadowClientFeatureHomeDependencies) {
        self.platformName = platformName
        self.baseDependencies = dependencies
        _hostDiscoveryRuntime = ObservedObject(wrappedValue: dependencies.hostDiscoveryRuntime)
        _remoteDesktopRuntime = ObservedObject(wrappedValue: dependencies.remoteDesktopRuntime)
        _sessionSurfaceContext = ObservedObject(wrappedValue: dependencies.remoteDesktopRuntime.sessionSurfaceContext)
        self.settingsTelemetryRuntime = SettingsDiagnosticsTelemetryRuntime(
            settingsMapper: dependencies.settingsMapper,
            hostCapabilities: dependencies.hostCapabilities
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
                .accessibilityIdentifier("shadow.root.tabview")
            } else {
                remoteSessionFlowView
                    .transition(.opacity)
                    .accessibilityIdentifier("shadow.root.remote-session")
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
            if !unlocked && bitrateKbps > ShadowClientAppSettingsDefaults.maximumBitrateWhenLocked {
                bitrateKbps = ShadowClientAppSettingsDefaults.maximumBitrateWhenLocked
            }
        }
        .onChange(of: remoteDesktopRuntime.launchState, initial: false) { _, newState in
            guard case let .failed(message) = newState else {
                return
            }

            let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return
            }
            launchFailureAlertMessage = trimmed
            isLaunchFailureAlertPresented = true
        }
        .onChange(of: remoteDesktopRuntime.activeSession != nil, initial: false) { _, isActive in
            guard !isActive else {
                return
            }
            sessionDiagnosticsHistory = .init(
                maxSamples: ShadowClientUIRuntimeDefaults.diagnosticsHUDSampleHistoryLimit
            )
        }
        .onChange(of: sessionSurfaceContext.controlRoundTripMs, initial: false) { _, newRoundTripMs in
            guard remoteDesktopRuntime.activeSession != nil else {
                return
            }
            sessionDiagnosticsHistory.appendControlRoundTripMs(newRoundTripMs)
        }
        .onDisappear {
            stopSettingsTelemetrySubscription()
            stopHostDiscovery()
        }
        .alert("Remote Session Launch Failed", isPresented: $isLaunchFailureAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(launchFailureAlertMessage)
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
        get {
            ShadowClientStreamingResolutionPreset(rawValue: resolutionRawValue) ??
                ShadowClientAppSettingsDefaults.defaultResolution
        }
        nonmutating set { resolutionRawValue = newValue.rawValue }
    }

    private var selectedFrameRate: ShadowClientStreamingFrameRatePreset {
        get {
            ShadowClientStreamingFrameRatePreset(rawValue: frameRateRawValue) ??
                ShadowClientAppSettingsDefaults.defaultFrameRate
        }
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

    private var activeSessionEndpoint: String {
        remoteDesktopRuntime.activeSession?.sessionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private var sessionPresentationModel: ShadowClientRemoteSessionPresentationModel {
        ShadowClientRemoteSessionPresentationMapper.make(
            activeSessionEndpoint: activeSessionEndpoint,
            launchState: remoteDesktopRuntime.launchState,
            renderState: sessionSurfaceContext.renderState
        )
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
        .accessibilityIdentifier("shadow.tab.home")
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
                                    connectToHost(autoLaunchAfterConnect: true)
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
                            .accessibilityIdentifier("shadow.settings.connection.refresh-discovery")
                            .accessibilityLabel("Refresh Discovered Hosts")
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
                                connectToHost(autoLaunchAfterConnect: true)
                            }
                            .accessibilityIdentifier("shadow.settings.connection.connect")
                            .accessibilityLabel("Connect to Host")
                            .disabled(!canConnect)
                            .buttonStyle(.borderedProminent)

                            Button("Disconnect") {
                                disconnectFromHost()
                            }
                            .accessibilityIdentifier("shadow.settings.connection.disconnect")
                            .accessibilityLabel("Disconnect from Host")
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
                                    in: Double(ShadowClientStreamingLaunchBounds.minimumBitrateKbps)...maxBitrateKbps,
                                    step: Double(ShadowClientAppSettingsDefaults.bitrateStepKbps)
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
        .accessibilityIdentifier("shadow.tab.settings")
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
                .accessibilityIdentifier("shadow.home.hosts.refresh")
                .accessibilityLabel("Refresh Remote Desktop Hosts")
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
                .accessibilityIdentifier("shadow.home.hosts.start-pairing")
                .accessibilityLabel("Start Pairing")
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
                    .accessibilityIdentifier("shadow.home.hosts.pairing-state")
                    .accessibilityLabel("Host Pairing State")
                    .accessibilityValue(remoteDesktopRuntime.pairingState.label)
                Spacer(minLength: 0)
            }

            remoteDesktopAppListSection
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shadow.home.hosts.card")
        .accessibilityLabel("Remote Desktop Hosts")
        .accessibilityValue(remoteDesktopHostsAccessibilityValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelSurface(cornerRadius: 14))
    }

    private func remoteDesktopHostRow(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        let isSelected = remoteDesktopRuntime.selectedHostID == host.id
        let hostIdentifier = sanitizedIdentifier(host.id)

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
                        .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).use")
                        .accessibilityLabel("Use \(host.displayName)")
                        .accessibilityHint("Marks \(host.displayName) as the preferred host without opening a connection")
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)

                        Button("Connect") {
                            connectionHost = host.host
                            connectToHost(autoLaunchAfterConnect: true, preferredHostID: host.id)
                        }
                        .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).connect")
                        .accessibilityLabel("Connect to \(host.displayName)")
                        .accessibilityHint("Connects to the selected host and prepares a remote session")
                        .buttonStyle(.borderedProminent)
                        .disabled(!canInitiateSessionConnection || !host.isReachable)
                        .frame(maxWidth: .infinity)
                    }

                    if !isSelected {
                        Button("Select") {
                            remoteDesktopRuntime.selectHost(host.id)
                        }
                        .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).select")
                        .accessibilityLabel("Select \(host.displayName)")
                        .accessibilityHint("Highlights \(host.displayName) in the host list for quick actions")
                        .buttonStyle(.bordered)
                    }
                } else {
                    HStack(spacing: 8) {
                        Button("Use") {
                            connectionHost = host.host
                            remoteDesktopRuntime.selectHost(host.id)
                        }
                        .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).use")
                        .accessibilityLabel("Use \(host.displayName)")
                        .accessibilityHint("Marks \(host.displayName) as the preferred host without opening a connection")
                        .buttonStyle(.bordered)

                        Button("Connect") {
                            connectionHost = host.host
                            connectToHost(autoLaunchAfterConnect: true, preferredHostID: host.id)
                        }
                        .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).connect")
                        .accessibilityLabel("Connect to \(host.displayName)")
                        .accessibilityHint("Connects to the selected host and prepares a remote session")
                        .buttonStyle(.borderedProminent)
                        .disabled(!canInitiateSessionConnection || !host.isReachable)

                        Button(isSelected ? "Selected" : "Select") {
                            remoteDesktopRuntime.selectHost(host.id)
                        }
                        .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).select")
                        .accessibilityLabel("Select \(host.displayName)")
                        .accessibilityHint("Highlights \(host.displayName) in the host list for quick actions")
                        .buttonStyle(.bordered)
                        .disabled(isSelected)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).row")
        .accessibilityLabel(hostAccessibilityLabel(for: host, isSelected: isSelected))
        .accessibilityHint("Double tap to reveal connect and select actions for \(host.displayName)")
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
                        .accessibilityIdentifier("shadow.home.applist.refresh")
                        .accessibilityLabel("Refresh Host App Library")
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
                    .accessibilityIdentifier("shadow.home.applist.refresh")
                    .accessibilityLabel("Refresh Host App Library")
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
                    let appIdentifier = sanitizedIdentifier(String(app.id))
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
                        .accessibilityIdentifier("shadow.home.applist.launch.\(appIdentifier)")
                        .accessibilityLabel("Launch \(app.title)")
                        .accessibilityHint("Launches the selected remote app and enters remote session view")
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
        .accessibilityIdentifier("shadow.home.applist.section")
        .accessibilityLabel("Host App Library")
        .accessibilityValue(hostAppLibraryAccessibilityValue)
    }

    private func hostAccessibilityLabel(
        for host: ShadowClientRemoteHostDescriptor,
        isSelected: Bool
    ) -> String {
        let selectionDetail = isSelected ? " Currently selected." : ""
        return "\(host.displayName), \(host.statusLabel). Host: \(host.host).\(selectionDetail) \(host.detailLabel)"
    }

    private func sanitizedIdentifier(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = raw.lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return sanitized.isEmpty ? "unknown" : sanitized
    }

    private var remoteDesktopHostsAccessibilityValue: String {
        "\(remoteDesktopRuntime.hosts.count) host(s). Discovery \(remoteDesktopRuntime.hostState.label). Pairing \(remoteDesktopRuntime.pairingState.label)."
    }

    private var hostAppLibraryAccessibilityValue: String {
        "\(remoteDesktopRuntime.apps.count) app(s). Catalog \(remoteDesktopRuntime.appState.label). Launch state \(remoteDesktopRuntime.launchState.label)."
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
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("shadow.home.connection-status")
        .accessibilityLabel("Client Connection")
        .accessibilityValue(connectionStatusText)
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
        switch sessionPresentationModel.launchTone {
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
                Color.black

                ZStack {
                    ShadowClientRealtimeSessionSurfaceView(
                        context: sessionSurfaceContext
                    )
                    .accessibilityIdentifier("shadow.remote.session.surface")
                    .accessibilityLabel("Remote Session Surface")

                    if let overlay = sessionPresentationModel.overlay {
                        playbackOverlayLabel(
                            overlay.title,
                            symbol: overlay.symbol
                        )
                        .padding(.horizontal, 20)
                    }

#if os(macOS)
                    ShadowClientMacOSSessionInputCaptureView { event in
                        remoteDesktopRuntime.sendInput(event)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
#endif
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        sessionControlsVisible.toggle()
                    }
                }

                VStack(spacing: 0) {
                    if sessionControlsVisible {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Remote Session")
                                    .font(.system(.headline, design: .rounded).weight(.bold))
                                    .foregroundStyle(.white)
                                Text("\(activeSession.appTitle) · \(activeSession.host)")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.86))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    showDiagnosticsHUD.toggle()
                                }
                            } label: {
                                Label(
                                    showDiagnosticsHUD ? "HUD On" : "HUD Off",
                                    systemImage: showDiagnosticsHUD
                                        ? "waveform.path.ecg.rectangle.fill"
                                        : "waveform.path.ecg.rectangle"
                                )
                            }
                            .accessibilityIdentifier("shadow.home.session.hud-toggle")
                            .accessibilityLabel("Toggle Session HUD")
                            .accessibilityHint("Shows or hides realtime diagnostics overlay.")
                            .buttonStyle(.bordered)

                            Button("End Session") {
                                remoteDesktopRuntime.clearActiveSession()
                            }
                            .accessibilityIdentifier("shadow.home.session.end")
                            .accessibilityLabel("End Session")
                            .accessibilityHint("Disconnects the active session and returns to the host list.")
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 12)
                        .padding(.top, 12)
                        .safeAreaPadding(.top)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Spacer(minLength: 0)

                    if sessionControlsVisible {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(sessionPresentationModel.statusText)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.90))
                                .accessibilityIdentifier("shadow.remote.session.status")

                            HStack(spacing: 8) {
                                Label(remoteDesktopRuntime.launchState.label, systemImage: "play.circle.fill")
                                    .font(.footnote.weight(.semibold))
                                    .foregroundStyle(launchStateColor)

                                if let sessionURL = activeSession.sessionURL, !sessionURL.isEmpty {
                                    Spacer(minLength: 6)
                                    Text(sessionURL)
                                        .font(.footnote.monospaced())
                                        .foregroundStyle(Color.white.opacity(0.70))
                                        .lineLimit(1)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .safeAreaPadding(.bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                if let hudDisplayState = realtimeSessionHUDDisplayState {
                    VStack {
                        HStack {
                            Spacer()
                            switch hudDisplayState {
                            case let .telemetry(model):
                                realtimeSessionDiagnosticsHUD(model)
                            case let .waitingForTelemetry(controlRoundTripMs):
                                realtimeSessionBootstrapDiagnosticsHUD(controlRoundTripMs: controlRoundTripMs)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.top, sessionControlsVisible ? 72 : 12)
                    .padding(.trailing, 12)
                    .safeAreaPadding([.top, .trailing])
                    .allowsHitTesting(false)
                }
            }
            .onAppear {
                sessionControlsVisible = true
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

    private var realtimeSessionHUDDisplayState: ShadowClientRealtimeSessionHUDDisplayState? {
        ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
            showDiagnosticsHUD: showDiagnosticsHUD,
            diagnosticsModel: settingsDiagnosticsModel,
            controlRoundTripMs: sessionSurfaceContext.controlRoundTripMs
        )
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

    private func realtimeSessionHUDCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(10)
            .frame(width: isCompactLayout ? 220 : 280, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 12, x: 0, y: 6)
    }

    private func realtimeSessionDiagnosticsHUD(_ model: SettingsDiagnosticsHUDModel) -> some View {
        realtimeSessionHUDCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundStyle(toneColor(for: model.tone))
                    Text("Realtime HUD")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Spacer(minLength: 8)
                    Text(model.tone.rawValue.uppercased())
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(toneColor(for: model.tone))
                }

                HStack(spacing: 10) {
                    diagnosticsStatChip(label: "Buffer", value: "\(model.targetBufferMs) ms")
                    diagnosticsStatChip(
                        label: "Ping",
                        value: diagnosticsLatestValue(
                            samples: sessionDiagnosticsHistory.controlRoundTripMsSamples,
                            unit: "ms"
                        )
                    )
                    diagnosticsStatChip(label: "Jitter", value: "\(model.jitterMs) ms")
                    diagnosticsStatChip(label: "Drop", value: String(format: "%.1f%%", model.frameDropPercent))
                }

                diagnosticsSparklineRow(
                    title: "Ping Spike",
                    samples: sessionDiagnosticsHistory.controlRoundTripMsSamples,
                    color: .mint,
                    unit: "ms"
                )
                diagnosticsSparklineRow(
                    title: "Jitter Spike",
                    samples: sessionDiagnosticsHistory.jitterMsSamples,
                    color: .orange,
                    unit: "ms"
                )
                diagnosticsSparklineRow(
                    title: "Frame Drop",
                    samples: sessionDiagnosticsHistory.frameDropPercentSamples,
                    color: .red,
                    unit: "%"
                )
                diagnosticsSparklineRow(
                    title: "Packet Loss",
                    samples: sessionDiagnosticsHistory.packetLossPercentSamples,
                    color: .yellow,
                    unit: "%"
                )
            }
        }
    }

    private func realtimeSessionBootstrapDiagnosticsHUD(controlRoundTripMs: Int?) -> some View {
        realtimeSessionHUDCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundStyle(Color.white.opacity(0.82))
                    Text("Realtime HUD")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Spacer(minLength: 8)
                    Text("BOOTSTRAP")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                Text("Telemetry stream pending. Showing connection health baseline.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.74))

                HStack(spacing: 10) {
                    diagnosticsStatChip(
                        label: "Ping",
                        value: diagnosticsRoundTripValue(controlRoundTripMs)
                    )
                    diagnosticsStatChip(
                        label: "Trend",
                        value: diagnosticsLatestValue(
                            samples: sessionDiagnosticsHistory.controlRoundTripMsSamples,
                            unit: "ms"
                        )
                    )
                    diagnosticsStatChip(label: "Telemetry", value: "Waiting")
                }

                diagnosticsSparklineRow(
                    title: "Ping Spike",
                    samples: sessionDiagnosticsHistory.controlRoundTripMsSamples,
                    color: .mint,
                    unit: "ms"
                )
            }
        }
    }

    private func diagnosticsRoundTripValue(_ roundTripMs: Int?) -> String {
        guard let roundTripMs else {
            return "--"
        }
        return "\(max(roundTripMs, 0)) ms"
    }

    private func diagnosticsSparklineRow(
        title: String,
        samples: [Double],
        color: Color,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer(minLength: 6)
                Text(diagnosticsLatestValue(samples: samples, unit: unit))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color.opacity(0.9))
            }

            ShadowClientDiagnosticsSparkline(samples: samples, color: color)
                .frame(height: 20)
        }
    }

    private func diagnosticsLatestValue(samples: [Double], unit: String) -> String {
        guard let latest = samples.last else {
            return "--"
        }

        if unit == "ms" {
            return "\(Int(latest.rounded())) \(unit)"
        }
        return "\(String(format: "%.1f", latest))\(unit)"
    }

    private func diagnosticsStatChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.72))
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
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
            .disabled(!canInitiateSessionConnection)
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
        unlockBitrateLimit
            ? Double(ShadowClientAppSettingsDefaults.maximumBitrateWhenUnlocked)
            : Double(ShadowClientAppSettingsDefaults.maximumBitrateWhenLocked)
    }

    private var bitrateSliderBinding: Binding<Double> {
        Binding(
            get: { Double(bitrateKbps) },
            set: { newValue in
                let rounded = Int(newValue.rounded() / Double(ShadowClientAppSettingsDefaults.bitrateStepKbps)) * ShadowClientAppSettingsDefaults.bitrateStepKbps
                let clamped = min(
                    max(ShadowClientStreamingLaunchBounds.minimumBitrateKbps, rounded),
                    Int(maxBitrateKbps)
                )
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

        return canInitiateSessionConnection
    }

    private var canInitiateSessionConnection: Bool {
        switch connectionState {
        case .connecting, .disconnecting:
            return false
        case .connected, .disconnected, .failed:
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
                    if remoteDesktopRuntime.activeSession != nil {
                        sessionDiagnosticsHistory.append(model)
                    }
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

        let normalizedTargetHost = host.lowercased()
        let alreadyConnectedToTarget: Bool = {
            guard case let .connected(connectedHost) = connectionState else {
                return false
            }
            return connectedHost
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == normalizedTargetHost
        }()

        if alreadyConnectedToTarget {
            if autoLaunchAfterConnect {
                Task {
                    await autoLaunchPreferredRemoteApp(preferredHostID: preferredHostID)
                }
            }
            return
        }

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
                await autoLaunchPreferredRemoteApp(preferredHostID: preferredHostID)
            }
        }
    }

    @MainActor
    private func connectToDiscoveredHost(_ discoveredHost: ShadowClientDiscoveredHost) {
        connectionHost = discoveredHost.host
        connectToHost(autoLaunchAfterConnect: true)
    }

    @MainActor
    private func autoLaunchPreferredRemoteApp(preferredHostID: String?) async {
        if let preferredHostID {
            remoteDesktopRuntime.selectHost(preferredHostID)
        }

        remoteDesktopRuntime.refreshSelectedHostApps()

        for _ in 0..<ShadowClientUIRuntimeDefaults.appListPollingAttempts {
            if case .loaded = remoteDesktopRuntime.appState {
                if let preferred = preferredLaunchApp(from: remoteDesktopRuntime.apps) {
                    launchRemoteApp(preferred)
                    return
                }
                await launchDesktopFallbackIfNeeded()
                return
            }

            if case .failed = remoteDesktopRuntime.appState {
                await launchDesktopFallbackIfNeeded()
                return
            }

            try? await Task.sleep(for: ShadowClientUIRuntimeDefaults.pollingInterval)
        }

        if let preferred = preferredLaunchApp(from: remoteDesktopRuntime.apps) {
            launchRemoteApp(preferred)
            return
        }

        await launchDesktopFallbackIfNeeded()
    }

    private func preferredLaunchApp(from apps: [ShadowClientRemoteAppDescriptor]) -> ShadowClientRemoteAppDescriptor? {
        if let nonCollector = apps.first(where: { !$0.isAppCollectorGame }) {
            return nonCollector
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
        let fallbackApp = preferredLaunchApp(from: remoteDesktopRuntime.apps) ?? {
            guard selectedHost.currentGameID > 0 else {
                return nil
            }
            return ShadowClientRemoteAppDescriptor(
                id: selectedHost.currentGameID,
                title: ShadowClientRemoteAppLabels.currentSession(selectedHost.currentGameID),
                hdrSupported: false,
                isAppCollectorGame: false
            )
        }()
        guard let fallbackApp else {
            return
        }

        remoteDesktopRuntime.launchSelectedApp(
            appID: fallbackApp.id,
            appTitle: fallbackApp.title,
            settings: settings
        )

        for _ in 0..<ShadowClientUIRuntimeDefaults.launchStatePollingAttempts {
            if case .launched = remoteDesktopRuntime.launchState {
                return
            }
            if case .failed = remoteDesktopRuntime.launchState {
                break
            }
            try? await Task.sleep(for: ShadowClientUIRuntimeDefaults.pollingInterval)
        }
    }

    @MainActor
    private func disconnectFromHost() {
        Task {
            let state = await baseDependencies.connectionRuntime.disconnect()
            await MainActor.run {
                connectionState = state
                settingsDiagnosticsModel = nil
                sessionDiagnosticsHistory = .init(
                    maxSamples: ShadowClientUIRuntimeDefaults.diagnosticsHUDSampleHistoryLimit
                )
                refreshRemoteDesktopCatalog()
            }
        }
    }
}

struct ShadowClientSessionDiagnosticsHistory {
    let maxSamples: Int
    private(set) var controlRoundTripMsSamples: [Double] = []
    private(set) var jitterMsSamples: [Double] = []
    private(set) var frameDropPercentSamples: [Double] = []
    private(set) var packetLossPercentSamples: [Double] = []

    mutating func append(_ model: SettingsDiagnosticsHUDModel) {
        let sampleLimit = max(maxSamples, 1)
        let jitter = max(0, Double(model.jitterMs))
        jitterMsSamples.append(jitter)
        if jitterMsSamples.count > sampleLimit {
            jitterMsSamples.removeFirst(jitterMsSamples.count - sampleLimit)
        }

        if model.frameDropPercent.isFinite {
            frameDropPercentSamples.append(max(0, model.frameDropPercent))
            if frameDropPercentSamples.count > sampleLimit {
                frameDropPercentSamples.removeFirst(frameDropPercentSamples.count - sampleLimit)
            }
        }
        if model.packetLossPercent.isFinite {
            packetLossPercentSamples.append(max(0, model.packetLossPercent))
            if packetLossPercentSamples.count > sampleLimit {
                packetLossPercentSamples.removeFirst(packetLossPercentSamples.count - sampleLimit)
            }
        }
    }

    mutating func appendControlRoundTripMs(_ roundTripMs: Int?) {
        guard let roundTripMs else {
            return
        }

        let sampleLimit = max(maxSamples, 1)
        controlRoundTripMsSamples.append(max(0, Double(roundTripMs)))
        if controlRoundTripMsSamples.count > sampleLimit {
            controlRoundTripMsSamples.removeFirst(controlRoundTripMsSamples.count - sampleLimit)
        }
    }
}

private struct ShadowClientDiagnosticsSparkline: View {
    let samples: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let graphPath = sparklinePath(for: size)

            ZStack {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.black.opacity(0.24))

                if !graphPath.isEmpty {
                    graphPath
                        .stroke(color.opacity(0.92), lineWidth: 1.6)
                }
            }
        }
    }

    private func sparklinePath(for size: CGSize) -> Path {
        guard samples.count >= 2 else {
            return Path()
        }

        let maximum = samples.max() ?? 0
        let minimum = samples.min() ?? 0
        let range = max(maximum - minimum, 1)
        let stepX = size.width / CGFloat(max(samples.count - 1, 1))

        var path = Path()
        for (index, sample) in samples.enumerated() {
            let x = CGFloat(index) * stepX
            let normalized = (sample - minimum) / range
            let y = size.height - (CGFloat(normalized) * size.height)
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }
}
