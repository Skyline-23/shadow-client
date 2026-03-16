import Foundation
import ShadowClientFeatureSession
import ShadowUIFoundation

enum ShadowClientSessionDiagnosticsPresentationKit {
    static func estimatedInputLatencyMs(
        controlRoundTripMs: Int?,
        targetBufferMs: Int,
        audioPendingDurationMs: Double,
        estimatedVideoFPS: Double?,
        defaultFPS: Int,
        timingBudget: ShadowClientAudioOutputTimingBudget
    ) -> Int? {
        guard let controlRoundTripMs else {
            return nil
        }

        let resolvedFPS: Double
        if let estimatedVideoFPS, estimatedVideoFPS.isFinite, estimatedVideoFPS > 0 {
            resolvedFPS = estimatedVideoFPS
        } else {
            resolvedFPS = Double(max(defaultFPS, 1))
        }

        let _ = audioPendingDurationMs
        let _ = timingBudget
        let frameIntervalMs = 1_000.0 / max(resolvedFPS, 1)

        let estimate =
            Double(max(controlRoundTripMs, 0)) +
            Double(max(targetBufferMs, 0)) +
            frameIntervalMs

        return Int(estimate.rounded())
    }

    static func estimatedInputLatencyValue(
        controlRoundTripMs: Int?,
        targetBufferMs: Int,
        audioPendingDurationMs: Double,
        estimatedVideoFPS: Double?,
        defaultFPS: Int,
        timingBudget: ShadowClientAudioOutputTimingBudget
    ) -> String {
        guard let estimatedInputLatencyMs = estimatedInputLatencyMs(
            controlRoundTripMs: controlRoundTripMs,
            targetBufferMs: targetBufferMs,
            audioPendingDurationMs: audioPendingDurationMs,
            estimatedVideoFPS: estimatedVideoFPS,
            defaultFPS: defaultFPS,
            timingBudget: timingBudget
        ) else {
            return "--"
        }
        return "\(estimatedInputLatencyMs) ms"
    }

    static func roundTripValue(_ roundTripMs: Int?) -> String {
        guard let roundTripMs else {
            return "--"
        }
        return "\(max(roundTripMs, 0)) ms"
    }

    static func fpsValue(
        estimatedVideoFPS: Double?,
        defaultFPS: Int
    ) -> String {
        if let estimatedVideoFPS, estimatedVideoFPS.isFinite {
            return "\(Int(estimatedVideoFPS.rounded())) fps"
        }
        return "\(defaultFPS) fps"
    }

    static func bitrateValue(
        estimatedVideoBitrateKbps: Int?,
        effectiveBitrateKbps: Int
    ) -> String {
        if let estimatedVideoBitrateKbps {
            return "\(max(0, estimatedVideoBitrateKbps))\n/ \(effectiveBitrateKbps) kbps"
        }
        return "\(effectiveBitrateKbps) kbps"
    }

    static func latestValue(samples: [Double], unit: String) -> String {
        guard let latest = samples.last else {
            return "--"
        }

        if unit == "ms" {
            return "\(Int(latest.rounded())) \(unit)"
        }
        return "\(String(format: "%.1f", latest))\(unit)"
    }

    static func resolutionValue(
        videoPresentationSize: CGSize?,
        selectedResolution: ShadowClientStreamingResolutionPreset,
        currentSettings: ShadowClientAppSettings,
        viewportMetrics: ShadowClientLaunchViewportMetrics,
        displayMetrics: ShadowClientDisplayMetricsState
    ) -> String {
        if let size = videoPresentationSize,
           size.width > 0,
           size.height > 0
        {
            return "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
        }

        if selectedResolution == .retinaAuto {
            let pixelSize = ShadowClientDisplayMetricsKit.resolvePixelSize(
                viewportMetrics: viewportMetrics,
                displayMetrics: displayMetrics
            )
            return "\(Int(pixelSize.width.rounded()))x\(Int(pixelSize.height.rounded()))"
        }

        return "\(currentSettings.resolution.width)x\(currentSettings.resolution.height)"
    }

    static func hdrValue(
        diagnosticsModel: SettingsDiagnosticsHUDModel?,
        activeDynamicRangeMode: ShadowClientRealtimeSessionSurfaceContext.DynamicRangeMode
    ) -> String {
        if let diagnosticsModel {
            return diagnosticsModel.hdrVideoMode == .hdr10 ? "ON" : "OFF"
        }

        switch activeDynamicRangeMode {
        case .hdr:
            return "ON"
        case .sdr:
            return "OFF"
        case .unknown:
            return "AUTO"
        }
    }

    static func audioChannelValue(
        audioOutputState: ShadowClientRealtimeAudioOutputState,
        currentSettings: ShadowClientAppSettings
    ) -> String {
        switch audioOutputState {
        case let .playing(_, _, channels):
            return "\(channels)ch"
        case .idle, .starting, .deviceUnavailable, .decoderFailed, .disconnected:
            return currentSettings.audioConfiguration.label
        }
    }
}
