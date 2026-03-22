import ShadowClientStreaming
import ShadowClientUI
import SwiftUI
import ShadowUIFoundation

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

private enum RemoteHostCardMetrics {
    static let panelPadding: CGFloat = 16
    static let cardPadding: CGFloat = 18
    static let tileMinHeight: CGFloat = 252
    static let tileCornerRadius: CGFloat = 22
    static let spotlightCornerRadius: CGFloat = 24
    static let badgeCornerRadius: CGFloat = 12
    static let insetCornerRadius: CGFloat = 10
    static let glyphCornerRadius: CGFloat = 16
    static let glyphSize: CGFloat = 48
    static let headerSpacing: CGFloat = 10
    static let contentSpacing: CGFloat = 14
    static let titleStackSpacing: CGFloat = 6
    static let sectionSpacing: CGFloat = 8
    static let faceSpacing: CGFloat = 18
    static let faceHeaderSpacing: CGFloat = 12
    static let spotlightShadowRadius: CGFloat = 32
    static let spotlightShadowY: CGFloat = 18
    static let spotlightStrokeWidth: CGFloat = 2
    static let compactTargetSide: CGFloat = 420
    static let regularTargetSide: CGFloat = 560
    static let compactHorizontalInset: CGFloat = 32
    static let regularHorizontalInset: CGFloat = 104
    static let spotlightBottomInset: CGFloat = 28
    static let transitionStart = 0.34
    static let transitionEnd = 0.66
}

private struct RemoteHostFrontLayoutStyle {
    let titleFontSize: CGFloat
    let titleStackSpacing: CGFloat
    let glyphSize: CGFloat
    let glyphCornerRadius: CGFloat
    let contentSpacing: CGFloat
    let headerSpacing: CGFloat
    let footerSpacing: CGFloat
    let badgeHorizontalPadding: CGFloat
    let badgeVerticalPadding: CGFloat

    static let tile = RemoteHostFrontLayoutStyle(
        titleFontSize: 18,
        titleStackSpacing: 6,
        glyphSize: 48,
        glyphCornerRadius: 16,
        contentSpacing: 14,
        headerSpacing: 12,
        footerSpacing: 8,
        badgeHorizontalPadding: 8,
        badgeVerticalPadding: 4
    )

    static let spotlight = RemoteHostFrontLayoutStyle(
        titleFontSize: 20,
        titleStackSpacing: 8,
        glyphSize: 56,
        glyphCornerRadius: 18,
        contentSpacing: 18,
        headerSpacing: 14,
        footerSpacing: 10,
        badgeHorizontalPadding: 10,
        badgeVerticalPadding: 6
    )

    static func interpolated(progress: CGFloat) -> RemoteHostFrontLayoutStyle {
        .init(
            titleFontSize: interpolate(tile.titleFontSize, spotlight.titleFontSize, progress),
            titleStackSpacing: interpolate(tile.titleStackSpacing, spotlight.titleStackSpacing, progress),
            glyphSize: interpolate(tile.glyphSize, spotlight.glyphSize, progress),
            glyphCornerRadius: interpolate(tile.glyphCornerRadius, spotlight.glyphCornerRadius, progress),
            contentSpacing: interpolate(tile.contentSpacing, spotlight.contentSpacing, progress),
            headerSpacing: interpolate(tile.headerSpacing, spotlight.headerSpacing, progress),
            footerSpacing: interpolate(tile.footerSpacing, spotlight.footerSpacing, progress),
            badgeHorizontalPadding: interpolate(tile.badgeHorizontalPadding, spotlight.badgeHorizontalPadding, progress),
            badgeVerticalPadding: interpolate(tile.badgeVerticalPadding, spotlight.badgeVerticalPadding, progress)
        )
    }

    private static func interpolate(_ from: CGFloat, _ to: CGFloat, _ progress: CGFloat) -> CGFloat {
        from + ((to - from) * progress)
    }
}

extension ShadowClientAppShellView {
var remoteDesktopHostCard: some View {
        VStack(alignment: .leading, spacing: RemoteHostCardMetrics.panelPadding) {
            remoteDesktopHostHeader

            if isShowingManualHostEntry {
                remoteDesktopManualEntryCard
            }

            if remoteDesktopRuntime.hosts.isEmpty {
                remoteDesktopEmptyStateCard
            } else {
                LazyVGrid(columns: remoteDesktopHostGridColumns, alignment: .leading, spacing: RemoteHostCardMetrics.panelPadding) {
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
        .padding(RemoteHostCardMetrics.panelPadding)
        .background(panelSurface(cornerRadius: RemoteHostCardMetrics.panelPadding + 2))
    }

    var remoteDesktopHostHeader: some View {
        let badge = ShadowClientHostPanelPresentationKit.headerBadge(autoFindHosts: autoFindHosts)
        return HStack(spacing: RemoteHostCardMetrics.headerSpacing) {
            Label(ShadowClientHostPanelPresentationKit.headerTitle(), systemImage: "desktopcomputer")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            Label(badge.title, systemImage: badge.symbol)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(Color.white.opacity(0.88))
                .background(hostHeaderBadgeSurface, in: Capsule())

            Button {
                refreshRemoteDesktopCatalog(force: true)
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
                Text(ShadowClientHostPanelPresentationKit.manualEntryTitle())
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                ShadowClientManualHostAddressField(
                    text: $manualHostDraft,
                    portText: $manualHostPortDraft,
                    focusedField: $manualHostFocusedField
                ) {
                    addManualHostToCatalog()
                }
                .background(hostPanelInsetSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            if isCompactLayout {
                VStack(spacing: 8) {
                    Button("Add") {
                        addManualHostToCatalog()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!ShadowClientManualHostEntryKit.canSubmit(manualHostDraft, portDraft: manualHostPortDraft))

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
                    .disabled(!ShadowClientManualHostEntryKit.canSubmit(manualHostDraft, portDraft: manualHostPortDraft))

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
                Text(ShadowClientHostPanelPresentationKit.emptyStateTitle())
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white)
                Text(ShadowClientHostPanelPresentationKit.emptyStateMessage(autoFindHosts: autoFindHosts))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.76))
            }
            Spacer(minLength: 0)
        }
    }

    func remoteDesktopHostTile(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        let isSelected = remoteDesktopRuntime.selectedHostID == host.id
        let hostIdentifier = ShadowClientRemoteHostPresentationKit.sanitizedIdentifier(host.id)
        let spotlighted = spotlightedHostID == host.id

        return Button {
            presentHostSpotlight(for: host)
        } label: {
            remoteDesktopHostFrontContent(
                host,
                isSelected: isSelected,
                summaryLineLimit: 2,
                style: .tile
            )
            .frame(maxWidth: .infinity, minHeight: RemoteHostCardMetrics.tileMinHeight, alignment: .topLeading)
            .padding(RemoteHostCardMetrics.cardPadding)
            .background(hostCardSurface(isSelected: isSelected))
        }
        .buttonStyle(.plain)
        .allowsHitTesting(!spotlighted)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).row")
        .accessibilityLabel(hostAccessibilityLabel(host, isSelected: isSelected))
        .accessibilityHint(hostAccessibilityHint(host))
        .overlay(
            RoundedRectangle(cornerRadius: RemoteHostCardMetrics.tileCornerRadius, style: .continuous)
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

            remoteDesktopHostFrontFace(host, style: .tile)
                .padding(RemoteHostCardMetrics.cardPadding)
                .opacity(frontOpacity)

            remoteDesktopHostBackFace(host, interactive: interactiveBackFace)
                .padding(RemoteHostCardMetrics.cardPadding)
                .opacity(backOpacity)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0), perspective: 0.9)
        }
        .frame(width: transform.currentFrame.width, height: transform.currentFrame.height)
        .overlay(
            RoundedRectangle(cornerRadius: RemoteHostCardMetrics.spotlightCornerRadius, style: .continuous)
                .stroke(accentColor.opacity(0.90), lineWidth: RemoteHostCardMetrics.spotlightStrokeWidth)
        )
        .shadow(color: Color.black.opacity(0.34), radius: RemoteHostCardMetrics.spotlightShadowRadius, x: 0, y: RemoteHostCardMetrics.spotlightShadowY)
        .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 1.25)
        .clipShape(RoundedRectangle(cornerRadius: RemoteHostCardMetrics.spotlightCornerRadius, style: .continuous))
    }

    fileprivate func spotlightFaceOpacity(progress: Double, face: SpotlightFace) -> Double {
        let transitionStart = 0.48
        let transitionEnd = 0.52
        let normalized = min(max((progress - transitionStart) / (transitionEnd - transitionStart), 0), 1)

        switch face {
        case .front:
            return 1 - normalized
        case .back:
            return normalized
        }
    }

    fileprivate func remoteDesktopHostFrontFace(
        _ host: ShadowClientRemoteHostDescriptor,
        style: RemoteHostFrontLayoutStyle
    ) -> some View {
        remoteDesktopHostFrontContent(
            host,
            isSelected: true,
            summaryLineLimit: 2,
            style: style
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    fileprivate func remoteDesktopHostFrontContent(
        _ host: ShadowClientRemoteHostDescriptor,
        isSelected: Bool,
        summaryLineLimit: Int,
        style: RemoteHostFrontLayoutStyle
    ) -> some View {
        VStack(alignment: .leading, spacing: style.contentSpacing) {
            HStack(alignment: .top, spacing: style.headerSpacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: style.glyphCornerRadius, style: .continuous)
                        .fill(hostGlyphColor(host).opacity(0.16))
                        .frame(width: style.glyphSize, height: style.glyphSize)

                    Image(systemName: hostGlyphSymbol(host))
                        .font(.title3.weight(.bold))
                        .foregroundStyle(hostGlyphColor(host))
                }

                VStack(alignment: .leading, spacing: style.titleStackSpacing) {
                    Text(hostDisplayTitle(host))
                        .font(.system(size: style.titleFontSize, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    Text(host.host)
                        .font(.footnote.monospaced())
                        .foregroundStyle(Color.white.opacity(0.70))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: style.headerSpacing)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(accentColor)
                }
            }

            VStack(alignment: .leading, spacing: RemoteHostCardMetrics.sectionSpacing) {
                Text(host.statusLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(remoteHostStatusColor(host))
                    .padding(.horizontal, style.badgeHorizontalPadding)
                    .padding(.vertical, style.badgeVerticalPadding)
                    .background(remoteHostStatusColor(host).opacity(0.14), in: Capsule())
            }

            Text(hostSummaryText(host))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(host.lastError == nil ? Color.white.opacity(0.76) : .red.opacity(0.92))
                .lineLimit(summaryLineLimit)

            Spacer(minLength: 0)

            HStack(spacing: style.footerSpacing) {
                Label(hostTileActionLabel(host), systemImage: hostFrontHintSymbol(host))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(hostFrontHintColor(host))

                Spacer(minLength: style.footerSpacing)

                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.46))
            }
        }
    }

    func remoteDesktopHostBackFace(_ host: ShadowClientRemoteHostDescriptor, interactive: Bool) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
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

                if host.pairStatus == .paired {
                    Button(role: .destructive) {
                        let dismissingHostID = spotlightedHostID
                        dismissHostSpotlight()
                        deleteStoredHost(host)
                        if dismissingHostID == host.id {
                            spotlightedHostID = nil
                        }
                    } label: {
                        Label("Delete Device", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .allowsHitTesting(interactive)
                }

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
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func remoteDesktopHostMetadataEditor(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Friendly Name")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.68))
                ShadowUIHostInsetField {
                    ShadowClientPlatformTextField(
                        text: hostFriendlyNameBinding(host),
                        placeholder: "Use the discovered name",
                        accessibilityLabel: "Friendly name",
                        fontWeight: .semibold
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.68))
                ShadowUIHostInsetField {
                    ShadowClientPlatformTextView(
                        text: hostNotesBinding(host),
                        placeholder: "Add a note for this device",
                        accessibilityLabel: "Device notes",
                        showsDoneToolbar: true
                    )
                    .frame(minHeight: 64)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Wake on LAN")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.68))

                ShadowUIHostInsetCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ShadowUIHostInsetField {
                            ShadowClientPlatformTextField(
                                text: hostWakeOnLANMACAddressBinding(host),
                                placeholder: "AA:BB:CC:DD:EE:FF",
                                accessibilityLabel: "Wake on LAN MAC address",
                                keyboardType: .ascii,
                                usesMonospacedFont: true,
                                fontWeight: .semibold
                            )
                        }

                        ShadowUIHostInsetField {
                            ShadowClientPlatformTextField(
                                text: hostWakeOnLANPortBinding(host),
                                placeholder: String(ShadowClientWakeOnLANKit.defaultPort),
                                accessibilityLabel: "Wake on LAN UDP port",
                                keyboardType: .numberPad,
                                usesMonospacedFont: true,
                                fontWeight: .semibold
                            )
                        }

                        if usesDiscoveredWakeOnLANMAC(host) {
                            Text("Using the MAC address discovered from host metadata.")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.68))
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                Button("Send Magic Packet") {
                                    remoteDesktopRuntime.wakeSelectedHost(
                                        macAddress: effectiveWakeOnLANMACAddress(for: host),
                                        port: effectiveWakeOnLANPort(for: host)
                                    )
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    remoteDesktopRuntime.selectedHostID != host.id ||
                                        !canWakeHost(host)
                                )

                                Text(hostWakeOnLANStateLabel(for: host))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.68))
                                    .lineLimit(2)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Button("Send Magic Packet") {
                                    remoteDesktopRuntime.wakeSelectedHost(
                                        macAddress: effectiveWakeOnLANMACAddress(for: host),
                                        port: effectiveWakeOnLANPort(for: host)
                                    )
                                }
                                .buttonStyle(.bordered)
                                .disabled(
                                    remoteDesktopRuntime.selectedHostID != host.id ||
                                        !canWakeHost(host)
                                )

                                Text(hostWakeOnLANStateLabel(for: host))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.68))
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Apollo Admin")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.68))

                ShadowUIHostInsetCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ShadowUIHostInsetField {
                            ShadowClientPlatformTextField(
                                text: hostApolloAdminUsernameBinding(host),
                                placeholder: "Admin username",
                                accessibilityLabel: "Apollo admin username",
                                fontWeight: .semibold
                            )
                        }

                        ShadowUIHostInsetField {
                            ShadowClientPlatformTextField(
                                text: hostApolloAdminPasswordBinding(host),
                                placeholder: "Admin password",
                                accessibilityLabel: "Apollo admin password",
                                fontWeight: .semibold,
                                isSecureTextEntry: true
                            )
                        }

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                Button("Sync Apollo Client") {
                                    remoteDesktopRuntime.refreshSelectedHostApolloAdmin(
                                        username: hostApolloAdminUsername(host),
                                        password: hostApolloAdminPassword(host)
                                    )
                                }
                                .buttonStyle(.bordered)
                                .disabled(remoteDesktopRuntime.selectedHostID != host.id)

                                Text(hostApolloAdminStateLabel(for: host))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.68))
                                    .lineLimit(1)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Button("Sync Apollo Client") {
                                    remoteDesktopRuntime.refreshSelectedHostApolloAdmin(
                                        username: hostApolloAdminUsername(host),
                                        password: hostApolloAdminPassword(host)
                                    )
                                }
                                .buttonStyle(.bordered)
                                .disabled(remoteDesktopRuntime.selectedHostID != host.id)

                                Text(hostApolloAdminStateLabel(for: host))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Color.white.opacity(0.68))
                            }
                        }
                    }
                }

                if hostApolloAdminProfile(host) != nil {
                    ShadowUIHostInsetCard {
                        VStack(alignment: .leading, spacing: 10) {
                            ShadowUIHostInsetField {
                                ShadowClientPlatformTextField(
                                    text: hostApolloDisplayModeBinding(for: host),
                                    placeholder: "Display mode override",
                                    accessibilityLabel: "Apollo display mode override",
                                    fontWeight: .semibold
                                )
                            }

                            Toggle(isOn: hostApolloAlwaysUseVirtualDisplayBinding(for: host)) {
                                Text("Always use virtual display")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                            .tint(.mint)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Apollo Permissions")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Color.white.opacity(0.68))

                                ForEach(ShadowClientApolloPermission.allCases, id: \.self) { permission in
                                    Toggle(isOn: hostApolloPermissionBinding(for: host, permission: permission)) {
                                        Text(permission.label)
                                            .font(.callout.weight(.semibold))
                                            .foregroundStyle(.white)
                                    }
                                    .tint(.mint)
                                }
                            }

                            Button("Save Apollo Overrides") {
                                remoteDesktopRuntime.updateSelectedHostApolloAdmin(
                                    username: hostApolloAdminUsername(host),
                                    password: hostApolloAdminPassword(host),
                                    displayModeOverride: hostApolloDisplayModeDraft(for: host),
                                    alwaysUseVirtualDisplay: hostApolloAlwaysUseVirtualDisplayDraft(for: host),
                                    permissions: hostApolloPermissionDraft(for: host)
                                )
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(remoteDesktopRuntime.selectedHostID != host.id)

                            ViewThatFits(in: .horizontal) {
                                HStack(spacing: 10) {
                                    Button("Disconnect Client") {
                                        remoteDesktopRuntime.disconnectSelectedHostApolloAdmin(
                                            username: hostApolloAdminUsername(host),
                                            password: hostApolloAdminPassword(host)
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(remoteDesktopRuntime.selectedHostID != host.id)

                                    Button("Unpair Client") {
                                        remoteDesktopRuntime.unpairSelectedHostApolloAdmin(
                                            username: hostApolloAdminUsername(host),
                                            password: hostApolloAdminPassword(host)
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(remoteDesktopRuntime.selectedHostID != host.id)
                                }

                                VStack(spacing: 8) {
                                    Button("Disconnect Client") {
                                        remoteDesktopRuntime.disconnectSelectedHostApolloAdmin(
                                            username: hostApolloAdminUsername(host),
                                            password: hostApolloAdminPassword(host)
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(remoteDesktopRuntime.selectedHostID != host.id)

                                    Button("Unpair Client") {
                                        remoteDesktopRuntime.unpairSelectedHostApolloAdmin(
                                            username: hostApolloAdminUsername(host),
                                            password: hostApolloAdminPassword(host)
                                        )
                                    }
                                    .buttonStyle(.bordered)
                                    .disabled(remoteDesktopRuntime.selectedHostID != host.id)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func remoteDesktopHostStatusCallout(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        let apolloSummary = hostApolloAdminProfile(host).map(hostApolloAdminSummary)
        let callouts = ShadowClientHostSpotlightPresentationKit.statusCallouts(
            host: host,
            issue: hostPresentationIssue(host),
            apolloSummary: apolloSummary
        )
        if !callouts.isEmpty {
            ForEach(Array(callouts.enumerated()), id: \.offset) { _, callout in
                remoteDesktopCalloutRow(
                    title: callout.title,
                    message: callout.message,
                    accent: ShadowClientHostSpotlightPresentationKit.accentColor(for: callout.tone)
                )
            }
        }
    }

    func hostPresentationIssue(_ host: ShadowClientRemoteHostDescriptor) -> ShadowClientRemoteHostIssuePresentation? {
        ShadowClientRemoteHostIssueMapper.issue(
            for: host,
            selectedHostID: remoteDesktopRuntime.selectedHostID,
            appState: remoteDesktopRuntime.appState,
            launchState: remoteDesktopRuntime.launchState,
            sessionIssue: remoteDesktopRuntime.sessionIssue
        )
    }

    func remoteDesktopHostActionBar(_ host: ShadowClientRemoteHostDescriptor) -> some View {
        Group {
            if isCompactLayout {
                VStack(alignment: .leading, spacing: 8) {
                    selectedHostPrimaryActionButtons(for: host, fullWidth: true)
                    if shouldShowPairAction(for: host) {
                        pairSelectedHostButton(fullWidth: true)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    selectedHostPrimaryActionButtons(for: host, fullWidth: false)
                    if shouldShowPairAction(for: host) {
                        pairSelectedHostButton(fullWidth: false)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func selectedHostPrimaryActionButtons(
        for host: ShadowClientRemoteHostDescriptor,
        fullWidth: Bool
    ) -> some View {
        Group {
            if host.currentGameID > 0 {
                if fullWidth {
                    VStack(alignment: .leading, spacing: 8) {
                        goSelectedHostButton(for: host, fullWidth: true)
                        stopSelectedHostButton(fullWidth: true)
                    }
                } else {
                    HStack(spacing: 8) {
                        goSelectedHostButton(for: host, fullWidth: false)
                        stopSelectedHostButton(fullWidth: false)
                    }
                }
            } else {
                goSelectedHostButton(for: host, fullWidth: fullWidth)
            }
        }
    }

    func goSelectedHostButton(
        for host: ShadowClientRemoteHostDescriptor,
        fullWidth: Bool
    ) -> some View {
        Button("Start") {
            connectionHost = connectionCandidate(for: host)
            connectToHost(autoLaunchAfterConnect: true, preferredHostID: host.id)
        }
        .accessibilityIdentifier("shadow.home.hosts.go-selected")
        .accessibilityLabel("Start selected host")
        .accessibilityHint(
            ShadowClientHostAppLibraryPresentationKit.primaryActionHint(
                hostTitle: hostDisplayTitle(host),
                canConnect: hostCanConnect(host)
            )
        )
        .buttonStyle(.borderedProminent)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .disabled(!hostCanConnect(host))
    }

    func stopSelectedHostButton(fullWidth: Bool) -> some View {
        Button("Stop") {
            remoteDesktopRuntime.clearActiveSession()
        }
        .accessibilityIdentifier("shadow.home.hosts.stop-selected")
        .accessibilityLabel("Stop selected host session")
        .accessibilityHint("Stops the active streaming session on the selected host.")
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .frame(maxWidth: fullWidth ? .infinity : nil)
    }

    @ViewBuilder
    func pairSelectedHostButton(fullWidth: Bool) -> some View {
        if canPairSelectedHost {
            Button("Pair") {
                if let selectedHost = remoteDesktopRuntime.selectedHost {
                    connectionHost = connectionCandidate(for: selectedHost)
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
                Text(ShadowClientHostAppLibraryPresentationKit.sectionTitle())
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
                let callout = ShadowClientHostAppLibraryPresentationKit.lockedCallout()
                remoteDesktopCalloutRow(
                    title: callout.title,
                    message: callout.message,
                    accent: ShadowClientHostSpotlightPresentationKit.accentColor(for: callout.tone)
                )
            } else if remoteDesktopRuntime.apps.isEmpty {
                let callout = ShadowClientHostAppLibraryPresentationKit.emptyCallout()
                remoteDesktopCalloutRow(
                    title: callout.title,
                    message: callout.message,
                    accent: ShadowClientHostSpotlightPresentationKit.accentColor(for: callout.tone)
                )
            } else {
                ForEach(remoteDesktopRuntime.apps.prefix(5)) { app in
                    let appIdentifier = ShadowClientRemoteHostPresentationKit.sanitizedIdentifier(String(app.id))
                    ShadowUIHostAppRow(
                        title: app.title,
                        subtitle: ShadowClientHostAppLibraryPresentationKit.metadata(
                            appID: app.id,
                            hdrSupported: app.hdrSupported
                        ),
                        launchTitle: "Launch",
                        launchAccessibilityLabel: "Launch \(app.title)",
                        launchAccessibilityHint: ShadowClientHostAppLibraryPresentationKit.launchAccessibilityHint(),
                        launchAccessibilityIdentifier: "shadow.home.applist.launch.\(appIdentifier)",
                        launchDisabled: remoteDesktopRuntime.launchState.isTransitioning
                    ) {
                        launchRemoteApp(app)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    func remoteDesktopCalloutRow(title: String, message: String, accent: Color) -> some View {
        ShadowUIHostCalloutRow(title: title, message: message, accent: accent)
    }

    func hostDisplayTitle(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientRemoteHostPresentationKit.displayTitle(
            hostPresentationInput(for: host)
        )
    }

    func hostSummaryText(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientRemoteHostPresentationKit.summaryText(
            hostPresentationInput(for: host)
        )
    }

    func hostTileActionLabel(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientRemoteHostPresentationKit.tileActionLabel(
            hostPresentationInput(for: host)
        )
    }

    func hostFrontHint(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientRemoteHostPresentationKit.frontHint(
            hostPresentationInput(for: host)
        )
    }

    func hostFrontHintSymbol(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientRemoteHostPresentationKit.frontHintSymbol(
            hostPresentationInput(for: host)
        )
    }

    func hostFrontHintColor(_ host: ShadowClientRemoteHostDescriptor) -> Color {
        ShadowClientRemoteHostPresentationKit.frontHintColor(
            hostPresentationInput(for: host)
        )
    }

    func hostFrontMessage(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientRemoteHostPresentationKit.frontMessage(
            hostPresentationInput(for: host)
        )
    }

    func hostGlyphSymbol(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientRemoteHostPresentationKit.glyphSymbol(
            hostPresentationInput(for: host)
        )
    }

    func hostGlyphColor(_ host: ShadowClientRemoteHostDescriptor) -> Color {
        ShadowClientRemoteHostPresentationKit.glyphColor(
            hostPresentationInput(for: host)
        )
    }

    private func hostPresentationInput(for host: ShadowClientRemoteHostDescriptor) -> ShadowClientRemoteHostPresentationInput {
        .init(
            host: host,
            issue: hostPresentationIssue(host),
            alias: hostFriendlyName(host),
            notes: hostNotes(host)
        )
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
        ShadowUIHostPanelPalette.panelInsetSurface
    }

    var hostHeaderBadgeSurface: some ShapeStyle {
        ShadowUIHostPanelPalette.headerBadgeSurface
    }

    var hostSpotlightInsetSurface: some ShapeStyle {
        ShadowUIHostPanelPalette.spotlightInsetSurface
    }

    var hostSpotlightBadgeSurface: some ShapeStyle {
        ShadowUIHostPanelPalette.spotlightBadgeSurface
    }

    func spotlightTransform(in containerSize: CGSize) -> (
        targetFrame: CGRect,
        currentFrame: CGRect
    ) {
        let sourceFrame = spotlightedHostSourceFrame == .zero
            ? CGRect(x: (containerSize.width - 260) / 2, y: 72, width: 260, height: 252)
            : spotlightedHostSourceFrame
        let horizontalTargetSide = min(
            containerSize.width - CGFloat(isCompactLayout ? 32 : 104),
            CGFloat(isCompactLayout ? 420 : 560)
        )
        let verticalTargetSide = max(
            sourceFrame.height,
            containerSize.height - sourceFrame.minY - RemoteHostCardMetrics.spotlightBottomInset
        )
        let targetSide = min(horizontalTargetSide, verticalTargetSide)
        let targetFrame = CGRect(
            x: (containerSize.width - targetSide) / 2,
            y: sourceFrame.minY,
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
        _ host: ShadowClientRemoteHostDescriptor,
        isSelected: Bool
    ) -> String {
        ShadowClientRemoteHostPresentationKit.accessibilityLabel(
            hostPresentationInput(for: host),
            isSelected: isSelected
        )
    }

    func hostAccessibilityHint(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientRemoteHostPresentationKit.spotlightAccessibilityHint(
            hostPresentationInput(for: host)
        )
    }

    var remoteDesktopHostGridColumns: [GridItem] {
        if isCompactLayout {
            return [GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 16)]
        }

        return [
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 16),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 16),
            GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 16),
        ]
    }

    var spotlightedRemoteDesktopHost: ShadowClientRemoteHostDescriptor? {
        guard let spotlightedHostID else {
            return nil
        }
        return remoteDesktopRuntime.hosts.first { $0.id == spotlightedHostID }
    }

    var remoteDesktopHostsAccessibilityValue: String {
        ShadowClientHostPanelPresentationKit.hostsAccessibilityValue(
            hostCount: remoteDesktopRuntime.hosts.count,
            autoFindHosts: autoFindHosts,
            hostStateLabel: remoteDesktopRuntime.hostState.label,
            pairingStateLabel: remoteDesktopRuntime.pairingState.label
        )
    }

    var canPairSelectedHost: Bool {
        ShadowClientRemoteHostActionKit.canPair(
            selectedHost: remoteDesktopRuntime.selectedHost
        )
    }

    var canRefreshSelectedHostApps: Bool {
        ShadowClientRemoteHostActionKit.canRefreshApps(
            selectedHost: remoteDesktopRuntime.selectedHost
        )
    }

    func hostCanConnect(_ host: ShadowClientRemoteHostDescriptor) -> Bool {
        ShadowClientRemoteHostActionKit.canConnect(
            host: host,
            canInitiateSessionConnection: canInitiateSessionConnection
        )
    }

    func shouldShowPairAction(for host: ShadowClientRemoteHostDescriptor) -> Bool {
        ShadowClientRemoteHostActionKit.shouldShowPairAction(host: host)
    }

    func hostRowActionColor(_ host: ShadowClientRemoteHostDescriptor, isSelected: Bool) -> Color {
        ShadowClientRemoteHostActionKit.rowActionColor(
            host: host,
            isSelected: isSelected,
            accentColor: accentColor
        )
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

    func hostFriendlyName(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientHostCustomizationKit.friendlyName(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostNotes(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientHostCustomizationKit.notes(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostFriendlyNameBinding(_ host: ShadowClientRemoteHostDescriptor) -> Binding<String> {
        ShadowClientHostCustomizationKit.friendlyNameBinding(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostNotesBinding(_ host: ShadowClientRemoteHostDescriptor) -> Binding<String> {
        ShadowClientHostCustomizationKit.notesBinding(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostWakeOnLANMACAddress(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientHostCustomizationKit.wakeOnLANMACAddress(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostWakeOnLANPort(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientHostCustomizationKit.wakeOnLANPort(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostWakeOnLANMACAddressBinding(_ host: ShadowClientRemoteHostDescriptor) -> Binding<String> {
        ShadowClientHostCustomizationKit.wakeOnLANMACAddressBinding(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostWakeOnLANPortBinding(_ host: ShadowClientRemoteHostDescriptor) -> Binding<String> {
        ShadowClientHostCustomizationKit.wakeOnLANPortBinding(
            store: hostCustomizationStore,
            host: host
        )
    }

    func effectiveWakeOnLANMACAddress(for host: ShadowClientRemoteHostDescriptor) -> String {
        hostWakeOnLANMACAddress(host)
    }

    func effectiveWakeOnLANPort(for host: ShadowClientRemoteHostDescriptor) -> UInt16 {
        ShadowClientWakeOnLANKit.resolvedPort(from: hostWakeOnLANPort(host))
    }

    func canWakeHost(_ host: ShadowClientRemoteHostDescriptor) -> Bool {
        let hasValidMACAddress = ShadowClientWakeOnLANKit.normalizedMACAddress(
            effectiveWakeOnLANMACAddress(for: host)
        ) != nil
        let wakeOnLANPortDraft = hostWakeOnLANPort(host).trimmingCharacters(in: .whitespacesAndNewlines)
        let hasValidPort = wakeOnLANPortDraft.isEmpty ||
            ShadowClientWakeOnLANKit.parsedPort(from: wakeOnLANPortDraft) != nil
        return hasValidMACAddress && hasValidPort
    }

    func usesDiscoveredWakeOnLANMAC(_ host: ShadowClientRemoteHostDescriptor) -> Bool {
        let stored = hostCustomizationStore.wakeOnLANMACAddress(forHostID: host.id)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stored.isEmpty && host.macAddress != nil
    }

    func hostWakeOnLANStateLabel(for host: ShadowClientRemoteHostDescriptor) -> String {
        guard remoteDesktopRuntime.selectedHostID == host.id else {
            return "Select this host first"
        }
        return remoteDesktopRuntime.selectedHostWakeState.label
    }

    func hostApolloAdminUsername(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientHostCustomizationKit.apolloAdminUsername(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostApolloAdminPassword(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientHostCustomizationKit.apolloAdminPassword(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostApolloAdminUsernameBinding(_ host: ShadowClientRemoteHostDescriptor) -> Binding<String> {
        ShadowClientHostCustomizationKit.apolloAdminUsernameBinding(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostApolloAdminPasswordBinding(_ host: ShadowClientRemoteHostDescriptor) -> Binding<String> {
        ShadowClientHostCustomizationKit.apolloAdminPasswordBinding(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostApolloAdminProfile(_ host: ShadowClientRemoteHostDescriptor) -> ShadowClientApolloAdminClientProfile? {
        guard remoteDesktopRuntime.selectedHostID == host.id else {
            return nil
        }
        return remoteDesktopRuntime.selectedHostApolloAdminProfile
    }

    func hostApolloAdminStateLabel(for host: ShadowClientRemoteHostDescriptor) -> String {
        guard remoteDesktopRuntime.selectedHostID == host.id else {
            return "Select this host first"
        }

        switch remoteDesktopRuntime.selectedHostApolloAdminState {
        case let state:
            return ShadowClientApolloAdminPresentationKit.stateLabel(
                state: state,
                selectedProfile: remoteDesktopRuntime.selectedHostApolloAdminProfile
            )
        }
    }

    func hostApolloAdminSummary(_ profile: ShadowClientApolloAdminClientProfile) -> String {
        ShadowClientApolloAdminPresentationKit.summary(profile)
    }

    func hostApolloDisplayModeDraft(for host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientApolloAdminPresentationKit.displayModeDraft(
            hostID: host.id,
            drafts: apolloDisplayModeDrafts,
            profile: hostApolloAdminProfile(host)
        )
    }

    func hostApolloAlwaysUseVirtualDisplayDraft(for host: ShadowClientRemoteHostDescriptor) -> Bool {
        ShadowClientApolloAdminPresentationKit.alwaysUseVirtualDisplayDraft(
            hostID: host.id,
            drafts: apolloAlwaysUseVirtualDisplayDrafts,
            profile: hostApolloAdminProfile(host)
        )
    }

    func hostApolloPermissionDraft(for host: ShadowClientRemoteHostDescriptor) -> UInt32 {
        ShadowClientApolloAdminPresentationKit.permissionDraft(
            hostID: host.id,
            drafts: apolloPermissionDrafts,
            profile: hostApolloAdminProfile(host)
        )
    }

    func hostApolloDisplayModeBinding(for host: ShadowClientRemoteHostDescriptor) -> Binding<String> {
        Binding(
            get: { hostApolloDisplayModeDraft(for: host) },
            set: { apolloDisplayModeDrafts[host.id] = $0 }
        )
    }

    func hostApolloAlwaysUseVirtualDisplayBinding(for host: ShadowClientRemoteHostDescriptor) -> Binding<Bool> {
        Binding(
            get: { hostApolloAlwaysUseVirtualDisplayDraft(for: host) },
            set: { apolloAlwaysUseVirtualDisplayDrafts[host.id] = $0 }
        )
    }

    func hostApolloPermissionBinding(
        for host: ShadowClientRemoteHostDescriptor,
        permission: ShadowClientApolloPermission
    ) -> Binding<Bool> {
        Binding(
            get: {
                ShadowClientApolloPermission.contains(
                    permission,
                    in: hostApolloPermissionDraft(for: host)
                )
            },
            set: { enabled in
                apolloPermissionDrafts[host.id] = ShadowClientApolloPermission.updating(
                    permission,
                    enabled: enabled,
                    in: hostApolloPermissionDraft(for: host)
                )
            }
        )
    }

var connectionStatusCard: some View {
        ShadowUIConnectionStatusCard(
            title: "Client Connection",
            statusText: connectionStatusText,
            indicatorColor: connectionStatusColor
        )
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("shadow.home.connection-status")
        .accessibilityLabel("Client Connection")
        .accessibilityValue(connectionStatusText)
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
