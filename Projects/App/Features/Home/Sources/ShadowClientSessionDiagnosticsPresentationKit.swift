import Foundation

enum ShadowClientSessionDiagnosticsPresentationKit {
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
