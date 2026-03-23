import CoreGraphics
import Metal

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
        let targetPixelFormat = prefersExtendedDynamicRange
            ? colorConfiguration.pixelFormat
            : .bgra8Unorm

        return .init(
            renderBackend: renderBackend,
            targetPixelFormat: targetPixelFormat,
            prefersExtendedDynamicRange: prefersExtendedDynamicRange,
            outputColorSpace: resolvedOutputColorSpace(
                prefersExtendedDynamicRange: prefersExtendedDynamicRange,
                sdrSourceColorSpace: colorConfiguration.renderColorSpace,
                hdrDisplayColorSpace: colorConfiguration.displayColorSpace,
                screenColorSpace: screenColorSpace,
                hdrSourceColorSpace: colorConfiguration.renderColorSpace,
                renderBackend: renderBackend
            )
        )
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
            if prefersDisplayP3ExtendedDynamicRangeOutput(screenColorSpace: screenColorSpace) {
                return CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
                    ?? hdrDisplayColorSpace
            }
            return hdrDisplayColorSpace
        }

        return sdrSourceColorSpace
    }

    private static func prefersDisplayP3ExtendedDynamicRangeOutput(
        screenColorSpace: CGColorSpace?
    ) -> Bool {
        guard let colorSpaceName = screenColorSpace?.name else {
            return false
        }
        return colorSpaceName == CGColorSpace.displayP3 ||
            colorSpaceName == CGColorSpace.extendedLinearDisplayP3
    }
}
