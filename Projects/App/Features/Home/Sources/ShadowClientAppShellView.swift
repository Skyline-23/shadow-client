import ShadowClientStreaming
import ShadowClientUI
import OSLog
import SwiftUI
import ShadowUIFoundation
import ShadowClientFeatureConnection
import ShadowClientFeatureSession
#if os(iOS) || os(tvOS)
@preconcurrency import AVFoundation
#endif

public struct ShadowClientAppShellView: View {
    static let catalogLogger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "HostCatalog"
    )

enum AppTab: Hashable {
        case home
        case settings
    }

let platformName: String
let baseDependencies: ShadowClientFeatureHomeDependencies
let settingsTelemetryRuntime: SettingsDiagnosticsTelemetryRuntime

    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.accessibilityReduceMotion) var accessibilityReduceMotion
    @State var selectedTab: AppTab = .home
    @AppStorage(ShadowClientAppSettings.StorageKeys.lowLatencyMode) var lowLatencyMode = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.preferHDR) var preferHDR = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.showDiagnosticsHUD) var showDiagnosticsHUD = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.connectionHost) var connectionHost = ""
    @AppStorage(ShadowClientAppSettings.StorageKeys.hiddenRemoteHostCandidates) var hiddenRemoteHostCandidatesRaw = ""
    @AppStorage(ShadowClientAppSettings.StorageKeys.resolution) var resolutionRawValue =
        ShadowClientAppSettingsDefaults.defaultResolution.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.frameRate) var frameRateRawValue =
        ShadowClientAppSettingsDefaults.defaultFrameRate.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.bitrateKbps) var bitrateKbps = ShadowClientAppSettingsDefaults.defaultBitrateKbps
    @AppStorage(ShadowClientAppSettings.StorageKeys.autoBitrate) var autoBitrate = ShadowClientAppSettingsDefaults.defaultAutoBitrate
    @AppStorage(ShadowClientAppSettings.StorageKeys.displayMode) var displayModeRawValue = ShadowClientDisplayMode.borderlessFullscreen.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.preferVirtualDisplay) var preferVirtualDisplay = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.audioConfiguration) var audioConfigurationRawValue = ShadowClientAudioConfiguration.surround71.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.videoCodec) var videoCodecRawValue = ShadowClientVideoCodecPreference.auto.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.videoDecoder) var videoDecoderRawValue = ShadowClientVideoDecoderPreference.automatic.rawValue
    @AppStorage(ShadowClientAppSettings.StorageKeys.enableVSync) var enableVSync = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.enableFramePacing) var enableFramePacing = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.enableYUV444) var enableYUV444 = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.unlockBitrateLimit) var unlockBitrateLimit = false
    @AppStorage(ShadowClientAppSettings.StorageKeys.prioritizeStreamingTraffic) var prioritizeStreamingTraffic = false
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
    @StateObject var hostCustomizationStore: ShadowClientHostCustomizationStore
    @State var connectionState: ShadowClientConnectionState = .disconnected
    @State var hostAddressDrafts: [String: String] = [:]
    @State var apolloDisplayModeDrafts: [String: String] = [:]
    @State var apolloAlwaysUseVirtualDisplayDrafts: [String: Bool] = [:]
    @State var apolloPermissionDrafts: [String: UInt32] = [:]
    @State var remoteDesktopHostFrames: [String: CGRect] = [:]
    @State var hostSpotlightState = ShadowClientHostSpotlightState()
    @State var manualHostEntryState = ShadowClientManualHostEntryState()
    @FocusState var manualHostFocusedField: ShadowClientManualHostAddressField.FocusField?
    @State var lastRemoteDesktopCatalogSignature = ""
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
    @State var isRemoteSessionKeyboardPresented = false
    @State var remoteSessionKeyboardText = ""
    @FocusState var isRemoteSessionKeyboardFocused: Bool
    @State var activeSessionReconfigurationTask: Task<Void, Never>?
    @State var lastActiveSessionReconfigurationSettings: ShadowClientGameStreamLaunchSettings?
    @State var launchViewportMetrics = ShadowClientLaunchViewportMetrics(
        logicalSize: .zero,
        safeAreaInsets: .init()
    )
    @State var displayMetrics = ShadowClientDisplayMetricsState.default
#if os(macOS)
    @State var activeSessionProcessActivity: NSObjectProtocol?
#endif

    public init(platformName: String, dependencies: ShadowClientFeatureHomeDependencies) {
        self.platformName = platformName
        self.baseDependencies = dependencies
        _hostDiscoveryRuntime = ObservedObject(wrappedValue: dependencies.hostDiscoveryRuntime)
        _remoteDesktopRuntime = ObservedObject(wrappedValue: dependencies.remoteDesktopRuntime)
        _sessionSurfaceContext = ObservedObject(wrappedValue: dependencies.remoteDesktopRuntime.sessionSurfaceContext)
        _hostCustomizationStore = StateObject(wrappedValue: ShadowClientHostCustomizationStore())
        self.settingsTelemetryRuntime = SettingsDiagnosticsTelemetryRuntime(
            settingsMapper: dependencies.settingsMapper,
            hostCapabilities: dependencies.hostCapabilities
        )
    }

    public var body: some View {
        ZStack {
            backgroundGradient
            rootContentView

            if let overlay = appBlockingOverlayModel {
                ZStack {
                    Color.black
                        .opacity(0.38)
                        .ignoresSafeArea()

                    ShadowUIRemoteSessionOverlayBadge(
                        title: overlay.title,
                        symbol: overlay.symbol,
                        textColor: Color.white.opacity(0.92),
                        backgroundOpacity: 0.56,
                        strokeOpacity: 0.26,
                        width: horizontalSizeClass == .compact ? 260 : 320,
                        animatesSymbol: false,
                        showsActivityIndicator: true
                    )
                    .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .accessibilityIdentifier("shadow.app.blocking-overlay")
            }
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
        .background(
            ShadowClientDisplayMetricsObserver { metrics in
                displayMetrics = metrics
            }
        )
        .tint(accentColor)
        .preferredColorScheme(.dark)
        .task {
            await syncConnectionStateFromRuntime()
            startHostDiscovery()
            refreshRemoteDesktopCatalog(force: true)
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
                isRemoteSessionKeyboardPresented = false
                isRemoteSessionKeyboardFocused = false
                remoteSessionKeyboardText = ""
                activeSessionReconfigurationTask?.cancel()
                activeSessionReconfigurationTask = nil
                lastActiveSessionReconfigurationSettings = nil
            } else {
                lastActiveSessionReconfigurationSettings = activeSessionLaunchSettings()
                Task { @MainActor in
                    guard remoteDesktopRuntime.activeSession != nil else {
                        return
                    }
                    lastActiveSessionReconfigurationSettings = await activeSessionNegotiatedLaunchSettings()
                }
            }
            gamepadInputRuntime.setSessionActive(isActive)
            updateActiveSessionProcessActivity(isActive: isActive)
            ShadowClientRemoteSessionOrientationCoordinator.updateSessionState(isActive: isActive)
        }
        .onChange(of: launchViewportMetrics, initial: false) { _, _ in
            scheduleActiveSessionLaunchReconfigurationIfNeeded()
        }
        .onChange(of: displayMetrics, initial: false) { _, _ in
            scheduleActiveSessionLaunchReconfigurationIfNeeded()
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
        #if os(iOS) || os(tvOS)
        .task(id: remoteDesktopRuntime.activeSession != nil) {
            guard remoteDesktopRuntime.activeSession != nil else {
                return
            }
            for await _ in NotificationCenter.default.notifications(
                named: AVAudioSession.routeChangeNotification
            ) {
                guard remoteDesktopRuntime.activeSession != nil else {
                    break
                }
                await scheduleActiveSessionAudioReconfigurationIfNeeded()
            }
        }
        .task(id: remoteDesktopRuntime.activeSession != nil) {
            guard remoteDesktopRuntime.activeSession != nil else {
                return
            }
            if #available(iOS 17.2, tvOS 17.2, *) {
                for await _ in NotificationCenter.default.notifications(
                    named: AVAudioSession.renderingModeChangeNotification
                ) {
                    guard remoteDesktopRuntime.activeSession != nil else {
                        break
                    }
                    await scheduleActiveSessionAudioReconfigurationIfNeeded()
                }
            }
        }
        .task(id: remoteDesktopRuntime.activeSession != nil) {
            guard remoteDesktopRuntime.activeSession != nil else {
                return
            }
            if #available(iOS 17.2, tvOS 17.2, *) {
                for await _ in NotificationCenter.default.notifications(
                    named: AVAudioSession.renderingCapabilitiesChangeNotification
                ) {
                    guard remoteDesktopRuntime.activeSession != nil else {
                        break
                    }
                    await scheduleActiveSessionAudioReconfigurationIfNeeded()
                }
            }
        }
        .task(id: remoteDesktopRuntime.activeSession != nil) {
            guard remoteDesktopRuntime.activeSession != nil else {
                return
            }
            for await _ in NotificationCenter.default.notifications(
                named: AVAudioSession.spatialPlaybackCapabilitiesChangedNotification
            ) {
                guard remoteDesktopRuntime.activeSession != nil else {
                    break
                }
                await scheduleActiveSessionAudioReconfigurationIfNeeded()
            }
        }
        #endif
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
            activeSessionReconfigurationTask?.cancel()
            activeSessionReconfigurationTask = nil
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
}
