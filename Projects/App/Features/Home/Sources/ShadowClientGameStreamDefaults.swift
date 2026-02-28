import Foundation

public enum ShadowClientGameStreamCommand: String, Sendable {
    case launch
    case resume
    case cancel
    case pair
    case unpair
}

public enum ShadowClientGameStreamNetworkDefaults {
    public static let httpScheme = "http"
    public static let httpsScheme = "https"
    public static let httpSchemePrefix = "\(httpScheme)://"

    public static let defaultHTTPPort = 47_989
    public static let defaultHTTPSPort = 47_984
    public static let defaultServicePorts: [Int] = [
        defaultHTTPSPort,
        defaultHTTPPort,
        48_010,
    ]

    public static let defaultRequestTimeout: TimeInterval = 8
    public static let pairingPINEntryTimeout: TimeInterval = 45
    public static let pairingStageTimeout: TimeInterval = 15
    public static let defaultSessionConnectTimeout: Duration = .seconds(10)

    public static let minimumPort = 1
    public static let maximumPort = Int(UInt16.max)
}

public enum ShadowClientGameStreamLaunchDefaults {
    public static let hdrCapabilityPlaceholder = "0x0x0x0x0x0x0x0x0x0x0"
}

public enum ShadowClientStreamingLaunchBounds {
    public static let defaultWidth = 1_920
    public static let defaultHeight = 1_080
    public static let defaultFPS = 60
    public static let defaultBitrateKbps = 20_000

    public static let minimumWidth = 640
    public static let minimumHeight = 360
    public static let minimumFPS = 30
    public static let minimumBitrateKbps = 500
    public static let maximumBitrateKbps = 500_000
}

public enum ShadowClientVideoDecoderDefaults {
    public static let defaultDecodePresentationTimeScale = ShadowClientStreamingLaunchBounds.defaultFPS
    public static let defaultPixelBufferPoolMinimumBufferCount = 8
    public static let minimumInFlightDecodeRequests = 6
    public static let maximumInFlightDecodeRequests = 64
    public static let inFlightDecodeCoreScalingDivisor = 3.0
    public static let inFlightDecodeMaximumCoreScale = 3.0
    public static let inFlightDecodeWorkloadGrowthExponent = 0.45
    public static let inFlightDecodeFPSBoostExponent = 0.30
    public static let inFlightDecodeBacklogBoostDivisor = 2
    public static let inFlightDecodeMaximumBacklogBoost = 24
    public static let inFlightDecodeInstabilityGraceFrameWindow = 3.0
    public static let inFlightDecodeBacklogBoostInstabilityDampingRatio = 0.8
    public static let decodePacingMinimumMultiplier = 0.25
    public static let decodePacingMaximumMultiplier = 2.0
    public static let decodePacingMultiplierStep = 0.10
    public static let decodePacingRecoveryFrameWindow = 6
    public static let inFlightDecodeWaitStep: Duration = .milliseconds(1)
}

public enum ShadowClientRealtimeSessionDefaults {
    public static let defaultConnectTimeout: Duration = .seconds(10)
    public static let rtspConnectTimeout: Duration = .seconds(10)
    public static let rtspConnectRetryWindowSeconds: TimeInterval = 10
    public static let rtspConnectRetryDelay: Duration = .milliseconds(500)
    public static let rtspReceiveTimeout: Duration = .seconds(15)
    public static let fallbackVideoPort: UInt16 = 47_998
    public static let fallbackAudioPort: UInt16 = 48_000
    public static let fallbackControlPort: UInt16 = 47_999
    public static let moonlightPrimaryAudioPayloadType = 97
    public static let moonlightAudioFECPayloadType = 127
    public static let pingInterval: Duration = .milliseconds(500)
    public static let describeResponsePreviewByteCount = 512
    public static let ignoredRTPControlPayloadType = 127
    public static let defaultPingASCII = "PING"
    public static let initialVideoDatagramTimeout: Duration = .seconds(10)
    public static let postStartVideoDatagramInactivityTimeoutSeconds: TimeInterval = 4.0
    public static let postStartVideoDatagramInactivityFallbackThresholdSeconds: TimeInterval = 12.0
    public static let udpParseFailureLogLimit = 6
    public static let minimumTransportReadLength = 1
    public static let maximumTransportReadLength = 64 * 1_024
    public static let videoEstimatedPacketPayloadBytes = 1_392
    public static let videoReceiveQueueTargetWindowSeconds: TimeInterval = 0.25
    public static let videoReceiveQueueMinimumTargetWindowSeconds: TimeInterval = 0.08
    public static let videoReceiveQueueTargetWindowFrameBudget = 6.0
    public static let videoReceiveQueueTargetFrameWindow = 3
    public static let videoReceiveQueueMinimumFrameWindow = 2
    public static let videoReceiveQueueMaximumFrameWindow = 4
    public static let videoReceiveQueueModelBitsPerPixel = 0.16
    public static let videoReceiveQueueBitratePacketsPerFrameCapRatio = 1.35
    public static let videoReceiveQueueMinimumPacketsPerFrameEstimate = 8
    public static let videoReceiveQueueMaximumPacketsPerFrameEstimate = 220
    public static let videoReceiveQueueMaximumCapacity = 8_192
    public static let videoReceiveQueueTrimFrameWindow = 3
    public static let videoReceiveQueueRecoveryFrameWindow = 8
    public static let videoReceiveQueueCapacity = 256
    public static let videoDecodeQueueCapacity = 24
    public static let videoDecodeQueueMaximumCapacity = 128
    public static let videoDecodeQueueConsumerMaxBufferedUnits = 10
    public static let videoDecodeQueueDropWindowSeconds: TimeInterval = 1.0
    public static let videoDecodeQueueDropRecoveryThreshold = 32
    public static let videoDecodeQueueRecoveryCooldownSeconds: TimeInterval = 1.0
    public static let videoDecodeQueueProducerTrimToRecentUnits = 2
    public static let videoDecodeQueueConsumerTargetRatio = 0.65
    public static let videoDecodeQueueConsumerPressureExpansionRatio = 0.92
    public static let videoReceiveQueueDropWindowSeconds: TimeInterval = 1.0
    public static let videoReceiveQueueDropRecoveryThreshold = 360
    public static let videoReceiveQueueRecoveryCooldownSeconds: TimeInterval = 0.75
    public static let videoReceiveQueueIngressSheddingMaximumBurstPackets = 240
    public static let videoReceiveQueuePressureTrimAlignmentMaximumExtraPackets = 48
    public static let videoReceiveQueueIngressDropLogInterval = 240
    public static let videoReceiveQueuePressureSignalInterval = 24
    public static let videoReceiveQueuePressureTrimInterval = 60
    public static let videoReceiveQueuePressureTrimToRecentPackets = 48
    public static let videoFrameAssemblyLogInterval = 1_800
    public static let videoDecodeQueueBackpressureLogInterval = 120
    public static let videoDecodeQueueProducerSheddingHighWatermark = 10
    public static let videoDepacketizerDecodeQueueProbeIntervalPackets = 4
    public static let videoDepacketizerDecodeQueueShedHighWatermark = 10
    public static let depacketizerCorruptionWindowSeconds: TimeInterval = 2.0
    public static let depacketizerCorruptionThreshold = 5
    public static let depacketizerRecoveryCooldownSeconds: TimeInterval = 1.5
    public static let depacketizerRecoveryAttemptWindowSeconds: TimeInterval = 8.0
    public static let depacketizerMaxRecoveryAttempts = 3
    public static let av1DepacketizerRecoveryWindowSeconds: TimeInterval = 8.0
    public static let av1MaxDepacketizerRecoveries = 3
    public static let decoderFailureWindowSeconds: TimeInterval = 1.5
    public static let decoderRecoveryCooldownSeconds: TimeInterval = 0.75
    public static let decoderRecoveryAttemptWindowSeconds: TimeInterval = 8.0
    public static let decoderMaxRecoveryAttempts = 3
    public static let av1MaxDecoderRecoveryAttempts = 2
    public static let av1DecoderFastFallbackWindowSeconds: TimeInterval = 20.0
    public static let av1DecoderFastFallbackFailureThreshold = 3
    public static let decoderOutputStallThresholdSeconds: TimeInterval = 2.2
    public static let decoderOutputStallActiveDecodeWindowSeconds: TimeInterval = 0.45
    public static let decoderOutputStallThresholdUnderPressureMultiplier: TimeInterval = 1.75
    public static let decoderOutputStallThresholdConsumerTrimMultiplier: TimeInterval = 2.25
    public static let decoderOutputStallActiveDecodeWindowUnderPressureMultiplier: TimeInterval = 1.35
    public static let decoderOutputStallActiveDecodeWindowConsumerTrimMultiplier: TimeInterval = 1.75
    public static let decoderOutputStallCandidateThreshold = 3
    public static let decoderOutputStallCandidateThresholdUnderPressure = 4
    public static let decoderOutputStallCandidateThresholdConsumerTrim = 6
    public static let decoderOutputStallCandidateWindowSeconds: TimeInterval = 3.0
    public static let decoderOutputStallRecoveryCooldownSeconds: TimeInterval = 1.35
    public static let decoderOutputStallRecoveryWindowSeconds: TimeInterval = 8.0
    public static let decoderMaxOutputStallRecoveries = 4
    public static let av1MaxDecoderOutputStallRecoveries = 4
    public static let av1DecoderOutputStallPressureWindowSeconds: TimeInterval = 6.0
    public static let av1DecoderOutputStallPressureEventsBeforeFallback = 2
    public static let decoderOutputStallSuppressionGraceSeconds: TimeInterval = 6.0
    public static let decoderOutputStallSuppressionMaximumSecondsUnderPressure: TimeInterval = 12.0
    public static let decoderOutputStallPressureSoftRecoveryAttempts = 4
    public static let decoderOutputStallConsumerTrimSoftRecoveryBonusAttempts = 5
    public static let decoderOutputStallPressureHardResetGraceAttempts = 2
    public static let decoderOutputStallConsumerTrimPressureWindowSeconds: TimeInterval = 2.5
    public static let decoderOutputStallConsumerTrimPacingWindowSeconds: TimeInterval = 2.0
    public static let videoQueuePressureRecentSignalWindowSeconds: TimeInterval = 2.5
    public static let videoQueuePressureRecoveryMinimumOutputStallSeconds: TimeInterval = 1.5
    public static let videoRecoveryFrameRequestCooldownSeconds: TimeInterval = 0.75
    public static let videoRecoveryFramePendingTimeoutSeconds: TimeInterval = 2.0
    public static let videoRecoveryFrameRequestUnderPressureCooldownSeconds: TimeInterval = 3.5
    public static let videoRenderSubmitPacingToleranceRatio: Double = 0.80
    public static let videoRenderSubmitDropSummaryInterval = 600
    public static let audioOutputQueueDropWindowSeconds: TimeInterval = 1.0
    public static let audioOutputQueuePressureSignalInterval = 30
    public static let audioOutputQueuePressureTrimInterval = 60
    public static let audioOutputQueuePressureTrimToRecentPackets = 8
    public static let audioOutputQueueDecodeSheddingLowWatermarkSlots = 3
    public static let audioJitterBufferTargetDepth = 6
    public static let audioJitterBufferMaximumDepth = 30
    public static let audioJitterBufferOutOfOrderWaitSeconds: TimeInterval = 0.010
    public static let audioOutputQueueSaturationBurstThreshold = 8
    public static let audioOutputQueueDecodeCooldown: Duration = .milliseconds(24)
    public static let audioPayloadTypeAdaptationObservationThreshold = 3
    public static let audioUnexpectedPayloadTypeLogInterval = 240
    public static let audioDecodeFailureAbortThreshold = 240
    public static let audioDecodeFailureLogInterval = 25
    public static let videoPayloadTypeAdaptationObservationThreshold = 3
    public static let controlRoundTripPublishMinimumIntervalSeconds: TimeInterval = 1.0 / 30.0
    public static let controlRoundTripPublishDeltaThresholdMs = 2
    public static let transientInputSendFailureBurstWindowSeconds: TimeInterval = 3.0
    public static let transientInputSendFailureBurstThreshold = 6
}

public enum ShadowClientRTSPRequestDefaults {
    public static let optionsMethod = "OPTIONS"
    public static let describeMethod = "DESCRIBE"
    public static let setupMethod = "SETUP"
    public static let announceMethod = "ANNOUNCE"
    public static let playMethod = "PLAY"

    public static let protocolVersion = "RTSP/1.0"
    public static let userAgent = "ShadowClient/1.0"
    public static let acceptSDP = "application/sdp"
    public static let ifModifiedSinceEpoch = "Thu, 01 Jan 1970 00:00:00 GMT"
    public static let clientVersionHeaderValue = "14"

    public static let headerAccept = "Accept"
    public static let headerContentLength = "Content-length"
    public static let headerContentType = "Content-type"
    public static let headerHost = "Host"
    public static let headerIfModifiedSince = "If-Modified-Since"
    public static let headerSession = "Session"
    public static let headerTransport = "Transport"
    public static let headerUserAgent = "User-Agent"
    public static let headerClientVersion = "X-GS-ClientVersion"

    public static let responseHeaderSession = "session"
    public static let responseHeaderTransport = "transport"
    public static let responseHeaderContentBase = "content-base"
    public static let responseHeaderContentLocation = "content-location"
    public static let responseHeaderContentLength = "content-length"
    public static let responseHeaderContentType = "content-type"
    public static let responseHeaderPingPayload = "x-ss-ping-payload"
    public static let responseHeaderConnectData = "x-ss-connect-data"
}

public enum ShadowClientPairingDefaults {
    public static let retryDeadlineSeconds: TimeInterval = 70
    public static let maximumAttempts = 4
    public static let retryBackoff: Duration = .milliseconds(900)
}

public enum ShadowClientHostProbeDefaults {
    public static let tcpPortTimeout: Duration = .seconds(1)
}

public enum ShadowClientTelemetrySimulationDefaults {
    public static let sampleInterval: Duration = .milliseconds(500)
    public static let baseRenderedFrames = 1_000
    public static let renderedFrameIncrement = 4

    public static let instabilityCycleLength = 20
    public static let unstableSampleCount = 3

    public static let unstableDroppedFrames = 20
    public static let stableDroppedFrames = 3
    public static let unstableNetworkDroppedFrames = 14
    public static let stableNetworkDroppedFrames = 2

    public static let unstableJitterMs = 72.0
    public static let stableJitterBaseMs = 8.0
    public static let stableJitterVarianceCycle = 5
    public static let unstablePacketLossPercent = 2.4
    public static let stablePacketLossPercent = 0.3
    public static let unstableAVSyncOffsetMs = 55.0
    public static let stableAVSyncOffsetMs = 11.0
}

public enum ShadowClientSunshineControlChannelDefaults {
    public static let connectTimeout: Duration = .seconds(2)
    public static let commandAcknowledgeTimeout: Duration = .seconds(2)
    public static let maximumRoundTripSampleMs = 5_000.0
}

public enum ShadowClientSunshineSessionDefaults {
    public static let prefersSessionIdentifierV1 = true
    public static let supportsEncryptedControlChannelV2 = true
}

public enum ShadowClientUIRuntimeDefaults {
    public static let appListPollingAttempts = 25
    public static let launchStatePollingAttempts = 15
    public static let pollingInterval: Duration = .milliseconds(200)
    public static let streamOutputHeartbeatInterval: Duration = .seconds(1)
    public static let diagnosticsHUDSampleHistoryLimit = 48
    public static let bitrateSignalFreshnessWindowMs = 5_000
}

public enum ShadowClientHostClassificationDefaults {
    public static let localhost = "localhost"
    public static let loopbackIPv6 = "::1"
    public static let linkLocalIPv6Prefix = "fe80:"
    public static let uniqueLocalIPv6PrefixFC = "fc"
    public static let uniqueLocalIPv6PrefixFD = "fd"

    public static let privateIPv4ClassA = 10
    public static let loopbackIPv4ClassA = 127
    public static let privateIPv4ClassCFirstOctet = 192
    public static let privateIPv4ClassCSecondOctet = 168
    public static let privateIPv4ClassBFirstOctet = 172
    public static let privateIPv4ClassBSecondOctetRange = 16 ... 31
    public static let linkLocalIPv4FirstOctet = 169
    public static let linkLocalIPv4SecondOctet = 254
}

public enum ShadowClientAppSettingsDefaults {
    public static let defaultResolution = ShadowClientStreamingResolutionPreset.p1080
    public static let defaultFrameRate = ShadowClientStreamingFrameRatePreset.fps60
    public static let defaultBitrateKbps = 24_000
    public static let defaultAutoBitrate = true
    public static let bitrateStepKbps = 500
    public static let maximumBitrateWhenUnlocked = ShadowClientStreamingLaunchBounds.maximumBitrateKbps
    public static let maximumBitrateWhenLocked = 150_000
    public static let bitrateEstimationBaselineKbps = 24_000
    public static let bitrateEstimationBaselinePixelsPerSecond = 1_920.0 * 1_080.0 * 60.0
    public static let bitrateEstimationScaleExponent = 0.92
}

public enum ShadowClientAudioPlaybackDefaults {
    public static let supportsClientPlayback = true
}

public enum ShadowClientRTSPAnnounceDefaults {
    public static let configuredBitrateKbps = ShadowClientAppSettingsDefaults.defaultBitrateKbps
    public static let bitrateScale = 1.0
    public static let minimumBitrateKbps = 1_000
    public static let maximumBitrateKbps = 100_000
}

public enum ShadowClientGameStreamServerState {
    public static let free = "SUNSHINE_SERVER_FREE"
    public static let idle = "SUNSHINE_SERVER_IDLE"
    public static let idleStates: Set<String> = [free, idle]
}

public enum ShadowClientRemoteAppLabels {
    public static func currentSession(_ gameID: Int) -> String {
        "Current Session (\(gameID))"
    }
}
