import ShadowClientStreaming
import ShadowClientUI
import SwiftUI
import ShadowUIFoundation
#if os(iOS)
import GameController
#endif

extension ShadowClientAppShellView {
    @ViewBuilder
    var remoteSessionFlowView: some View {
        if remoteDesktopRuntime.activeSession != nil {
            let presentationModel = sessionPresentationModel
            ZStack {
                Color.black

                ZStack {
                    ShadowClientRealtimeSessionSurfaceView(
                        context: sessionSurfaceContext
                    )
                    .padding(remoteSessionSafeAreaInsets)
                    .accessibilityIdentifier("shadow.remote.session.surface")
                    .accessibilityLabel("Remote Session Surface")

                    if let overlay = presentationModel.overlay {
                        ZStack {
                            Color.black
                                .opacity(ShadowClientRemoteSessionOverlayPresentationKit.dimOpacity(for: presentationModel.launchTone))
                                .ignoresSafeArea()

                            playbackOverlayLabel(
                                overlay.title,
                                symbol: overlay.symbol,
                                tone: presentationModel.launchTone,
                                showsLoadingIndicator: presentationModel.showsLoadingIndicator
                            )
                            .padding(.horizontal, 20)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .allowsHitTesting(presentationModel.blocksRemoteInteraction)
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
                        visiblePointerRegions: sessionVisiblePointerRegions,
                        captureHardwareKeyboard: !isRemoteSessionKeyboardPresented
                    ) { event in
                        remoteDesktopRuntime.sendInput(event)
                    } onSoftwareKeyboardToggleCommand: {
                        #if os(iOS)
                        guard GCKeyboard.coalesced == nil else {
                            return
                        }
                        #endif
                        isRemoteSessionKeyboardPresented.toggle()
                        if isRemoteSessionKeyboardPresented {
                            DispatchQueue.main.async {
                                isRemoteSessionKeyboardFocused = true
                            }
                        } else {
                            isRemoteSessionKeyboardFocused = false
                            remoteSessionKeyboardText = ""
                        }
                    } onSessionTerminateCommand: {
                        remoteDesktopRuntime.clearActiveSession()
                    } onCopyClipboardCommand: {
                        copyRemoteClipboardIntoLocalClipboard()
                    } onPasteClipboardCommand: {
                        pasteLocalClipboardIntoRemoteSession()
                    }
                    .allowsHitTesting(!presentationModel.blocksRemoteInteraction)
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
                        .disabled(remoteDesktopRuntime.launchState.isTransitioning)
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
                guard regions != sessionVisiblePointerRegions else {
                    return
                }
                sessionVisiblePointerRegions = regions
            }
            .overlay(alignment: .bottomLeading) {
                remoteSessionSoftwareKeyboardProxy
            }
        }
    }

    @ViewBuilder
    private var remoteSessionSoftwareKeyboardProxy: some View {
        ShadowClientPlatformTextField(
            text: $remoteSessionKeyboardText,
            placeholder: "",
            isFocused: Binding(
                get: { isRemoteSessionKeyboardFocused },
                set: { isRemoteSessionKeyboardFocused = $0 }
            ),
            submitAction: {
                isRemoteSessionKeyboardFocused = false
                isRemoteSessionKeyboardPresented = false
                remoteSessionKeyboardText = ""
            }
        )
            .frame(width: 1, height: 1)
            .opacity(isRemoteSessionKeyboardPresented ? 0.01 : 0.0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: remoteSessionKeyboardText, initial: false) { oldValue, newValue in
                sendRemoteSessionSoftwareKeyboardDelta(from: oldValue, to: newValue)
            }
    }

    @MainActor
    private func sendRemoteSessionSoftwareKeyboardDelta(from oldValue: String, to newValue: String) {
        let oldScalars = Array(oldValue.unicodeScalars)
        let newScalars = Array(newValue.unicodeScalars)

        var prefixCount = 0
        while prefixCount < oldScalars.count,
              prefixCount < newScalars.count,
              oldScalars[prefixCount] == newScalars[prefixCount] {
            prefixCount += 1
        }

        var oldSuffixIndex = oldScalars.count
        var newSuffixIndex = newScalars.count
        while oldSuffixIndex > prefixCount,
              newSuffixIndex > prefixCount,
              oldScalars[oldSuffixIndex - 1] == newScalars[newSuffixIndex - 1] {
            oldSuffixIndex -= 1
            newSuffixIndex -= 1
        }

        let deletedCount = oldSuffixIndex - prefixCount
        if deletedCount > 0 {
            for _ in 0..<deletedCount {
                remoteDesktopRuntime.sendInput(
                    .keyDown(
                        keyCode: ShadowClientRemoteInputEvent.softwareKeyboardSyntheticKeyCode,
                        characters: "\u{08}"
                    )
                )
                remoteDesktopRuntime.sendInput(
                    .keyUp(
                        keyCode: ShadowClientRemoteInputEvent.softwareKeyboardSyntheticKeyCode,
                        characters: "\u{08}"
                    )
                )
            }
        }

        let inserted = String(String.UnicodeScalarView(newScalars[prefixCount..<newSuffixIndex]))
        if !inserted.isEmpty {
            sendRemoteSessionSoftwareKeyboardInsertedText(inserted)
        }
    }

    @MainActor
    private func sendRemoteSessionSoftwareKeyboardInsertedText(_ text: String) {
        var bufferedText = String()

        for scalar in text.unicodeScalars {
            let character = String(scalar)

            guard let virtualKey = ShadowClientWindowsVirtualKeyMap.windowsVirtualKeyCode(
                keyCode: ShadowClientRemoteInputEvent.softwareKeyboardSyntheticKeyCode,
                characters: character
            ) else {
                bufferedText.unicodeScalars.append(scalar)
                continue
            }

            if !bufferedText.isEmpty {
                remoteDesktopRuntime.sendInput(.text(bufferedText))
                bufferedText.removeAll(keepingCapacity: true)
            }

            let translatedKeyCode = ShadowClientRemoteInputEvent.pretranslatedWindowsVirtualKey(virtualKey)
            remoteDesktopRuntime.sendInput(
                .keyDown(
                    keyCode: translatedKeyCode,
                    characters: character
                )
            )
            remoteDesktopRuntime.sendInput(
                .keyUp(
                    keyCode: translatedKeyCode,
                    characters: character
                )
            )
        }

        if !bufferedText.isEmpty {
            remoteDesktopRuntime.sendInput(.text(bufferedText))
        }
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
        tone: ShadowClientRemoteSessionLaunchTone,
        showsLoadingIndicator: Bool
    ) -> some View {
        let style = ShadowClientRemoteSessionOverlayPresentationKit.overlayStyle(for: tone)
        let overlayWidth = isCompactLayout ? 250.0 : 320.0
        let animatesSymbol =
            tone == .launching &&
            (symbol.contains("clockwise") || title.localizedCaseInsensitiveContains("optimizing"))

        return ShadowUIRemoteSessionOverlayBadge(
            title: title,
            symbol: symbol,
            textColor: style.textColor,
            backgroundOpacity: style.backgroundOpacity,
            strokeOpacity: style.strokeOpacity,
            width: overlayWidth,
            animatesSymbol: animatesSymbol,
            showsActivityIndicator: showsLoadingIndicator
        )
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

                diagnosticsStatGrid {
                    diagnosticsStatChip(label: "HDR", value: diagnosticsHDRValue(model: model))
                    diagnosticsStatChip(
                        label: "Latency Est.",
                        value: diagnosticsEstimatedInputLatencyValue(model: model)
                    )
                    diagnosticsStatChip(label: "FPS", value: diagnosticsFPSValue())
                    diagnosticsStatChip(label: "Bitrate", value: diagnosticsBitrateValue())
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

                diagnosticsStatGrid {
                    diagnosticsStatChip(
                        label: "HDR",
                        value: diagnosticsHDRValue(model: nil)
                    )
                    diagnosticsStatChip(
                        label: "Latency Est.",
                        value: diagnosticsBootstrapEstimatedInputLatencyValue(controlRoundTripMs)
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

func diagnosticsEstimatedInputLatencyValue(model: SettingsDiagnosticsHUDModel) -> String {
        ShadowClientSessionDiagnosticsPresentationKit.estimatedInputLatencyValue(
            controlRoundTripMs: sessionSurfaceContext.controlRoundTripMs,
            targetBufferMs: model.targetBufferMs,
            audioPendingDurationMs: sessionSurfaceContext.audioPendingDurationMs,
            estimatedVideoFPS: sessionSurfaceContext.estimatedVideoFPS,
            defaultFPS: currentSettings.frameRate.fps,
            timingBudget: ShadowClientAudioOutputCapabilityKit.currentTimingBudget()
        )
    }

func diagnosticsBootstrapEstimatedInputLatencyValue(_ controlRoundTripMs: Int?) -> String {
        guard controlRoundTripMs != nil else {
            return "--"
        }

        return ShadowClientSessionDiagnosticsPresentationKit.estimatedInputLatencyValue(
            controlRoundTripMs: controlRoundTripMs,
            targetBufferMs: 0,
            audioPendingDurationMs: sessionSurfaceContext.audioPendingDurationMs,
            estimatedVideoFPS: sessionSurfaceContext.estimatedVideoFPS,
            defaultFPS: currentSettings.frameRate.fps,
            timingBudget: ShadowClientAudioOutputCapabilityKit.currentTimingBudget()
        )
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

func diagnosticsStatGrid<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 10),
                count: 4
            ),
            alignment: .leading,
            spacing: 10
        ) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
