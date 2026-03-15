import Foundation

public enum ShadowClientTelemetrySimulationDefaults {
    public static let sampleInterval: Duration = .milliseconds(500)
    public static let baseRenderedFrames = 1_000
    public static let renderedFrameIncrement = 4

    public static let instabilityCycleLength = 20
    public static let unstableSampleCount = 3
    public static let unstableDroppedFrames = 3
    public static let unstableNetworkDroppedFrames = 2
    public static let unstableJitterMs = 42
    public static let unstablePacketLossPercent = 2.4
    public static let unstableAVSyncOffsetMs = 14

    public static let stableDroppedFrames = 0
    public static let stableNetworkDroppedFrames = 0
    public static let stableJitterBaseMs = 6
    public static let stableJitterVarianceCycle = 3
    public static let stablePacketLossPercent = 0.0
    public static let stableAVSyncOffsetMs = 2
}
