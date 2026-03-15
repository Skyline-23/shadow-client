import Foundation
import ShadowUIFoundation

enum ShadowClientSessionDiagnosticsPresentationKit {


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
            return "\(max(0, estimatedVideoBitrateKbps)) / \(effectiveBitrateKbps) kbps"
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
