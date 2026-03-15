import CoreGraphics

enum ShadowClientSurfaceColorSpaceKit {
    static func resolvedOutputColorSpace(
        prefersExtendedDynamicRange: Bool,
        sdrSourceColorSpace: CGColorSpace,
        hdrDisplayColorSpace: CGColorSpace,
        screenColorSpace: CGColorSpace? = nil
    ) -> CGColorSpace {
        if prefersExtendedDynamicRange {
            return screenColorSpace ?? hdrDisplayColorSpace
        }

        return sdrSourceColorSpace
    }
}
