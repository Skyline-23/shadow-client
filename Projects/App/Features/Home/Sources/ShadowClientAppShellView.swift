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

    @State private var selectedTab: AppTab = .home
    @AppStorage(ShadowClientAppSettings.StorageKeys.lowLatencyMode) private var lowLatencyMode = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.preferHDR) private var preferHDR = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.preferSurroundAudio) private var preferSurroundAudio = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.showDiagnosticsHUD) private var showDiagnosticsHUD = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.connectionHost) private var connectionHost = ""
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
        .preferredColorScheme(.dark)
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
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
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
                                .background(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .fill(Color.black.opacity(0.32))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                )
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

                        settingsSection(title: "Streaming Quality") {
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
                                    Label("Prefer HDR", systemImage: "sparkles.tv")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                                .tint(.mint)
                            }
                            settingsRow {
                                Toggle(isOn: $preferSurroundAudio) {
                                    Label("Prefer Surround Audio", systemImage: "hifispeaker.and.homepod.fill")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.white)
                                }
                                .tint(.mint)
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
                    .frame(maxWidth: 920)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 24)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Settings")
        }
        .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        .tag(AppTab.settings)
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.34))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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

    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 10) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.42))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.28))
        )
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
