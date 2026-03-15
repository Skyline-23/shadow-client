import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox
import ShadowClientFeatureSession

public enum ShadowClientVideoToolboxDecoderError: Error, Equatable, Sendable {
    case missingParameterSets
    case missingAV1CodecConfiguration
    case missingFrameDimensions
    case unsupportedCodec
    case cannotCreateFormatDescription(OSStatus)
    case cannotCreateDecoder(OSStatus)
    case cannotCreateSampleBuffer(OSStatus)
    case decodeFailed(OSStatus)
}

extension ShadowClientVideoToolboxDecoderError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .missingParameterSets:
            return "Waiting for codec parameter sets (SPS/PPS or VPS/SPS/PPS) before decode."
        case .missingAV1CodecConfiguration:
            return "AV1 codec configuration record (av1C) is missing or invalid."
        case .missingFrameDimensions:
            return "Waiting for launch video dimensions before starting decoder."
        case .unsupportedCodec:
            return "Decoder codec is not supported."
        case let .cannotCreateFormatDescription(status):
            return "Could not create video format description (OSStatus \(status))."
        case let .cannotCreateDecoder(status):
            return "Could not create hardware decoder session (OSStatus \(status))."
        case let .cannotCreateSampleBuffer(status):
            return "Could not create sample buffer for decode (OSStatus \(status))."
        case let .decodeFailed(status):
            return "Hardware decode failed (OSStatus \(status))."
        }
    }
}

private final class ShadowClientRealtimeDecoderOutputBridge: @unchecked Sendable {
    private let onFrame: @Sendable (CVPixelBuffer) async -> Void
    private let deliveryQueue = DispatchQueue(
        label: "com.skyline23.shadow-client.video-decoder.output",
        qos: .userInteractive
    )
    private var latestPixelBuffer: CVPixelBuffer?
    private var isDelivering = false
    private var activeDeliveryTask: Task<Void, Never>?

    init(onFrame: @escaping @Sendable (CVPixelBuffer) async -> Void) {
        self.onFrame = onFrame
    }

    deinit {
        activeDeliveryTask?.cancel()
    }

    func emit(_ pixelBuffer: CVPixelBuffer) {
        let sendablePixelBuffer = ShadowClientDecoderSendablePixelBuffer(value: pixelBuffer)
        deliveryQueue.async { [weak self] in
            guard let self else {
                return
            }
            self.latestPixelBuffer = sendablePixelBuffer.value
            self.scheduleDeliveryIfNeeded()
        }
    }

    func stop() {
        activeDeliveryTask?.cancel()
        activeDeliveryTask = nil
        deliveryQueue.async { [weak self] in
            self?.latestPixelBuffer = nil
            self?.isDelivering = false
        }
    }

    func setTargetFramesPerSecond(_ fps: Int) {
        _ = fps
    }

    private func scheduleDeliveryIfNeeded() {
        guard !isDelivering,
              let pixelBuffer = latestPixelBuffer
        else {
            return
        }

        latestPixelBuffer = nil
        isDelivering = true
        let sendablePixelBuffer = ShadowClientDecoderSendablePixelBuffer(value: pixelBuffer)
        activeDeliveryTask = Task { [weak self] in
            guard let self else {
                return
            }
            await self.onFrame(sendablePixelBuffer.value)
            self.deliveryQueue.async { [weak self] in
                guard let self else {
                    return
                }
                self.isDelivering = false
                self.scheduleDeliveryIfNeeded()
            }
        }
    }
}

private final class ShadowClientRealtimeDecoderOutputCallbackContext: @unchecked Sendable {
    private let bridge: ShadowClientRealtimeDecoderOutputBridge
    private let onDecodeCompleted: @Sendable () -> Void
    private let onDecodeFailed: @Sendable (OSStatus) -> Void

    init(
        bridge: ShadowClientRealtimeDecoderOutputBridge,
        onDecodeCompleted: @escaping @Sendable () -> Void,
        onDecodeFailed: @escaping @Sendable (OSStatus) -> Void
    ) {
        self.bridge = bridge
        self.onDecodeCompleted = onDecodeCompleted
        self.onDecodeFailed = onDecodeFailed
    }

    func handleCallback(
        status: OSStatus,
        imageBuffer: CVImageBuffer?
    ) {
        onDecodeCompleted()
        guard status == noErr else {
            onDecodeFailed(status)
            return
        }
        guard let pixelBuffer = imageBuffer else {
            return
        }
        bridge.emit(pixelBuffer)
    }
}

enum ShadowClientRetainedRef {
    static func retain<T: AnyObject>(_ object: T) -> UnsafeMutableRawPointer {
        UnsafeMutableRawPointer(Unmanaged.passRetained(object).toOpaque())
    }

    static func unretainedValue<T: AnyObject>(
        from opaque: UnsafeMutableRawPointer,
        as type: T.Type = T.self
    ) -> T {
        Unmanaged<T>.fromOpaque(opaque).takeUnretainedValue()
    }

    static func release<T: AnyObject>(
        _ opaque: UnsafeMutableRawPointer?,
        as type: T.Type = T.self
    ) {
        guard let opaque else {
            return
        }
        _ = Unmanaged<T>.fromOpaque(opaque).takeRetainedValue()
    }
}

private struct ShadowClientDecoderSendablePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

public actor ShadowClientVideoToolboxDecoder {
    private var codec: ShadowClientVideoCodec?
    private var latestParameterSets: [Data] = []
    private var configuredParameterSets: [Data] = []
    private var formatDescription: CMFormatDescription?
    private var session: VTDecompressionSession?
    private var outputBridge: ShadowClientRealtimeDecoderOutputBridge?
    private var outputCallbackContextRef: UnsafeMutableRawPointer?
    private var frameIndex: Int64 = 0
    private var preferredOutputDimensions: CMVideoDimensions?
    private var decodePresentationTimeScale: CMTimeScale
    private var maximumInFlightDecodeRequests: Int
    private var inFlightDecodeRequests = 0
    private var decodePacingPenalty = 0
    private var decodeSubmitPacingMultiplier = 1.0
    private var lastDecodeSubmitUptime: TimeInterval = 0
    private var lastDecoderInstabilitySignalUptime: TimeInterval = 0
    private var latestPendingDecodeFailure: OSStatus?
    private var av1FallbackHDR = false
    private var av1FallbackYUV444 = false
    private var av1CodecConfigurationOrigin: ShadowClientAV1CodecConfigurationOrigin?

    public init(
        decodePresentationTimeScale: CMTimeScale = CMTimeScale(
            ShadowClientVideoDecoderDefaults.defaultDecodePresentationTimeScale
        )
    ) {
        let normalizedPresentationTimeScale = Self.normalizedPresentationTimeScale(
            decodePresentationTimeScale
        )
        self.decodePresentationTimeScale = normalizedPresentationTimeScale
        maximumInFlightDecodeRequests = Self.recommendedMaximumInFlightDecodeRequests(
            for: Int(normalizedPresentationTimeScale),
            frameWidth: ShadowClientStreamingLaunchBounds.defaultWidth,
            frameHeight: ShadowClientStreamingLaunchBounds.defaultHeight
        )
        decodePacingPenalty = 0
    }

    public func reset() {
        resetForRecovery()
        latestParameterSets = []
        av1CodecConfigurationOrigin = nil
        codec = nil
    }

    public func resetForRecovery() {
        invalidateDecoderSessionForReconfiguration()
    }

    public func setPreferredOutputDimensions(
        width: Int,
        height: Int,
        fps: Int? = nil
    ) {
        preferredOutputDimensions = CMVideoDimensions(
            width: Int32(max(1, width)),
            height: Int32(max(1, height))
        )
        if let fps {
            setDecodePresentationTimeScale(fps: fps)
        } else {
            recalculateDecodeConcurrencyBudget()
        }
    }

    public func setDecodePresentationTimeScale(fps: Int) {
        let boundedFPS = min(max(fps, 1), Int(Int32.max))
        let normalizedPresentationTimeScale = Self.normalizedPresentationTimeScale(
            CMTimeScale(boundedFPS)
        )
        decodePresentationTimeScale = normalizedPresentationTimeScale
        outputBridge?.setTargetFramesPerSecond(Int(normalizedPresentationTimeScale))
        recalculateDecodeConcurrencyBudget()
    }

    public func setDecodePresentationTimeScale(_ timescale: CMTimeScale) {
        let normalizedPresentationTimeScale = Self.normalizedPresentationTimeScale(timescale)
        decodePresentationTimeScale = normalizedPresentationTimeScale
        outputBridge?.setTargetFramesPerSecond(Int(normalizedPresentationTimeScale))
        recalculateDecodeConcurrencyBudget()
    }

    public func applyLaunchSettings(_ settings: ShadowClientGameStreamLaunchSettings) {
        setDecodePresentationTimeScale(fps: settings.fps)
        configureAV1Fallback(
            hdrEnabled: settings.enableHDR,
            yuv444Enabled: settings.enableYUV444
        )
    }

    public func configureAV1Fallback(
        hdrEnabled: Bool,
        yuv444Enabled: Bool
    ) {
        let didChangeAV1FallbackMode =
            av1FallbackHDR != hdrEnabled ||
            av1FallbackYUV444 != yuv444Enabled
        av1FallbackHDR = hdrEnabled
        av1FallbackYUV444 = yuv444Enabled
        if didChangeAV1FallbackMode, codec == .av1 {
            reset()
        }
    }

    public func reportQueueSaturationSignal() {
        lastDecoderInstabilitySignalUptime = ProcessInfo.processInfo.systemUptime
        let reliefStrength = queuePressureReliefStrength()
        decodePacingPenalty = max(0, decodePacingPenalty - reliefStrength)
        let minimumReliefMultiplier = queuePressureReliefMinimumMultiplier()
        decodeSubmitPacingMultiplier = max(
            minimumReliefMultiplier,
            decodeSubmitPacingMultiplier - (ShadowClientVideoDecoderDefaults.decodePacingMultiplierStep * Double(reliefStrength))
        )
    }

    public func reportDecoderInstabilitySignal() {
        let now = ProcessInfo.processInfo.systemUptime
        lastDecoderInstabilitySignalUptime = now
        let severity = decoderInstabilitySeverity()
        let maximumPenalty = maximumDecodePacingPenalty()
        decodePacingPenalty = min(maximumPenalty, decodePacingPenalty + severity)
        decodeSubmitPacingMultiplier = min(
            ShadowClientVideoDecoderDefaults.decodePacingMaximumMultiplier,
            decodeSubmitPacingMultiplier + (ShadowClientVideoDecoderDefaults.decodePacingMultiplierStep * Double(severity))
        )
        clampDecodeSubmitPacingMultiplier()
    }

    public func consumePendingDecodeFailure() -> ShadowClientVideoToolboxDecoderError? {
        guard let status = latestPendingDecodeFailure else {
            return nil
        }
        latestPendingDecodeFailure = nil
        return .decodeFailed(status)
    }

    public func decode(
        accessUnit annexBAccessUnit: Data,
        codec newCodec: ShadowClientVideoCodec,
        parameterSets explicitParameterSets: [Data],
        backlogHint: Int = 0,
        onFrame: @escaping @Sendable (CVPixelBuffer) async -> Void
    ) async throws {
        if codec != newCodec {
            reset()
            codec = newCodec
        }

        let samplePayload: Data
        switch newCodec {
        case .h264, .h265:
            guard let parsedAccessUnit = makeLengthPrefixedSamplePayload(
                from: annexBAccessUnit,
                codec: newCodec
            ) else {
                return
            }
            if !parsedAccessUnit.parameterSets.isEmpty {
                latestParameterSets = parsedAccessUnit.parameterSets
            } else if latestParameterSets.isEmpty, !explicitParameterSets.isEmpty {
                // Use SDP-provided sets for bootstrap only. Prefer in-band sets once observed.
                latestParameterSets = explicitParameterSets
            }
            samplePayload = parsedAccessUnit.samplePayload
            if samplePayload.isEmpty {
                return
            }
        case .av1:
            let discoveredAV1CodecConfiguration = ShadowClientAV1CodecConfigurationBuilder.build(
                fromAccessUnit: annexBAccessUnit
            )
            let fallbackCodecConfiguration = ShadowClientAV1CodecConfigurationBuilder.fallbackCodecConfigurationRecord(
                hdrEnabled: av1FallbackHDR,
                yuv444Enabled: av1FallbackYUV444
            )
            let av1Configuration = ShadowClientAV1CodecConfigurationPolicy.resolve(
                currentParameterSets: latestParameterSets,
                currentOrigin: av1CodecConfigurationOrigin,
                explicitParameterSets: explicitParameterSets,
                discoveredConfiguration: discoveredAV1CodecConfiguration,
                fallbackConfiguration: fallbackCodecConfiguration
            )
            latestParameterSets = av1Configuration.parameterSets
            av1CodecConfigurationOrigin = av1Configuration.origin

            guard !latestParameterSets.isEmpty else {
                return
            }

            if session != nil, configuredParameterSets != latestParameterSets {
                #if DEBUG
                print(
                    "AV1 decoder reconfiguration requested origin=\(String(describing: av1CodecConfigurationOrigin)) " +
                        "configured-bytes=\(configuredParameterSets.first?.count ?? 0) " +
                        "next-bytes=\(latestParameterSets.first?.count ?? 0)"
                )
                #endif
                invalidateDecoderSessionForReconfiguration()
            }
            samplePayload = annexBAccessUnit
        }

        try ensureDecoderSession(codec: newCodec, onFrame: onFrame)
        guard let session, let formatDescription else {
            throw ShadowClientVideoToolboxDecoderError.missingParameterSets
        }

        try await waitForSubmitPacingWindow(backlogHint: backlogHint)
        try await waitForDecodeSlot(backlogHint: backlogHint)
        do {
            let pts = CMTime(value: frameIndex, timescale: decodePresentationTimeScale)
            frameIndex += 1
            let sampleBuffer = try makeSampleBuffer(
                payload: samplePayload,
                formatDescription: formatDescription,
                presentationTimeStamp: pts
            )

            var flagsOut = VTDecodeInfoFlags()
            let flags: VTDecodeFrameFlags = [
                ._EnableAsynchronousDecompression,
                ._1xRealTimePlayback,
            ]
            let status = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sampleBuffer,
                flags: flags,
                frameRefcon: nil,
                infoFlagsOut: &flagsOut
            )
            guard status == noErr else {
                releaseDecodeSlot()
                throw ShadowClientVideoToolboxDecoderError.decodeFailed(status)
            }
            lastDecodeSubmitUptime = ProcessInfo.processInfo.systemUptime
        } catch {
            releaseDecodeSlot()
            throw error
        }
    }

    private func ensureDecoderSession(
        codec: ShadowClientVideoCodec,
        onFrame: @escaping @Sendable (CVPixelBuffer) async -> Void
    ) throws {
        if session != nil {
            return
        }

        let parameterSets = latestParameterSets
        if codec == .av1, parameterSets.isEmpty {
            throw ShadowClientVideoToolboxDecoderError.missingAV1CodecConfiguration
        }
        guard codec == .av1 || !parameterSets.isEmpty else {
            throw ShadowClientVideoToolboxDecoderError.missingParameterSets
        }

        let initialDescription = try makeFormatDescription(
            codec: codec,
            parameterSets: parameterSets
        )

        let bridge = ShadowClientRealtimeDecoderOutputBridge(onFrame: onFrame)
        let decoder = self
        let callbackContext = ShadowClientRealtimeDecoderOutputCallbackContext(
            bridge: bridge,
            onDecodeCompleted: {
                Task {
                    await decoder.releaseDecodeSlot()
                }
            },
            onDecodeFailed: { status in
                Task {
                    await decoder.recordPendingDecodeFailure(status: status)
                }
            }
        )
        let callbackContextRef = ShadowClientRetainedRef.retain(callbackContext)
        bridge.setTargetFramesPerSecond(Int(decodePresentationTimeScale))
        outputBridge = bridge
        outputCallbackContextRef = callbackContextRef
        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refCon, _, status, _, imageBuffer, _, _ in
                guard let refCon else {
                    return
                }

                let callbackContext: ShadowClientRealtimeDecoderOutputCallbackContext =
                    ShadowClientRetainedRef.unretainedValue(
                        from: refCon
                    )
                callbackContext.handleCallback(
                    status: status,
                    imageBuffer: imageBuffer
                )
            },
            decompressionOutputRefCon: callbackContextRef
        )

        let fallbackPixelBufferAttributes = Self.defaultPixelBufferAttributes
        let preferredPixelBufferAttributes = pixelBufferAttributes(for: codec)
        let shouldRetryWithoutPreferredPixelFormat = codec == .av1

        func createDecompressionSession(
            formatDescription: CMFormatDescription,
            imageBufferAttributes: [String: Any]
        ) -> (OSStatus, VTDecompressionSession?) {
            var createdSession: VTDecompressionSession?
            let creationStatus = VTDecompressionSessionCreate(
                allocator: kCFAllocatorDefault,
                formatDescription: formatDescription,
                decoderSpecification: Self.hardwareDecoderSpecification,
                imageBufferAttributes: imageBufferAttributes as CFDictionary,
                outputCallback: &callbackRecord,
                decompressionSessionOut: &createdSession
            )
            return (creationStatus, createdSession)
        }

        func createDecompressionSession(
            formatDescription: CMFormatDescription
        ) -> (OSStatus, VTDecompressionSession?) {
            let preferredResult = createDecompressionSession(
                formatDescription: formatDescription,
                imageBufferAttributes: preferredPixelBufferAttributes
            )
            if preferredResult.0 == noErr || !shouldRetryWithoutPreferredPixelFormat {
                return preferredResult
            }
            return createDecompressionSession(
                formatDescription: formatDescription,
                imageBufferAttributes: fallbackPixelBufferAttributes
            )
        }

        var resolvedParameterSets = parameterSets
        var resolvedDescription = initialDescription
        var creationResult = createDecompressionSession(formatDescription: resolvedDescription)

        if codec == .av1,
           creationResult.0 != noErr,
           av1CodecConfigurationOrigin != .fallback
        {
            let fallbackParameterSets = [
                ShadowClientAV1CodecConfigurationBuilder.fallbackCodecConfigurationRecord(
                    hdrEnabled: av1FallbackHDR,
                    yuv444Enabled: av1FallbackYUV444
                ),
            ]
            if resolvedParameterSets != fallbackParameterSets {
                let fallbackDescription = try makeFormatDescription(
                    codec: .av1,
                    parameterSets: fallbackParameterSets
                )
                resolvedDescription = fallbackDescription
                creationResult = createDecompressionSession(formatDescription: fallbackDescription)
                if creationResult.0 == noErr {
                    latestParameterSets = fallbackParameterSets
                    av1CodecConfigurationOrigin = .fallback
                    resolvedParameterSets = fallbackParameterSets
                }
            }
        }

        guard creationResult.0 == noErr, let newSession = creationResult.1 else {
            ShadowClientRetainedRef.release(
                outputCallbackContextRef,
                as: ShadowClientRealtimeDecoderOutputCallbackContext.self
            )
            outputCallbackContextRef = nil
            throw ShadowClientVideoToolboxDecoderError.cannotCreateDecoder(creationResult.0)
        }

        VTSessionSetProperty(newSession, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        formatDescription = resolvedDescription
        session = newSession
        configuredParameterSets = resolvedParameterSets
    }

    private func invalidateDecoderSessionForReconfiguration() {
        if let session {
            VTDecompressionSessionWaitForAsynchronousFrames(session)
            VTDecompressionSessionInvalidate(session)
        }
        outputBridge?.stop()
        session = nil
        formatDescription = nil
        outputBridge = nil
        ShadowClientRetainedRef.release(
            outputCallbackContextRef,
            as: ShadowClientRealtimeDecoderOutputCallbackContext.self
        )
        outputCallbackContextRef = nil
        configuredParameterSets = []
        frameIndex = 0
        inFlightDecodeRequests = 0
        latestPendingDecodeFailure = nil
        decodePacingPenalty = 0
        decodeSubmitPacingMultiplier = 1.0
        lastDecodeSubmitUptime = 0
        lastDecoderInstabilitySignalUptime = 0
    }

    private func waitForSubmitPacingWindow(backlogHint: Int) async throws {
        let now = ProcessInfo.processInfo.systemUptime
        recoverDecodePacingIfStable(now: now)
        guard lastDecodeSubmitUptime > 0 else {
            return
        }
        let normalizedBacklogHint = max(0, backlogHint)
        if normalizedBacklogHint > 0 {
            let instabilityGraceSeconds = currentFrameIntervalSeconds() * 2.0
            let shouldHonorPacingDespiteBacklog =
                lastDecoderInstabilitySignalUptime > 0 &&
                now - lastDecoderInstabilitySignalUptime < instabilityGraceSeconds
            if !shouldHonorPacingDespiteBacklog {
                return
            }
        }

        let targetIntervalSeconds = currentTargetSubmitIntervalSeconds()
        let nextSubmitUptime = lastDecodeSubmitUptime + targetIntervalSeconds
        guard now < nextSubmitUptime else {
            return
        }

        let waitMilliseconds = Int(((nextSubmitUptime - now) * 1_000).rounded(.up))
        if waitMilliseconds > 0 {
            try await Task.sleep(for: .milliseconds(waitMilliseconds))
        }
    }

    private func waitForDecodeSlot(backlogHint: Int) async throws {
        var spinAttempts = 0
        while !tryAcquireDecodeSlot(
            limit: effectiveMaximumInFlightDecodeRequests(backlogHint: backlogHint)
        ) {
            try Task.checkCancellation()
            spinAttempts += 1
            if spinAttempts <= 2 {
                await Task.yield()
                continue
            }
            try await Task.sleep(for: currentInFlightDecodeWaitStep())
        }
    }

    private func releaseDecodeSlot() {
        inFlightDecodeRequests = max(0, inFlightDecodeRequests - 1)
    }

    private func tryAcquireDecodeSlot(limit: Int) -> Bool {
        guard inFlightDecodeRequests < limit else {
            return false
        }
        inFlightDecodeRequests += 1
        return true
    }

    private func recordPendingDecodeFailure(status: OSStatus) {
        guard status != noErr else {
            return
        }
        latestPendingDecodeFailure = status
    }

    private func recalculateDecodeConcurrencyBudget() {
        let dimensions = preferredOutputDimensions ?? CMVideoDimensions(
            width: Int32(ShadowClientStreamingLaunchBounds.defaultWidth),
            height: Int32(ShadowClientStreamingLaunchBounds.defaultHeight)
        )
        maximumInFlightDecodeRequests = Self.recommendedMaximumInFlightDecodeRequests(
            for: Int(decodePresentationTimeScale),
            frameWidth: Int(dimensions.width),
            frameHeight: Int(dimensions.height)
        )
        clampDecodePacingPenalty()
        clampDecodeSubmitPacingMultiplier()
    }

    private func effectiveMaximumInFlightDecodeRequests(backlogHint: Int = 0) -> Int {
        let minimumInFlight = max(1, ShadowClientVideoDecoderDefaults.minimumInFlightDecodeRequests)
        let baseBudget = max(
            minimumInFlight,
            maximumInFlightDecodeRequests - decodePacingPenalty
        )
        let backlogBoost = adaptiveBacklogInFlightBoost(backlogHint: backlogHint)
        return min(
            maximumInFlightDecodeRequests,
            max(minimumInFlight, baseBudget + backlogBoost)
        )
    }

    private func adaptiveBacklogInFlightBoost(backlogHint: Int) -> Int {
        let normalizedBacklogHint = max(0, backlogHint)
        guard normalizedBacklogHint > 0 else {
            return 0
        }

        let divisor = max(1, ShadowClientVideoDecoderDefaults.inFlightDecodeBacklogBoostDivisor)
        let maxBoost = max(0, ShadowClientVideoDecoderDefaults.inFlightDecodeMaximumBacklogBoost)
        guard maxBoost > 0 else {
            return 0
        }

        var boost = min(maxBoost, normalizedBacklogHint / divisor)
        guard boost > 0 else {
            return 0
        }

        let now = ProcessInfo.processInfo.systemUptime
        let instabilityGraceSeconds = currentFrameIntervalSeconds() * max(
            1.0,
            ShadowClientVideoDecoderDefaults.inFlightDecodeInstabilityGraceFrameWindow
        )
        let isRecentlyUnstable = lastDecoderInstabilitySignalUptime > 0 &&
            now - lastDecoderInstabilitySignalUptime < instabilityGraceSeconds
        if isRecentlyUnstable {
            let dampingRatio = min(
                1.0,
                max(
                    0.0,
                    ShadowClientVideoDecoderDefaults.inFlightDecodeBacklogBoostInstabilityDampingRatio
                )
            )
            boost = Int((Double(boost) * dampingRatio).rounded(.down))
        }

        return max(0, boost)
    }

    private func maximumDecodePacingPenalty() -> Int {
        max(
            0,
            maximumInFlightDecodeRequests - max(1, ShadowClientVideoDecoderDefaults.minimumInFlightDecodeRequests)
        )
    }

    private func clampDecodePacingPenalty() {
        decodePacingPenalty = min(
            decodePacingPenalty,
            maximumDecodePacingPenalty()
        )
    }

    private func clampDecodeSubmitPacingMultiplier() {
        let minimumMultiplier = minimumDecodeSubmitPacingMultiplier()
        let maximumMultiplier = max(
            minimumMultiplier,
            ShadowClientVideoDecoderDefaults.decodePacingMaximumMultiplier
        )
        decodeSubmitPacingMultiplier = min(
            maximumMultiplier,
            max(minimumMultiplier, decodeSubmitPacingMultiplier)
        )
    }

    private func recoverDecodePacingIfStable(now: TimeInterval) {
        guard lastDecoderInstabilitySignalUptime > 0 else {
            return
        }
        guard decodePacingPenalty > 0 || abs(decodeSubmitPacingMultiplier - 1.0) > .ulpOfOne else {
            return
        }

        let frameIntervalSeconds = currentFrameIntervalSeconds()
        let recoveryIntervalSeconds = frameIntervalSeconds *
            Double(ShadowClientVideoDecoderDefaults.decodePacingRecoveryFrameWindow)
        guard now - lastDecoderInstabilitySignalUptime >= recoveryIntervalSeconds else {
            return
        }

        decodePacingPenalty = max(0, decodePacingPenalty - 1)
        if decodeSubmitPacingMultiplier > 1.0 {
            decodeSubmitPacingMultiplier = max(
                1.0,
                decodeSubmitPacingMultiplier - ShadowClientVideoDecoderDefaults.decodePacingMultiplierStep
            )
        } else if decodeSubmitPacingMultiplier < 1.0 {
            decodeSubmitPacingMultiplier = min(
                1.0,
                decodeSubmitPacingMultiplier + ShadowClientVideoDecoderDefaults.decodePacingMultiplierStep
            )
        }
        lastDecoderInstabilitySignalUptime = now
    }

    private func currentFrameIntervalSeconds() -> TimeInterval {
        1.0 / Double(max(1, decodePresentationTimeScale))
    }

    private func currentDecodeWorkloadScale() -> Double {
        let dimensions = preferredOutputDimensions ?? CMVideoDimensions(
            width: Int32(ShadowClientStreamingLaunchBounds.defaultWidth),
            height: Int32(ShadowClientStreamingLaunchBounds.defaultHeight)
        )
        let normalizedWidth = max(ShadowClientStreamingLaunchBounds.minimumWidth, Int(dimensions.width))
        let normalizedHeight = max(ShadowClientStreamingLaunchBounds.minimumHeight, Int(dimensions.height))
        let normalizedFPS = max(Int(decodePresentationTimeScale), ShadowClientStreamingLaunchBounds.minimumFPS)
        let baselinePixelsPerSecond = Double(
            ShadowClientStreamingLaunchBounds.defaultWidth *
                ShadowClientStreamingLaunchBounds.defaultHeight *
                ShadowClientStreamingLaunchBounds.defaultFPS
        )
        let pixelsPerSecond = Double(normalizedWidth * normalizedHeight * normalizedFPS)
        return max(0.25, pixelsPerSecond / max(1.0, baselinePixelsPerSecond))
    }

    private func queuePressureReliefStrength() -> Int {
        let scale = currentDecodeWorkloadScale()
        if scale >= 5.0 {
            return 5
        }
        if scale >= 3.0 {
            return 4
        }
        if scale >= 1.5 {
            return 3
        }
        return 2
    }

    private func queuePressureReliefMinimumMultiplier() -> Double {
        let scale = currentDecodeWorkloadScale()
        let defaultMinimum = minimumDecodeSubmitPacingMultiplier()
        if scale >= 5.0 {
            return max(0.70, defaultMinimum)
        }
        if scale >= 3.0 {
            return max(0.75, defaultMinimum)
        }
        if scale >= 1.5 {
            return max(0.85, defaultMinimum)
        }
        return defaultMinimum
    }

    private func decoderInstabilitySeverity() -> Int {
        let scale = currentDecodeWorkloadScale()
        if scale >= 3.0 {
            return 3
        }
        if scale >= 1.5 {
            return 2
        }
        return 1
    }

    private func currentTargetSubmitIntervalSeconds() -> TimeInterval {
        currentFrameIntervalSeconds() * max(
            minimumDecodeSubmitPacingMultiplier(),
            decodeSubmitPacingMultiplier
        )
    }

    private func currentInFlightDecodeWaitStep() -> Duration {
        let frameIntervalSeconds = currentFrameIntervalSeconds()
        let waitSeconds = min(
            0.0015,
            max(0.0002, frameIntervalSeconds * 0.05)
        )
        return .nanoseconds(Int((waitSeconds * 1_000_000_000).rounded(.up)))
    }

    private func minimumDecodeSubmitPacingMultiplier() -> Double {
        min(
            1.0,
            max(0.1, ShadowClientVideoDecoderDefaults.decodePacingMinimumMultiplier)
        )
    }

    private static func normalizedPresentationTimeScale(_ timescale: CMTimeScale) -> CMTimeScale {
        guard timescale > 0 else {
            return CMTimeScale(ShadowClientVideoDecoderDefaults.defaultDecodePresentationTimeScale)
        }
        return timescale
    }

    static func recommendedMaximumInFlightDecodeRequests(
        for fps: Int,
        frameWidth: Int,
        frameHeight: Int,
        activeProcessorCount: Int
    ) -> Int {
        let minimumInFlight = max(1, ShadowClientVideoDecoderDefaults.minimumInFlightDecodeRequests)
        let maximumInFlight = max(minimumInFlight, ShadowClientVideoDecoderDefaults.maximumInFlightDecodeRequests)
        let normalizedFPS = max(fps, ShadowClientStreamingLaunchBounds.minimumFPS)
        let normalizedWidth = max(frameWidth, ShadowClientStreamingLaunchBounds.minimumWidth)
        let normalizedHeight = max(frameHeight, ShadowClientStreamingLaunchBounds.minimumHeight)
        let baselinePixelsPerSecond = Double(
            ShadowClientStreamingLaunchBounds.defaultWidth *
                ShadowClientStreamingLaunchBounds.defaultHeight *
                ShadowClientStreamingLaunchBounds.defaultFPS
        )
        let requestedPixelsPerSecond = Double(normalizedWidth * normalizedHeight * normalizedFPS)
        let workloadScale = max(0.25, requestedPixelsPerSecond / max(1.0, baselinePixelsPerSecond))
        let cpuScaleDivisor = max(1.0, ShadowClientVideoDecoderDefaults.inFlightDecodeCoreScalingDivisor)
        let cpuScale = min(
            ShadowClientVideoDecoderDefaults.inFlightDecodeMaximumCoreScale,
            max(1.0, Double(max(1, activeProcessorCount)) / cpuScaleDivisor)
        )
        let workloadGrowth = max(
            1.0,
            pow(
                workloadScale,
                ShadowClientVideoDecoderDefaults.inFlightDecodeWorkloadGrowthExponent
            )
        )
        let fpsBoost = max(
            1.0,
            pow(
                Double(normalizedFPS) / Double(max(1, ShadowClientStreamingLaunchBounds.defaultFPS)),
                ShadowClientVideoDecoderDefaults.inFlightDecodeFPSBoostExponent
            )
        )
        let recommendedInFlight = Int(
            (Double(minimumInFlight) * cpuScale * workloadGrowth * fpsBoost)
                .rounded(.toNearestOrAwayFromZero)
        )
        return min(
            maximumInFlight,
            max(minimumInFlight, recommendedInFlight)
        )
    }

    static func recommendedMaximumInFlightDecodeRequests(
        for fps: Int,
        frameWidth: Int,
        frameHeight: Int
    ) -> Int {
        recommendedMaximumInFlightDecodeRequests(
            for: fps,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
        )
    }

    static func recommendedMaximumInFlightDecodeRequests(
        for fps: Int,
        activeProcessorCount: Int
    ) -> Int {
        recommendedMaximumInFlightDecodeRequests(
            for: fps,
            frameWidth: ShadowClientStreamingLaunchBounds.defaultWidth,
            frameHeight: ShadowClientStreamingLaunchBounds.defaultHeight,
            activeProcessorCount: activeProcessorCount
        )
    }

    private static func recommendedMaximumInFlightDecodeRequests(for fps: Int) -> Int {
        recommendedMaximumInFlightDecodeRequests(
            for: fps,
            frameWidth: ShadowClientStreamingLaunchBounds.defaultWidth,
            frameHeight: ShadowClientStreamingLaunchBounds.defaultHeight,
            activeProcessorCount: ProcessInfo.processInfo.activeProcessorCount
        )
    }

    private static var defaultPixelBufferAttributes: [String: Any] {
        [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
            kCVPixelBufferPoolMinimumBufferCountKey as String:
                ShadowClientVideoDecoderDefaults.defaultPixelBufferPoolMinimumBufferCount,
        ]
    }

    private static var hardwareDecoderSpecification: CFDictionary {
        [
            kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: true,
            kVTVideoDecoderSpecification_RequireHardwareAcceleratedVideoDecoder as String: true,
        ] as CFDictionary
    }

    private func pixelBufferAttributes(for codec: ShadowClientVideoCodec) -> [String: Any] {
        var attributes = Self.defaultPixelBufferAttributes
        guard codec == .av1 else {
            return attributes
        }

        let pixelFormat: OSType = av1FallbackHDR
            ? kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
        attributes[kCVPixelBufferPixelFormatTypeKey as String] = pixelFormat
        return attributes
    }

    private func makeFormatDescription(
        codec: ShadowClientVideoCodec,
        parameterSets: [Data]
    ) throws -> CMFormatDescription {
        switch codec {
        case .h264:
            let ordered = normalizeH264ParameterSets(parameterSets)
            guard ordered.count >= 2 else {
                throw ShadowClientVideoToolboxDecoderError.missingParameterSets
            }

            var formatDescription: CMFormatDescription?
            let status = withUnsafeParameterSetPointers(ordered) { pointers, sizes in
                pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: pointerBuffer.count,
                            parameterSetPointers: pointerBuffer.baseAddress!,
                            parameterSetSizes: sizeBuffer.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &formatDescription
                        )
                    }
                }
            }
            guard status == noErr, let formatDescription else {
                throw ShadowClientVideoToolboxDecoderError.cannotCreateFormatDescription(status)
            }
            return formatDescription
        case .h265:
            guard parameterSets.count >= 3 else {
                throw ShadowClientVideoToolboxDecoderError.missingParameterSets
            }

            var formatDescription: CMFormatDescription?
            let status = withUnsafeParameterSetPointers(parameterSets) { pointers, sizes in
                pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: pointerBuffer.count,
                            parameterSetPointers: pointerBuffer.baseAddress!,
                            parameterSetSizes: sizeBuffer.baseAddress!,
                            nalUnitHeaderLength: 4,
                            extensions: nil,
                            formatDescriptionOut: &formatDescription
                        )
                    }
                }
            }
            guard status == noErr, let formatDescription else {
                throw ShadowClientVideoToolboxDecoderError.cannotCreateFormatDescription(status)
            }
            return formatDescription
        case .av1:
            guard #available(iOS 17.0, macOS 14.0, tvOS 17.0, *) else {
                throw ShadowClientVideoToolboxDecoderError.unsupportedCodec
            }
            guard let dimensions = preferredOutputDimensions else {
                throw ShadowClientVideoToolboxDecoderError.missingFrameDimensions
            }
            guard let codecConfiguration = firstAV1CodecConfiguration(from: parameterSets) else {
                throw ShadowClientVideoToolboxDecoderError.missingAV1CodecConfiguration
            }

            let sampleDescriptionAtoms: [CFString: Any] = [
                "av1C" as CFString: codecConfiguration as CFData,
            ]
            var extensions: [CFString: Any] = [
                kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: sampleDescriptionAtoms as CFDictionary,
            ]
            for (key, value) in av1FormatColorExtensions() {
                extensions[key] = value
            }

            var formatDescription: CMFormatDescription?
            let status = CMVideoFormatDescriptionCreate(
                allocator: kCFAllocatorDefault,
                codecType: kCMVideoCodecType_AV1,
                width: dimensions.width,
                height: dimensions.height,
                extensions: extensions as CFDictionary,
                formatDescriptionOut: &formatDescription
            )
            guard status == noErr, let formatDescription else {
                throw ShadowClientVideoToolboxDecoderError.cannotCreateFormatDescription(status)
            }
            return formatDescription
        }
    }

    private func av1FormatColorExtensions() -> [CFString: Any] {
        let fullRangeValue: CFBoolean = kCFBooleanTrue
        if av1FallbackHDR {
            return [
                kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_2020,
                kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ,
                kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_2020,
                kCMFormatDescriptionExtension_FullRangeVideo: fullRangeValue,
            ]
        }

        return [
            kCVImageBufferColorPrimariesKey: kCVImageBufferColorPrimaries_ITU_R_709_2,
            kCVImageBufferTransferFunctionKey: kCVImageBufferTransferFunction_ITU_R_709_2,
            kCVImageBufferYCbCrMatrixKey: kCVImageBufferYCbCrMatrix_ITU_R_709_2,
            kCMFormatDescriptionExtension_FullRangeVideo: fullRangeValue,
        ]
    }

    private func normalizeH264ParameterSets(_ sets: [Data]) -> [Data] {
        var sps: Data?
        var pps: Data?
        for parameterSet in sets {
            guard let first = parameterSet.first else {
                continue
            }
            let type = first & 0x1F
            if type == 7 {
                sps = parameterSet
            } else if type == 8 {
                pps = parameterSet
            }
        }

        var ordered: [Data] = []
        if let sps {
            ordered.append(sps)
        }
        if let pps {
            ordered.append(pps)
        }

        if ordered.count >= 2 {
            return ordered
        }

        for parameterSet in sets where !ordered.contains(parameterSet) {
            ordered.append(parameterSet)
        }
        return ordered
    }

    private func firstAV1CodecConfiguration(from parameterSets: [Data]) -> Data? {
        for parameterSet in parameterSets where isLikelyAV1CodecConfigurationRecord(parameterSet) {
            return parameterSet
        }
        return nil
    }

    private func isLikelyAV1CodecConfigurationRecord(_ value: Data) -> Bool {
        guard value.count >= 4 else {
            return false
        }

        let markerSet = (value[0] & 0x80) != 0
        let version = value[0] & 0x7F
        return markerSet && version >= 1
    }

    private func makeSampleBuffer(
        payload: Data,
        formatDescription: CMFormatDescription,
        presentationTimeStamp: CMTime
    ) throws -> CMSampleBuffer {
        var blockBuffer: CMBlockBuffer?
        var status = CMBlockBufferCreateEmpty(
            allocator: kCFAllocatorDefault,
            capacity: 0,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr, let blockBuffer else {
            throw ShadowClientVideoToolboxDecoderError.cannotCreateSampleBuffer(status)
        }

        status = CMBlockBufferAppendMemoryBlock(
            blockBuffer,
            memoryBlock: nil,
            length: payload.count,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: payload.count,
            flags: 0
        )
        guard status == noErr else {
            throw ShadowClientVideoToolboxDecoderError.cannotCreateSampleBuffer(status)
        }

        payload.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else {
                return
            }
            CMBlockBufferReplaceDataBytes(
                with: base,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: payload.count
            )
        }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: presentationTimeStamp,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        var sampleSize = payload.count
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw ShadowClientVideoToolboxDecoderError.cannotCreateSampleBuffer(status)
        }
        return sampleBuffer
    }

    private struct LengthPrefixedSampleParseResult {
        let samplePayload: Data
        let parameterSets: [Data]
    }

    private enum NALUnitDisposition {
        case sample
        case ignore
        case h264SPS
        case h264PPS
        case h265VPS
        case h265SPS
        case h265PPS
    }

    private func makeLengthPrefixedSamplePayload(
        from accessUnit: Data,
        codec: ShadowClientVideoCodec
    ) -> LengthPrefixedSampleParseResult? {
        makeLengthPrefixedSamplePayloadFromAnnexB(
            accessUnit,
            codec: codec
        ) ?? makeLengthPrefixedSamplePayloadFromLengthPrefixed(
            accessUnit,
            codec: codec
        )
    }

    private func makeLengthPrefixedSamplePayloadFromAnnexB(
        _ accessUnit: Data,
        codec: ShadowClientVideoCodec
    ) -> LengthPrefixedSampleParseResult? {
        var samplePayload = Data()
        samplePayload.reserveCapacity(accessUnit.count + 32)

        var h264SPS: Data?
        var h264PPS: Data?
        var h265VPS: Data?
        var h265SPS: Data?
        var h265PPS: Data?
        var hasSampleNAL = false

        var index = accessUnit.startIndex
        while index < accessUnit.endIndex {
            let prefixLength = annexBStartCodeLength(in: accessUnit, at: index)
            if prefixLength == 0 {
                index += 1
                continue
            }

            let nalStart = index + prefixLength
            var next = nalStart
            while next < accessUnit.endIndex {
                if annexBStartCodeLength(in: accessUnit, at: next) > 0 {
                    break
                }
                next += 1
            }

            if nalStart < next {
                consumeNALUnit(
                    from: accessUnit,
                    range: nalStart ..< next,
                    codec: codec,
                    samplePayload: &samplePayload,
                    hasSampleNAL: &hasSampleNAL,
                    h264SPS: &h264SPS,
                    h264PPS: &h264PPS,
                    h265VPS: &h265VPS,
                    h265SPS: &h265SPS,
                    h265PPS: &h265PPS
                )
            }
            index = next
        }

        let parameterSets = collectedParameterSets(
            codec: codec,
            h264SPS: h264SPS,
            h264PPS: h264PPS,
            h265VPS: h265VPS,
            h265SPS: h265SPS,
            h265PPS: h265PPS
        )

        guard hasSampleNAL || !parameterSets.isEmpty else {
            return nil
        }

        return LengthPrefixedSampleParseResult(
            samplePayload: samplePayload,
            parameterSets: parameterSets
        )
    }

    private func makeLengthPrefixedSamplePayloadFromLengthPrefixed(
        _ accessUnit: Data,
        codec: ShadowClientVideoCodec
    ) -> LengthPrefixedSampleParseResult? {
        var samplePayload = Data()
        samplePayload.reserveCapacity(accessUnit.count)

        var h264SPS: Data?
        var h264PPS: Data?
        var h265VPS: Data?
        var h265SPS: Data?
        var h265PPS: Data?
        var hasSampleNAL = false

        var index = accessUnit.startIndex
        while index + 4 <= accessUnit.endIndex {
            let length = Int(accessUnit[index]) << 24 |
                Int(accessUnit[index + 1]) << 16 |
                Int(accessUnit[index + 2]) << 8 |
                Int(accessUnit[index + 3])
            index += 4

            guard length > 0 else {
                return nil
            }
            let nalEnd = index + length
            guard nalEnd <= accessUnit.endIndex else {
                return nil
            }

            consumeNALUnit(
                from: accessUnit,
                range: index ..< nalEnd,
                codec: codec,
                samplePayload: &samplePayload,
                hasSampleNAL: &hasSampleNAL,
                h264SPS: &h264SPS,
                h264PPS: &h264PPS,
                h265VPS: &h265VPS,
                h265SPS: &h265SPS,
                h265PPS: &h265PPS
            )
            index = nalEnd
        }

        let parameterSets = collectedParameterSets(
            codec: codec,
            h264SPS: h264SPS,
            h264PPS: h264PPS,
            h265VPS: h265VPS,
            h265SPS: h265SPS,
            h265PPS: h265PPS
        )

        guard index == accessUnit.endIndex, hasSampleNAL || !parameterSets.isEmpty else {
            return nil
        }

        return LengthPrefixedSampleParseResult(
            samplePayload: samplePayload,
            parameterSets: parameterSets
        )
    }

    private func consumeNALUnit(
        from accessUnit: Data,
        range: Range<Int>,
        codec: ShadowClientVideoCodec,
        samplePayload: inout Data,
        hasSampleNAL: inout Bool,
        h264SPS: inout Data?,
        h264PPS: inout Data?,
        h265VPS: inout Data?,
        h265SPS: inout Data?,
        h265PPS: inout Data?
    ) {
        let disposition = nalUnitDisposition(
            in: accessUnit,
            range: range,
            codec: codec
        )
        switch disposition {
        case .sample:
            hasSampleNAL = true
            var nalLength = UInt32(range.count).bigEndian
            withUnsafeBytes(of: &nalLength) { samplePayload.append(contentsOf: $0) }
            samplePayload.append(accessUnit[range])
        case .ignore:
            break
        case .h264SPS:
            h264SPS = Data(accessUnit[range])
        case .h264PPS:
            h264PPS = Data(accessUnit[range])
        case .h265VPS:
            h265VPS = Data(accessUnit[range])
        case .h265SPS:
            h265SPS = Data(accessUnit[range])
        case .h265PPS:
            h265PPS = Data(accessUnit[range])
        }
    }

    private func nalUnitDisposition(
        in accessUnit: Data,
        range: Range<Int>,
        codec: ShadowClientVideoCodec
    ) -> NALUnitDisposition {
        guard !range.isEmpty else {
            return .ignore
        }

        switch codec {
        case .h264:
            let nalType = accessUnit[range.lowerBound] & 0x1F
            switch nalType {
            case 7:
                return .h264SPS
            case 8:
                return .h264PPS
            case 9:
                return .ignore
            default:
                return .sample
            }
        case .h265:
            guard range.count >= 2 else {
                return .ignore
            }
            let nalType = (accessUnit[range.lowerBound] >> 1) & 0x3F
            switch nalType {
            case 32:
                return .h265VPS
            case 33:
                return .h265SPS
            case 34:
                return .h265PPS
            default:
                return .sample
            }
        case .av1:
            return .sample
        }
    }

    private func collectedParameterSets(
        codec: ShadowClientVideoCodec,
        h264SPS: Data?,
        h264PPS: Data?,
        h265VPS: Data?,
        h265SPS: Data?,
        h265PPS: Data?
    ) -> [Data] {
        switch codec {
        case .h264:
            if let h264SPS, let h264PPS {
                return [h264SPS, h264PPS]
            }
            return []
        case .h265:
            if let h265VPS, let h265SPS, let h265PPS {
                return [h265VPS, h265SPS, h265PPS]
            }
            return []
        case .av1:
            return []
        }
    }

    private func annexBStartCodeLength(in accessUnit: Data, at index: Int) -> Int {
        let remaining = accessUnit.count - index
        guard remaining >= 3 else {
            return 0
        }
        if accessUnit[index] == 0 && accessUnit[index + 1] == 0 && accessUnit[index + 2] == 1 {
            return 3
        }
        if remaining >= 4 &&
            accessUnit[index] == 0 &&
            accessUnit[index + 1] == 0 &&
            accessUnit[index + 2] == 0 &&
            accessUnit[index + 3] == 1
        {
            return 4
        }
        return 0
    }

    private func withUnsafeParameterSetPointers<T>(
        _ parameterSets: [Data],
        body: ([UnsafePointer<UInt8>], [Int]) -> T
    ) -> T {
        var pointers: [UnsafePointer<UInt8>] = []
        var sizes: [Int] = []
        pointers.reserveCapacity(parameterSets.count)
        sizes.reserveCapacity(parameterSets.count)

        func recurse(index: Int) -> T {
            if index == parameterSets.count {
                return body(pointers, sizes)
            }

            return parameterSets[index].withUnsafeBytes { rawBuffer in
                pointers.append(rawBuffer.bindMemory(to: UInt8.self).baseAddress!)
                sizes.append(parameterSets[index].count)
                defer {
                    pointers.removeLast()
                    sizes.removeLast()
                }
                return recurse(index: index + 1)
            }
        }

        return recurse(index: 0)
    }
}
