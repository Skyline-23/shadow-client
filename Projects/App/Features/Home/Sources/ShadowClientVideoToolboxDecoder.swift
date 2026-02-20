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

    init(onFrame: @escaping @Sendable (CVPixelBuffer) async -> Void) {
        self.onFrame = onFrame
    }

    func emit(_ pixelBuffer: CVPixelBuffer) {
        let sendablePixelBuffer = ShadowClientDecoderSendablePixelBuffer(value: pixelBuffer)
        Task {
            await onFrame(sendablePixelBuffer.value)
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
    private var frameIndex: Int64 = 0
    private var preferredOutputDimensions: CMVideoDimensions?
    private var decodePresentationTimeScale: CMTimeScale
    private var av1FallbackHDR = false
    private var av1FallbackYUV444 = false
    private var av1CodecConfigurationOrigin: ShadowClientAV1CodecConfigurationOrigin?

    public init(
        decodePresentationTimeScale: CMTimeScale = CMTimeScale(
            ShadowClientVideoDecoderDefaults.defaultDecodePresentationTimeScale
        )
    ) {
        self.decodePresentationTimeScale = Self.normalizedPresentationTimeScale(decodePresentationTimeScale)
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
        decodePresentationTimeScale = Self.normalizedPresentationTimeScale(
            CMTimeScale(boundedFPS)
        )
    }

    public func setDecodePresentationTimeScale(_ timescale: CMTimeScale) {
        decodePresentationTimeScale = Self.normalizedPresentationTimeScale(timescale)
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

    public func decode(
        accessUnit annexBAccessUnit: Data,
        codec newCodec: ShadowClientVideoCodec,
        parameterSets explicitParameterSets: [Data],
        onFrame: @escaping @Sendable (CVPixelBuffer) async -> Void
    ) throws {
        if codec != newCodec {
            reset()
            codec = newCodec
        }

        let samplePayload: Data
        switch newCodec {
        case .h264, .h265:
            var nals = splitAnnexB(annexBAccessUnit)
            if nals.isEmpty {
                nals = splitLengthPrefixedNALUnits(annexBAccessUnit)
            }
            guard !nals.isEmpty else {
                return
            }
            let streamParameterSets = extractParameterSets(from: nals, codec: newCodec)
            if !explicitParameterSets.isEmpty {
                latestParameterSets = explicitParameterSets
            }
            if !streamParameterSets.isEmpty {
                latestParameterSets = streamParameterSets
            }

            let sampleNals = nals.filter { !isParameterSetNAL($0, codec: newCodec) }
            guard !sampleNals.isEmpty else {
                return
            }
            samplePayload = makeLengthPrefixedBuffer(from: sampleNals)
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
            throw ShadowClientVideoToolboxDecoderError.decodeFailed(status)
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
        outputBridge = bridge
        var callbackRecord = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: { refCon, _, status, _, imageBuffer, _, _ in
                guard status == noErr,
                      let imageBuffer,
                      let refCon
                else {
                    return
                }

                let bridge = Unmanaged<ShadowClientRealtimeDecoderOutputBridge>
                    .fromOpaque(refCon)
                    .takeUnretainedValue()
                bridge.emit(imageBuffer)
            },
            decompressionOutputRefCon: UnsafeMutableRawPointer(
                Unmanaged.passUnretained(bridge).toOpaque()
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
                decoderSpecification: nil,
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
        session = nil
        formatDescription = nil
        outputBridge = nil
        configuredParameterSets = []
        frameIndex = 0
    }

    private static func normalizedPresentationTimeScale(_ timescale: CMTimeScale) -> CMTimeScale {
        guard timescale > 0 else {
            return CMTimeScale(ShadowClientVideoDecoderDefaults.defaultDecodePresentationTimeScale)
        }
        return timescale
    }

    private static var defaultPixelBufferAttributes: [String: Any] {
        [
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as CFDictionary,
        ]
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

    private func splitAnnexB(_ buffer: Data) -> [Data] {
        var nals: [Data] = []
        var index = buffer.startIndex

        func startCodeLength(at i: Int) -> Int {
            let remaining = buffer.count - i
            guard remaining >= 3 else {
                return 0
            }
            if buffer[i] == 0 && buffer[i + 1] == 0 && buffer[i + 2] == 1 {
                return 3
            }
            if remaining >= 4 &&
                buffer[i] == 0 &&
                buffer[i + 1] == 0 &&
                buffer[i + 2] == 0 &&
                buffer[i + 3] == 1
            {
                return 4
            }
            return 0
        }

        while index < buffer.endIndex {
            let prefixLength = startCodeLength(at: index)
            if prefixLength == 0 {
                index += 1
                continue
            }

            let nalStart = index + prefixLength
            var next = nalStart
            while next < buffer.endIndex {
                if startCodeLength(at: next) > 0 {
                    break
                }
                next += 1
            }

            if nalStart < next {
                nals.append(Data(buffer[nalStart..<next]))
            }
            index = next
        }

        return nals
    }

    private func splitLengthPrefixedNALUnits(_ buffer: Data) -> [Data] {
        var nals: [Data] = []
        var index = buffer.startIndex

        while index + 4 <= buffer.endIndex {
            let length = Int(buffer[index]) << 24 |
                Int(buffer[index + 1]) << 16 |
                Int(buffer[index + 2]) << 8 |
                Int(buffer[index + 3])
            index += 4

            guard length > 0 else {
                return []
            }
            let nalEnd = index + length
            guard nalEnd <= buffer.endIndex else {
                return []
            }
            nals.append(Data(buffer[index..<nalEnd]))
            index = nalEnd
        }

        guard index == buffer.endIndex else {
            return []
        }
        return nals
    }

    private func extractParameterSets(
        from nals: [Data],
        codec: ShadowClientVideoCodec
    ) -> [Data] {
        switch codec {
        case .h264:
            var sps: Data?
            var pps: Data?
            for nal in nals {
                guard let first = nal.first else {
                    continue
                }
                let type = first & 0x1F
                if type == 7 {
                    sps = nal
                } else if type == 8 {
                    pps = nal
                }
            }
            if let sps, let pps {
                return [sps, pps]
            }
            return []
        case .h265:
            var vps: Data?
            var sps: Data?
            var pps: Data?
            for nal in nals {
                guard nal.count >= 2 else {
                    continue
                }
                let type = (nal[0] >> 1) & 0x3F
                if type == 32 {
                    vps = nal
                } else if type == 33 {
                    sps = nal
                } else if type == 34 {
                    pps = nal
                }
            }
            if let vps, let sps, let pps {
                return [vps, sps, pps]
            }
            return []
        case .av1:
            return []
        }
    }

    private func isParameterSetNAL(_ nal: Data, codec: ShadowClientVideoCodec) -> Bool {
        guard !nal.isEmpty else {
            return false
        }

        switch codec {
        case .h264:
            let type = nal[0] & 0x1F
            return type == 7 || type == 8 || type == 9
        case .h265:
            guard nal.count >= 2 else {
                return false
            }
            let type = (nal[0] >> 1) & 0x3F
            return type == 32 || type == 33 || type == 34
        case .av1:
            return false
        }
    }

    private func makeLengthPrefixedBuffer(from nalUnits: [Data]) -> Data {
        var output = Data()
        output.reserveCapacity(nalUnits.reduce(0) { $0 + $1.count + 4 })

        for nal in nalUnits {
            var bigEndianLength = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &bigEndianLength) { output.append(contentsOf: $0) }
            output.append(nal)
        }
        return output
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
