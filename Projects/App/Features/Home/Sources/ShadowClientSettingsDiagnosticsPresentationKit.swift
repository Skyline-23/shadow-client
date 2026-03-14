import SwiftUI
import ShadowClientUI

struct ShadowClientSettingsDiagnosticsRow: Equatable {
    let label: String
    let value: String
    let usesSecondaryValueColor: Bool
    let usesWarningValueColor: Bool
}

enum ShadowClientSettingsDiagnosticsPresentationKit {
    static func telemetryRows(_ model: SettingsDiagnosticsHUDModel) -> [ShadowClientSettingsDiagnosticsRow] {
        let packetLossValue = String(format: "%.1f", model.packetLossPercent)
        let frameDropValue = String(format: "%.1f", model.frameDropPercent)
        let sampleIntervalValue = model.sampleIntervalMs.map { "\($0) ms" } ?? "--"
        let reconfigureVideo = model.shouldRenegotiateVideoPipeline ? "Y" : "N"
        let reconfigureAudio = model.shouldRenegotiateAudioPipeline ? "Y" : "N"
        let reconfigureQualityDrop = model.shouldApplyQualityDropImmediately ? "Y" : "N"
        let reconfigureValue = "V:\(reconfigureVideo) A:\(reconfigureAudio) QDrop:\(reconfigureQualityDrop)"

        var rows: [ShadowClientSettingsDiagnosticsRow] = [
            .init(label: "Tone", value: model.tone.rawValue.uppercased(), usesSecondaryValueColor: false, usesWarningValueColor: false),
            .init(label: "Target Buffer", value: "\(model.targetBufferMs) ms", usesSecondaryValueColor: false, usesWarningValueColor: false),
            .init(label: "Jitter / Packet Loss", value: "\(model.jitterMs) ms / \(packetLossValue)%", usesSecondaryValueColor: false, usesWarningValueColor: false),
            .init(label: "Frame Drop / AV Sync", value: "\(frameDropValue)% / \(model.avSyncOffsetMs) ms", usesSecondaryValueColor: false, usesWarningValueColor: false),
            .init(label: "Drop Origin", value: "NET \(model.networkDroppedFrames) / PACER \(model.pacerDroppedFrames)", usesSecondaryValueColor: false, usesWarningValueColor: false),
            .init(label: "Telemetry Timestamp", value: "\(model.timestampMs) ms", usesSecondaryValueColor: true, usesWarningValueColor: false),
            .init(label: "Sample Interval", value: sampleIntervalValue, usesSecondaryValueColor: true, usesWarningValueColor: false),
            .init(label: "Session Video / Audio", value: "\(model.hdrVideoMode.rawValue.uppercased()) / \(model.audioMode.rawValue.uppercased())", usesSecondaryValueColor: false, usesWarningValueColor: false),
            .init(label: "Reconfigure", value: reconfigureValue, usesSecondaryValueColor: true, usesWarningValueColor: false),
        ]

        if model.receivedOutOfOrderSample {
            rows.insert(
                .init(label: "Sample Order", value: "Out-of-order telemetry sample ignored", usesSecondaryValueColor: false, usesWarningValueColor: true),
                at: 7
            )
        }

        if model.recoveryStableSamplesRemaining > 0 {
            rows.append(
                .init(label: "Recovery Hold", value: "\(model.recoveryStableSamplesRemaining) stable sample(s) remaining", usesSecondaryValueColor: false, usesWarningValueColor: true)
            )
        }

        return rows
    }

    static func emptyTelemetryMessage() -> String {
        "Awaiting telemetry samples from active session."
    }

    static func controllerContractMessage() -> String {
        "DualSense feedback contract follows Apple Game Controller capabilities."
    }

    static func valueColor(for row: ShadowClientSettingsDiagnosticsRow, tone: HealthTone) -> Color {
        if row.usesWarningValueColor {
            return .orange
        }
        if row.usesSecondaryValueColor {
            return Color.white.opacity(0.78)
        }
        if row.label == "Tone" {
            return ShadowClientSessionControlPresentationKit.toneColor(for: tone)
        }
        return Color.white.opacity(0.92)
    }
}
