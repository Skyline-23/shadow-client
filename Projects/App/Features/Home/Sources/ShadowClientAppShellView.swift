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
    @ObservedObject private var hostDiscoveryRuntime: ShadowClientHostDiscoveryRuntime
    @ObservedObject private var remoteDesktopRuntime: ShadowClientRemoteDesktopRuntime
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
            TabView(selection: $selectedTab) {
                homeTab
                settingsTab
            }
        }
        .tint(.mint)
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
        .onDisappear {
            stopSettingsTelemetrySubscription()
            stopHostDiscovery()
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
                .frame(maxWidth: 920)
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                .padding(.horizontal, 20)
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

                        settingsRow {
                            Label("Auto Discovery: \(hostDiscoveryRuntime.state.label)", systemImage: "dot.radiowaves.left.and.right")
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
        .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
        .tag(AppTab.settings)
    }

    private var remoteDesktopHostCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Remote Desktop Hosts", systemImage: "desktopcomputer")
                    .font(.title3.weight(.bold))
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

            remoteDesktopAppListSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
        )
    }

    private func remoteDesktopHostRow(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        settingsRow {
            VStack(alignment: .leading, spacing: 4) {
                Text(host.displayName)
                    .font(.callout.weight(.bold))
                    .foregroundStyle(.white)
                Text("\(host.host) · \(host.statusLabel)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(remoteHostStatusColor(host))
                Text(host.detailLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.74))
            }

            Spacer(minLength: 8)

            Button("Use") {
                connectionHost = host.host
            }
            .buttonStyle(.bordered)

            Button("Connect") {
                connectionHost = host.host
                connectToHost()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStartConnection || !host.isReachable)

            Button("Select") {
                remoteDesktopRuntime.selectHost(host.id)
            }
            .buttonStyle(.bordered)
        }
    }

    private var remoteDesktopAppListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                        Spacer(minLength: 0)
                    }
                }
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
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.56))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
                .fill(Color.black.opacity(0.58))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.10), lineWidth: 1)
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
                .fill(Color.black.opacity(0.46))
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

    private func discoveredHostRow(_ discoveredHost: ShadowClientDiscoveredHost) -> some View {
        settingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(discoveredHost.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text("\(discoveredHost.host):\(discoveredHost.port) · \(discoveredHost.serviceType)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.74))
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
        hostDiscoveryRuntime.start()
    }

    @MainActor
    private func refreshRemoteDesktopCatalog() {
        var candidates = hostDiscoveryRuntime.hosts.map(\.host)
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
    private func connectToHost() {
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
        }
    }

    @MainActor
    private func connectToDiscoveredHost(_ discoveredHost: ShadowClientDiscoveredHost) {
        connectionHost = discoveredHost.host
        connectToHost()
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
