import CoreGraphics
import CoreVideo
import Foundation
import Metal

struct ShadowClientRealtimeSessionColorConfiguration {
    let renderColorSpace: CGColorSpace
    let displayColorSpace: CGColorSpace
    let pixelFormat: MTLPixelFormat
    let prefersExtendedDynamicRange: Bool
}

enum ShadowClientRealtimeSessionColorPipeline {
    private static let defaultSDRSourceColorSpace = CGColorSpace(name: CGColorSpace.itur_709)
        ?? CGColorSpace(name: CGColorSpace.sRGB)
        ?? CGColorSpaceCreateDeviceRGB()
    private static let defaultSDRDisplayColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        ?? CGColorSpace(name: CGColorSpace.displayP3)
        ?? CGColorSpaceCreateDeviceRGB()

    private static let defaultHDRDisplayColorSpace = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        ?? CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)
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
                prefersExtendedDynamicRange: false
            )
        }

        let metadata = colorMetadata(for: pixelBuffer)
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

        let renderColorSpace = sourceColorSpace(
            for: pixelBuffer,
            metadata: metadata,
            prefersExtendedDynamicRange: prefersExtendedDynamicRange
        )
        let displayColorSpace = prefersExtendedDynamicRange ? defaultHDRDisplayColorSpace : defaultSDRDisplayColorSpace
        let pixelFormat: MTLPixelFormat = prefersExtendedDynamicRange ? .rgba16Float : .bgra8Unorm

        return ShadowClientRealtimeSessionColorConfiguration(
            renderColorSpace: renderColorSpace,
            displayColorSpace: displayColorSpace,
            pixelFormat: pixelFormat,
            prefersExtendedDynamicRange: prefersExtendedDynamicRange
        )
    }

    private static func sourceColorSpace(
        for pixelBuffer: CVPixelBuffer,
        metadata: ShadowClientColorMetadata,
        prefersExtendedDynamicRange: Bool
    ) -> CGColorSpace {
        if prefersExtendedDynamicRange {
            if metadata.isPQ {
                return CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? defaultHDRDisplayColorSpace
            }
            if metadata.isHLG {
                return CGColorSpace(name: CGColorSpace.itur_2100_HLG) ?? defaultHDRDisplayColorSpace
            }
        }
        if let bufferColorSpace = CVImageBufferGetColorSpace(pixelBuffer)?.takeUnretainedValue() {
            return bufferColorSpace
        }
        if metadata.isBT2020 {
            return CGColorSpace(name: CGColorSpace.itur_2020) ?? defaultSDRSourceColorSpace
        }
        return defaultSDRSourceColorSpace
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
        let isPQ = matchesTransferFunctionPQ(transferFunction)
        let isHLG = matchesTransferFunctionHLG(transferFunction)
        let isBT2020 = matchesColorPrimaries2020(colorPrimaries)
        return ShadowClientColorMetadata(
            isPQ: isPQ,
            isHLG: isHLG,
            isBT2020: isBT2020,
            hasTransferFunction: transferFunction != nil
        )
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
}

private struct ShadowClientColorMetadata {
    let isPQ: Bool
    let isHLG: Bool
    let isBT2020: Bool
    let hasTransferFunction: Bool
}
