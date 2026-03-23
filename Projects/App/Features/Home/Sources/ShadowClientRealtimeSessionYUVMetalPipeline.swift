import CoreGraphics
import CoreVideo
import Foundation
import Metal
import os
import simd

final class ShadowClientRealtimeSessionYUVMetalPipeline {
    struct CSCParameters {
        var row0: SIMD3<Float>
        var row1: SIMD3<Float>
        var row2: SIMD3<Float>
        var offsets: SIMD3<Float>
        var chromaOffset: SIMD2<Float>
        var bitnessScaleFactor: Float
        var transferFunction: UInt32
        var decodesTransfer: UInt32
        var appliesToneMapToSDR: UInt32
        var appliesGamutTransform: UInt32
        var hlgSystemGamma: Float
        var toneMapSourceHeadroom: Float
        var toneMapTargetHeadroom: Float
        var _padding: Float
        var gamutRow0: SIMD3<Float>
        var gamutRow1: SIMD3<Float>
        var gamutRow2: SIMD3<Float>
    }

    enum TransferFunctionKind: UInt32, Sendable {
        case linear = 0
        case pq = 1
        case hlg = 2
    }

    struct ColorProcessingDescriptor: Equatable, Sendable {
        let transferFunction: TransferFunctionKind
        let decodesTransfer: Bool
        let appliesToneMapToSDR: Bool
        let appliesGamutTransform: Bool
        let hlgSystemGamma: Float
        let toneMapSourceHeadroom: Float
        let toneMapTargetHeadroom: Float
        let gamutRow0: SIMD3<Float>
        let gamutRow1: SIMD3<Float>
        let gamutRow2: SIMD3<Float>
    }

    struct Vertex {
        var position: SIMD2<Float>
        var texCoord: SIMD2<Float>
    }

    private enum Constants {
        static let bt601 = (
            SIMD3<Float>(1.0, 0.0, 1.4020),
            SIMD3<Float>(1.0, -0.3441, -0.7141),
            SIMD3<Float>(1.0, 1.7720, 0.0)
        )
        static let bt709 = (
            SIMD3<Float>(1.0, 0.0, 1.5748),
            SIMD3<Float>(1.0, -0.1873, -0.4681),
            SIMD3<Float>(1.0, 1.8556, 0.0)
        )
        static let bt2020 = (
            SIMD3<Float>(1.0, 0.0, 1.4746),
            SIMD3<Float>(1.0, -0.1646, -0.5714),
            SIMD3<Float>(1.0, 1.8814, 0.0)
        )
        static let identity3x3 = (
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(0, 1, 0),
            SIMD3<Float>(0, 0, 1)
        )
        static let rec2020ToDisplayP3 = (
            SIMD3<Float>(1.34357825, -0.28217967, -0.06139859),
            SIMD3<Float>(-0.06529745, 1.07578791, -0.01049045),
            SIMD3<Float>(0.00282179, -0.0195985, 1.01677671)
        )
    }

    private static let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "SurfaceView.YUVMetal"
    )

    private let device: MTLDevice
    private let pipelineStates: [MTLPixelFormat: MTLRenderPipelineState]
    private let textureCache: CVMetalTextureCache
    private var lastLoggedDiagnosticsSignature: String?

    static func supportsPixelFormat(_ pixelFormat: OSType) -> Bool {
        switch pixelFormat {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_Lossless_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_Lossless_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarFullRange,
             kCVPixelFormatType_Lossy_420YpCbCr8BiPlanarVideoRange,
             kCVPixelFormatType_Lossy_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_Lossy_420YpCbCr10PackedBiPlanarVideoRange:
            return true
        default:
            return false
        }
    }

    init?(device: MTLDevice) {
        self.device = device

        let library: MTLLibrary?
        if let defaultLibrary = device.makeDefaultLibrary() {
            Self.logger.notice("YUV Metal pipeline loaded default Metal library from app bundle")
            library = defaultLibrary
        } else {
            let bundle = Bundle(for: ShadowClientRealtimeSessionYUVMetalBundleMarker.self)
            if let bundledLibrary = try? device.makeDefaultLibrary(bundle: bundle) {
                Self.logger.notice("YUV Metal pipeline loaded bundled Metal library")
                library = bundledLibrary
            } else {
                Self.logger.error("YUV Metal pipeline failed to load Metal library")
                library = nil
            }
        }

        guard let library else {
            return nil
        }
        var pipelineStates: [MTLPixelFormat: MTLRenderPipelineState] = [:]
        for pixelFormat in [MTLPixelFormat.bgra8Unorm, .bgr10a2Unorm, .rgba16Float] {
            let descriptor = MTLRenderPipelineDescriptor()
            descriptor.vertexFunction = library.makeFunction(name: "shadowYUVVertex")
            descriptor.fragmentFunction = library.makeFunction(name: "shadowYUVBiplanarFragment")
            descriptor.colorAttachments[0].pixelFormat = pixelFormat
            guard let pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor) else {
                return nil
            }
            pipelineStates[pixelFormat] = pipelineState
        }
        self.pipelineStates = pipelineStates

        var textureCache: CVMetalTextureCache?
        guard CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache) == kCVReturnSuccess,
              let textureCache
        else {
            return nil
        }
        self.textureCache = textureCache
    }

    func canRender(_ pixelBuffer: CVPixelBuffer) -> Bool {
        Self.supportsPixelFormat(CVPixelBufferGetPixelFormatType(pixelBuffer))
    }

    func render(
        pixelBuffer: CVPixelBuffer,
        into renderPassDescriptor: MTLRenderPassDescriptor,
        commandBuffer: MTLCommandBuffer,
        drawableSize: CGSize,
        colorPixelFormat: MTLPixelFormat,
        outputColorSpace: CGColorSpace,
        prefersExtendedDynamicRange: Bool
    ) -> Bool {
        guard canRender(pixelBuffer),
              let pipelineState = pipelineStates[colorPixelFormat],
              let lumaTextureRef = makeTexture(
                from: pixelBuffer,
                planeIndex: 0,
                pixelFormat: lumaTextureFormat(for: pixelBuffer)
              ),
              let chromaTextureRef = makeTexture(
                from: pixelBuffer,
                planeIndex: 1,
                pixelFormat: chromaTextureFormat(for: pixelBuffer)
              ),
              let lumaTexture = CVMetalTextureGetTexture(lumaTextureRef),
              let chromaTexture = CVMetalTextureGetTexture(chromaTextureRef),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDescriptor
              )
        else {
            return false
        }

        let vertices = vertexData(
            videoSize: CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            ),
            drawableSize: drawableSize
        )
        var parameters = cscParameters(
            for: pixelBuffer,
            outputColorSpace: outputColorSpace,
            prefersExtendedDynamicRange: prefersExtendedDynamicRange
        )
        logDiagnosticsIfNeeded(
            pixelBuffer: pixelBuffer,
            colorPixelFormat: colorPixelFormat,
            parameters: parameters
        )

        renderEncoder.setRenderPipelineState(pipelineState)
        renderEncoder.setVertexBytes(
            vertices,
            length: MemoryLayout<Vertex>.stride * vertices.count,
            index: 0
        )
        renderEncoder.setFragmentTexture(lumaTexture, index: 0)
        renderEncoder.setFragmentTexture(chromaTexture, index: 1)
        renderEncoder.setFragmentBytes(
            &parameters,
            length: MemoryLayout<CSCParameters>.stride,
            index: 0
        )
        renderEncoder.drawPrimitives(
            type: .triangleStrip,
            vertexStart: 0,
            vertexCount: vertices.count
        )
        renderEncoder.endEncoding()

        commandBuffer.addCompletedHandler { _ in
            _ = lumaTextureRef
            _ = chromaTextureRef
        }
        return true
    }

    private func makeTexture(
        from pixelBuffer: CVPixelBuffer,
        planeIndex: Int,
        pixelFormat: MTLPixelFormat
    ) -> CVMetalTexture? {
        let dimensions = planeDimensions(
            for: pixelBuffer,
            planeIndex: planeIndex
        )
        guard dimensions.width > 0, dimensions.height > 0 else {
            return nil
        }

        var textureRef: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            pixelFormat,
            dimensions.width,
            dimensions.height,
            planeIndex,
            &textureRef
        )
        guard status == kCVReturnSuccess else {
            return nil
        }
        return textureRef
    }

    private func lumaTextureFormat(for pixelBuffer: CVPixelBuffer) -> MTLPixelFormat {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarFullRange,
             kCVPixelFormatType_Lossy_420YpCbCr10PackedBiPlanarVideoRange:
            return .r16Unorm
        default:
            return .r8Unorm
        }
    }

    private func chromaTextureFormat(for pixelBuffer: CVPixelBuffer) -> MTLPixelFormat {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarFullRange,
             kCVPixelFormatType_Lossy_420YpCbCr10PackedBiPlanarVideoRange:
            return .rg16Unorm
        default:
            return .rg8Unorm
        }
    }

    private func cscParameters(
        for pixelBuffer: CVPixelBuffer,
        outputColorSpace: CGColorSpace,
        prefersExtendedDynamicRange: Bool
    ) -> CSCParameters {
        let matrix = cscMatrix(for: pixelBuffer)
        let fullRange = isFullRange(pixelBuffer)
        let bitDepth = bitsPerChannel(for: pixelBuffer)
        let channelRange = Float((1 << bitDepth) - 1)
        let yMin = fullRange ? 0.0 : Float(16 << (bitDepth - 8))
        let yMax = fullRange ? channelRange : Float(235 << (bitDepth - 8))
        let uvMin = fullRange ? 0.0 : Float(16 << (bitDepth - 8))
        let uvMax = fullRange ? channelRange : Float(240 << (bitDepth - 8))
        let yScale = channelRange / max(1, (yMax - yMin))
        let uvScale = channelRange / max(1, (uvMax - uvMin))
        let colorProcessing = Self.colorProcessingDescriptor(
            for: pixelBuffer,
            outputColorSpace: outputColorSpace,
            prefersExtendedDynamicRange: prefersExtendedDynamicRange
        )

        return CSCParameters(
            row0: SIMD3<Float>(matrix.0.x * yScale, matrix.0.y * uvScale, matrix.0.z * uvScale),
            row1: SIMD3<Float>(matrix.1.x * yScale, matrix.1.y * uvScale, matrix.1.z * uvScale),
            row2: SIMD3<Float>(matrix.2.x * yScale, matrix.2.y * uvScale, matrix.2.z * uvScale),
            offsets: SIMD3<Float>(
                yMin / channelRange,
                Float(1 << (bitDepth - 1)) / channelRange,
                Float(1 << (bitDepth - 1)) / channelRange
            ),
            chromaOffset: chromaOffsets(for: pixelBuffer),
            bitnessScaleFactor: 1,
            transferFunction: colorProcessing.transferFunction.rawValue,
            decodesTransfer: colorProcessing.decodesTransfer ? 1 : 0,
            appliesToneMapToSDR: colorProcessing.appliesToneMapToSDR ? 1 : 0,
            appliesGamutTransform: colorProcessing.appliesGamutTransform ? 1 : 0,
            hlgSystemGamma: colorProcessing.hlgSystemGamma,
            toneMapSourceHeadroom: colorProcessing.toneMapSourceHeadroom,
            toneMapTargetHeadroom: colorProcessing.toneMapTargetHeadroom,
            _padding: 0,
            gamutRow0: colorProcessing.gamutRow0,
            gamutRow1: colorProcessing.gamutRow1,
            gamutRow2: colorProcessing.gamutRow2
        )
    }

    static func colorProcessingDescriptor(
        for pixelBuffer: CVPixelBuffer,
        outputColorSpace: CGColorSpace,
        prefersExtendedDynamicRange: Bool
    ) -> ColorProcessingDescriptor {
        let transfer = staticAttachmentStringValue(
            forKey: kCVImageBufferTransferFunctionKey,
            pixelBuffer: pixelBuffer
        )?.uppercased()

        let transferFunction: TransferFunctionKind
        if transfer == nil {
            transferFunction = .linear
        } else if transfer == (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String).uppercased() ||
            transfer?.contains("_PQ") == true ||
            transfer?.hasSuffix("PQ") == true
        {
            transferFunction = .pq
        } else if transfer == (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String).uppercased() ||
            transfer?.hasSuffix("HLG") == true
        {
            transferFunction = .hlg
        } else {
            transferFunction = .linear
        }

        let sourceStandard = ShadowClientRealtimeSessionColorPipeline.sourceStandard(for: pixelBuffer)
        let carriesHDRTransfer = transferFunction == .pq || transferFunction == .hlg
        let usesLinearHDROutput =
            prefersExtendedDynamicRange &&
            (
                outputColorSpace.name == CGColorSpace.extendedLinearITUR_2020 ||
                outputColorSpace.name == CGColorSpace.extendedLinearDisplayP3 ||
                    outputColorSpace.name == CGColorSpace.extendedLinearSRGB
            )
        let decodesTransfer =
            carriesHDRTransfer &&
            (!prefersExtendedDynamicRange || usesLinearHDROutput)
        let appliesToneMapToSDR =
            carriesHDRTransfer &&
            !prefersExtendedDynamicRange
        let appliesGamutTransform =
            sourceStandard == .rec2020 &&
            outputColorSpace.name == CGColorSpace.extendedLinearDisplayP3

        let gamutRows = appliesGamutTransform
            ? Constants.rec2020ToDisplayP3
            : Constants.identity3x3
        let hdrReferenceWhiteScale: Float
        switch transferFunction {
        case .pq:
            // ST 2084 PQ is absolute (normalized to 10,000 nits). Apple EDR render targets
            // expect reference white near 1.0, so remap 100 nit reference white to 1.0.
            hdrReferenceWhiteScale = 100.0
        case .hlg:
            hdrReferenceWhiteScale = 1.0
        case .linear:
            hdrReferenceWhiteScale = 1.0
        }

        return .init(
            transferFunction: transferFunction,
            decodesTransfer: decodesTransfer,
            appliesToneMapToSDR: appliesToneMapToSDR,
            appliesGamutTransform: appliesGamutTransform,
            hlgSystemGamma: 1.2,
            toneMapSourceHeadroom: hdrReferenceWhiteScale,
            toneMapTargetHeadroom: ShadowClientRealtimeSessionColorPipeline.hdrToSdrToneMapTargetHeadroom,
            gamutRow0: gamutRows.0,
            gamutRow1: gamutRows.1,
            gamutRow2: gamutRows.2
        )
    }

    private func logDiagnosticsIfNeeded(
        pixelBuffer: CVPixelBuffer,
        colorPixelFormat: MTLPixelFormat,
        parameters: CSCParameters
    ) {
        let primaries = attachmentStringValue(
            forKey: kCVImageBufferColorPrimariesKey,
            pixelBuffer: pixelBuffer
        ) ?? "nil"
        let transfer = attachmentStringValue(
            forKey: kCVImageBufferTransferFunctionKey,
            pixelBuffer: pixelBuffer
        ) ?? "nil"
        let matrix = attachmentStringValue(
            forKey: kCVImageBufferYCbCrMatrixKey,
            pixelBuffer: pixelBuffer
        ) ?? "nil"
        let chromaLocation = attachmentStringValue(
            forKey: kCVImageBufferChromaLocationTopFieldKey,
            pixelBuffer: pixelBuffer
        ) ?? attachmentStringValue(
            forKey: kCVImageBufferChromaLocationBottomFieldKey,
            pixelBuffer: pixelBuffer
        ) ?? "nil"
        let sourceStandard = String(describing: ShadowClientRealtimeSessionColorPipeline.sourceStandard(for: pixelBuffer))
        let fullRange = isFullRange(pixelBuffer)
        let bitDepth = bitsPerChannel(for: pixelBuffer)
        let sampleSummary = sampledDiagnostics(
            pixelBuffer: pixelBuffer,
            parameters: parameters
        ) ?? "nil"
        let signature = [
            String(CVPixelBufferGetPixelFormatType(pixelBuffer)),
            primaries,
            transfer,
            matrix,
            chromaLocation,
            sourceStandard,
            fullRange ? "full" : "limited",
            String(bitDepth),
            String(colorPixelFormat.rawValue),
        ].joined(separator: "|")

        guard signature != lastLoggedDiagnosticsSignature else {
            return
        }
        lastLoggedDiagnosticsSignature = signature

        Self.logger.notice(
            """
            YUV Metal diagnostics pixel-format=0x\(String(CVPixelBufferGetPixelFormatType(pixelBuffer), radix: 16), privacy: .public) drawable-format=\(colorPixelFormat.rawValue, privacy: .public) source-standard=\(sourceStandard, privacy: .public) primaries=\(primaries, privacy: .public) transfer=\(transfer, privacy: .public) matrix=\(matrix, privacy: .public) chroma-location=\(chromaLocation, privacy: .public) range=\(fullRange ? "full" : "limited", privacy: .public) bit-depth=\(bitDepth, privacy: .public) csc-row0=[\(parameters.row0.x, privacy: .public),\(parameters.row0.y, privacy: .public),\(parameters.row0.z, privacy: .public)] csc-row1=[\(parameters.row1.x, privacy: .public),\(parameters.row1.y, privacy: .public),\(parameters.row1.z, privacy: .public)] csc-row2=[\(parameters.row2.x, privacy: .public),\(parameters.row2.y, privacy: .public),\(parameters.row2.z, privacy: .public)] offsets=[\(parameters.offsets.x, privacy: .public),\(parameters.offsets.y, privacy: .public),\(parameters.offsets.z, privacy: .public)] chroma-offset=[\(parameters.chromaOffset.x, privacy: .public),\(parameters.chromaOffset.y, privacy: .public)] bitness-scale=\(parameters.bitnessScaleFactor, privacy: .public) samples=\(sampleSummary, privacy: .public)
            """
        )
    }

    private func sampledDiagnostics(
        pixelBuffer: CVPixelBuffer,
        parameters: CSCParameters
    ) -> String? {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        guard pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange ||
            pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
        else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0),
              let uvBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)
        else {
            return nil
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let yRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        let uvRowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1)
        let yPointer = yBase.bindMemory(to: UInt8.self, capacity: yRowBytes * height)
        let uvPointer = uvBase.bindMemory(
            to: UInt8.self,
            capacity: uvRowBytes * CVPixelBufferGetHeightOfPlane(pixelBuffer, 1)
        )
        let labels: [(String, CGFloat, CGFloat)] = [
            ("tl", 0.1, 0.1),
            ("tr", 0.9, 0.1),
            ("c", 0.5, 0.5),
            ("bl", 0.1, 0.9),
            ("br", 0.9, 0.9),
        ]

        var parts: [String] = []
        for (label, normalizedX, normalizedY) in labels {
            let x = max(0, min(width - 1, Int(CGFloat(width - 1) * normalizedX)))
            let y = max(0, min(height - 1, Int(CGFloat(height - 1) * normalizedY)))
            let ySample = Int(yPointer[y * yRowBytes + x])
            let uvX = (x / 2) * 2
            let uvY = y / 2
            let uvOffset = uvY * uvRowBytes + uvX
            let cbSample = Int(uvPointer[uvOffset])
            let crSample = Int(uvPointer[uvOffset + 1])
            let predicted = predictedRGB(
                y: ySample,
                cb: cbSample,
                cr: crSample,
                parameters: parameters
            )
            parts.append("\(label)=Y\(ySample)/Cb\(cbSample)/Cr\(crSample)->RGB\(predicted)")
        }
        return parts.joined(separator: " ")
    }

    private func predictedRGB(
        y: Int,
        cb: Int,
        cr: Int,
        parameters: CSCParameters
    ) -> String {
        var yuv = SIMD3<Float>(
            Float(y) / 255.0,
            Float(cb) / 255.0,
            Float(cr) / 255.0
        )
        yuv *= parameters.bitnessScaleFactor
        yuv -= parameters.offsets

        let rgb = SIMD3<Float>(
            dot(parameters.row0, yuv),
            dot(parameters.row1, yuv),
            dot(parameters.row2, yuv)
        )
        let r = clampToByte(rgb.x * 255.0)
        let g = clampToByte(rgb.y * 255.0)
        let b = clampToByte(rgb.z * 255.0)
        return "[\(r),\(g),\(b)]"
    }

    private func clampToByte(_ value: Float) -> Int {
        Int(max(0, min(255, lroundf(value))))
    }

    private func cscMatrix(for pixelBuffer: CVPixelBuffer) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
        switch ShadowClientRealtimeSessionColorPipeline.matrixStandard(for: pixelBuffer) {
        case .rec2020:
            return Constants.bt2020
        case .displayP3:
            return Constants.bt709
        case .rec709:
            return Constants.bt709
        case .rec601:
            return Constants.bt601
        }
    }

    private func isFullRange(_ pixelBuffer: CVPixelBuffer) -> Bool {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_Lossless_420YpCbCr8BiPlanarFullRange,
             kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarFullRange:
            return true
        default:
            return false
        }
    }

    private func bitsPerChannel(for pixelBuffer: CVPixelBuffer) -> Int {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
             kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
             kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarVideoRange,
             kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarFullRange,
             kCVPixelFormatType_Lossy_420YpCbCr10PackedBiPlanarVideoRange:
            return 10
        default:
            return 8
        }
    }

    private func planeDimensions(
        for pixelBuffer: CVPixelBuffer,
        planeIndex: Int
    ) -> (width: Int, height: Int) {
        let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
        if planeCount > planeIndex {
            return (
                CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex),
                CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
            )
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        switch planeIndex {
        case 0:
            return (width, height)
        case 1:
            return ((width + 1) / 2, (height + 1) / 2)
        default:
            return (0, 0)
        }
    }

    private func chromaOffsets(for pixelBuffer: CVPixelBuffer) -> SIMD2<Float> {
        let location = attachmentStringValue(
            forKey: kCVImageBufferChromaLocationTopFieldKey,
            pixelBuffer: pixelBuffer
        ) ?? attachmentStringValue(
            forKey: kCVImageBufferChromaLocationBottomFieldKey,
            pixelBuffer: pixelBuffer
        ) ?? (kCVImageBufferChromaLocation_Left as String)

        let horizontalSubsampled = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1) < CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let verticalSubsampled = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1) < CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)

        let offset: SIMD2<Float>
        if location == (kCVImageBufferChromaLocation_Center as String) {
            offset = SIMD2<Float>(0, 0)
        } else if location == (kCVImageBufferChromaLocation_TopLeft as String) {
            offset = SIMD2<Float>(0.5, 0.5)
        } else if location == (kCVImageBufferChromaLocation_Top as String) {
            offset = SIMD2<Float>(0, 0.5)
        } else if location == (kCVImageBufferChromaLocation_BottomLeft as String) {
            offset = SIMD2<Float>(0.5, -0.5)
        } else if location == (kCVImageBufferChromaLocation_Bottom as String) {
            offset = SIMD2<Float>(0, -0.5)
        } else {
            offset = SIMD2<Float>(0.5, 0)
        }

        return SIMD2<Float>(
            horizontalSubsampled ? offset.x : 0,
            verticalSubsampled ? offset.y : 0
        )
    }

    private func vertexData(
        videoSize: CGSize,
        drawableSize: CGSize
    ) -> [Vertex] {
        let widthScale = drawableSize.width / max(videoSize.width, 1)
        let heightScale = drawableSize.height / max(videoSize.height, 1)
        let scale = min(widthScale, heightScale)
        let scaledWidth = videoSize.width * scale
        let scaledHeight = videoSize.height * scale
        let originX = (drawableSize.width - scaledWidth) * 0.5
        let originY = (drawableSize.height - scaledHeight) * 0.5

        let left = Float((originX / drawableSize.width) * 2.0 - 1.0)
        let right = Float(((originX + scaledWidth) / drawableSize.width) * 2.0 - 1.0)
        let top = Float(1.0 - (originY / drawableSize.height) * 2.0)
        let bottom = Float(1.0 - ((originY + scaledHeight) / drawableSize.height) * 2.0)

        return [
            Vertex(position: SIMD2<Float>(left, bottom), texCoord: SIMD2<Float>(0, 1)),
            Vertex(position: SIMD2<Float>(left, top), texCoord: SIMD2<Float>(0, 0)),
            Vertex(position: SIMD2<Float>(right, bottom), texCoord: SIMD2<Float>(1, 1)),
            Vertex(position: SIMD2<Float>(right, top), texCoord: SIMD2<Float>(1, 0)),
        ]
    }

    private func attachmentStringValue(
        forKey key: CFString,
        pixelBuffer: CVPixelBuffer
    ) -> String? {
        Self.staticAttachmentStringValue(forKey: key, pixelBuffer: pixelBuffer)
    }

    private static func staticAttachmentStringValue(
        forKey key: CFString,
        pixelBuffer: CVPixelBuffer
    ) -> String? {
        guard let attachment = CVBufferCopyAttachment(pixelBuffer, key, nil) else {
            return nil
        }
        return attachment as? String
    }
}

private final class ShadowClientRealtimeSessionYUVMetalBundleMarker {}
