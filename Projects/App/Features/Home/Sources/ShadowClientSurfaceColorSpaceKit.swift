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

    static func frameCarriesStaticHDRMetadata(
        _ pixelBuffer: CVPixelBuffer
    ) -> Bool {
        staticHDRAttachmentData(
            forKey: kCVImageBufferMasteringDisplayColorVolumeKey,
            pixelBuffer: pixelBuffer
        ) != nil ||
            staticHDRAttachmentData(
                forKey: kCVImageBufferContentLightLevelInfoKey,
                pixelBuffer: pixelBuffer
            ) != nil
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
            let maxLuminance = Float(max(hdrMetadata.maxDisplayLuminance, 1))
            let minLuminance = hdrMetadata.minDisplayLuminance > 0
                ? Float(hdrMetadata.minDisplayLuminance) / 10_000.0
                : 0.0001
            return "enabled=true source=hdrMode-luminance output-color-space=\(outputColorSpaceName) source-color-space=\(sourceHDRColorSpaceName) optical-output-scale=\(opticalOutputScale) min-display-nits=\(minLuminance) max-display-nits=\(maxLuminance) raw-\(hdrMetadata.debugSummary)"
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
}
