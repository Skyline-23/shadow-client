import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

private struct RemoteDesktopHostFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum SpotlightFace {
    case front
    case back
}

extension ShadowClientAppShellView {
var remoteDesktopHostCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            remoteDesktopHostHeader

            if isShowingManualHostEntry {
                remoteDesktopManualEntryCard
            }

            if remoteDesktopRuntime.hosts.isEmpty {
                remoteDesktopEmptyStateCard
            } else {
                LazyVGrid(columns: remoteDesktopHostGridColumns, alignment: .leading, spacing: 16) {
                    ForEach(remoteDesktopRuntime.hosts.prefix(8)) { host in
                        remoteDesktopHostTile(host)
                    }
                }
            }
        }
        .onPreferenceChange(RemoteDesktopHostFramePreferenceKey.self) { frames in
            remoteDesktopHostFrames = frames
        }
        .allowsHitTesting(spotlightedHostID == nil)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shadow.home.hosts.card")
        .accessibilityLabel("Remote Desktop Hosts")
        .accessibilityValue(remoteDesktopHostsAccessibilityValue)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(panelSurface(cornerRadius: 18))
    }

    var remoteDesktopHostHeader: some View {
        HStack(spacing: 10) {
            Label("Remote Desktop Hosts", systemImage: "desktopcomputer")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            Label(autoFindHosts ? "Auto Scan" : "Manual", systemImage: autoFindHosts ? "dot.radiowaves.left.and.right" : "plus.circle")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(Color.white.opacity(0.88))
                .background(hostHeaderBadgeSurface, in: Capsule())

            Button {
                refreshRemoteDesktopCatalog()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityIdentifier("shadow.home.hosts.refresh")
            .accessibilityLabel("Refresh Remote Desktop Hosts")
            .buttonStyle(.bordered)

            Button {
                presentManualHostEntry()
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityIdentifier("shadow.home.hosts.add")
            .accessibilityLabel("Add Remote Desktop Host")
            .buttonStyle(.borderedProminent)
        }
    }

    var remoteDesktopManualEntryCard: some View {
        settingsRow {
            VStack(alignment: .leading, spacing: 8) {
                Text("Add device")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                TextField("Host or IP", text: $manualHostDraft)
                    .font(.body.weight(.semibold))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(hostPanelInsetSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .onSubmit {
                        addManualHostToCatalog()
                    }
            }

            Spacer(minLength: 8)

            if isCompactLayout {
                VStack(spacing: 8) {
                    Button("Add") {
                        addManualHostToCatalog()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualHostDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Cancel") {
                        cancelManualHostEntry()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                HStack(spacing: 8) {
                    Button("Add") {
                        addManualHostToCatalog()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(manualHostDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Cancel") {
                        cancelManualHostEntry()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    var remoteDesktopEmptyStateCard: some View {
        settingsRow {
            VStack(alignment: .leading, spacing: 4) {
                Text("No devices")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text(autoFindHosts
                    ? "Auto Scan is running. Tap + to add one manually if your device does not appear."
                    : "Auto Scan is off. Tap + to add a device manually.")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.76))
            }
            Spacer(minLength: 0)
        }
    }

    func remoteDesktopHostTile(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        let isSelected = remoteDesktopRuntime.selectedHostID == host.id
        let hostIdentifier = sanitizedIdentifier(host.id)
        let spotlighted = spotlightedHostID == host.id

        return Button {
            presentHostSpotlight(for: host)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(hostGlyphColor(host).opacity(0.16))
                            .frame(width: 48, height: 48)

                        Image(systemName: hostGlyphSymbol(host))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(hostGlyphColor(host))
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(hostDisplayTitle(host))
                            .font(.title3.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .truncationMode(.tail)

                        Text(host.host)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Color.white.opacity(0.70))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer(minLength: 12)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(accentColor)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(host.statusLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(remoteHostStatusColor(host))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(remoteHostStatusColor(host).opacity(0.14), in: Capsule())
                }

                Text(hostSummaryText(host))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(host.lastError == nil ? Color.white.opacity(0.76) : .red.opacity(0.92))
                    .lineLimit(2)

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Label(hostTileActionLabel(host), systemImage: hostFrontHintSymbol(host))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(hostFrontHintColor(host))

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.46))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 252, alignment: .topLeading)
            .padding(18)
            .background(hostCardSurface(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!spotlighted)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).row")
        .accessibilityLabel(hostAccessibilityLabel(for: host, isSelected: isSelected))
        .accessibilityHint("Opens \(hostDisplayTitle(host)) in a focused rotating card")
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isSelected ? accentColor.opacity(0.92) : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
        )
        .opacity(spotlighted ? 0 : 1)
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: RemoteDesktopHostFramePreferenceKey.self,
                    value: [host.id: proxy.frame(in: .named("shadow.home.spotlightSpace"))]
                )
            }
        )
    }

    func remoteDesktopHostSpotlightCard(_ host: ShadowClientRemoteHostDescriptor, containerSize: CGSize) -> some View {
        let transform = spotlightTransform(in: containerSize)
        return AnyView(
            remoteDesktopHostAnimatedSpotlightCard(
                host,
                transform: transform,
                interactiveBackFace: spotlightCardSettled
            )
                .position(x: transform.currentFrame.midX, y: transform.currentFrame.midY)
                .zIndex(2)
        )
    }

    func remoteDesktopHostAnimatedSpotlightCard(
        _ host: ShadowClientRemoteHostDescriptor,
        transform: (targetFrame: CGRect, currentFrame: CGRect),
        interactiveBackFace: Bool
    ) -> some View {
        let flipAngle = -180 * spotlightAnimationProgress
        let frontOpacity = spotlightFaceOpacity(progress: spotlightAnimationProgress, face: .front)
        let backOpacity = spotlightFaceOpacity(progress: spotlightAnimationProgress, face: .back)

        return ZStack {
            hostSpotlightSurface

            remoteDesktopHostFrontFace(host, interactive: false)
                .padding(18)
                .opacity(frontOpacity)

            remoteDesktopHostBackFace(host, interactive: interactiveBackFace)
                .padding(18)
                .opacity(backOpacity)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0), perspective: 0.9)
        }
        .frame(width: transform.currentFrame.width, height: transform.currentFrame.height)
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accentColor.opacity(0.90), lineWidth: 2)
        )
        .shadow(color: Color.black.opacity(0.34), radius: 32, x: 0, y: 18)
        .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 1.25)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    fileprivate func spotlightFaceOpacity(progress: Double, face: SpotlightFace) -> Double {
        let transitionStart = 0.34
        let transitionEnd = 0.66
        let normalized = min(max((progress - transitionStart) / (transitionEnd - transitionStart), 0), 1)

        switch face {
        case .front:
            return 1 - normalized
        case .back:
            return normalized
        }
    }

    func remoteDesktopHostFrontFace(_ host: ShadowClientRemoteHostDescriptor, interactive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(hostGlyphColor(host).opacity(0.18))
                        .frame(width: 48, height: 48)

                    Image(systemName: hostGlyphSymbol(host))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(hostGlyphColor(host))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(hostDisplayTitle(host))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(host.host)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                Spacer(minLength: 12)
            }

            HStack(spacing: 8) {
                Text(host.statusLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(remoteHostStatusColor(host))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(remoteHostStatusColor(host).opacity(0.14), in: Capsule())

                Text(hostTileActionLabel(host))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(hostRowActionColor(host, isSelected: true))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(hostRowActionColor(host, isSelected: true).opacity(0.12), in: Capsule())
            }

            Text(hostSummaryText(host))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(host.lastError == nil ? Color.white.opacity(0.82) : .red.opacity(0.92))
                .lineLimit(3)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Label(hostTileActionLabel(host), systemImage: hostFrontHintSymbol(host))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hostFrontHintColor(host))

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.46))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func remoteDesktopHostBackFace(_ host: ShadowClientRemoteHostDescriptor, interactive: Bool) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(hostDisplayTitle(host))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                    Text(host.host)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                Spacer(minLength: 12)

                Text(host.statusLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(remoteHostStatusColor(host))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(hostSpotlightBadgeSurface, in: Capsule())
            }

            remoteDesktopHostMetadataEditor(host)
                .allowsHitTesting(interactive)

            remoteDesktopHostStatusCallout(host)

            remoteDesktopHostActionBar(host)
                .allowsHitTesting(interactive)

            if let pairingPIN = remoteDesktopRuntime.activePairingPIN {
                HStack(spacing: 8) {
                    Label("Pair PIN", systemImage: "number.square")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.70))
                    Text(pairingPIN)
                        .font(.title3.monospacedDigit().weight(.bold))
                        .foregroundStyle(.mint)
                    Spacer(minLength: 0)
                }
            }

            remoteDesktopAppLibrarySection(for: host)
                .allowsHitTesting(interactive)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func remoteDesktopHostMetadataPreview(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        let friendlyName = hostFriendlyName(for: host).trimmingCharacters(in: .whitespacesAndNewlines)
        let note = hostNotes(for: host).trimmingCharacters(in: .whitespacesAndNewlines)

        return VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Friendly Name")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.68))
                Text(friendlyName.isEmpty ? "Use the discovered name" : friendlyName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(friendlyName.isEmpty ? Color.white.opacity(0.42) : .white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(hostSpotlightInsetSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.68))
                Text(note.isEmpty ? "Add a note for this device" : note)
                    .font(.body)
                    .foregroundStyle(note.isEmpty ? Color.white.opacity(0.42) : .white.opacity(0.88))
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(hostSpotlightInsetSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    func remoteDesktopHostActionBarPreview(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        Group {
            if isCompactLayout {
                VStack(alignment: .leading, spacing: 8) {
                    previewActionPill(title: "Go", accent: hostCanConnect(host) ? accentColor : .white.opacity(0.25))
                    if shouldShowPairAction(for: host) {
                        previewActionPill(title: "Pair", accent: .yellow.opacity(0.8))
                    }
                }
            } else {
                HStack(spacing: 8) {
                    previewActionPill(title: "Go", accent: hostCanConnect(host) ? accentColor : .white.opacity(0.25))
                    if shouldShowPairAction(for: host) {
                        previewActionPill(title: "Pair", accent: .yellow.opacity(0.8))
                    }
                }
            }
        }
    }

    func remoteDesktopAppLibraryPreview(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("App Library")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Label(remoteDesktopRuntime.appState.label, systemImage: "gamecontroller.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
                Image(systemName: "arrow.clockwise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.45))
                    .padding(8)
                    .background(hostSpotlightInsetSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if host.pairStatus != .paired {
                remoteDesktopCalloutRow(
                    title: "Locked",
                    message: "Pair this device first to load desktop or game apps.",
                    accent: .yellow
                )
            } else if remoteDesktopRuntime.apps.isEmpty {
                remoteDesktopCalloutRow(
                    title: "No Apps Yet",
                    message: "Refresh after the host session becomes ready.",
                    accent: Color.white.opacity(0.65)
                )
            } else {
                ForEach(remoteDesktopRuntime.apps.prefix(3)) { app in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.title)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.white)
                            Text("App ID: \(app.id) · HDR: \(app.hdrSupported ? "Y" : "N")")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Color.white.opacity(0.68))
                        }

                        Spacer(minLength: 8)
                        previewActionPill(title: "Launch", accent: accentColor)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(hostSpotlightInsetSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(.top, 4)
    }

    func previewActionPill(title: String, accent: Color) -> some View {
        Text(title)
            .font(.callout.weight(.bold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(accent.opacity(0.22), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(accent.opacity(0.28), lineWidth: 1)
            )
    }

    func remoteDesktopHostMetadataEditor(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Friendly Name")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.68))
                TextField("Use the discovered name", text: hostFriendlyNameBinding(for: host))
                    .font(.body.weight(.semibold))
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(hostSpotlightInsetSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.68))
                TextField("Add a note for this device", text: hostNotesBinding(for: host), axis: .vertical)
                    .font(.body)
                    .textFieldStyle(.plain)
                    .foregroundStyle(.white)
                    .lineLimit(2...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(hostSpotlightInsetSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    @ViewBuilder
    func remoteDesktopHostStatusCallout(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        if let lastError = host.lastError, !lastError.isEmpty {
            remoteDesktopCalloutRow(
                title: "Connection Issue",
                message: lastError,
                accent: .red
            )
        } else if host.pairStatus == .paired {
            remoteDesktopCalloutRow(
                title: "Ready",
                message: "This device is paired and ready to launch a remote desktop session.",
                accent: .mint
            )
        } else {
            remoteDesktopCalloutRow(
                title: "Pairing Required",
                message: "This device is reachable, but you need to pair it before browsing apps or launching a session.",
                accent: .yellow
            )
        }
    }

    func remoteDesktopHostActionBar(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        Group {
            if isCompactLayout {
                VStack(alignment: .leading, spacing: 8) {
                    selectedHostPrimaryActionButton(for: host)
                        .frame(maxWidth: .infinity)
                    if shouldShowPairAction(for: host) {
                        pairSelectedHostButton(fullWidth: true)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    selectedHostPrimaryActionButton(for: host)
                    if shouldShowPairAction(for: host) {
                        pairSelectedHostButton(fullWidth: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func selectedHostPrimaryActionButton(for host: ShadowClientRemoteHostDescriptor) -> some View {
        Button("Go") {
            connectionHost = host.host
            connectToHost(autoLaunchAfterConnect: true, preferredHostID: host.id)
        }
        .accessibilityIdentifier("shadow.home.hosts.go-selected")
        .accessibilityLabel("Go to selected host")
        .accessibilityHint(hostCanConnect(host)
            ? "Connects to \(hostDisplayTitle(host)) and opens the preferred remote session"
            : "Disabled until \(hostDisplayTitle(host)) is ready")
        .buttonStyle(.borderedProminent)
        .disabled(!hostCanConnect(host))
    }

    @ViewBuilder
    func pairSelectedHostButton(fullWidth: Bool) -> some View {
        if canPairSelectedHost {
            Button("Pair") {
                if let selectedHost = remoteDesktopRuntime.selectedHost {
                    connectionHost = selectedHost.host
                }
                remoteDesktopRuntime.pairSelectedHost()
            }
            .accessibilityIdentifier("shadow.home.hosts.start-pairing")
            .accessibilityLabel("Pair selected host")
            .buttonStyle(.bordered)
            .frame(maxWidth: fullWidth ? .infinity : nil)
        }
    }

    func remoteDesktopAppLibrarySection(for host: ShadowClientRemoteHostDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("App Library")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Label(remoteDesktopRuntime.appState.label, systemImage: "gamecontroller.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.82))
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

            if host.pairStatus != .paired {
                remoteDesktopCalloutRow(
                    title: "Locked",
                    message: "Pair this device first to load desktop or game apps.",
                    accent: .yellow
                )
            } else if remoteDesktopRuntime.apps.isEmpty {
                remoteDesktopCalloutRow(
                    title: "No Apps Yet",
                    message: "Refresh after the host session becomes ready.",
                    accent: Color.white.opacity(0.65)
                )
            } else {
                ForEach(remoteDesktopRuntime.apps.prefix(5)) { app in
                    let appIdentifier = sanitizedIdentifier(String(app.id))
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(app.title)
                                .font(.callout.weight(.bold))
                                .foregroundStyle(.white)
                            Text("App ID: \(app.id) · HDR: \(app.hdrSupported ? "Y" : "N")")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(Color.white.opacity(0.68))
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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(hostSpotlightInsetSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(.top, 4)
    }

    func remoteDesktopCalloutRow(title: String, message: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(accent)
            Text(message)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.78))
                .lineLimit(3)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(hostSpotlightInsetSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        )
    }

    func hostDisplayTitle(_ host: ShadowClientRemoteHostDescriptor) -> String {
        let alias = hostFriendlyName(for: host).trimmingCharacters(in: .whitespacesAndNewlines)
        return alias.isEmpty ? host.displayName : alias
    }

    func hostSummaryText(_ host: ShadowClientRemoteHostDescriptor) -> String {
        let notes = hostNotes(for: host).trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty {
            return notes
        }
        if let lastError = host.lastError, !lastError.isEmpty {
            return lastError
        }
        return host.detailLabel
    }

    func hostTileActionLabel(_ host: ShadowClientRemoteHostDescriptor) -> String {
        if !host.isReachable {
            return "Needs Attention"
        }
        switch host.pairStatus {
        case .paired:
            return "Ready to Go"
        case .notPaired:
            return "Pair First"
        case .unknown:
            return "Inspect"
        }
    }

    func hostFrontHint(_ host: ShadowClientRemoteHostDescriptor) -> String {
        if !host.isReachable {
            return "Connection issue"
        }
        if host.pairStatus == .paired {
            return "Ready"
        }
        return "Pair first"
    }

    func hostFrontHintSymbol(_ host: ShadowClientRemoteHostDescriptor) -> String {
        if !host.isReachable {
            return "exclamationmark.shield"
        }
        if host.pairStatus == .paired {
            return "play.circle"
        }
        return "lock.shield"
    }

    func hostFrontHintColor(_ host: ShadowClientRemoteHostDescriptor) -> Color {
        if !host.isReachable {
            return .red.opacity(0.9)
        }
        if host.pairStatus == .paired {
            return .mint
        }
        return .yellow
    }

    func hostFrontMessage(_ host: ShadowClientRemoteHostDescriptor) -> String {
        if let lastError = host.lastError, !lastError.isEmpty {
            return lastError
        }
        if host.pairStatus == .paired {
            return "Flip the card for launch controls and a quick app library."
        }
        return "Flip the card to pair this host before browsing or launching apps."
    }

    func hostGlyphSymbol(_ host: ShadowClientRemoteHostDescriptor) -> String {
        if !host.isReachable {
            return "wifi.exclamationmark"
        }
        if host.pairStatus == .paired {
            return "checkmark.desktopcomputer"
        }
        return "lock.desktopcomputer"
    }

    func hostGlyphColor(_ host: ShadowClientRemoteHostDescriptor) -> Color {
        if !host.isReachable {
            return .red.opacity(0.92)
        }
        if host.pairStatus == .paired {
            return .mint
        }
        return .yellow
    }

    var hostSpotlightSurface: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.15, green: 0.20, blue: 0.27),
                        Color(red: 0.11, green: 0.16, blue: 0.22),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    var hostPanelInsetSurface: some ShapeStyle {
        Color(red: 0.17, green: 0.20, blue: 0.26)
    }

    var hostHeaderBadgeSurface: some ShapeStyle {
        Color(red: 0.20, green: 0.24, blue: 0.30)
    }

    var hostSpotlightInsetSurface: some ShapeStyle {
        Color(red: 0.12, green: 0.15, blue: 0.21)
    }

    var hostSpotlightBadgeSurface: some ShapeStyle {
        Color(red: 0.16, green: 0.11, blue: 0.14)
    }

    func spotlightTransform(in containerSize: CGSize) -> (
        targetFrame: CGRect,
        currentFrame: CGRect
    ) {
        let sourceFrame = spotlightedHostSourceFrame == .zero
            ? CGRect(x: (containerSize.width - 260) / 2, y: 72, width: 260, height: 252)
            : spotlightedHostSourceFrame
        let targetSide = min(
            containerSize.width - CGFloat(isCompactLayout ? 32 : 104),
            CGFloat(isCompactLayout ? 420 : 560)
        )
        let targetMinY = max(
            sourceFrame.minY + 20,
            isCompactLayout ? 132 : 148
        )
        let targetFrame = CGRect(
            x: (containerSize.width - targetSide) / 2,
            y: targetMinY,
            width: targetSide,
            height: targetSide
        )
        let currentFrame = CGRect(
            x: sourceFrame.minX + ((targetFrame.minX - sourceFrame.minX) * spotlightAnimationProgress),
            y: sourceFrame.minY + ((targetFrame.minY - sourceFrame.minY) * spotlightAnimationProgress),
            width: sourceFrame.width + ((targetFrame.width - sourceFrame.width) * spotlightAnimationProgress),
            height: sourceFrame.height + ((targetFrame.height - sourceFrame.height) * spotlightAnimationProgress)
        )

        return (targetFrame, currentFrame)
    }

    func hostAccessibilityLabel(
        for host: ShadowClientRemoteHostDescriptor,
        isSelected: Bool
    ) -> String {
        let selectionDetail = isSelected ? " Currently selected." : ""
        return "\(hostDisplayTitle(host)), \(host.statusLabel). Host: \(host.host).\(selectionDetail) \(hostSummaryText(host))"
    }

    func sanitizedIdentifier(_ raw: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = raw.lowercased()
            .components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return sanitized.isEmpty ? "unknown" : sanitized
    }

    var remoteDesktopHostGridColumns: [GridItem] {
        if isCompactLayout {
            return [GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 16)]
        }

        return [
            GridItem(.adaptive(minimum: 220, maximum: 260), spacing: 16),
        ]
    }

    var spotlightedRemoteDesktopHost: ShadowClientRemoteHostDescriptor? {
        guard let spotlightedHostID else {
            return nil
        }
        return remoteDesktopRuntime.hosts.first { $0.id == spotlightedHostID }
    }

    var remoteDesktopHostsAccessibilityValue: String {
        "\(remoteDesktopRuntime.hosts.count) host(s). Auto Scan \(autoFindHosts ? remoteDesktopRuntime.hostState.label : "Disabled"). Pairing \(remoteDesktopRuntime.pairingState.label)."
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

    func shouldShowPairAction(for host: ShadowClientRemoteHostDescriptor) -> Bool {
        host.isReachable && host.pairStatus != .paired
    }

    func hostRowActionColor(_ host: ShadowClientRemoteHostDescriptor, isSelected: Bool) -> Color {
        if !host.isReachable {
            return .red.opacity(0.92)
        }
        if isSelected {
            return accentColor
        }
        switch host.pairStatus {
        case .paired:
            return .mint
        case .notPaired:
            return .yellow
        case .unknown:
            return Color.white.opacity(0.72)
        }
    }

    func hostCardSurface(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isSelected
                        ? [
                            Color(red: 0.15, green: 0.20, blue: 0.27),
                            Color(red: 0.11, green: 0.16, blue: 0.22),
                        ]
                        : [
                            Color(red: 0.12, green: 0.16, blue: 0.22),
                            Color(red: 0.09, green: 0.13, blue: 0.18),
                        ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
    }

    func hostFriendlyName(for host: ShadowClientRemoteHostDescriptor) -> String {
        hostCustomizationStore.alias(forHostID: host.id)
    }

    func hostNotes(for host: ShadowClientRemoteHostDescriptor) -> String {
        hostCustomizationStore.note(forHostID: host.id)
    }

    func hostFriendlyNameBinding(for host: ShadowClientRemoteHostDescriptor) -> Binding<String> {
        Binding(
            get: { hostFriendlyName(for: host) },
            set: { hostCustomizationStore.setAlias($0, forHostID: host.id) }
        )
    }

    func hostNotesBinding(for host: ShadowClientRemoteHostDescriptor) -> Binding<String> {
        Binding(
            get: { hostNotes(for: host) },
            set: { hostCustomizationStore.setNote($0, forHostID: host.id) }
        )
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
