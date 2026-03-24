import ShadowClientStreaming
import ShadowClientUI
import ShadowClientFeatureConnection
import SwiftUI
import ShadowUIFoundation

extension ShadowClientAppShellView {
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
                Text("Connection Address")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.white.opacity(0.68))
                ShadowUIHostInsetCard {
                    VStack(alignment: .leading, spacing: 10) {
                        ShadowUIHostInsetField {
                            ShadowClientPlatformTextField(
                                text: hostAddressBinding(for: host),
                                placeholder: connectionCandidate(for: host),
                                accessibilityLabel: "Connection address",
                                keyboardType: .ascii,
                                usesMonospacedFont: true,
                                fontWeight: .semibold
                            )
                        }

                        Button("Save Address") {
                            let updatedAddress = hostAddressDraft(for: host)
                            remoteDesktopRuntime.updateSavedHostCandidate(
                                forHostID: host.id,
                                host: updatedAddress
                            )
                            connectionHost = updatedAddress
                            refreshRemoteDesktopCatalog(force: true)
                        }
                        .buttonStyle(.bordered)

                        Text(hostAddressSummary(for: host))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.white.opacity(0.68))
                    }
                }
            }

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
            startRemoteHostSession(host)
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
}
