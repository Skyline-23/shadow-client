import ShadowClientStreaming
import ShadowClientUI
import SwiftUI
import ShadowUIFoundation

extension ShadowClientAppShellView {
    @ViewBuilder
var remoteSessionFlowView: some View {
        if remoteDesktopRuntime.activeSession != nil {
            ZStack {
                Color.black

                ZStack {
                    ShadowClientRealtimeSessionSurfaceView(
                        context: sessionSurfaceContext
                    )
                    .padding(remoteSessionSafeAreaInsets)
                    .accessibilityIdentifier("shadow.remote.session.surface")
                    .accessibilityLabel("Remote Session Surface")

                    if let overlay = sessionPresentationModel.overlay {
                        ZStack {
                            Color.black
                                .opacity(ShadowClientRemoteSessionOverlayPresentationKit.dimOpacity(for: sessionPresentationModel.launchTone))
                                .ignoresSafeArea()

                            playbackOverlayLabel(
                                overlay.title,
                                symbol: overlay.symbol,
                                tone: sessionPresentationModel.launchTone
                            )
                            .padding(.horizontal, 20)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    }

                    if let hudDisplayState = realtimeSessionHUDDisplayState {
                        VStack {
                            HStack {
                                Spacer()
                                switch hudDisplayState {
                                case let .telemetry(model):
                                    realtimeSessionDiagnosticsHUD(model)
                                case let .waitingForTelemetry(controlRoundTripMs):
                                    realtimeSessionBootstrapDiagnosticsHUD(controlRoundTripMs: controlRoundTripMs)
                                case let .connectionIssue(title, message):
                                    realtimeSessionConnectionIssueHUD(
                                        title: title,
                                        message: message
                                    )
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.top, 12)
                        .padding(.trailing, 12)
                        .safeAreaPadding([.top, .trailing])
                        .allowsHitTesting(false)
                    }

                    ShadowClientSessionInputInteractionView(
                        referenceVideoSize: sessionSurfaceContext.videoPresentationSize,
                        visiblePointerRegions: sessionVisiblePointerRegions
                    ) { event in
                        remoteDesktopRuntime.sendInput(event)
                    } onSessionTerminateCommand: {
                        remoteDesktopRuntime.clearActiveSession()
                    } onCopyClipboardCommand: {
                        copyRemoteClipboardIntoLocalClipboard()
                    } onPasteClipboardCommand: {
                        pasteLocalClipboardIntoRemoteSession()
                    }
                    .padding(remoteSessionSafeAreaInsets)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())

                VStack {
                    HStack {
                        Button {
                            remoteDesktopRuntime.clearActiveSession()
                        } label: {
                            Label("세션 종료", systemImage: "xmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.white.opacity(0.95))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("shadow.remote.session.terminate")
                        .accessibilityLabel("Terminate Remote Session")
                        .background(
                            GeometryReader { geometry in
                                Color.clear
                                    .preference(
                                        key: ShadowClientSessionPointerVisibleRegionsPreferenceKey.self,
                                        value: [geometry.frame(in: .named("shadow.remote.session.root"))]
                                    )
                            }
                        )

                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
                .padding(.leading, 12)
                .safeAreaPadding([.top, .leading])
            }
            .ignoresSafeArea()
            .coordinateSpace(name: "shadow.remote.session.root")
            .onPreferenceChange(ShadowClientSessionPointerVisibleRegionsPreferenceKey.self) { regions in
                sessionVisiblePointerRegions = regions
            }
        }
    }

var backgroundGradient: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.08, blue: 0.15),
                    Color(red: 0.06, green: 0.16, blue: 0.20),
                    Color(red: 0.13, green: 0.14, blue: 0.10),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    accentColor.opacity(0.26),
                    .clear,
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 420
            )

            RadialGradient(
                colors: [
                    Color(red: 0.35, green: 0.45, blue: 0.95).opacity(0.18),
                    .clear,
                ],
                center: .bottomLeading,
                startRadius: 10,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }

var accentColor: Color {
        Color(red: 0.34, green: 0.88, blue: 0.82)
    }

    @MainActor
var isLocalHDRDisplayAvailable: Bool {
        ShadowClientDisplayDynamicRangeSupport.currentDisplaySupportsHDR()
    }

var contentMaxWidth: CGFloat {
        horizontalSizeClass == .compact ? 380 : 920
    }

var isCompactLayout: Bool {
        horizontalSizeClass == .compact
    }

var horizontalContentPadding: CGFloat {
        horizontalSizeClass == .compact ? 14 : 20
    }

var topContentPadding: CGFloat {
        horizontalSizeClass == .compact ? 20 : 28
    }

var realtimeSessionHUDDisplayState: ShadowClientRealtimeSessionHUDDisplayState? {
        ShadowClientRealtimeSessionHUDDisplayStateMapper.make(
            showDiagnosticsHUD: showDiagnosticsHUD,
            diagnosticsModel: settingsDiagnosticsModel,
            controlRoundTripMs: sessionSurfaceContext.controlRoundTripMs,
            renderState: sessionSurfaceContext.renderState,
            audioOutputState: sessionSurfaceContext.audioOutputState,
            sessionIssue: remoteDesktopRuntime.sessionIssue
        )
    }

func updateActiveSessionProcessActivity(isActive: Bool) {
#if os(macOS)
        if isActive {
            guard activeSessionProcessActivity == nil else {
                return
            }
            activeSessionProcessActivity = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiated, .latencyCritical, .idleSystemSleepDisabled],
                reason: "ShadowClient active remote session"
            )
            return
        }
#endif
        endActiveSessionProcessActivity()
    }

func endActiveSessionProcessActivity() {
#if os(macOS)
        guard let activeSessionProcessActivity else {
            return
        }
        ProcessInfo.processInfo.endActivity(activeSessionProcessActivity)
        self.activeSessionProcessActivity = nil
#endif
    }

func panelSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        ShadowClientAppShellChrome.Palette.panelGradientTop,
                        ShadowClientAppShellChrome.Palette.panelGradientBottom,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        ShadowClientAppShellChrome.Palette.panelStroke,
                        lineWidth: ShadowClientAppShellChrome.Metrics.panelStrokeWidth
                    )
            )
            .shadow(
                color: ShadowClientAppShellChrome.Palette.panelShadow,
                radius: ShadowClientAppShellChrome.Metrics.panelShadowRadius,
                x: 0,
                y: ShadowClientAppShellChrome.Metrics.panelShadowY
            )
    }

    @MainActor
    func pasteLocalClipboardIntoRemoteSession() {
        guard let clipboardText = ShadowClientClipboardBridge.currentString() else {
            return
        }
        remoteDesktopRuntime.syncClipboard(clipboardText)
    }

    @MainActor
    func copyRemoteClipboardIntoLocalClipboard() {
        remoteDesktopRuntime.pullClipboard()
    }

func rowSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        ShadowClientAppShellChrome.Palette.rowGradientTop,
                        ShadowClientAppShellChrome.Palette.rowGradientBottom,
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(
                        ShadowClientAppShellChrome.Palette.rowStroke,
                        lineWidth: ShadowClientAppShellChrome.Metrics.rowStrokeWidth
                    )
            )
    }

func playbackOverlayLabel(
        _ title: String,
        symbol: String,
        tone: ShadowClientRemoteSessionLaunchTone
    ) -> some View {
        let style = ShadowClientRemoteSessionOverlayPresentationKit.overlayStyle(for: tone)

        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black.opacity(style.backgroundOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(style.textColor.opacity(style.strokeOpacity), lineWidth: 1)
            )
            .overlay {
                Label(title, systemImage: symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(style.textColor)
            }
    }

func realtimeSessionHUDCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        ShadowUIRemoteSessionHUDCard(
            width: isCompactLayout ? 220 : 280,
            content: content
        )
    }

func realtimeSessionDiagnosticsHUD(_ model: SettingsDiagnosticsHUDModel) -> some View {
        realtimeSessionHUDCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundStyle(toneColor(for: model.tone))
                    Text(ShadowClientRemoteSessionOverlayPresentationKit.hudTitle())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Spacer(minLength: 8)
                    Text(model.tone.rawValue.uppercased())
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(toneColor(for: model.tone))
                }

                HStack(spacing: 10) {
                    diagnosticsStatChip(label: "HDR", value: diagnosticsHDRValue(model: model))
                    diagnosticsStatChip(label: "FPS", value: diagnosticsFPSValue())
                    diagnosticsStatChip(label: "Bitrate", value: diagnosticsBitrateValue())
                    diagnosticsStatChip(
                        label: "Ping",
                        value: diagnosticsLatestValue(
                            samples: sessionDiagnosticsHistory.controlRoundTripMsSamples,
                            unit: "ms"
                        )
                    )
                    diagnosticsStatChip(label: "Drop", value: String(format: "%.1f%%", model.frameDropPercent))
                }

                Text(
                    ShadowClientRemoteSessionOverlayPresentationKit.diagnosticsSummary(
                        codecLabel: activeSessionVideoCodecLabel,
                        resolutionValue: diagnosticsResolutionValue(),
                        audioChannelValue: diagnosticsAudioChannelValue()
                    )
                )
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.mint.opacity(0.86))

                diagnosticsSparklineRow(
                    title: "Ping Spike",
                    samples: sessionDiagnosticsHistory.controlRoundTripMsSamples,
                    color: .mint,
                    unit: "ms"
                )
                diagnosticsSparklineRow(
                    title: "Jitter Spike",
                    samples: sessionDiagnosticsHistory.jitterMsSamples,
                    color: .orange,
                    unit: "ms"
                )
                diagnosticsSparklineRow(
                    title: "Frame Drop",
                    samples: sessionDiagnosticsHistory.frameDropPercentSamples,
                    color: .red,
                    unit: "%"
                )
                diagnosticsSparklineRow(
                    title: "Packet Loss",
                    samples: sessionDiagnosticsHistory.packetLossPercentSamples,
                    color: .yellow,
                    unit: "%"
                )
            }
        }
    }

func realtimeSessionBootstrapDiagnosticsHUD(controlRoundTripMs: Int?) -> some View {
        realtimeSessionHUDCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundStyle(Color.white.opacity(0.82))
                    Text(ShadowClientRemoteSessionOverlayPresentationKit.hudTitle())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Spacer(minLength: 8)
                    Text(ShadowClientRemoteSessionOverlayPresentationKit.bootstrapBadgeText())
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                Text(ShadowClientRemoteSessionOverlayPresentationKit.bootstrapDescription())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.74))

                Text(
                    ShadowClientRemoteSessionOverlayPresentationKit.diagnosticsSummary(
                        codecLabel: activeSessionVideoCodecLabel,
                        resolutionValue: diagnosticsResolutionValue(),
                        audioChannelValue: diagnosticsAudioChannelValue()
                    )
                )
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Color.mint.opacity(0.86))

                HStack(spacing: 10) {
                    diagnosticsStatChip(
                        label: "HDR",
                        value: diagnosticsHDRValue(model: nil)
                    )
                    diagnosticsStatChip(
                        label: "Ping",
                        value: diagnosticsRoundTripValue(controlRoundTripMs)
                    )
                    diagnosticsStatChip(
                        label: "FPS",
                        value: diagnosticsFPSValue()
                    )
                    diagnosticsStatChip(label: "Bitrate", value: diagnosticsBitrateValue())
                }

                diagnosticsSparklineRow(
                    title: "Ping Spike",
                    samples: sessionDiagnosticsHistory.controlRoundTripMsSamples,
                    color: .mint,
                    unit: "ms"
                )
            }
        }
    }

func realtimeSessionConnectionIssueHUD(
        title: String,
        message: String
    ) -> some View {
        realtimeSessionHUDCard {
            ShadowUIRemoteSessionConnectionIssueHUD(
                title: title,
                message: message,
                badgeText: ShadowClientRemoteSessionOverlayPresentationKit.connectionIssueBadgeText(),
                footnote: ShadowClientRemoteSessionOverlayPresentationKit.connectionIssueFootnote()
            )
        }
    }

func diagnosticsRoundTripValue(_ roundTripMs: Int?) -> String {
        ShadowClientSessionDiagnosticsPresentationKit.roundTripValue(roundTripMs)
    }

func diagnosticsFPSValue() -> String {
        ShadowClientSessionDiagnosticsPresentationKit.fpsValue(
            estimatedVideoFPS: sessionSurfaceContext.estimatedVideoFPS,
            defaultFPS: currentSettings.frameRate.fps
        )
    }

func diagnosticsBitrateValue() -> String {
        ShadowClientSessionDiagnosticsPresentationKit.bitrateValue(
            estimatedVideoBitrateKbps: sessionSurfaceContext.estimatedVideoBitrateKbps,
            effectiveBitrateKbps: effectiveBitrateKbps
        )
    }

func diagnosticsResolutionValue() -> String {
        ShadowClientSessionDiagnosticsPresentationKit.resolutionValue(
            videoPresentationSize: sessionSurfaceContext.videoPresentationSize,
            selectedResolution: selectedResolution,
            currentSettings: currentSettings,
            viewportMetrics: launchViewportMetrics,
            displayMetrics: displayMetrics
        )
    }

func diagnosticsHDRValue(model: SettingsDiagnosticsHUDModel?) -> String {
        ShadowClientSessionDiagnosticsPresentationKit.hdrValue(
            diagnosticsModel: model,
            activeDynamicRangeMode: sessionSurfaceContext.activeDynamicRangeMode
        )
}

func diagnosticsAudioChannelValue() -> String {
        ShadowClientSessionDiagnosticsPresentationKit.audioChannelValue(
            audioOutputState: sessionSurfaceContext.audioOutputState,
            currentSettings: currentSettings
        )
    }

var remoteSessionSafeAreaInsets: EdgeInsets {
        let insets = displayMetrics.safeAreaInsets
        return EdgeInsets(
            top: max(insets.top, launchViewportMetrics.safeAreaInsets.top),
            leading: max(insets.leading, launchViewportMetrics.safeAreaInsets.leading),
            bottom: max(insets.bottom, launchViewportMetrics.safeAreaInsets.bottom),
            trailing: max(insets.trailing, launchViewportMetrics.safeAreaInsets.trailing)
        )
    }

func diagnosticsSparklineRow(
        title: String,
        samples: [Double],
        color: Color,
        unit: String
    ) -> some View {
        ShadowUIRemoteSessionSparklineRow(
            title: title,
            latestValue: diagnosticsLatestValue(samples: samples, unit: unit),
            samples: samples,
            color: color
        )
    }

func diagnosticsLatestValue(samples: [Double], unit: String) -> String {
        ShadowClientSessionDiagnosticsPresentationKit.latestValue(samples: samples, unit: unit)
    }

func diagnosticsStatChip(label: String, value: String) -> some View {
        ShadowUIRemoteSessionStatChip(label: label, value: value)
    }
}
