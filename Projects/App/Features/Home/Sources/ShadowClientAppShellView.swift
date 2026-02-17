import SwiftUI

public struct ShadowClientAppShellView: View {
    private enum AppTab: Hashable {
        case home
        case settings
    }

    private let platformName: String
    private let baseDependencies: ShadowClientFeatureHomeDependencies

    @State private var selectedTab: AppTab = .home
    @AppStorage(ShadowClientAppSettings.StorageKeys.lowLatencyMode) private var lowLatencyMode = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.preferHDR) private var preferHDR = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.preferSurroundAudio) private var preferSurroundAudio = true
    @AppStorage(ShadowClientAppSettings.StorageKeys.showDiagnosticsHUD) private var showDiagnosticsHUD = true
    @State private var latestDiagnosticsTick: HomeDiagnosticsTick?

    public init(platformName: String, dependencies: ShadowClientFeatureHomeDependencies) {
        self.platformName = platformName
        self.baseDependencies = dependencies
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            homeTab
            settingsTab
        }
        .tint(.mint)
    }

    private var currentSettings: ShadowClientAppSettings {
        ShadowClientAppSettings(
            lowLatencyMode: lowLatencyMode,
            preferHDR: preferHDR,
            preferSurroundAudio: preferSurroundAudio,
            showDiagnosticsHUD: showDiagnosticsHUD
        )
    }

    private var settingsDiagnosticsModel: SettingsDiagnosticsHUDModel? {
        latestDiagnosticsTick.map(SettingsDiagnosticsHUDModel.init(tick:))
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
                            showsDiagnosticsHUD: currentSettings.showDiagnosticsHUD,
                            onDiagnosticsTick: { tick in
                                latestDiagnosticsTick = tick
                            }
                        )
                        .id(currentSettings.identityKey)
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
                        Label("Awaiting telemetry samples from Home tab.", systemImage: "antenna.radiowaves.left.and.right")
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
}
