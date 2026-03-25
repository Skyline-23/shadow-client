import CoreVideo
import CoreGraphics
import Foundation
import Metal
import QuartzCore

enum ShadowClientSurfaceColorRenderBackend {
    case coreImage
    case metalYUV
}

struct ShadowClientSurfaceRenderTargetConfiguration {
    let renderBackend: ShadowClientSurfaceColorRenderBackend
    let targetPixelFormat: MTLPixelFormat
    let prefersExtendedDynamicRange: Bool
    let outputColorSpace: CGColorSpace
}

enum ShadowClientSurfaceColorSpaceKit {
    private enum HDRColorFamily: Equatable {
        case displayP3
        case rec2020
        case sRGB
        case unknown
    }

    private enum HDRTransferKind: Equatable {
        case pq
        case hlg
        case sdr
        case unknown
    }

    static func staticHDRAttachmentData(
        forKey key: CFString,
        pixelBuffer: CVPixelBuffer
    ) -> Data? {
        guard let value = CVBufferCopyAttachment(
            pixelBuffer,
            key,
            nil
        ) else {
            return nil
        }

        if let data = value as? Data {
            return data
        }

        if let data = value as? NSData {
            return Data(referencing: data)
        }

        guard CFGetTypeID(value) == CFDataGetTypeID() else {
            return nil
        }

        let cfData = unsafeBitCast(value, to: CFData.self)
        return Data(referencing: cfData as NSData)
    }

    static func renderedFrameHDRMetadata(
        colorConfiguration: ShadowClientRealtimeSessionColorConfiguration,
        pixelBuffer: CVPixelBuffer?
    ) -> ShadowClientHDRMetadata? {
        guard colorConfiguration.prefersExtendedDynamicRange,
              let pixelBuffer
        else {
            return nil
        }

        let displayInfoData = staticHDRAttachmentData(
            forKey: kCVImageBufferMasteringDisplayColorVolumeKey,
            pixelBuffer: pixelBuffer
        )
        let contentInfoData = staticHDRAttachmentData(
            forKey: kCVImageBufferContentLightLevelInfoKey,
            pixelBuffer: pixelBuffer
        )

        return hdrMetadata(
            displayInfoData: displayInfoData,
            contentInfoData: contentInfoData
        )
    }

    static func renderBackend(
        hasPixelBuffer: Bool,
        canRenderWithMetalYUV: Bool
    ) -> ShadowClientSurfaceColorRenderBackend {
        guard hasPixelBuffer else {
            return .coreImage
        }
        return canRenderWithMetalYUV ? .metalYUV : .coreImage
    }

    static func fallbackRenderBackend(
        from renderBackend: ShadowClientSurfaceColorRenderBackend
    ) -> ShadowClientSurfaceColorRenderBackend {
        switch renderBackend {
        case .metalYUV:
            return .coreImage
        case .coreImage:
            return .coreImage
        }
    }

    static func renderTargetConfiguration(
        colorConfiguration: ShadowClientRealtimeSessionColorConfiguration,
        supportsExtendedDynamicRange: Bool,
        renderBackend: ShadowClientSurfaceColorRenderBackend,
        screenColorSpace: CGColorSpace? = nil
    ) -> ShadowClientSurfaceRenderTargetConfiguration {
        let prefersExtendedDynamicRange =
            colorConfiguration.prefersExtendedDynamicRange && supportsExtendedDynamicRange
        let outputColorSpace = resolvedOutputColorSpace(
            prefersExtendedDynamicRange: prefersExtendedDynamicRange,
            sdrSourceColorSpace: colorConfiguration.renderColorSpace,
            hdrDisplayColorSpace: colorConfiguration.displayColorSpace,
            screenColorSpace: screenColorSpace,
            hdrSourceColorSpace: colorConfiguration.renderColorSpace,
            renderBackend: renderBackend
        )
        let targetPixelFormat = preferredTargetPixelFormat(
            prefersExtendedDynamicRange: prefersExtendedDynamicRange,
            renderBackend: renderBackend,
            fallbackPixelFormat: colorConfiguration.pixelFormat,
            outputColorSpace: outputColorSpace
        )

        return .init(
            renderBackend: renderBackend,
            targetPixelFormat: targetPixelFormat,
            prefersExtendedDynamicRange: prefersExtendedDynamicRange,
            outputColorSpace: outputColorSpace
        )
    }

    static func edrMetadata(
        colorConfiguration: ShadowClientRealtimeSessionColorConfiguration,
        renderTargetConfiguration: ShadowClientSurfaceRenderTargetConfiguration,
        hdrMetadata: ShadowClientHDRMetadata?,
        currentHeadroom: CGFloat
    ) -> CAEDRMetadata? {
        guard renderTargetConfiguration.prefersExtendedDynamicRange else {
            return nil
        }

        let sourceHDRColorSpaceName =
            colorConfiguration.displayColorSpace.name ??
            colorConfiguration.renderColorSpace.name
        let opticalOutputScale = opticalOutputScale(
            for: renderTargetConfiguration
        )

        if isHLGLikeColorSpaceName(sourceHDRColorSpaceName) {
            return nil
        }

        if let hdrMetadata {
            let displayInfo = hdrMetadata.hasHDR10DisplayInfo
                ? hdrMetadata.hdr10DisplayInfoData
                : nil
            let contentInfo = hdrMetadata.hasHDR10ContentInfo
                ? hdrMetadata.hdr10ContentInfoData
                : nil
            if displayInfo != nil || contentInfo != nil {
                return CAEDRMetadata.hdr10(
                    displayInfo: displayInfo,
                    contentInfo: contentInfo,
                    opticalOutputScale: opticalOutputScale
                )
            }
            let maxLuminance = Float(max(hdrMetadata.maxDisplayLuminance, 1))
            let minLuminance = hdrMetadata.minDisplayLuminance > 0
                ? Float(hdrMetadata.minDisplayLuminance) / 10_000.0
                : 0.0001
            return CAEDRMetadata.hdr10(
                minLuminance: minLuminance,
                maxLuminance: maxLuminance,
                opticalOutputScale: opticalOutputScale
            )
        }

        let peakLuminance = Float(max(currentHeadroom, 1.0) * 100.0)
        return CAEDRMetadata.hdr10(
            minLuminance: 0.0001,
            maxLuminance: peakLuminance,
            opticalOutputScale: opticalOutputScale
        )
    }

    static func edrMetadataDebugSummary(
        colorConfiguration: ShadowClientRealtimeSessionColorConfiguration,
        renderTargetConfiguration: ShadowClientSurfaceRenderTargetConfiguration,
        hdrMetadata: ShadowClientHDRMetadata?,
        currentHeadroom: CGFloat
    ) -> String {
        let outputColorSpaceName =
            renderTargetConfiguration.outputColorSpace.name as String? ?? "nil"
        let sourceHDRColorSpaceName =
            colorConfiguration.displayColorSpace.name as String? ??
            colorConfiguration.renderColorSpace.name as String? ??
            "nil"
        guard renderTargetConfiguration.prefersExtendedDynamicRange else {
            return "enabled=false output-color-space=\(outputColorSpaceName) source-color-space=\(sourceHDRColorSpaceName)"
        }

        let opticalOutputScale = opticalOutputScale(for: renderTargetConfiguration)
        if isHLGLikeColorSpaceName(
            colorConfiguration.displayColorSpace.name ??
                colorConfiguration.renderColorSpace.name
        ) {
            return "enabled=true source=hlg-skip output-color-space=\(outputColorSpaceName) source-color-space=\(sourceHDRColorSpaceName) optical-output-scale=\(opticalOutputScale)"
        }

        if let hdrMetadata {
            let hasDisplayInfo = hdrMetadata.hasHDR10DisplayInfo
            let hasContentInfo = hdrMetadata.hasHDR10ContentInfo
            if hasDisplayInfo || hasContentInfo {
                return "enabled=true source=frame-attachments-hdr10 output-color-space=\(outputColorSpaceName) source-color-space=\(sourceHDRColorSpaceName) optical-output-scale=\(opticalOutputScale) raw-\(hdrMetadata.debugSummary)"
            }
            let maxLuminance = Float(max(hdrMetadata.maxDisplayLuminance, 1))
            let minLuminance = hdrMetadata.minDisplayLuminance > 0
                ? Float(hdrMetadata.minDisplayLuminance) / 10_000.0
                : 0.0001
            return "enabled=true source=frame-attachments-luminance output-color-space=\(outputColorSpaceName) source-color-space=\(sourceHDRColorSpaceName) optical-output-scale=\(opticalOutputScale) min-display-nits=\(minLuminance) max-display-nits=\(maxLuminance) raw-\(hdrMetadata.debugSummary)"
        }

        let peakLuminance = Float(max(currentHeadroom, 1.0) * 100.0)
        return "enabled=true source=fallback output-color-space=\(outputColorSpaceName) source-color-space=\(sourceHDRColorSpaceName) optical-output-scale=\(opticalOutputScale) current-headroom=\(currentHeadroom) min-display=0.0001 max-display=\(peakLuminance)"
    }

    static func resolvedOutputColorSpace(
        prefersExtendedDynamicRange: Bool,
        sdrSourceColorSpace: CGColorSpace,
        hdrDisplayColorSpace: CGColorSpace,
        screenColorSpace: CGColorSpace? = nil,
        hdrSourceColorSpace: CGColorSpace? = nil,
        renderBackend: ShadowClientSurfaceColorRenderBackend = .coreImage
    ) -> CGColorSpace {
        if prefersExtendedDynamicRange {
            if renderBackend == .metalYUV,
               prefersDirectHDRPresentation(
                   screenColorSpace: screenColorSpace,
                   hdrSourceColorSpace: hdrSourceColorSpace,
                   hdrDisplayColorSpace: hdrDisplayColorSpace
               )
            {
                return hdrDisplayColorSpace
            }
            if renderBackend == .metalYUV,
               let linearHDROutputColorSpace = preferredLinearHDROutputColorSpace(
                   screenColorSpace: screenColorSpace,
                   hdrSourceColorSpace: hdrSourceColorSpace,
                   hdrDisplayColorSpace: hdrDisplayColorSpace
               )
            {
                return linearHDROutputColorSpace
            }
            return hdrDisplayColorSpace
        }

        return sdrSourceColorSpace
    }

    private static func preferredTargetPixelFormat(
        prefersExtendedDynamicRange: Bool,
        renderBackend: ShadowClientSurfaceColorRenderBackend,
        fallbackPixelFormat: MTLPixelFormat,
        outputColorSpace: CGColorSpace
    ) -> MTLPixelFormat {
        guard prefersExtendedDynamicRange else {
            return .bgra8Unorm
        }
        guard renderBackend == .metalYUV,
              isLinearHDROutputColorSpace(outputColorSpace)
        else {
            return fallbackPixelFormat
        }
        return .rgba16Float
    }

    private static func opticalOutputScale(
        for renderTargetConfiguration: ShadowClientSurfaceRenderTargetConfiguration
    ) -> Float {
        if renderTargetConfiguration.targetPixelFormat == .rgba16Float {
            return 100.0
        }
        return 10_000.0
    }

    private static func prefersDirectHDRPresentation(
        screenColorSpace: CGColorSpace?,
        hdrSourceColorSpace: CGColorSpace?,
        hdrDisplayColorSpace: CGColorSpace
    ) -> Bool {
        let displayFamily = hdrColorFamily(for: hdrDisplayColorSpace.name)
        let sourceFamily = hdrColorFamily(for: hdrSourceColorSpace?.name ?? hdrDisplayColorSpace.name)
        let screenFamily = hdrColorFamily(for: screenColorSpace?.name)
        let transferKind = hdrTransferKind(for: hdrDisplayColorSpace.name)
        let screenTransferKind = hdrTransferKind(for: screenColorSpace?.name)

        guard transferKind == .pq || transferKind == .hlg else {
            return false
        }
        guard displayFamily != .unknown,
              sourceFamily == displayFamily
        else {
            return false
        }
        guard screenFamily != .unknown else {
            return false
        }
        guard screenFamily == displayFamily else {
            return false
        }
        return screenTransferKind == transferKind
    }

    private static func preferredLinearHDROutputColorSpace(
        screenColorSpace: CGColorSpace?,
        hdrSourceColorSpace: CGColorSpace?,
        hdrDisplayColorSpace: CGColorSpace
    ) -> CGColorSpace? {
        let candidateNames = [
            screenColorSpace?.name,
            hdrSourceColorSpace?.name,
            hdrDisplayColorSpace.name,
        ]

        if candidateNames.contains(where: isDisplayP3LikeColorSpaceName),
           let linearDisplayP3 = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
        {
            return linearDisplayP3
        }

        if candidateNames.contains(where: isRec2020LikeColorSpaceName),
           let linearRec2020 = CGColorSpace(name: CGColorSpace.extendedLinearITUR_2020)
        {
            return linearRec2020
        }

        if candidateNames.contains(where: isSRGBLikeColorSpaceName),
           let linearSRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        {
            return linearSRGB
        }

        return nil
    }

    private static func isLinearHDROutputColorSpace(_ colorSpace: CGColorSpace) -> Bool {
        switch colorSpace.name {
        case CGColorSpace.extendedLinearDisplayP3,
             CGColorSpace.extendedLinearITUR_2020,
             CGColorSpace.extendedLinearSRGB:
            return true
        default:
            return false
        }
    }

    private static func isHLGLikeColorSpaceName(_ name: CFString?) -> Bool {
        guard let name else {
            return false
        }
        if name == CGColorSpace.itur_2100_HLG ||
            name == CGColorSpace.displayP3_HLG
        {
            return true
        }
        return (name as String).uppercased().contains("HLG")
    }

    private static func hdrColorFamily(for name: CFString?) -> HDRColorFamily {
        if isDisplayP3LikeColorSpaceName(name) {
            return .displayP3
        }
        if isRec2020LikeColorSpaceName(name) {
            return .rec2020
        }
        if isSRGBLikeColorSpaceName(name) {
            return .sRGB
        }
        return .unknown
    }

    private static func hdrTransferKind(for name: CFString?) -> HDRTransferKind {
        if isHLGLikeColorSpaceName(name) {
            return .hlg
        }
        guard let name else {
            return .unknown
        }
        if name == CGColorSpace.itur_2100_PQ ||
            name == CGColorSpace.displayP3_PQ ||
            (name as String).uppercased().contains("PQ")
        {
            return .pq
        }
        if name == CGColorSpace.itur_709 ||
            name == CGColorSpace.sRGB ||
            name == CGColorSpace.displayP3
        {
            return .sdr
        }
        return .unknown
    }

    private static func isDisplayP3LikeColorSpaceName(_ name: CFString?) -> Bool {
        guard let name else {
            return false
        }
        if name == CGColorSpace.displayP3 ||
            name == CGColorSpace.displayP3_PQ ||
            name == CGColorSpace.displayP3_HLG ||
            name == CGColorSpace.extendedLinearDisplayP3
        {
            return true
        }
        let stringName = name as String
        return stringName.uppercased().contains("DISPLAYP3") || stringName.uppercased().contains("P3_D65")
    }

    private static func isRec2020LikeColorSpaceName(_ name: CFString?) -> Bool {
        guard let name else {
            return false
        }
        if name == CGColorSpace.itur_2020 ||
            name == CGColorSpace.itur_2100_PQ ||
            name == CGColorSpace.itur_2100_HLG ||
            name == CGColorSpace.extendedLinearITUR_2020
        {
            return true
        }
        let stringName = name as String
        return stringName.uppercased().contains("2020") || stringName.uppercased().contains("2100")
    }

    private static func isSRGBLikeColorSpaceName(_ name: CFString?) -> Bool {
        guard let name else {
            return false
        }
        if name == CGColorSpace.sRGB || name == CGColorSpace.extendedLinearSRGB {
            return true
        }
        return (name as String).uppercased().contains("SRGB")
    }

    private static func hdrMetadata(
        displayInfoData: Data?,
        contentInfoData: Data?
    ) -> ShadowClientHDRMetadata? {
        let parsedDisplayInfo = parseDisplayInfo(displayInfoData)
        let parsedContentInfo = parseContentInfo(contentInfoData)
        guard parsedDisplayInfo != nil || parsedContentInfo != nil else {
            return nil
        }

        return ShadowClientHDRMetadata(
            displayPrimaries: parsedDisplayInfo?.displayPrimaries ??
                Array(repeating: .init(x: 0, y: 0), count: 3),
            whitePoint: parsedDisplayInfo?.whitePoint ?? .init(x: 0, y: 0),
            maxDisplayLuminance: parsedDisplayInfo?.maxDisplayLuminance ?? 0,
            minDisplayLuminance: parsedDisplayInfo?.minDisplayLuminance ?? 0,
            maxContentLightLevel: parsedContentInfo?.maxContentLightLevel ?? 0,
            maxFrameAverageLightLevel: parsedContentInfo?.maxFrameAverageLightLevel ?? 0,
            maxFullFrameLuminance: 0
        )
    }

    private static func parseDisplayInfo(
        _ data: Data?
    ) -> (
        displayPrimaries: [ShadowClientHDRMetadataChromaticity],
        whitePoint: ShadowClientHDRMetadataChromaticity,
        maxDisplayLuminance: UInt16,
        minDisplayLuminance: UInt16
    )? {
        guard let data, data.count == 24 else {
            return nil
        }

        var offset = 0
        var primaries: [ShadowClientHDRMetadataChromaticity] = []
        primaries.reserveCapacity(3)
        for _ in 0 ..< 3 {
            primaries.append(
                .init(
                    x: readUInt16BE(data, at: offset),
                    y: readUInt16BE(data, at: offset + 2)
                )
            )
            offset += 4
        }

        return (
            displayPrimaries: primaries,
            whitePoint: .init(
                x: readUInt16BE(data, at: offset),
                y: readUInt16BE(data, at: offset + 2)
            ),
            maxDisplayLuminance: UInt16(clamping: readUInt32BE(data, at: offset + 4)),
            minDisplayLuminance: UInt16(clamping: readUInt32BE(data, at: offset + 8))
        )
    }

    private static func parseContentInfo(
        _ data: Data?
    ) -> (
        maxContentLightLevel: UInt16,
        maxFrameAverageLightLevel: UInt16
    )? {
        guard let data, data.count == 4 else {
            return nil
        }

        return (
            maxContentLightLevel: readUInt16BE(data, at: 0),
            maxFrameAverageLightLevel: readUInt16BE(data, at: 2)
        )
    }

    private static func readUInt16BE(_ data: Data, at offset: Int) -> UInt16 {
        let b0 = UInt16(data[offset]) << 8
        let b1 = UInt16(data[offset + 1])
        return b0 | b1
    }

    private static func readUInt32BE(_ data: Data, at offset: Int) -> UInt32 {
        let b0 = UInt32(data[offset]) << 24
        let b1 = UInt32(data[offset + 1]) << 16
        let b2 = UInt32(data[offset + 2]) << 8
        let b3 = UInt32(data[offset + 3])
        return b0 | b1 | b2 | b3
    }
}
