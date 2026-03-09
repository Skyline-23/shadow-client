import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

public struct ShadowClientAppShellView: View {
enum AppTab: Hashable {
        case home
        case settings
    }

let platformName: String
let baseDependencies: ShadowClientFeatureHomeDependencies
let settingsTelemetryRuntime: SettingsDiagnosticsTelemetryRuntime

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State var selectedTab: AppTab = .home
    @AppStorage(ShadowClientAppSettings.StorageKeys.lowLatencyMode) var lowLatencyMode = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.preferHDR) var preferHDR = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.showDiagnosticsHUD) var showDiagnosticsHUD = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.connectionHost) var connectionHost = ""
    @AppStorage(ShadowClientAppSettings.StorageKeys.resolution) var resolutionRawValue =
        ShadowClientAppSettingsDefaults.defaultResolution.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.frameRate) var frameRateRawValue =
        ShadowClientAppSettingsDefaults.defaultFrameRate.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.bitrateKbps) var bitrateKbps = ShadowClientAppSettingsDefaults.defaultBitrateKbps
    @AppStorage(ShadowClientAppSettings.StorageKeys.autoBitrate) var autoBitrate = ShadowClientAppSettingsDefaults.defaultAutoBitrate
    @AppStorage(ShadowClientAppSettings.StorageKeys.displayMode) var displayModeRawValue = ShadowClientDisplayMode.borderlessFullscreen.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.audioConfiguration) var audioConfigurationRawValue = ShadowClientAudioConfiguration.surround71.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.videoCodec) var videoCodecRawValue = ShadowClientVideoCodecPreference.auto.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.videoDecoder) var videoDecoderRawValue = ShadowClientVideoDecoderPreference.forceHardware.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.enableVSync) var enableVSync = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.enableFramePacing) var enableFramePacing = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.enableYUV444) var enableYUV444 = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.unlockBitrateLimit) var unlockBitrateLimit = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.optimizeMouseForDesktop) var optimizeMouseForDesktop = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.captureSystemKeyboardShortcuts) var captureSystemKeyboardShortcuts = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.keyboardShortcutCaptureMode) var keyboardShortcutCaptureModeRawValue = ShadowClientKeyboardShortcutCaptureMode.fullscreenOnly.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.useTouchscreenTrackpad) var useTouchscreenTrackpad = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.swapMouseButtons) var swapMouseButtons = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.reverseMouseScrollDirection) var reverseMouseScrollDirection = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.swapABXYButtons) var swapABXYButtons = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.forceGamepadOneAlwaysConnected) var forceGamepadOneAlwaysConnected = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.enableGamepadMouseMode) var enableGamepadMouseMode = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.processGamepadInputInBackground) var processGamepadInputInBackground = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.optimizeGameSettingsForStreaming) var optimizeGameSettingsForStreaming = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.quitAppOnHostAfterStream) var quitAppOnHostAfterStream = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.muteHostSpeakersWhileStreaming) var muteHostSpeakersWhileStreaming = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.muteAudioWhenInactiveWindow) var muteAudioWhenInactiveWindow = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.autoFindHosts) var autoFindHosts = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.language) var languageRawValue = ShadowClientLanguagePreference.automatic.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.guiDisplayMode) var guiDisplayModeRawValue = ShadowClientGUIDisplayMode.windowed.rawValue
    @ObservedObject var hostDiscoveryRuntime: ShadowClientHostDiscoveryRuntime
    @ObservedObject var remoteDesktopRuntime: ShadowClientRemoteDesktopRuntime
    @ObservedObject var sessionSurfaceContext: ShadowClientRealtimeSessionSurfaceContext
    @State var connectionState: ShadowClientConnectionState = .disconnected
    @State var settingsTelemetryTask: Task<Void, Never>?
    @State var settingsDiagnosticsModel: SettingsDiagnosticsHUDModel?
    @State var sessionDiagnosticsHistory = ShadowClientSessionDiagnosticsHistory(
        maxSamples: ShadowClientUIRuntimeDefaults.diagnosticsHUDSampleHistoryLimit
    )
    @State var roundTripHistoryRateLimiter = ShadowClientUptimeRateLimiter(
        minimumIntervalSeconds: 0.05
    )
    @State var launchFailureAlertMessage = ""
    @State var isLaunchFailureAlertPresented = false
    @State var gamepadInputRuntime = ShadowClientGamepadInputPassthroughRuntime()
    @State var sessionVisiblePointerRegions: [CGRect] = []
    @State var launchViewportMetrics = ShadowClientLaunchViewportMetrics(
        logicalSize: .zero,
        safeAreaInsets: .init()
    )
#if os(macOS)
    @State var activeSessionProcessActivity: NSObjectProtocol?
#endif

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
            rootContentView
        }
        .background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ShadowClientLaunchViewportPreferenceKey.self,
                    value: ShadowClientLaunchViewportMetrics(
                        logicalSize: geometry.size,
                        safeAreaInsets: geometry.safeAreaInsets
                    )
                )
            }
        )
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
        .onChange(of: remoteDesktopRuntime.activeSession != nil, initial: true) { _, isActive in
            if !isActive {
                roundTripHistoryRateLimiter.reset()
                sessionDiagnosticsHistory = .init(
                    maxSamples: ShadowClientUIRuntimeDefaults.diagnosticsHUDSampleHistoryLimit
                )
            }
            gamepadInputRuntime.setSessionActive(isActive)
            updateActiveSessionProcessActivity(isActive: isActive)
            ShadowClientRemoteSessionOrientationCoordinator.updateSessionState(isActive: isActive)
        }
        .onChange(of: gamepadInputConfiguration, initial: true) { _, configuration in
            gamepadInputRuntime.updateConfiguration(configuration)
        }
        .task(id: remoteDesktopRuntime.activeSession != nil) {
            guard remoteDesktopRuntime.activeSession != nil else {
                return
            }
            for await roundTripMs in sessionSurfaceContext.controlRoundTripAsyncStream() {
                guard remoteDesktopRuntime.activeSession != nil else {
                    break
                }
                if roundTripHistoryRateLimiter.shouldEmit(
                    nowUptime: ProcessInfo.processInfo.systemUptime
                ) {
                    sessionDiagnosticsHistory.appendControlRoundTripMs(roundTripMs)
                }
            }
        }
        .task(id: remoteDesktopRuntime.activeSession != nil) {
            guard remoteDesktopRuntime.activeSession != nil else {
                return
            }
            for await feedbackEvent in sessionSurfaceContext.controllerFeedbackAsyncStream() {
                guard remoteDesktopRuntime.activeSession != nil else {
                    break
                }
                gamepadInputRuntime.applyControllerFeedback(feedbackEvent)
            }
        }
        .onAppear {
            ShadowClientRemoteSessionOrientationCoordinator.updateSessionState(
                isActive: remoteDesktopRuntime.activeSession != nil
            )
            gamepadInputRuntime.start { event in
                remoteDesktopRuntime.sendInput(event)
            }
            gamepadInputRuntime.updateConfiguration(gamepadInputConfiguration)
            gamepadInputRuntime.setSessionActive(remoteDesktopRuntime.activeSession != nil)
        }
        .onDisappear {
            ShadowClientRemoteSessionOrientationCoordinator.updateSessionState(isActive: false)
            gamepadInputRuntime.stop()
            endActiveSessionProcessActivity()
            stopSettingsTelemetrySubscription()
            stopHostDiscovery()
        }
        .alert("Remote Session Launch Failed", isPresented: $isLaunchFailureAlertPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(launchFailureAlertMessage)
        }
        .onPreferenceChange(ShadowClientLaunchViewportPreferenceKey.self) { metrics in
            launchViewportMetrics = metrics
        }
        .animation(.easeInOut(duration: 0.2), value: remoteDesktopRuntime.activeSession != nil)
        .shadowClientRemoteSessionAutoFullscreen(
            isSessionActive: remoteDesktopRuntime.activeSession != nil
        )
        .shadowClientMobileSessionLifecycle(remoteDesktopRuntime: remoteDesktopRuntime)
    }

var rootContentView: AnyView {
        if remoteDesktopRuntime.activeSession == nil {
            return AnyView(mainTabView)
        }

        return AnyView(
            remoteSessionFlowView
                .transition(.opacity)
                .accessibilityIdentifier("shadow.root.remote-session")
        )
    }

var mainTabView: some View {
        TabView(selection: $selectedTab) {
            homeTab
            settingsTab
        }
        .accessibilityIdentifier("shadow.root.tabview")
    }

var currentSettings: ShadowClientAppSettings {
        ShadowClientAppSettings(
            lowLatencyMode: lowLatencyMode,
            preferHDR: preferHDR,
            showDiagnosticsHUD: showDiagnosticsHUD,
            resolution: selectedResolution,
            frameRate: selectedFrameRate,
            bitrateKbps: bitrateKbps,
            autoBitrate: autoBitrate,
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

var gamepadInputConfiguration: ShadowClientGamepadInputPassthroughRuntime.Configuration {
        .init(
            swapABXYButtons: swapABXYButtons,
            forceGamepadOneAlwaysConnected: forceGamepadOneAlwaysConnected,
            processInputInBackground: processGamepadInputInBackground
        )
    }

var selectedResolution: ShadowClientStreamingResolutionPreset {
        get {
            ShadowClientStreamingResolutionPreset(rawValue: resolutionRawValue) ??
                ShadowClientAppSettingsDefaults.defaultResolution
        }
        nonmutating set { resolutionRawValue = newValue.rawValue }
    }

var selectedFrameRate: ShadowClientStreamingFrameRatePreset {
        get {
            ShadowClientStreamingFrameRatePreset(rawValue: frameRateRawValue) ??
                ShadowClientAppSettingsDefaults.defaultFrameRate
        }
        nonmutating set { frameRateRawValue = newValue.rawValue }
    }

var selectedDisplayMode: ShadowClientDisplayMode {
        get { ShadowClientDisplayMode(rawValue: displayModeRawValue) ?? .borderlessFullscreen }
        nonmutating set { displayModeRawValue = newValue.rawValue }
    }

var selectedAudioConfiguration: ShadowClientAudioConfiguration {
        get { ShadowClientAudioConfiguration(rawValue: audioConfigurationRawValue) ?? .surround71 }
        nonmutating set { audioConfigurationRawValue = newValue.rawValue }
    }

var selectedVideoCodec: ShadowClientVideoCodecPreference {
        get { ShadowClientVideoCodecPreference(rawValue: videoCodecRawValue) ?? .auto }
        nonmutating set { videoCodecRawValue = newValue.rawValue }
    }

var selectedVideoDecoder: ShadowClientVideoDecoderPreference {
        get { ShadowClientVideoDecoderPreference(rawValue: videoDecoderRawValue) ?? .forceHardware }
        nonmutating set { videoDecoderRawValue = newValue.rawValue }
    }

var selectedKeyboardShortcutCaptureMode: ShadowClientKeyboardShortcutCaptureMode {
        get { ShadowClientKeyboardShortcutCaptureMode(rawValue: keyboardShortcutCaptureModeRawValue) ?? .fullscreenOnly }
        nonmutating set { keyboardShortcutCaptureModeRawValue = newValue.rawValue }
    }

var selectedLanguage: ShadowClientLanguagePreference {
        get { ShadowClientLanguagePreference(rawValue: languageRawValue) ?? .automatic }
        nonmutating set { languageRawValue = newValue.rawValue }
    }

var selectedGUIDisplayMode: ShadowClientGUIDisplayMode {
        get { ShadowClientGUIDisplayMode(rawValue: guiDisplayModeRawValue) ?? .windowed }
        nonmutating set { guiDisplayModeRawValue = newValue.rawValue }
    }

var activeSessionEndpoint: String {
        remoteDesktopRuntime.activeSession?.sessionURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

var sessionPresentationModel: ShadowClientRemoteSessionPresentationModel {
        ShadowClientRemoteSessionPresentationMapper.make(
            activeSessionEndpoint: activeSessionEndpoint,
            launchState: remoteDesktopRuntime.launchState,
            renderState: sessionSurfaceContext.renderState
        )
    }

var normalizedConnectionHost: String {
        connectionHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

var canConnect: Bool {
        guard !normalizedConnectionHost.isEmpty else {
            return false
        }

        return canInitiateSessionConnection
    }

var canInitiateSessionConnection: Bool {
        switch connectionState {
        case .connecting, .disconnecting:
            return false
        case .connected, .disconnected, .failed:
            return true
        }
    }

var canDisconnect: Bool {
        switch connectionState {
        case .connected, .connecting, .failed:
            return true
        case .disconnected, .disconnecting:
            return false
        }
    }

var connectionStatusText: String {
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

var connectionStatusColor: Color {
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

var connectionStatusSymbol: String {
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
func restartSettingsTelemetrySubscription(for settings: ShadowClientAppSettings) {
        settingsTelemetryTask?.cancel()
        settingsTelemetryTask = Task {
            let telemetryStream = await baseDependencies.makeTelemetryStream()
            for await snapshot in telemetryStream {
                if Task.isCancelled {
                    return
                }
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
func stopSettingsTelemetrySubscription() {
        settingsTelemetryTask?.cancel()
        settingsTelemetryTask = nil
    }

    @MainActor
func syncConnectionStateFromRuntime() async {
        connectionState = await baseDependencies.connectionRuntime.currentState()
        if connectionHost.isEmpty, let host = connectionState.host, !host.isEmpty {
            connectionHost = host
        }
    }

    @MainActor
func startHostDiscovery() {
        guard autoFindHosts else {
            hostDiscoveryRuntime.stop()
            return
        }
        hostDiscoveryRuntime.start()
    }

    @MainActor
func refreshRemoteDesktopCatalog() {
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
func stopHostDiscovery() {
        hostDiscoveryRuntime.stop()
    }

    @MainActor
func connectToHost(
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
func connectToDiscoveredHost(_ discoveredHost: ShadowClientDiscoveredHost) {
        connectionHost = discoveredHost.host
        connectToHost(autoLaunchAfterConnect: true)
    }

    @MainActor
func autoLaunchPreferredRemoteApp(preferredHostID: String?) async {
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

func preferredLaunchApp(from apps: [ShadowClientRemoteAppDescriptor]) -> ShadowClientRemoteAppDescriptor? {
        if let nonCollector = apps.first(where: { !$0.isAppCollectorGame }) {
            return nonCollector
        }
        return apps.first
    }

    @MainActor
func launchRemoteApp(_ app: ShadowClientRemoteAppDescriptor) {
        let settings = resolvedLaunchSettings(
            hostApp: app,
            networkSignal: launchBitrateNetworkSignal,
            localHDRDisplayAvailable: isLocalHDRDisplayAvailable
        )

        remoteDesktopRuntime.launchSelectedApp(
            appID: app.id,
            appTitle: app.title,
            settings: settings
        )
    }

    @MainActor
func launchDesktopFallbackIfNeeded() async {
        guard let selectedHost = remoteDesktopRuntime.selectedHost else {
            return
        }
        guard selectedHost.pairStatus == .paired else {
            return
        }
        guard remoteDesktopRuntime.launchState != .launching else {
            return
        }

        let settings = resolvedLaunchSettings(
            hostApp: nil,
            networkSignal: launchBitrateNetworkSignal,
            localHDRDisplayAvailable: isLocalHDRDisplayAvailable
        )
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
    private func resolvedLaunchSettings(
        hostApp: ShadowClientRemoteAppDescriptor?,
        networkSignal: StreamingNetworkSignal?,
        localHDRDisplayAvailable: Bool
    ) -> ShadowClientGameStreamLaunchSettings {
        let base = currentSettings.launchSettings(
            hostApp: hostApp,
            networkSignal: networkSignal,
            localHDRDisplayAvailable: localHDRDisplayAvailable
        )
        guard selectedResolution == .retinaAuto else {
            return base
        }

        let pixelSize = ShadowClientAutoResolutionPolicy.resolvePixelSize(
            logicalSize: launchViewportMetrics.logicalSize,
            safeAreaInsets: launchViewportMetrics.safeAreaInsets
        )
        return .init(
            width: Int(pixelSize.width),
            height: Int(pixelSize.height),
            fps: base.fps,
            bitrateKbps: base.bitrateKbps,
            preferredCodec: base.preferredCodec,
            enableHDR: base.enableHDR,
            enableSurroundAudio: base.enableSurroundAudio,
            lowLatencyMode: base.lowLatencyMode,
            enableVSync: base.enableVSync,
            enableFramePacing: base.enableFramePacing,
            enableYUV444: base.enableYUV444,
            unlockBitrateLimit: base.unlockBitrateLimit,
            forceHardwareDecoding: base.forceHardwareDecoding,
            optimizeGameSettingsForStreaming: base.optimizeGameSettingsForStreaming,
            quitAppOnHostAfterStreamEnds: base.quitAppOnHostAfterStreamEnds,
            playAudioOnHost: base.playAudioOnHost
        )
    }

    @MainActor
func disconnectFromHost() {
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

final class ShadowClientUptimeRateLimiter {
let minimumIntervalSeconds: TimeInterval
var lastEmissionUptime: TimeInterval = 0

    init(minimumIntervalSeconds: TimeInterval) {
        self.minimumIntervalSeconds = max(0, minimumIntervalSeconds)
    }

    func shouldEmit(nowUptime: TimeInterval) -> Bool {
        if lastEmissionUptime == 0 ||
            nowUptime - lastEmissionUptime >= minimumIntervalSeconds
        {
            lastEmissionUptime = nowUptime
            return true
        }
        return false
    }

    func reset() {
        lastEmissionUptime = 0
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

struct ShadowClientDiagnosticsSparkline: View {
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

func sparklinePath(for size: CGSize) -> Path {
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
