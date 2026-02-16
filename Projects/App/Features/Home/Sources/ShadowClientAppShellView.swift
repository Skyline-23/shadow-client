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
