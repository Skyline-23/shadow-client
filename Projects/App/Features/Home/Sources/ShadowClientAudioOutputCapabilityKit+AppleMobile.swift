#if os(iOS) || os(tvOS)
@preconcurrency import AVFoundation
import Foundation

enum ShadowClientAudioOutputCapabilityPlatformKit {
    static func supportsHeadTrackedRoute() -> Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { output in
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

    static func prefersSpatialHeadphoneRendering(channels: Int) async -> Bool {
        guard channels > 2 else {
            return false
        }
        return await MainActor.run {
            let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
            return outputs.contains { output in
                output.isSpatialAudioEnabled
            }
        }
    }

    static func maximumOutputChannels() async -> Int {
        await MainActor.run {
            let session = AVAudioSession.sharedInstance()
            let outputs = session.currentRoute.outputs
            let headphoneSpatialRoute = outputs.contains { output in
                output.isSpatialAudioEnabled
            }
            if headphoneSpatialRoute {
                return 8
            }
            let routeChannelCount = outputs
                .compactMap { output in
                    let count = output.channels?.count ?? 0
                    return count > 0 ? count : nil
                }
                .max() ?? 0
            let currentRouteChannels = Int(session.outputNumberOfChannels)
            return max(2, routeChannelCount, currentRouteChannels)
        }
    }

    static func currentRouteSummary() -> String {
        AVAudioSession.sharedInstance().currentRoute.outputs
            .map { output in
                "\(output.portType.rawValue){name=\(output.portName),channels=\(output.channels?.count ?? 0),spatial=\(output.isSpatialAudioEnabled)}"
            }
            .joined(separator: ",")
    }
}
#endif
