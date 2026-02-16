import ShadowClientFeatureHome
import ShadowClientStreaming
import SwiftUI

struct ContentView: View {
    private enum AppTab: Hashable {
        case home
        case settings
    }

    private let baseDependencies: ShadowClientFeatureHomeDependencies
    @State private var selectedTab: AppTab = .home
    @AppStorage("settings.lowLatencyMode") private var lowLatencyMode = true
    @AppStorage("settings.preferHDR") private var preferHDR = true
    @AppStorage("settings.preferSurroundAudio") private var preferSurroundAudio = true
    @AppStorage("settings.showDiagnosticsHUD") private var showDiagnosticsHUD = true

    init(dependencies: ShadowClientFeatureHomeDependencies) {
        self.baseDependencies = dependencies
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            homeTab
            settingsTab
        }
        .tint(.mint)
    }

    private var homeTab: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                ShadowClientFeatureHomeView(
                    platformName: "macOS",
                    dependencies: configuredDependencies,
                    showsDiagnosticsHUD: showDiagnosticsHUD
                )
                .id(settingsVersion)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private var configuredDependencies: ShadowClientFeatureHomeDependencies {
        .init(
            telemetryPublisher: baseDependencies.telemetryPublisher,
            pipeline: baseDependencies.pipeline,
            diagnosticsPresenter: baseDependencies.diagnosticsPresenter,
            settingsMapper: baseDependencies.settingsMapper,
            launchPlanBuilder: baseDependencies.launchPlanBuilder,
            sessionPreferences: StreamingUserPreferences(
                preferHDR: preferHDR,
                preferSurroundAudio: preferSurroundAudio,
                lowLatencyMode: lowLatencyMode
            ),
            hostCapabilities: baseDependencies.hostCapabilities
        )
    }

    private var settingsVersion: String {
        "\(lowLatencyMode)-\(preferHDR)-\(preferSurroundAudio)-\(showDiagnosticsHUD)"
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
