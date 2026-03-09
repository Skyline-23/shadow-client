import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

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
                    .ignoresSafeArea()
                    .accessibilityIdentifier("shadow.remote.session.surface")
                    .accessibilityLabel("Remote Session Surface")

                    if let overlay = sessionPresentationModel.overlay {
                        ZStack {
                            Color.black
                                .opacity(playbackOverlayDimOpacity(for: sessionPresentationModel.launchTone))
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
                    }
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.clear)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())

#if os(iOS)
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
#endif
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
            audioOutputState: sessionSurfaceContext.audioOutputState
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
                        Color.white.opacity(0.12),
                        Color.white.opacity(0.06),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.28), radius: 18, x: 0, y: 10)
    }

func rowSurface(cornerRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.30),
                        Color.black.opacity(0.22),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 0.8)
            )
    }

func playbackOverlayLabel(
        _ title: String,
        symbol: String,
        tone: ShadowClientRemoteSessionLaunchTone
    ) -> some View {
        let backgroundOpacity: Double
        let strokeOpacity: Double
        let textColor: Color
        switch tone {
        case .failed:
            backgroundOpacity = 0.66
            strokeOpacity = 0.78
            textColor = Color.red.opacity(0.95)
        case .launching:
            backgroundOpacity = 0.56
            strokeOpacity = 0.42
            textColor = Color.orange.opacity(0.95)
        case .idle, .launched:
            backgroundOpacity = 0.45
            strokeOpacity = 0.18
            textColor = Color.white.opacity(0.88)
        }

        return RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.black.opacity(backgroundOpacity))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(textColor.opacity(strokeOpacity), lineWidth: 1)
            )
            .overlay {
                Label(title, systemImage: symbol)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(textColor)
            }
    }

func playbackOverlayDimOpacity(for tone: ShadowClientRemoteSessionLaunchTone) -> Double {
        switch tone {
        case .failed:
            return 0.58
        case .launching:
            return 0.46
        case .idle, .launched:
            return 0.34
        }
    }

func realtimeSessionHUDCard<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(10)
            .frame(width: isCompactLayout ? 220 : 280, alignment: .leading)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 12, x: 0, y: 6)
    }

func realtimeSessionDiagnosticsHUD(_ model: SettingsDiagnosticsHUDModel) -> some View {
        realtimeSessionHUDCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path.ecg.rectangle")
                        .foregroundStyle(toneColor(for: model.tone))
                    Text("Realtime HUD")
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

                Text("Codec \(activeSessionVideoCodecLabel) · Resolution \(diagnosticsResolutionValue())")
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
                    Text("Realtime HUD")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.9))
                    Spacer(minLength: 8)
                    Text("BOOTSTRAP")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                Text("Telemetry stream pending. Showing connection health baseline.")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.74))

                Text("Codec \(activeSessionVideoCodecLabel) · Resolution \(diagnosticsResolutionValue())")
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .foregroundStyle(Color.red.opacity(0.95))
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                    Spacer(minLength: 8)
                    Text("OFFLINE")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(Color.red.opacity(0.95))
                }

                Text(message)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .lineLimit(3)

                Text("Remote input is paused until stream reconnects.")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.red.opacity(0.90))
            }
        }
    }

func diagnosticsRoundTripValue(_ roundTripMs: Int?) -> String {
        guard let roundTripMs else {
            return "--"
        }
        return "\(max(roundTripMs, 0)) ms"
    }

func diagnosticsFPSValue() -> String {
        if let estimatedFPS = sessionSurfaceContext.estimatedVideoFPS, estimatedFPS.isFinite {
            return "\(Int(estimatedFPS.rounded())) fps"
        }
        return "\(currentSettings.frameRate.fps) fps"
    }

func diagnosticsBitrateValue() -> String {
        if let bitrate = sessionSurfaceContext.estimatedVideoBitrateKbps {
            return "\(max(0, bitrate)) / \(effectiveBitrateKbps) kbps"
        }
        return "\(effectiveBitrateKbps) kbps"
    }

func diagnosticsResolutionValue() -> String {
        if let size = sessionSurfaceContext.videoPresentationSize,
           size.width > 0,
           size.height > 0
        {
            return "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
        }

        if selectedResolution == .retinaAuto {
            let pixelSize = ShadowClientAutoResolutionPolicy.resolvePixelSize(
                logicalSize: launchViewportMetrics.logicalSize,
                safeAreaInsets: launchViewportMetrics.safeAreaInsets
            )
            return "\(Int(pixelSize.width.rounded()))x\(Int(pixelSize.height.rounded()))"
        }

        return "\(currentSettings.resolution.width)x\(currentSettings.resolution.height)"
    }

func diagnosticsHDRValue(model: SettingsDiagnosticsHUDModel?) -> String {
        if let model {
            return model.hdrVideoMode == .hdr10 ? "ON" : "OFF"
        }

        switch sessionSurfaceContext.activeDynamicRangeMode {
        case .hdr:
            return "ON"
        case .sdr:
            return "OFF"
        case .unknown:
            return "AUTO"
        }
    }

func diagnosticsSparklineRow(
        title: String,
        samples: [Double],
        color: Color,
        unit: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.85))
                Spacer(minLength: 6)
                Text(diagnosticsLatestValue(samples: samples, unit: unit))
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(color.opacity(0.9))
            }

            ShadowClientDiagnosticsSparkline(samples: samples, color: color)
                .frame(height: 20)
        }
    }

func diagnosticsLatestValue(samples: [Double], unit: String) -> String {
        guard let latest = samples.last else {
            return "--"
        }

        if unit == "ms" {
            return "\(Int(latest.rounded())) \(unit)"
        }
        return "\(String(format: "%.1f", latest))\(unit)"
    }

func diagnosticsStatChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color.white.opacity(0.72))
            Text(value)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.white.opacity(0.92))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
    }

}
