import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

extension ShadowClientAppShellView {
func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: ShadowClientAppShellChrome.Metrics.sectionHeaderSpacing) {
            Text(title)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: ShadowClientAppShellChrome.Metrics.sectionContentSpacing) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(ShadowClientAppShellChrome.Metrics.sectionPadding)
        .background(panelSurface(cornerRadius: ShadowClientAppShellChrome.Metrics.panelCornerRadius))
    }

func settingsRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: ShadowClientAppShellChrome.Metrics.rowSpacing) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, ShadowClientAppShellChrome.Metrics.rowHorizontalPadding)
        .padding(.vertical, ShadowClientAppShellChrome.Metrics.rowVerticalPadding)
        .background(rowSurface(cornerRadius: ShadowClientAppShellChrome.Metrics.rowCornerRadius))
    }

func settingsPickerRow<Value: Hashable, Content: View>(
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

func diagnosticsRow(
        label: String,
        value: String,
        valueColor: Color = Color.white.opacity(0.92)
    ) -> some View {
        settingsRow {
            Text(label)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(ShadowClientAppShellChrome.Palette.secondaryText)
            Spacer(minLength: 8)
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
    }

func discoveredHostRow(_ discoveredHost: ShadowClientDiscoveredHost) -> some View {
        settingsRow {
            VStack(alignment: .leading, spacing: 3) {
                Text(discoveredHost.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text("\(discoveredHost.host):\(discoveredHost.port) · \(discoveredHost.serviceType)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(ShadowClientAppShellChrome.Palette.tertiaryText)
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

func toneColor(for tone: HealthTone) -> Color {
        switch tone {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

var activeSessionVideoCodecLabel: String {
        guard let codec = sessionSurfaceContext.activeVideoCodec else {
            return "Negotiating"
        }
        return realtimeSessionVideoCodecLabel(codec)
    }

func videoCodecLabel(_ codec: ShadowClientVideoCodecPreference) -> String {
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

func realtimeSessionVideoCodecLabel(_ codec: ShadowClientVideoCodec) -> String {
        switch codec {
        case .av1:
            return "AV1"
        case .h265:
            return "H.265"
        case .h264:
            return "H.264"
        }
    }

var maxBitrateKbps: Double {
        unlockBitrateLimit
            ? Double(ShadowClientAppSettingsDefaults.maximumBitrateWhenUnlocked)
            : Double(ShadowClientAppSettingsDefaults.maximumBitrateWhenLocked)
    }

var effectiveBitrateKbps: Int {
        currentSettings.resolvedBitrateKbps(networkSignal: launchBitrateNetworkSignal)
    }

var launchBitrateNetworkSignal: StreamingNetworkSignal? {
        guard autoBitrate, let settingsDiagnosticsModel else {
            return nil
        }

        let nowMs = Int(Date().timeIntervalSince1970 * 1_000)
        let sampleAgeMs = max(0, nowMs - settingsDiagnosticsModel.timestampMs)
        guard sampleAgeMs <= ShadowClientUIRuntimeDefaults.bitrateSignalFreshnessWindowMs else {
            return nil
        }

        return .init(
            jitterMs: Double(settingsDiagnosticsModel.jitterMs),
            packetLossPercent: settingsDiagnosticsModel.packetLossPercent
        )
    }

var bitrateSliderBinding: Binding<Double> {
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

}
