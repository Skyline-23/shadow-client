import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

extension ShadowClientAppShellView {
var remoteDesktopHostCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Label("Remote Desktop Hosts", systemImage: "desktopcomputer")
                    .font(.system(.title3, design: .rounded).weight(.bold))
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
                .accessibilityIdentifier("shadow.home.hosts.refresh")
                .accessibilityLabel("Refresh Remote Desktop Hosts")
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

            if let selectedHost = remoteDesktopRuntime.selectedHost {
                selectedRemoteDesktopHostActions(selectedHost)
            } else {
                settingsRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Select a host")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Pick one host to unlock pairing, connection, and app actions.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }
                    Spacer(minLength: 0)
                }
            }

            if let pairingPIN = remoteDesktopRuntime.activePairingPIN {
                settingsRow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Pair PIN: \(pairingPIN)")
                            .font(.title3.monospacedDigit().weight(.bold))
                            .foregroundStyle(.mint)
                        Text("Enter this PIN in Sunshine Web UI.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.82))
                    }
                    Spacer(minLength: 0)
                }
            }

            settingsRow {
                Label(remoteDesktopRuntime.pairingState.label, systemImage: "number.square")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(pairingStateColor)
                    .accessibilityIdentifier("shadow.home.hosts.pairing-state")
                    .accessibilityLabel("Host Pairing State")
                    .accessibilityValue(remoteDesktopRuntime.pairingState.label)
                Spacer(minLength: 0)
            }

            remoteDesktopAppListSection
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shadow.home.hosts.card")
        .accessibilityLabel("Remote Desktop Hosts")
        .accessibilityValue(remoteDesktopHostsAccessibilityValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelSurface(cornerRadius: 14))
    }

func remoteDesktopHostRow(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        let isSelected = remoteDesktopRuntime.selectedHostID == host.id
        let hostIdentifier = sanitizedIdentifier(host.id)

        return settingsRow {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(host.displayName)
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.85)

                        Text(host.host)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Color.white.opacity(0.86))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .minimumScaleFactor(0.8)

                        Text(host.statusLabel)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(remoteHostStatusColor(host))

                        Text(host.detailLabel)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.82))
                            .lineLimit(3)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 8)

                    if isSelected {
                        Label("Selected", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(accentColor)
                    }
                }

                remoteDesktopHostSelectionButton(
                    host: host,
                    hostIdentifier: hostIdentifier,
                    isSelected: isSelected
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).row")
        .accessibilityLabel(hostAccessibilityLabel(for: host, isSelected: isSelected))
        .accessibilityHint("Shows status for \(host.displayName) and lets you select it for actions below")
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isSelected ? Color.mint.opacity(0.9) : Color.clear, lineWidth: 1.5)
        )
    }

var remoteDesktopAppListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isCompactLayout {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Host App Library")
                            .font(.headline)
                            .foregroundStyle(.white)
                        Spacer(minLength: 8)
                        Button {
                            remoteDesktopRuntime.refreshSelectedHostApps()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .accessibilityIdentifier("shadow.home.applist.refresh")
                        .accessibilityLabel("Refresh Host App Library")
                        .buttonStyle(.bordered)
                        .disabled(!canRefreshSelectedHostApps)
                    }

                    Label(remoteDesktopRuntime.appState.label, systemImage: "gamecontroller.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.84))
                        .lineLimit(2)
                }
            } else {
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
                    .accessibilityIdentifier("shadow.home.applist.refresh")
                    .accessibilityLabel("Refresh Host App Library")
                    .buttonStyle(.bordered)
                    .disabled(!canRefreshSelectedHostApps)
                }
            }

            if let selectedHost = remoteDesktopRuntime.selectedHost {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Selected Host: \(selectedHost.displayName) (\(selectedHost.host))")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.78))
                    if selectedHost.pairStatus != .paired {
                        Label("Pair this host before loading desktop or game apps.", systemImage: "lock.shield")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.yellow)
                    }
                }
            } else {
                Text("Select a host to inspect available desktop/game apps.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.78))
            }

            if remoteDesktopRuntime.selectedHost == nil {
                settingsRow {
                    Text("Choose a host first. The app library appears after a paired host is selected.")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.82))
                    Spacer(minLength: 0)
                }
            } else if let selectedHost = remoteDesktopRuntime.selectedHost, selectedHost.pairStatus != .paired {
                settingsRow {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pairing required")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("Sunshine sees this host, but this client is not paired yet. Complete pairing first, then refresh the app library.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }
                    Spacer(minLength: 8)
                    pairSelectedHostButton(fullWidth: false)
                }
            } else if remoteDesktopRuntime.apps.isEmpty {
                settingsRow {
                    Text("No app metadata loaded yet. The host may require pairing before app list queries.")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.82))
                    Spacer(minLength: 0)
                }
            } else {
                ForEach(remoteDesktopRuntime.apps.prefix(8)) { app in
                    let appIdentifier = sanitizedIdentifier(String(app.id))
                    settingsRow {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.title)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.white)
                            Text("App ID: \(app.id) · HDR: \(app.hdrSupported ? "Y" : "N")")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Color.white.opacity(0.72))
                        }
                        Spacer(minLength: 8)
                        Button("Launch") {
                            launchRemoteApp(app)
                        }
                        .accessibilityIdentifier("shadow.home.applist.launch.\(appIdentifier)")
                        .accessibilityLabel("Launch \(app.title)")
                        .accessibilityHint("Launches the selected remote app and enters remote session view")
                        .buttonStyle(.borderedProminent)
                        .disabled(remoteDesktopRuntime.launchState == .launching)
                    }
                }
            }

            settingsRow {
                Label(remoteDesktopRuntime.launchState.label, systemImage: "play.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(launchStateColor)
                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("shadow.home.applist.section")
        .accessibilityLabel("Host App Library")
        .accessibilityValue(hostAppLibraryAccessibilityValue)
    }

    func hostAccessibilityLabel(
        for host: ShadowClientRemoteHostDescriptor,
        isSelected: Bool
    ) -> String {
        let selectionDetail = isSelected ? " Currently selected." : ""
        return "\(host.displayName), \(host.statusLabel). Host: \(host.host).\(selectionDetail) \(host.detailLabel)"
    }

    @ViewBuilder
    func selectedRemoteDesktopHostActions(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        settingsRow {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(host.displayName)
                            .font(.callout.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(host.statusLabel)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(remoteHostStatusColor(host))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(remoteHostStatusColor(host).opacity(0.14), in: Capsule())
                    }

                    Text(host.host)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.white.opacity(0.82))

                    if host.pairStatus == .paired {
                        Text("Pairing is complete. Connect to this host or refresh apps below.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.78))
                    } else {
                        Text("This host is reachable, but pairing is still required before you can open apps or launch a session.")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.yellow)
                    }
                }

                if isCompactLayout {
                    VStack(alignment: .leading, spacing: 8) {
                        selectedHostPrimaryActionButton(for: host)
                            .frame(maxWidth: .infinity)
                        if host.pairStatus != .paired {
                            pairSelectedHostButton(fullWidth: true)
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        selectedHostPrimaryActionButton(for: host)
                        if host.pairStatus != .paired {
                            pairSelectedHostButton(fullWidth: false)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    func selectedHostPrimaryActionButton(for host: ShadowClientRemoteHostDescriptor) -> some View {
        if host.pairStatus == .paired {
            Button("Connect Selected") {
                connectionHost = host.host
                connectToHost(autoLaunchAfterConnect: true, preferredHostID: host.id)
            }
            .accessibilityIdentifier("shadow.home.hosts.connect-selected")
            .accessibilityLabel("Connect selected host")
            .accessibilityHint("Connects to \(host.displayName) and opens the preferred remote session")
            .buttonStyle(.borderedProminent)
            .disabled(!hostCanConnect(host))
        } else {
            Button("Connect Selected") {
                connectionHost = host.host
                connectToHost(autoLaunchAfterConnect: true, preferredHostID: host.id)
            }
            .accessibilityIdentifier("shadow.home.hosts.connect-selected")
            .accessibilityLabel("Connect selected host")
            .accessibilityHint("Disabled until \(host.displayName) is paired")
            .buttonStyle(.bordered)
            .disabled(true)
        }
    }

    @ViewBuilder
    func pairSelectedHostButton(fullWidth: Bool) -> some View {
        if canPairSelectedHost {
            Button {
                if let selectedHost = remoteDesktopRuntime.selectedHost {
                    connectionHost = selectedHost.host
                }
                remoteDesktopRuntime.pairSelectedHost()
            } label: {
                if case .pairing = remoteDesktopRuntime.pairingState {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Start Pairing")
                }
            }
            .accessibilityIdentifier("shadow.home.hosts.start-pairing")
            .accessibilityLabel("Start Pairing")
            .buttonStyle(.borderedProminent)
            .frame(maxWidth: fullWidth ? .infinity : nil)
        } else {
            Button("Start Pairing") {
                remoteDesktopRuntime.pairSelectedHost()
            }
            .accessibilityIdentifier("shadow.home.hosts.start-pairing")
            .accessibilityLabel("Start Pairing")
            .buttonStyle(.bordered)
            .disabled(true)
            .frame(maxWidth: fullWidth ? .infinity : nil)
        }
    }

    @ViewBuilder
    func remoteDesktopHostSelectionButton(
        host: ShadowClientRemoteHostDescriptor,
        hostIdentifier: String,
        isSelected: Bool
    ) -> some View {
        if isSelected {
            Button("Selected Host") {
                connectionHost = host.host
                remoteDesktopRuntime.selectHost(host.id)
            }
            .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).select")
            .accessibilityLabel("\(host.displayName) selected")
            .accessibilityHint("Makes \(host.displayName) the active host for pairing and connection actions")
            .buttonStyle(.borderedProminent)
            .disabled(true)
            .frame(maxWidth: isCompactLayout ? .infinity : nil, alignment: .leading)
        } else {
            Button("Select Host") {
                connectionHost = host.host
                remoteDesktopRuntime.selectHost(host.id)
            }
            .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).select")
            .accessibilityLabel("Select \(host.displayName)")
            .accessibilityHint("Makes \(host.displayName) the active host for pairing and connection actions")
            .buttonStyle(.bordered)
            .frame(maxWidth: isCompactLayout ? .infinity : nil, alignment: .leading)
        }
    }

    func sanitizedIdentifier(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = raw.lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return sanitized.isEmpty ? "unknown" : sanitized
    }

    var remoteDesktopHostsAccessibilityValue: String {
        "\(remoteDesktopRuntime.hosts.count) host(s). Discovery \(remoteDesktopRuntime.hostState.label). Pairing \(remoteDesktopRuntime.pairingState.label)."
    }

    var hostAppLibraryAccessibilityValue: String {
        "\(remoteDesktopRuntime.apps.count) app(s). Catalog \(remoteDesktopRuntime.appState.label). Launch state \(remoteDesktopRuntime.launchState.label)."
    }

    var canPairSelectedHost: Bool {
        guard let selectedHost = remoteDesktopRuntime.selectedHost else {
            return false
        }
        return selectedHost.isReachable && selectedHost.pairStatus != .paired
    }

    var canRefreshSelectedHostApps: Bool {
        guard let selectedHost = remoteDesktopRuntime.selectedHost else {
            return false
        }
        return selectedHost.isReachable && selectedHost.pairStatus == .paired
    }

    func hostCanConnect(_ host: ShadowClientRemoteHostDescriptor) -> Bool {
        canInitiateSessionConnection && host.isReachable && host.pairStatus == .paired
    }

var connectionStatusCard: some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("shadow.home.connection-status")
        .accessibilityLabel("Client Connection")
        .accessibilityValue(connectionStatusText)
        .padding(14)
        .background(panelSurface(cornerRadius: 12))
    }

func remoteHostStatusColor(_ host: ShadowClientRemoteHostDescriptor) -> Color {
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

var pairingStateColor: Color {
        switch remoteDesktopRuntime.pairingState {
        case .idle:
            return Color.white.opacity(0.74)
        case .pairing:
            return .orange
        case .paired:
            return .green
        case .failed:
            return .red
        }
    }

var launchStateColor: Color {
        switch sessionPresentationModel.launchTone {
        case .idle:
            return Color.white.opacity(0.74)
        case .launching:
            return .orange
        case .launched:
            return .green
        case .failed:
            return .red
        }
    }

}
