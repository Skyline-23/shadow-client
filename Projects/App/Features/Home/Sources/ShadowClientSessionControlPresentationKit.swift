import ShadowClientStreaming
import ShadowClientUI
import SwiftUI
import ShadowClientFeatureSession

enum ShadowClientSessionControlPresentationKit {
    static func toneColor(for tone: HealthTone) -> Color {
        switch tone {
        case .healthy:
            return .green
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }

    static func videoCodecLabel(_ codec: ShadowClientVideoCodecPreference) -> String {
        switch codec {
        case .auto:
            return "Auto"
        case .av1:
            return "AV1"
        case .h265:
            return "H.265"
        case .h264:
            return "H.264"
        case .prores:
            return "ProRes (Experimental)"
        }
    }

    static func realtimeSessionVideoCodecLabel(_ codec: ShadowClientVideoCodec) -> String {
        switch codec {
        case .av1:
            return "AV1"
        case .h265:
            return "H.265"
        case .h264:
            return "H.264"
        case .prores:
            return "ProRes"
        }
    }

    static func launchBitrateNetworkSignal(
        diagnosticsModel: SettingsDiagnosticsHUDModel?
    ) -> StreamingNetworkSignal? {
        guard let diagnosticsModel else {
            return nil
        }

        let nowMs = Int(Date().timeIntervalSince1970 * 1_000)
        let sampleAgeMs = max(0, nowMs - diagnosticsModel.timestampMs)
        guard sampleAgeMs <= ShadowClientUIRuntimeDefaults.bitrateSignalFreshnessWindowMs else {
            return nil
        }

        return .init(
            jitterMs: Double(diagnosticsModel.jitterMs),
            packetLossPercent: diagnosticsModel.packetLossPercent
        )
    }
}
