import ShadowClientStreaming
import ShadowClientUI
import ShadowClientFeatureConnection
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

enum RemoteHostCardMetrics {
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
    static let quickConnectReservationWidth: CGFloat = 96
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
                    text: manualHostDraftBinding,
                    portText: manualHostPortDraftBinding,
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
        let canQuickConnect = hostCanConnect(host)

        return ZStack(alignment: .bottomTrailing) {
            Button {
                presentHostSpotlight(for: host)
            } label: {
                remoteDesktopHostFrontContent(
                    host,
                    isSelected: isSelected,
                    summaryLineLimit: 2,
                    style: .tile,
                    reservesTrailingActionSpace: canQuickConnect
                )
                .frame(maxWidth: .infinity, minHeight: RemoteHostCardMetrics.tileMinHeight, alignment: .topLeading)
                .padding(RemoteHostCardMetrics.cardPadding)
                .background(hostCardSurface(isSelected: isSelected))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).row")
            .accessibilityLabel(hostAccessibilityLabel(host, isSelected: isSelected))
            .accessibilityHint(hostAccessibilityHint(host))

            if canQuickConnect {
                Button(ShadowClientDiscoveredHostPresentationKit.connectButtonTitle()) {
                    startRemoteHostSession(host)
                }
                .accessibilityIdentifier("shadow.home.host.\(hostIdentifier).quick-connect")
                .accessibilityLabel("Connect to \(hostDisplayTitle(host))")
                .accessibilityHint(
                    ShadowClientHostAppLibraryPresentationKit.primaryActionHint(
                        hostTitle: hostDisplayTitle(host),
                        canConnect: true
                    )
                )
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .padding(RemoteHostCardMetrics.cardPadding)
            }
        }
        .allowsHitTesting(!spotlighted)
        .accessibilityElement(children: .contain)
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

    fileprivate func remoteDesktopHostFrontContent(
        _ host: ShadowClientRemoteHostDescriptor,
        isSelected: Bool,
        summaryLineLimit: Int,
        style: RemoteHostFrontLayoutStyle,
        reservesTrailingActionSpace: Bool = false
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

                if reservesTrailingActionSpace {
                    Color.clear
                        .frame(width: RemoteHostCardMetrics.quickConnectReservationWidth, height: 1)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.white.opacity(0.46))
                }
            }
        }
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
}
