import ShadowClientStreaming
import ShadowClientUI
import ShadowClientFeatureConnection
import SwiftUI
import ShadowUIFoundation

extension ShadowClientAppShellView {
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
        let progress = spotlightAnimationProgress
        let currentX = sourceFrame.minX + ((targetFrame.minX - sourceFrame.minX) * progress)
        let currentY = sourceFrame.minY + ((targetFrame.minY - sourceFrame.minY) * progress)
        let currentWidth = sourceFrame.width + ((targetFrame.width - sourceFrame.width) * progress)
        let currentHeight = sourceFrame.height + ((targetFrame.height - sourceFrame.height) * progress)
        let currentFrame = CGRect(
            x: currentX,
            y: currentY,
            width: currentWidth,
            height: currentHeight
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

    func hostAddressDraft(for host: ShadowClientRemoteHostDescriptor) -> String {
        let draft = hostAddressDrafts[host.id]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !draft.isEmpty {
            return draft
        }
        return connectionCandidate(for: host)
    }

    func hostAddressBinding(for host: ShadowClientRemoteHostDescriptor) -> Binding<String> {
        Binding(
            get: { hostAddressDraft(for: host) },
            set: { hostAddressDrafts[host.id] = $0 }
        )
    }

    func hostAddressSummary(for host: ShadowClientRemoteHostDescriptor) -> String {
        let routeLabels = [
            host.routes.local.map { "Local: \(connectionCandidateLabel(for: $0))" },
            host.routes.remote.map { "External: \(connectionCandidateLabel(for: $0))" },
            host.routes.manual.map { "Override: \(connectionCandidateLabel(for: $0))" },
        ]
        .compactMap { $0 }

        if routeLabels.isEmpty {
            return "This card uses the address you save here as its primary route."
        }

        return routeLabels.joined(separator: " | ")
    }

    private func connectionCandidateLabel(for endpoint: ShadowClientRemoteHostEndpoint) -> String {
        if endpoint.httpsPort == ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort {
            return endpoint.host
        }
        return "\(endpoint.host):\(endpoint.httpsPort)"
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

    func hostLumenAdminUsername(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientHostCustomizationKit.lumenAdminUsername(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostLumenAdminPassword(_ host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientHostCustomizationKit.lumenAdminPassword(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostLumenAdminUsernameBinding(_ host: ShadowClientRemoteHostDescriptor) -> Binding<String> {
        ShadowClientHostCustomizationKit.lumenAdminUsernameBinding(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostLumenAdminPasswordBinding(_ host: ShadowClientRemoteHostDescriptor) -> Binding<String> {
        ShadowClientHostCustomizationKit.lumenAdminPasswordBinding(
            store: hostCustomizationStore,
            host: host
        )
    }

    func hostLumenAdminProfile(_ host: ShadowClientRemoteHostDescriptor) -> ShadowClientLumenAdminClientProfile? {
        guard remoteDesktopRuntime.selectedHostID == host.id else {
            return nil
        }
        return remoteDesktopRuntime.selectedHostLumenAdminProfile
    }

    func hostAuthenticationState(_ host: ShadowClientRemoteHostDescriptor) -> ShadowClientRemoteHostAuthenticationState {
        guard remoteDesktopRuntime.selectedHostID == host.id,
              let selectedState = remoteDesktopRuntime.selectedHostAuthenticationState
        else {
            return host.authenticationState
        }
        return selectedState
    }

    func hostLumenAdminStateLabel(for host: ShadowClientRemoteHostDescriptor) -> String {
        guard remoteDesktopRuntime.selectedHostID == host.id else {
            return "Select this host first"
        }
        return hostAuthenticationState(host).adminStatusLabel
    }

    func hostLumenAdminSummary(_ profile: ShadowClientLumenAdminClientProfile) -> String {
        ShadowClientLumenAdminPresentationKit.summary(profile)
    }

    func hostLumenDisplayModeDraft(for host: ShadowClientRemoteHostDescriptor) -> String {
        ShadowClientLumenAdminPresentationKit.displayModeDraft(
            hostID: host.id,
            drafts: lumenDisplayModeDrafts,
            profile: hostLumenAdminProfile(host)
        )
    }

    func hostLumenAlwaysUseVirtualDisplayDraft(for host: ShadowClientRemoteHostDescriptor) -> Bool {
        ShadowClientLumenAdminPresentationKit.alwaysUseVirtualDisplayDraft(
            hostID: host.id,
            drafts: lumenAlwaysUseVirtualDisplayDrafts,
            profile: hostLumenAdminProfile(host)
        )
    }

    func hostLumenPermissionDraft(for host: ShadowClientRemoteHostDescriptor) -> UInt32 {
        ShadowClientLumenAdminPresentationKit.permissionDraft(
            hostID: host.id,
            drafts: lumenPermissionDrafts,
            profile: hostLumenAdminProfile(host)
        )
    }

    func hostLumenDisplayModeBinding(for host: ShadowClientRemoteHostDescriptor) -> Binding<String> {
        Binding(
            get: { hostLumenDisplayModeDraft(for: host) },
            set: { lumenDisplayModeDrafts[host.id] = $0 }
        )
    }

    func hostLumenAlwaysUseVirtualDisplayBinding(for host: ShadowClientRemoteHostDescriptor) -> Binding<Bool> {
        Binding(
            get: { hostLumenAlwaysUseVirtualDisplayDraft(for: host) },
            set: { lumenAlwaysUseVirtualDisplayDrafts[host.id] = $0 }
        )
    }

    func hostLumenPermissionBinding(
        for host: ShadowClientRemoteHostDescriptor,
        permission: ShadowClientLumenPermission
    ) -> Binding<Bool> {
        Binding(
            get: {
                ShadowClientLumenPermission.contains(
                    permission,
                    in: hostLumenPermissionDraft(for: host)
                )
            },
            set: { enabled in
                lumenPermissionDrafts[host.id] = ShadowClientLumenPermission.updating(
                    permission,
                    enabled: enabled,
                    in: hostLumenPermissionDraft(for: host)
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
        switch hostAuthenticationState(host).hostIndicatorTone {
        case .neutral:
            return Color.white.opacity(0.78)
        case .unavailable:
            return .red
        case .ready:
            return .green
        case .pairingRequired:
            return .yellow
        case .streaming:
            return .orange
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
