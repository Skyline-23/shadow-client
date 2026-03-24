import Foundation

final class ShadowClientUptimeRateLimiter {
    let minimumIntervalSeconds: TimeInterval
    var lastEmissionUptime: TimeInterval = 0

    init(minimumIntervalSeconds: TimeInterval) {
        self.minimumIntervalSeconds = max(0, minimumIntervalSeconds)
    }

    func shouldEmit(nowUptime: TimeInterval) -> Bool {
        if lastEmissionUptime == 0 ||
            nowUptime - lastEmissionUptime >= minimumIntervalSeconds
        {
            lastEmissionUptime = nowUptime
            return true
        }
        return false
    }

    func reset() {
        lastEmissionUptime = 0
    }
}

struct ShadowClientSessionDiagnosticsHistory {
    let maxSamples: Int
    private(set) var controlRoundTripMsSamples: [Double] = []
    private(set) var jitterMsSamples: [Double] = []
    private(set) var frameDropPercentSamples: [Double] = []
    private(set) var packetLossPercentSamples: [Double] = []

    mutating func append(_ model: SettingsDiagnosticsHUDModel) {
        let sampleLimit = max(maxSamples, 1)
        let jitter = max(0, Double(model.jitterMs))
        jitterMsSamples.append(jitter)
        if jitterMsSamples.count > sampleLimit {
            jitterMsSamples.removeFirst(jitterMsSamples.count - sampleLimit)
        }

        if model.frameDropPercent.isFinite {
            frameDropPercentSamples.append(max(0, model.frameDropPercent))
            if frameDropPercentSamples.count > sampleLimit {
                frameDropPercentSamples.removeFirst(frameDropPercentSamples.count - sampleLimit)
            }
        }
        if model.packetLossPercent.isFinite {
            packetLossPercentSamples.append(max(0, model.packetLossPercent))
            if packetLossPercentSamples.count > sampleLimit {
                packetLossPercentSamples.removeFirst(packetLossPercentSamples.count - sampleLimit)
            }
        }
    }

    mutating func appendControlRoundTripMs(_ roundTripMs: Int?) {
        guard let roundTripMs else {
            return
        }

        let sampleLimit = max(maxSamples, 1)
        controlRoundTripMsSamples.append(max(0, Double(roundTripMs)))
        if controlRoundTripMsSamples.count > sampleLimit {
            controlRoundTripMsSamples.removeFirst(controlRoundTripMsSamples.count - sampleLimit)
        }
    }
}
