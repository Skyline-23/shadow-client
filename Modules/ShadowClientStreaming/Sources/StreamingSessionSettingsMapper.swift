public enum HDRVideoMode: String, Equatable, Sendable {
    case off
    case hdr10
}

public enum StreamAudioMode: String, Equatable, Sendable {
    case stereo
    case surround51
}

public struct StreamingUserPreferences: Equatable, Sendable {
    public let preferHDR: Bool
    public let preferSurroundAudio: Bool
    public let lowLatencyMode: Bool

    public init(preferHDR: Bool, preferSurroundAudio: Bool, lowLatencyMode: Bool) {
        self.preferHDR = preferHDR
        self.preferSurroundAudio = preferSurroundAudio
        self.lowLatencyMode = lowLatencyMode
    }
}

public struct HostStreamingCapabilities: Equatable, Sendable {
    public let supportsHDR10: Bool
    public let supportsSurround51: Bool

    public init(supportsHDR10: Bool, supportsSurround51: Bool) {
        self.supportsHDR10 = supportsHDR10
        self.supportsSurround51 = supportsSurround51
    }
}

public struct StreamingSessionConfiguration: Equatable, Sendable {
    public let hdrVideoMode: HDRVideoMode
    public let audioMode: StreamAudioMode

    public init(hdrVideoMode: HDRVideoMode, audioMode: StreamAudioMode) {
        self.hdrVideoMode = hdrVideoMode
        self.audioMode = audioMode
    }
}

public struct StreamingSessionSettingsPolicy: Equatable, Sendable {
    public let hdrPacketLossThresholdPercent: Double
    public let hdrJitterThresholdMs: Double
    public let surroundPacketLossThresholdPercent: Double
    public let surroundJitterThresholdMs: Double

    public init(
        hdrPacketLossThresholdPercent: Double = 1.5,
        hdrJitterThresholdMs: Double = 20.0,
        surroundPacketLossThresholdPercent: Double = 2.5,
        surroundJitterThresholdMs: Double = 30.0
    ) {
        self.hdrPacketLossThresholdPercent = max(0.0, hdrPacketLossThresholdPercent)
        self.hdrJitterThresholdMs = max(0.0, hdrJitterThresholdMs)
        self.surroundPacketLossThresholdPercent = max(0.0, surroundPacketLossThresholdPercent)
        self.surroundJitterThresholdMs = max(0.0, surroundJitterThresholdMs)
    }
}

public struct StreamingSessionSettingsMapper: Sendable {
    public let policy: StreamingSessionSettingsPolicy

    public init(policy: StreamingSessionSettingsPolicy = .init()) {
        self.policy = policy
    }

    public func map(
        preferences: StreamingUserPreferences,
        capabilities: HostStreamingCapabilities,
        signal: StreamingNetworkSignal
    ) -> StreamingSessionConfiguration {
        let normalizedJitter = max(0.0, signal.jitterMs)
        let normalizedPacketLoss = min(max(0.0, signal.packetLossPercent), 100.0)

        let hdrHealthy =
            normalizedPacketLoss <= policy.hdrPacketLossThresholdPercent &&
            normalizedJitter <= policy.hdrJitterThresholdMs

        let surroundHealthy =
            normalizedPacketLoss <= policy.surroundPacketLossThresholdPercent &&
            normalizedJitter <= policy.surroundJitterThresholdMs

        let hdrVideoMode: HDRVideoMode
        if preferences.preferHDR && capabilities.supportsHDR10 && hdrHealthy {
            hdrVideoMode = .hdr10
        } else {
            hdrVideoMode = .off
        }

        let audioMode: StreamAudioMode
        if preferences.lowLatencyMode {
            audioMode = .stereo
        } else if preferences.preferSurroundAudio && capabilities.supportsSurround51 && surroundHealthy {
            audioMode = .surround51
        } else {
            audioMode = .stereo
        }

        return StreamingSessionConfiguration(hdrVideoMode: hdrVideoMode, audioMode: audioMode)
    }
}
