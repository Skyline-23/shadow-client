import CoreGraphics
import CoreVideo
import Foundation
import Metal

struct ShadowClientRealtimeSessionColorConfiguration {
    let renderColorSpace: CGColorSpace
    let displayColorSpace: CGColorSpace
    let pixelFormat: MTLPixelFormat
    let prefersExtendedDynamicRange: Bool
    let videoRangeExpansion: ShadowClientVideoRangeExpansion?
}

struct ShadowClientVideoRangeExpansion: Equatable, Sendable {
    let scale: CGFloat
    let bias: CGFloat
}

enum ShadowClientRealtimeSessionSourceColorSpaceStandard: Sendable {
    case rec601
    case rec709
    case displayP3
    case rec2020
}

enum ShadowClientRealtimeSessionColorPipeline {
    private static let defaultSDRSourceColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        ?? CGColorSpaceCreateDeviceRGB()
    private static let rec709ColorSpace = CGColorSpace(name: CGColorSpace.itur_709)
        ?? defaultSDRSourceColorSpace
    private static let displayP3ColorSpace = CGColorSpace(name: CGColorSpace.displayP3)
        ?? defaultSDRSourceColorSpace
    private static let rec601LikeColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        ?? defaultSDRSourceColorSpace
    private static let defaultSDRDisplayColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        ?? CGColorSpace(name: CGColorSpace.sRGB)
        ?? CGColorSpaceCreateDeviceRGB()

    private static let defaultHDRDisplayColorSpace = CGColorSpace(name: CGColorSpace.itur_2100_PQ)
        ?? CGColorSpace(name: CGColorSpace.itur_2020)
        ?? defaultSDRDisplayColorSpace
    static let hdrToSdrToneMapSourceHeadroom: Float = 4.0
    static let hdrToSdrToneMapTargetHeadroom: Float = 1.0

    static var defaultDisplayColorSpace: CGColorSpace {
        defaultSDRDisplayColorSpace
    }

    static func shouldAttachExplicitSourceColorSpace(for pixelBuffer: CVPixelBuffer) -> Bool {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_32BGRA,
             kCVPixelFormatType_32RGBA,
             kCVPixelFormatType_64RGBAHalf,
             kCVPixelFormatType_128RGBAFloat:
            return true
        default:
            return false
        }
    }

    static func configuration(
        for pixelBuffer: CVPixelBuffer?,
        allowExtendedDynamicRange: Bool = true
    ) -> ShadowClientRealtimeSessionColorConfiguration {
        guard let pixelBuffer else {
            return ShadowClientRealtimeSessionColorConfiguration(
                renderColorSpace: defaultSDRSourceColorSpace,
                displayColorSpace: defaultSDRDisplayColorSpace,
                pixelFormat: .bgra8Unorm,
                prefersExtendedDynamicRange: false,
                videoRangeExpansion: nil
            )
        }

        var metadata = colorMetadata(for: pixelBuffer)
        let prefersExtendedDynamicRange = shouldPreferExtendedDynamicRange(
            for: pixelBuffer,
            metadata: metadata,
            allowExtendedDynamicRange: allowExtendedDynamicRange
        )
        applyAttachmentFallbacks(
            for: pixelBuffer,
            metadata: metadata,
            prefersExtendedDynamicRange: prefersExtendedDynamicRange
        )
        metadata = colorMetadata(for: pixelBuffer)

        let renderColorSpace = sourceColorSpace(
            for: pixelBuffer,
            metadata: metadata,
            prefersExtendedDynamicRange: prefersExtendedDynamicRange
        )
        let displayColorSpace = prefersExtendedDynamicRange
            ? hdrDisplayColorSpace(for: metadata)
            : defaultSDRDisplayColorSpace
        let pixelFormat: MTLPixelFormat = prefersExtendedDynamicRange ? .bgr10a2Unorm : .bgra8Unorm
        let videoRangeExpansion = prefersExtendedDynamicRange
            ? nil
            : Self.videoRangeExpansion(for: pixelBuffer)

        return ShadowClientRealtimeSessionColorConfiguration(
            renderColorSpace: renderColorSpace,
            displayColorSpace: displayColorSpace,
            pixelFormat: pixelFormat,
            prefersExtendedDynamicRange: prefersExtendedDynamicRange,
            videoRangeExpansion: videoRangeExpansion
        )
    }

    static func videoRangeExpansion(for pixelBuffer: CVPixelBuffer) -> ShadowClientVideoRangeExpansion? {
        switch CVPixelBufferGetPixelFormatType(pixelBuffer) {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
            return .init(
                scale: CGFloat(255.0 / 219.0),
                bias: CGFloat(-16.0 / 219.0)
            )
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange:
            return .init(
                scale: CGFloat(1023.0 / 876.0),
                bias: CGFloat(-64.0 / 876.0)
            )
        default:
            return nil
        }
    }

    static func sourceStandard(
        for pixelBuffer: CVPixelBuffer
    ) -> ShadowClientRealtimeSessionSourceColorSpaceStandard {
        colorMetadata(for: pixelBuffer).sourceStandard
    }

    static func matrixStandard(
        for pixelBuffer: CVPixelBuffer
    ) -> ShadowClientRealtimeSessionSourceColorSpaceStandard {
        colorMetadata(for: pixelBuffer).matrixStandard
    }

    private static func sourceColorSpace(
        for pixelBuffer: CVPixelBuffer,
        metadata: ShadowClientColorMetadata,
        prefersExtendedDynamicRange: Bool
    ) -> CGColorSpace {
        if prefersExtendedDynamicRange {
            if metadata.isPQ {
                if metadata.sourceStandard == .displayP3 {
                    return CGColorSpace(name: CGColorSpace.displayP3_PQ)
                        ?? displayP3ColorSpace
                }
                return CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? defaultHDRDisplayColorSpace
            }
            if metadata.isHLG {
                if metadata.sourceStandard == .displayP3 {
                    return CGColorSpace(name: CGColorSpace.displayP3_HLG)
                        ?? displayP3ColorSpace
                }
                return CGColorSpace(name: CGColorSpace.itur_2100_HLG) ?? defaultHDRDisplayColorSpace
            }
        }

        if shouldAttachExplicitSourceColorSpace(for: pixelBuffer),
           let bufferColorSpace = CVImageBufferGetColorSpace(pixelBuffer)?.takeUnretainedValue()
        {
            return bufferColorSpace
        }

        switch metadata.sourceStandard {
        case .rec2020:
            return CGColorSpace(name: CGColorSpace.itur_2020) ?? defaultSDRSourceColorSpace
        case .displayP3:
            return displayP3ColorSpace
        case .rec709:
            return rec709ColorSpace
        case .rec601:
            return rec601LikeColorSpace
        }
    }

    private static func hdrDisplayColorSpace(
        for metadata: ShadowClientColorMetadata
    ) -> CGColorSpace {
        if metadata.isPQ {
            if metadata.sourceStandard == .displayP3 {
                return CGColorSpace(name: CGColorSpace.displayP3_PQ)
                    ?? defaultHDRDisplayColorSpace
            }
            return CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? defaultHDRDisplayColorSpace
        }
        if metadata.isHLG {
            if metadata.sourceStandard == .displayP3 {
                return CGColorSpace(name: CGColorSpace.displayP3_HLG)
                    ?? defaultHDRDisplayColorSpace
            }
            return CGColorSpace(name: CGColorSpace.itur_2100_HLG) ?? defaultHDRDisplayColorSpace
        }
        return CGColorSpace(name: CGColorSpace.itur_2020) ?? defaultHDRDisplayColorSpace
    }

    private static func colorMetadata(for pixelBuffer: CVPixelBuffer) -> ShadowClientColorMetadata {
        let transferFunction = normalizedAttachmentValue(
            forKey: kCVImageBufferTransferFunctionKey,
            pixelBuffer: pixelBuffer
        )
        let colorPrimaries = normalizedAttachmentValue(
            forKey: kCVImageBufferColorPrimariesKey,
            pixelBuffer: pixelBuffer
        )
        let yCbCrMatrix = normalizedAttachmentValue(
            forKey: kCVImageBufferYCbCrMatrixKey,
            pixelBuffer: pixelBuffer
        )
        let isPQ = matchesTransferFunctionPQ(transferFunction)
        let isHLG = matchesTransferFunctionHLG(transferFunction)
        let isBT2020 = matchesColorPrimaries2020(colorPrimaries) || matchesYCbCrMatrix2020(yCbCrMatrix)
        let sourceStandard = sourceStandard(
            colorPrimaries: colorPrimaries,
            yCbCrMatrix: yCbCrMatrix,
            isHDRTransfer: isPQ || isHLG
        )
        let matrixStandard = matrixStandard(yCbCrMatrix: yCbCrMatrix)
        return ShadowClientColorMetadata(
            transferFunction: transferFunction,
            colorPrimaries: colorPrimaries,
            yCbCrMatrix: yCbCrMatrix,
            isPQ: isPQ,
            isHLG: isHLG,
            isBT2020: isBT2020,
            isBT709Like: sourceStandard == .rec709,
            isBT601Like: sourceStandard == .rec601,
            sourceStandard: sourceStandard,
            matrixStandard: matrixStandard,
            hasTransferFunction: transferFunction != nil
        )
    }

    private static func sourceStandard(
        colorPrimaries: String?,
        yCbCrMatrix: String?,
        isHDRTransfer: Bool
    ) -> ShadowClientRealtimeSessionSourceColorSpaceStandard {
        if matchesColorPrimariesDisplayP3(colorPrimaries) || matchesYCbCrMatrixDisplayP3(yCbCrMatrix) {
            return .displayP3
        }
        if isHDRTransfer || matchesColorPrimaries2020(colorPrimaries) || matchesYCbCrMatrix2020(yCbCrMatrix) {
            return .rec2020
        }
        if matchesYCbCrMatrix709(yCbCrMatrix) {
            return .rec709
        }
        if matchesYCbCrMatrix601(yCbCrMatrix) {
            return .rec601
        }
        if matchesColorPrimaries709(colorPrimaries) {
            return .rec709
        }
        if matchesColorPrimaries601(colorPrimaries) {
            return .rec601
        }

        // Match Moonlight's default when colorspace metadata is missing.
        return .rec601
    }

    private static func matrixStandard(
        yCbCrMatrix: String?
    ) -> ShadowClientRealtimeSessionSourceColorSpaceStandard {
        if matchesYCbCrMatrix2020(yCbCrMatrix) {
            return .rec2020
        }
        if matchesYCbCrMatrix709(yCbCrMatrix) {
            return .rec709
        }
        if matchesYCbCrMatrix601(yCbCrMatrix) {
            return .rec601
        }
        return .rec601
    }

    private static func shouldPreferExtendedDynamicRange(
        for pixelBuffer: CVPixelBuffer,
        metadata: ShadowClientColorMetadata,
        allowExtendedDynamicRange: Bool
    ) -> Bool {
        _ = pixelBuffer
        return allowExtendedDynamicRange && (metadata.isPQ || metadata.isHLG)
    }

    private static func applyAttachmentFallbacks(
        for pixelBuffer: CVPixelBuffer,
        metadata: ShadowClientColorMetadata,
        prefersExtendedDynamicRange: Bool
    ) {
        if prefersExtendedDynamicRange {
            if !metadata.isBT2020 {
                CVBufferSetAttachment(
                    pixelBuffer,
                    kCVImageBufferColorPrimariesKey,
                    kCVImageBufferColorPrimaries_ITU_R_2020,
                    .shouldPropagate
                )
            }

            if !metadata.hasTransferFunction {
                CVBufferSetAttachment(
                    pixelBuffer,
                    kCVImageBufferTransferFunctionKey,
                    kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ,
                    .shouldPropagate
                )
            }

            if !hasAttachment(forKey: kCVImageBufferYCbCrMatrixKey, pixelBuffer: pixelBuffer) {
                CVBufferSetAttachment(
                    pixelBuffer,
                    kCVImageBufferYCbCrMatrixKey,
                    kCVImageBufferYCbCrMatrix_ITU_R_2020,
                    .shouldPropagate
                )
            }
        }
    }

    private static func hasAttachment(
        forKey key: CFString,
        pixelBuffer: CVPixelBuffer
    ) -> Bool {
        CVBufferCopyAttachment(pixelBuffer, key, nil) != nil
    }

    private static func normalizedAttachmentValue(
        forKey key: CFString,
        pixelBuffer: CVPixelBuffer
    ) -> String? {
        guard let attachment = CVBufferCopyAttachment(pixelBuffer, key, nil) else {
            return nil
        }
        if CFGetTypeID(attachment) == CFStringGetTypeID(),
           let value = attachment as? String
        {
            return value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        }
        return nil
    }

    private static func matchesTransferFunctionPQ(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        let pqToken = (kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ as String).uppercased()
        return value == pqToken || value.contains("_PQ") || value.hasSuffix("PQ")
    }

    private static func matchesTransferFunctionHLG(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        let hlgToken = (kCVImageBufferTransferFunction_ITU_R_2100_HLG as String).uppercased()
        return value == hlgToken || value.hasSuffix("HLG")
    }

    private static func matchesColorPrimaries2020(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        let token = (kCVImageBufferColorPrimaries_ITU_R_2020 as String).uppercased()
        return value == token || value.contains("2020")
    }

    private static func matchesColorPrimariesDisplayP3(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        let accepted: Set<String> = [
            (kCVImageBufferColorPrimaries_P3_D65 as String).uppercased(),
            (kCVImageBufferColorPrimaries_DCI_P3 as String).uppercased(),
            "P3_D65",
            "DCI_P3",
        ]
        return accepted.contains(value) || value.contains("DISPLAYP3") || value.contains("P3")
    }

    private static func matchesYCbCrMatrix2020(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        let accepted: Set<String> = [
            (kCVImageBufferYCbCrMatrix_ITU_R_2020 as String).uppercased(),
            "ITU_R_2020",
            "ITU_R_2020_CL",
            "ITU_R_2020_NCL",
        ]
        return accepted.contains(value) || value.contains("2020")
    }

    private static func matchesYCbCrMatrixDisplayP3(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        let accepted: Set<String> = [
            "P3_D65",
        ]
        return accepted.contains(value) || value.contains("DISPLAYP3") || value.contains("P3_D65")
    }

    private static func matchesColorPrimaries709(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        let token = (kCVImageBufferColorPrimaries_ITU_R_709_2 as String).uppercased()
        return value == token || value.contains("709")
    }

    private static func matchesColorPrimaries601(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        let accepted: Set<String> = [
            (kCVImageBufferColorPrimaries_SMPTE_C as String).uppercased(),
            "SMPTE_C",
            "SMPTE170M",
            "BT470BG",
        ]
        return accepted.contains(value)
    }

    private static func matchesYCbCrMatrix709(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        let token = (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String).uppercased()
        return value == token || value.contains("709")
    }

    private static func matchesYCbCrMatrix601(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        let accepted: Set<String> = [
            (kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String).uppercased(),
            "ITU_R_601_4",
            "ITU_R_601_4_525",
            "ITU_R_601_4_625",
            "SMPTE170M",
            "BT470BG",
        ]
        return accepted.contains(value)
    }
}

private struct ShadowClientColorMetadata {
    let transferFunction: String?
    let colorPrimaries: String?
    let yCbCrMatrix: String?
    let isPQ: Bool
    let isHLG: Bool
    let isBT2020: Bool
    let isBT709Like: Bool
    let isBT601Like: Bool
    let sourceStandard: ShadowClientRealtimeSessionSourceColorSpaceStandard
    let matrixStandard: ShadowClientRealtimeSessionSourceColorSpaceStandard
    let hasTransferFunction: Bool
}
