import Foundation

public enum ShadowClientRemoteLaunchState: Equatable, Sendable {
    case idle
    case launching
    case optimizing(String)
    case launched(String)
    case failed(String)
}

public extension ShadowClientRemoteLaunchState {
    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .launching:
            return "Launching"
        case let .optimizing(message):
            return message
        case let .launched(message):
            return message
        case let .failed(message):
            return "Failed - \(message)"
        }
    }

    var isTransitioning: Bool {
        switch self {
        case .launching, .optimizing:
            return true
        case .idle, .launched, .failed:
            return false
        }
    }
}

public enum ShadowClientVideoCodecPreference: String, CaseIterable, Equatable, Sendable {
    case auto
    case av1
    case h265
    case h264
    case prores

    public var launchParameterValue: String? {
        switch self {
        case .auto:
            return nil
        case .av1:
            return "av1"
        case .h265:
            return "hevc"
        case .h264:
            return "h264"
        case .prores:
            return "prores"
        }
    }

    public var requiresCustomHostSupport: Bool {
        switch self {
        case .prores:
            return true
        case .auto, .av1, .h265, .h264:
            return false
        }
    }
}

public struct ShadowClientGameStreamLaunchSettings: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let fps: Int
    public let bitrateKbps: Int
    public let preferredCodec: ShadowClientVideoCodecPreference
    public let enableHDR: Bool
    public let enableSurroundAudio: Bool
    public let preferredSurroundChannelCount: Int
    public let lowLatencyMode: Bool
    public let enableVSync: Bool
    public let enableFramePacing: Bool
    public let enableYUV444: Bool
    public let unlockBitrateLimit: Bool
    public let prioritizeNetworkTraffic: Bool
    public let forceHardwareDecoding: Bool
    public let resolutionScalePercent: Int
    public let requestHiDPI: Bool
    public let preferVirtualDisplay: Bool
    public let optimizeGameSettingsForStreaming: Bool
    public let quitAppOnHostAfterStreamEnds: Bool
    public let playAudioOnHost: Bool

    public init(
        width: Int = ShadowClientStreamingLaunchBounds.defaultWidth,
        height: Int = ShadowClientStreamingLaunchBounds.defaultHeight,
        fps: Int = ShadowClientStreamingLaunchBounds.defaultFPS,
        bitrateKbps: Int = ShadowClientStreamingLaunchBounds.defaultBitrateKbps,
        preferredCodec: ShadowClientVideoCodecPreference = .auto,
        enableHDR: Bool,
        enableSurroundAudio: Bool,
        preferredSurroundChannelCount: Int = 6,
        lowLatencyMode: Bool,
        enableVSync: Bool = false,
        enableFramePacing: Bool = false,
        enableYUV444: Bool = false,
        unlockBitrateLimit: Bool = false,
        prioritizeNetworkTraffic: Bool = false,
        forceHardwareDecoding: Bool = true,
        resolutionScalePercent: Int = 100,
        requestHiDPI: Bool = false,
        preferVirtualDisplay: Bool = false,
        optimizeGameSettingsForStreaming: Bool = true,
        quitAppOnHostAfterStreamEnds: Bool = false,
        playAudioOnHost: Bool = false
    ) {
        self.width = max(ShadowClientStreamingLaunchBounds.minimumWidth, width)
        self.height = max(ShadowClientStreamingLaunchBounds.minimumHeight, height)
        self.fps = max(ShadowClientStreamingLaunchBounds.minimumFPS, fps)
        self.bitrateKbps = min(
            max(ShadowClientStreamingLaunchBounds.minimumBitrateKbps, bitrateKbps),
            ShadowClientStreamingLaunchBounds.maximumBitrateKbps
        )
        self.preferredCodec = preferredCodec
        self.enableHDR = enableHDR
        self.enableSurroundAudio = enableSurroundAudio
        self.preferredSurroundChannelCount = max(2, min(8, preferredSurroundChannelCount))
        self.lowLatencyMode = lowLatencyMode
        self.enableVSync = enableVSync
        self.enableFramePacing = enableFramePacing
        self.enableYUV444 = enableYUV444
        self.unlockBitrateLimit = unlockBitrateLimit
        self.prioritizeNetworkTraffic = prioritizeNetworkTraffic
        self.forceHardwareDecoding = forceHardwareDecoding
        self.resolutionScalePercent = max(20, min(200, resolutionScalePercent))
        self.requestHiDPI = requestHiDPI
        self.preferVirtualDisplay = preferVirtualDisplay
        self.optimizeGameSettingsForStreaming = optimizeGameSettingsForStreaming
        self.quitAppOnHostAfterStreamEnds = quitAppOnHostAfterStreamEnds
        self.playAudioOnHost = playAudioOnHost
    }
}

public struct ShadowClientGameStreamLaunchResult: Equatable, Sendable {
    public let sessionURL: String?
    public let verb: String
    public let remoteInputKey: Data?
    public let remoteInputKeyID: UInt32?

    public init(
        sessionURL: String?,
        verb: String,
        remoteInputKey: Data? = nil,
        remoteInputKeyID: UInt32? = nil
    ) {
        self.sessionURL = sessionURL
        self.verb = verb
        self.remoteInputKey = remoteInputKey
        self.remoteInputKeyID = remoteInputKeyID
    }
}
