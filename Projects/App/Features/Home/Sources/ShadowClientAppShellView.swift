import Combine
import SwiftUI

public struct ShadowClientAppShellView: View {
    private enum AppTab: Hashable {
        case home
        case settings
    }

    private let platformName: String
    private let baseDependencies: ShadowClientFeatureHomeDependencies
    private let settingsTelemetryRuntime: SettingsDiagnosticsTelemetryRuntime

    @State private var selectedTab: AppTab = .home
    @AppStorage(ShadowClientAppSettings.StorageKeys.lowLatencyMode) private var lowLatencyMode = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.preferHDR) private var preferHDR = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.preferSurroundAudio) private var preferSurroundAudio = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.showDiagnosticsHUD) private var showDiagnosticsHUD = true
    @State private var connectionHost = ""
    @State private var connectionState: ShadowClientConnectionState = .disconnected
    @State private var settingsTelemetryCancellable: AnyCancellable?
    @State private var settingsDiagnosticsModel: SettingsDiagnosticsHUDModel?

    public init(platformName: String, dependencies: ShadowClientFeatureHomeDependencies) {
        self.platformName = platformName
        self.baseDependencies = dependencies
        self.settingsTelemetryRuntime = SettingsDiagnosticsTelemetryRuntime(
            baseDependencies: dependencies
        )
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            homeTab
            settingsTab
        }
        .tint(.mint)
        .task {
            await syncConnectionStateFromRuntime()
        }
        .task(id: currentSettings.streamingIdentityKey) {
            restartSettingsTelemetrySubscription(for: currentSettings)
        }
        .onDisappear {
            stopSettingsTelemetrySubscription()
        }
    }

    private var currentSettings: ShadowClientAppSettings {
        ShadowClientAppSettings(
            lowLatencyMode: lowLatencyMode,
            preferHDR: preferHDR,
            preferSurroundAudio: preferSurroundAudio,
            showDiagnosticsHUD: showDiagnosticsHUD
        )
    }

    private var homeTab: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                ScrollView {
                    VStack(spacing: 28) {
                        ShadowClientFeatureHomeView(
                            platformName: platformName,
                            dependencies: baseDependencies.applying(settings: currentSettings),
                            showsDiagnosticsHUD: currentSettings.showDiagnosticsHUD
                        )
                        .id(currentSettings.streamingIdentityKey)
                        .frame(maxWidth: .infinity, alignment: .top)

                        ControllerFeedbackStatusPanel()
                            .frame(maxWidth: .infinity)
                    }
                    .padding(.top, 28)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Home")
        }
        .tabItem { Label("Home", systemImage: "house.fill") }
        .tag(AppTab.home)
    }

    private var settingsTab: some View {
        NavigationStack {
            Form {
                Section("Client Connection") {
                    TextField("Host (IP or hostname)", text: $connectionHost)
                    HStack {
                        Button("Connect") {
                            connectToHost()
                        }
                        .disabled(!canConnect)

                        Button("Disconnect") {
                            disconnectFromHost()
                        }
                        .disabled(!canDisconnect)
                    }

                    Text(connectionStatusText)
                        .font(.footnote)
                        .foregroundStyle(connectionStatusColor)
                }

                Section("Streaming Quality") {
                    Toggle(isOn: $lowLatencyMode) {
                        Label("Low-Latency Mode", systemImage: "speedometer")
                    }
                    Toggle(isOn: $preferHDR) {
                        Label("Prefer HDR", systemImage: "sparkles.tv")
                    }
                    Toggle(isOn: $preferSurroundAudio) {
                        Label("Prefer Surround Audio", systemImage: "hifispeaker.and.homepod.fill")
                    }
                }

                Section("Diagnostics") {
                    Toggle(isOn: $showDiagnosticsHUD) {
                        Label("Show Debug HUD", systemImage: "waveform.path.ecg.rectangle")
                    }
                }

                Section("Session Launch Plan") {
                    if let settingsDiagnosticsModel {
                        Text("Tone: \(settingsDiagnosticsModel.tone.rawValue.uppercased())")
                            .font(.footnote.monospacedDigit())
                        Text("Target Buffer: \(settingsDiagnosticsModel.targetBufferMs) ms")
                            .font(.footnote.monospacedDigit())
                        Text("Jitter: \(settingsDiagnosticsModel.jitterMs) ms | Packet Loss: \(String(format: "%.1f", settingsDiagnosticsModel.packetLossPercent))%")
                            .font(.footnote.monospacedDigit())
                        Text("Frame Drop: \(String(format: "%.1f", settingsDiagnosticsModel.frameDropPercent))% | AV Sync: \(settingsDiagnosticsModel.avSyncOffsetMs) ms")
                            .font(.footnote.monospacedDigit())
                        Text("Drop Origin: NET \(settingsDiagnosticsModel.networkDroppedFrames) | PACER \(settingsDiagnosticsModel.pacerDroppedFrames)")
                            .font(.footnote.monospacedDigit())
                        Text("Telemetry Timestamp: \(settingsDiagnosticsModel.timestampMs) ms")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if let sampleIntervalMs = settingsDiagnosticsModel.sampleIntervalMs {
                            Text("Sample Interval: \(sampleIntervalMs) ms")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Sample Interval: --")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        if settingsDiagnosticsModel.receivedOutOfOrderSample {
                            Text("Out-of-order telemetry sample ignored")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.orange)
                        }
                        Text("Session Video: \(settingsDiagnosticsModel.hdrVideoMode.rawValue.uppercased()) | Audio: \(settingsDiagnosticsModel.audioMode.rawValue.uppercased())")
                            .font(.footnote.monospacedDigit())
                        Text("Reconfig V:\(settingsDiagnosticsModel.shouldRenegotiateVideoPipeline ? "Y" : "N") A:\(settingsDiagnosticsModel.shouldRenegotiateAudioPipeline ? "Y" : "N") | QDrop: \(settingsDiagnosticsModel.shouldApplyQualityDropImmediately ? "Y" : "N")")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if settingsDiagnosticsModel.recoveryStableSamplesRemaining > 0 {
                            Text("Recovery Hold: \(settingsDiagnosticsModel.recoveryStableSamplesRemaining) stable sample(s) remaining")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.orange)
                        }
                    } else {
                        Label("Awaiting telemetry samples from active session.", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Controller") {
                    Label("USB-first DualSense feedback contract remains enabled.", systemImage: "gamecontroller.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(backgroundGradient)
            .navigationTitle("Settings")
        }
        .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        .tag(AppTab.settings)
    }

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.04, green: 0.11, blue: 0.16),
                Color(red: 0.08, green: 0.20, blue: 0.20),
                Color(red: 0.20, green: 0.14, blue: 0.08),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var normalizedConnectionHost: String {
        connectionHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canConnect: Bool {
        guard !normalizedConnectionHost.isEmpty else {
            return false
        }

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
    private func connectToHost() {
        let host = normalizedConnectionHost
        guard !host.isEmpty else {
            return
        }

        Task {
            let state = await baseDependencies.connectionRuntime.connect(to: host)
            await MainActor.run {
                connectionState = state
                if let connectedHost = state.host, !connectedHost.isEmpty {
                    connectionHost = connectedHost
                }
            }
        }
    }

    @MainActor
    private func disconnectFromHost() {
        Task {
            let state = await baseDependencies.connectionRuntime.disconnect()
            await MainActor.run {
                connectionState = state
                settingsDiagnosticsModel = nil
            }
        }
    }
}
