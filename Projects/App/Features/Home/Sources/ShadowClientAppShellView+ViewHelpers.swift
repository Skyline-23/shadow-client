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
                Text(ShadowClientDiscoveredHostPresentationKit.detailText(discoveredHost))
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(ShadowClientAppShellChrome.Palette.tertiaryText)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button(ShadowClientDiscoveredHostPresentationKit.useButtonTitle()) {
                connectionHost = discoveredHost.host
                refreshRemoteDesktopCatalog()
            }
            .buttonStyle(.bordered)
            Button(ShadowClientDiscoveredHostPresentationKit.connectButtonTitle()) {
                connectToDiscoveredHost(discoveredHost)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canInitiateSessionConnection)
        }
    }

func toneColor(for tone: HealthTone) -> Color {
        ShadowClientSessionControlPresentationKit.toneColor(for: tone)
    }

var activeSessionVideoCodecLabel: String {
        guard let codec = sessionSurfaceContext.activeVideoCodec else {
            return "Negotiating"
        }
        return realtimeSessionVideoCodecLabel(codec)
    }

func videoCodecLabel(_ codec: ShadowClientVideoCodecPreference) -> String {
        ShadowClientSessionControlPresentationKit.videoCodecLabel(codec)
    }

func realtimeSessionVideoCodecLabel(_ codec: ShadowClientVideoCodec) -> String {
        ShadowClientSessionControlPresentationKit.realtimeSessionVideoCodecLabel(codec)
    }

var maxBitrateKbps: Double {
        ShadowClientSessionControlPresentationKit.maxBitrateKbps(
            unlockBitrateLimit: unlockBitrateLimit
        )
    }

var effectiveBitrateKbps: Int {
        currentSettings.resolvedBitrateKbps(networkSignal: launchBitrateNetworkSignal)
    }

var launchBitrateNetworkSignal: StreamingNetworkSignal? {
        ShadowClientSessionControlPresentationKit.launchBitrateNetworkSignal(
            autoBitrate: autoBitrate,
            diagnosticsModel: settingsDiagnosticsModel
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
