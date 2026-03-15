import CoreGraphics

enum ShadowClientSurfaceColorRenderBackend {
    case coreImage
    case metalYUV
}

enum ShadowClientSurfaceColorSpaceKit {
    static func resolvedOutputColorSpace(
        prefersExtendedDynamicRange: Bool,
        sdrSourceColorSpace: CGColorSpace,
        hdrDisplayColorSpace: CGColorSpace,
        screenColorSpace: CGColorSpace? = nil,
        hdrSourceColorSpace: CGColorSpace? = nil,
        renderBackend: ShadowClientSurfaceColorRenderBackend = .coreImage
    ) -> CGColorSpace {
        if prefersExtendedDynamicRange {
            switch renderBackend {
            case .coreImage:
                return screenColorSpace ?? hdrDisplayColorSpace
            case .metalYUV:
                return hdrSourceColorSpace ?? screenColorSpace ?? hdrDisplayColorSpace
            }
        }

        return sdrSourceColorSpace
    }
}
