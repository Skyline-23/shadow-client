import ShadowClientStreaming
import ShadowClientUI
import SwiftUI

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
        }
    }

    static func maxBitrateKbps(unlockBitrateLimit: Bool) -> Double {
        unlockBitrateLimit
            ? Double(ShadowClientAppSettingsDefaults.maximumBitrateWhenUnlocked)
            : Double(ShadowClientAppSettingsDefaults.maximumBitrateWhenLocked)
    }

    static func launchBitrateNetworkSignal(
        autoBitrate: Bool,
        diagnosticsModel: SettingsDiagnosticsHUDModel?
    ) -> StreamingNetworkSignal? {
        guard autoBitrate, let diagnosticsModel else {
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
