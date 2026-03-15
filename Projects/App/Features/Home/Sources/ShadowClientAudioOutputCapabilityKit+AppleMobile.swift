#if os(iOS) || os(tvOS)
@preconcurrency import AVFoundation
import Foundation

enum ShadowClientAudioOutputCapabilityPlatformKit {
    static func supportsHeadTrackedRoute() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
            isHeadphoneSpatialRoute(output)
        }
    }

    static func prefersSpatialHeadphoneRendering(channels: Int) async -> Bool {
        _ = channels
        return await MainActor.run {
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
            return outputs.contains { output in
                isHeadphoneSpatialRoute(output)
            }
        }
    }

    static func maximumOutputChannels() async -> Int {
        await MainActor.run {
            currentMaximumOutputChannels()
        }
    }

    @MainActor
    static func currentMaximumOutputChannels() -> Int {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        let routeChannelCount = outputs
            .compactMap { output in
                let count = output.channels?.count ?? 0
                return count > 0 ? count : nil
            }
            .max() ?? 0
        let currentRouteChannels = Int(session.outputNumberOfChannels)
        return max(2, routeChannelCount, currentRouteChannels)
    }

    static func currentRouteSummary() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs
            .map { output in
                "\(output.portType.rawValue){name=\(output.portName),channels=\(output.channels?.count ?? 0),spatial=\(output.isSpatialAudioEnabled)}"
            }
            .joined(separator: ",")
    }

    static func currentRenderingSummary() -> String {
        let session = AVAudioSession.sharedInstance()
        let renderingModeDescription: String
        if #available(iOS 17.2, tvOS 17.2, *) {
            renderingModeDescription = String(describing: session.renderingMode)
        } else {
            renderingModeDescription = "unavailable"
        }
        return "multichannel=\(session.supportsMultichannelContent),rendering-mode=\(renderingModeDescription),max-output-channels=\(session.maximumOutputNumberOfChannels),output-channels=\(session.outputNumberOfChannels)"
    }

    private static func isHeadphoneSpatialRoute(_ output: AVAudioSessionPortDescription) -> Bool {
        guard output.isSpatialAudioEnabled else {
            return false
        }

        switch output.portType {
        case .headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP:
            return true
        default:
            return false
        }
    }
}
#endif
