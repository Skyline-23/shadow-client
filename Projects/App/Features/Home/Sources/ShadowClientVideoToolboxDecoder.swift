import AVFoundation
import CoreMedia
import CoreVideo
import Foundation
import VideoToolbox

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
    private let onDecodeCompleted: @Sendable () async -> Void

    init(
        bridge: ShadowClientRealtimeDecoderOutputBridge,
        onDecodeCompleted: @escaping @Sendable () async -> Void
    ) {
        self.bridge = bridge
        self.onDecodeCompleted = onDecodeCompleted
    }

    func handleCallback(
        status: OSStatus,
        imageBuffer: CVImageBuffer?
    ) {
        Task(priority: .high) {
            await onDecodeCompleted()
            guard status == noErr,
                  let pixelBuffer = imageBuffer
            else {
                return
            }
            bridge.emit(pixelBuffer)
        }
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
    private var outputCallbackContext: ShadowClientRealtimeDecoderOutputCallbackContext?
    private var frameIndex: Int64 = 0
    private var preferredOutputDimensions: CMVideoDimensions?
    private var decodePresentationTimeScale: CMTimeScale
    private var maximumInFlightDecodeRequests: Int
    private var inFlightDecodeRequests = 0
    private var decodePacingPenalty = 0
    private var decodeSubmitPacingMultiplier = 1.0
    private var lastDecodeSubmitUptime: TimeInterval = 0
    private var lastBackpressureSignalUptime: TimeInterval = 0
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
            for: Int(normalizedPresentationTimeScale)
        )
        decodePacingPenalty = 0
    }

    public func reset() {
        invalidateDecoderSessionForReconfiguration()
        latestParameterSets = []
        av1CodecConfigurationOrigin = nil
        codec = nil
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
        }
    }

    public func setDecodePresentationTimeScale(fps: Int) {
        let boundedFPS = min(max(fps, 1), Int(Int32.max))
        let normalizedPresentationTimeScale = Self.normalizedPresentationTimeScale(
            CMTimeScale(boundedFPS)
        )
        decodePresentationTimeScale = normalizedPresentationTimeScale
        maximumInFlightDecodeRequests = Self.recommendedMaximumInFlightDecodeRequests(
            for: Int(normalizedPresentationTimeScale)
        )
        clampDecodePacingPenalty()
    }

    public func setDecodePresentationTimeScale(_ timescale: CMTimeScale) {
        let normalizedPresentationTimeScale = Self.normalizedPresentationTimeScale(timescale)
        decodePresentationTimeScale = normalizedPresentationTimeScale
        maximumInFlightDecodeRequests = Self.recommendedMaximumInFlightDecodeRequests(
            for: Int(normalizedPresentationTimeScale)
        )
        clampDecodePacingPenalty()
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
        av1FallbackHDR = hdrEnabled
        av1FallbackYUV444 = yuv444Enabled
    }

    public func reportBackpressureSignal() {
        let now = ProcessInfo.processInfo.systemUptime
        lastBackpressureSignalUptime = now
        let maximumPenalty = maximumDecodePacingPenalty()
        decodePacingPenalty = min(maximumPenalty, decodePacingPenalty + 1)
        decodeSubmitPacingMultiplier = min(
            ShadowClientVideoDecoderDefaults.decodePacingMaximumMultiplier,
            decodeSubmitPacingMultiplier + ShadowClientVideoDecoderDefaults.decodePacingMultiplierStep
        )
    }

    public func decode(
        accessUnit annexBAccessUnit: Data,
        codec newCodec: ShadowClientVideoCodec,
        parameterSets explicitParameterSets: [Data],
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
            if !explicitParameterSets.isEmpty {
                latestParameterSets = explicitParameterSets
            }
            if !parsedAccessUnit.parameterSets.isEmpty {
                latestParameterSets = parsedAccessUnit.parameterSets
            }
            samplePayload = parsedAccessUnit.samplePayload
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
                invalidateDecoderSessionForReconfiguration()
            }
            samplePayload = annexBAccessUnit
        }

        try ensureDecoderSession(codec: newCodec, onFrame: onFrame)
        guard let session, let formatDescription else {
            throw ShadowClientVideoToolboxDecoderError.missingParameterSets
        }

        try await waitForSubmitPacingWindow()
        try await waitForDecodeSlot()
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
        let callbackContext = ShadowClientRealtimeDecoderOutputCallbackContext(
            bridge: bridge,
            onDecodeCompleted: { [decoder = self] in
                await decoder.didCompleteDecodeRequest()
            }
        )
        outputBridge = bridge
        outputCallbackContext = callbackContext
        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refCon, _, status, _, imageBuffer, _, _ in
                guard let refCon else {
                    return
                }

                let callbackContext = Unmanaged<ShadowClientRealtimeDecoderOutputCallbackContext>
                    .fromOpaque(refCon)
                    .takeUnretainedValue()
                callbackContext.handleCallback(
                    status: status,
                    imageBuffer: imageBuffer
                )
            },
            decompressionOutputRefCon: UnsafeMutableRawPointer(
                Unmanaged.passUnretained(callbackContext).toOpaque()
            )
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
            throw ShadowClientVideoToolboxDecoderError.cannotCreateDecoder(creationResult.0)
        }

        VTSessionSetProperty(newSession, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        formatDescription = resolvedDescription
        session = newSession
        configuredParameterSets = resolvedParameterSets
    }

    private func invalidateDecoderSessionForReconfiguration() {
        if let session {
            VTDecompressionSessionInvalidate(session)
        }
        outputBridge?.stop()
        session = nil
        formatDescription = nil
        outputBridge = nil
        outputCallbackContext = nil
        configuredParameterSets = []
        frameIndex = 0
        inFlightDecodeRequests = 0
        decodePacingPenalty = 0
        decodeSubmitPacingMultiplier = 1.0
        lastDecodeSubmitUptime = 0
        lastBackpressureSignalUptime = 0
    }

    private func waitForSubmitPacingWindow() async throws {
        let now = ProcessInfo.processInfo.systemUptime
        recoverDecodePacingIfStable(now: now)
        guard lastDecodeSubmitUptime > 0 else {
            return
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

    private func waitForDecodeSlot() async throws {
        while inFlightDecodeRequests >= effectiveMaximumInFlightDecodeRequests() {
            try Task.checkCancellation()
            try await Task.sleep(for: ShadowClientVideoDecoderDefaults.inFlightDecodeWaitStep)
        }
        inFlightDecodeRequests += 1
    }

    private func releaseDecodeSlot() {
        inFlightDecodeRequests = max(0, inFlightDecodeRequests - 1)
    }

    private func didCompleteDecodeRequest() {
        releaseDecodeSlot()
    }

    private func effectiveMaximumInFlightDecodeRequests() -> Int {
        let minimumInFlight = max(1, ShadowClientVideoDecoderDefaults.minimumInFlightDecodeRequests)
        return max(
            minimumInFlight,
            maximumInFlightDecodeRequests - decodePacingPenalty
        )
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

    private func recoverDecodePacingIfStable(now: TimeInterval) {
        guard lastBackpressureSignalUptime > 0 else {
            return
        }
        guard decodePacingPenalty > 0 || decodeSubmitPacingMultiplier > 1.0 else {
            return
        }

        let frameIntervalSeconds = currentFrameIntervalSeconds()
        let recoveryIntervalSeconds = frameIntervalSeconds *
            Double(ShadowClientVideoDecoderDefaults.decodePacingRecoveryFrameWindow)
        guard now - lastBackpressureSignalUptime >= recoveryIntervalSeconds else {
            return
        }

        decodePacingPenalty = max(0, decodePacingPenalty - 1)
        decodeSubmitPacingMultiplier = max(
            1.0,
            decodeSubmitPacingMultiplier - ShadowClientVideoDecoderDefaults.decodePacingMultiplierStep
        )
        lastBackpressureSignalUptime = now
    }

    private func currentFrameIntervalSeconds() -> TimeInterval {
        1.0 / Double(max(1, decodePresentationTimeScale))
    }

    private func currentTargetSubmitIntervalSeconds() -> TimeInterval {
        currentFrameIntervalSeconds() * decodeSubmitPacingMultiplier
    }

    private static func normalizedPresentationTimeScale(_ timescale: CMTimeScale) -> CMTimeScale {
        guard timescale > 0 else {
            return CMTimeScale(ShadowClientVideoDecoderDefaults.defaultDecodePresentationTimeScale)
        }
        return timescale
    }

    static func recommendedMaximumInFlightDecodeRequests(
        for fps: Int,
        activeProcessorCount: Int
    ) -> Int {
        let minimumInFlight = max(1, ShadowClientVideoDecoderDefaults.minimumInFlightDecodeRequests)
        let maximumInFlight = max(minimumInFlight, ShadowClientVideoDecoderDefaults.maximumInFlightDecodeRequests)
        let normalizedFPS = max(fps, ShadowClientStreamingLaunchBounds.minimumFPS)
        let fpsScale = Double(normalizedFPS) / Double(ShadowClientStreamingLaunchBounds.defaultFPS)
        let cpuScaleDivisor = max(1.0, ShadowClientVideoDecoderDefaults.inFlightDecodeCoreScalingDivisor)
        let cpuScale = max(1.0, Double(max(1, activeProcessorCount)) / cpuScaleDivisor)
        let recommendedInFlight = Int(
            (Double(minimumInFlight) * fpsScale * cpuScale).rounded(.toNearestOrAwayFromZero)
        )
        return min(
            maximumInFlight,
            max(minimumInFlight, recommendedInFlight)
        )
    }

    private static func recommendedMaximumInFlightDecodeRequests(for fps: Int) -> Int {
        recommendedMaximumInFlightDecodeRequests(
            for: fps,
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
            ? kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
            : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
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
        let fullRangeValue: CFBoolean = kCFBooleanFalse
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

        guard hasSampleNAL else {
            return nil
        }

        return LengthPrefixedSampleParseResult(
            samplePayload: samplePayload,
            parameterSets: collectedParameterSets(
                codec: codec,
                h264SPS: h264SPS,
                h264PPS: h264PPS,
                h265VPS: h265VPS,
                h265SPS: h265SPS,
                h265PPS: h265PPS
            )
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

        guard index == accessUnit.endIndex, hasSampleNAL else {
            return nil
        }

        return LengthPrefixedSampleParseResult(
            samplePayload: samplePayload,
            parameterSets: collectedParameterSets(
                codec: codec,
                h264SPS: h264SPS,
                h264PPS: h264PPS,
                h265VPS: h265VPS,
                h265SPS: h265SPS,
                h265PPS: h265PPS
            )
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
