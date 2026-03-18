import ShadowClientStreaming
import ShadowClientFeatureConnection
import ShadowClientFeatureSession
import ShadowClientUI
import SwiftUI
import ShadowUIFoundation

extension ShadowClientAppShellView {
func connectionCandidate(for host: ShadowClientRemoteHostDescriptor) -> String {
        let endpoint = host.routes.active
        if endpoint.httpsPort == ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort {
            return endpoint.host
        }
        return "\(endpoint.host):\(endpoint.httpsPort)"
    }

func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ShadowUISettingsSection(title: title, content: content)
    }

func settingsRow<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ShadowUISettingsRow(content: content)
    }

func settingsPickerRow<Value: Hashable, Content: View>(
        title: String,
        symbol: String,
        selection: Binding<Value>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ShadowUISettingsPickerRow(
            title: title,
            symbol: symbol,
            selection: selection,
            content: content
        )
    }

func diagnosticsRow(
        label: String,
        value: String,
        valueColor: Color = Color.white.opacity(0.92)
    ) -> some View {
        ShadowUIDiagnosticsRow(label: label, value: value, valueColor: valueColor)
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
                connectionHost = discoveredHost.probeCandidate
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
        ShadowClientBitrateControlKit.effectiveBitrateKbps(
            settings: currentSettings,
            networkSignal: launchBitrateNetworkSignal
        )
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
                bitrateKbps = ShadowClientBitrateControlKit.clampedBitrateKbps(
                    sliderValue: newValue,
                    maxBitrateKbps: maxBitrateKbps
                )
            }
        )
    }

}
