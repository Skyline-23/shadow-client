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

func storedConnectionCandidates(for host: ShadowClientRemoteHostDescriptor) -> Set<String> {
        Set(host.routes.allEndpoints.flatMap { endpoint in
            let normalizedHost = endpoint.host
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalizedHost.isEmpty else {
                return [String]()
            }

            var candidates = ["\(normalizedHost):\(endpoint.httpsPort)"]
            if endpoint.httpsPort == ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort {
                candidates.append(normalizedHost)
            }
            if let connectPort = ShadowClientGameStreamNetworkDefaults.mappedHTTPPort(
                forHTTPSPort: endpoint.httpsPort
            ) {
                candidates.append("\(normalizedHost):\(connectPort)")
            }
            return candidates
        })
    }

func normalizedStoredConnectionCandidate(_ candidate: String) -> String {
        candidate.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

var hiddenRemoteHostCandidates: Set<String> {
        Set(
            hiddenRemoteHostCandidatesRaw
                .split(separator: "\n")
                .map { normalizedStoredConnectionCandidate(String($0)) }
                .filter { !$0.isEmpty }
        )
    }

func persistHiddenRemoteHostCandidates(_ candidates: Set<String>) {
        hiddenRemoteHostCandidatesRaw = candidates.sorted().joined(separator: "\n")
    }

func candidateVariants(for hostCandidate: String) -> Set<String> {
        let trimmed = hostCandidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return []
        }

        let urlCandidate = ShadowClientRTSPProtocolProfile.withHTTPSchemeIfMissing(trimmed)
        guard let url = URL(string: urlCandidate),
              let host = url.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty
        else {
            return [normalizedStoredConnectionCandidate(trimmed)]
        }

        let port = url.port ?? ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
        let canonicalHTTPSPort = ShadowClientGameStreamNetworkDefaults.canonicalHTTPSPort(
            fromCandidatePort: port
        )
        var candidates: Set<String> = ["\(host):\(canonicalHTTPSPort)"]
        if canonicalHTTPSPort == ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort {
            candidates.insert(host)
        }
        if let connectPort = ShadowClientGameStreamNetworkDefaults.mappedHTTPPort(
            forHTTPSPort: canonicalHTTPSPort
        ) {
            candidates.insert("\(host):\(connectPort)")
        }
        return candidates
    }

func suppressStoredHostCandidates(for host: ShadowClientRemoteHostDescriptor) {
        var candidates = hiddenRemoteHostCandidates
        candidates.formUnion(storedConnectionCandidates(for: host))
        persistHiddenRemoteHostCandidates(candidates)
    }

func clearHiddenRemoteHostCandidates(matching hostCandidate: String) {
        let variants = candidateVariants(for: hostCandidate)
        guard !variants.isEmpty else {
            return
        }

        let updatedCandidates = hiddenRemoteHostCandidates.subtracting(variants)
        persistHiddenRemoteHostCandidates(updatedCandidates)
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
