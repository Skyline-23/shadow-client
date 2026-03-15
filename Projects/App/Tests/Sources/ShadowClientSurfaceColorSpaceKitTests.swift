import CoreGraphics
import Testing
@testable import ShadowClientFeatureHome

@Test("Surface color space kit preserves HDR output color space on iOS-style displays")
func surfaceColorSpaceKitPreservesHDRColorSpace() {
    let sdr = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
    let hdr = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) ?? CGColorSpaceCreateDeviceRGB()

    let resolved = ShadowClientSurfaceColorSpaceKit.resolvedOutputColorSpace(
        prefersExtendedDynamicRange: true,
        sdrSourceColorSpace: sdr,
        hdrDisplayColorSpace: hdr
    )

    #expect(resolved.name == hdr.name)
}

@Test("Surface color space kit prefers the screen color space for HDR when provided")
func surfaceColorSpaceKitPrefersScreenColorSpaceForHDR() {
    let sdr = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
    let hdr = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) ?? CGColorSpaceCreateDeviceRGB()
    let screen = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    let resolved = ShadowClientSurfaceColorSpaceKit.resolvedOutputColorSpace(
        prefersExtendedDynamicRange: true,
        sdrSourceColorSpace: sdr,
        hdrDisplayColorSpace: hdr,
        screenColorSpace: screen
    )

    #expect(resolved.name == screen.name)
}

@Test("Surface color space kit preserves the source HDR color space for Metal YUV rendering")
func surfaceColorSpaceKitPreservesSourceHDRColorSpaceForMetalYUV() {
    let sdr = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
    let hdr = CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) ?? CGColorSpaceCreateDeviceRGB()
    let sourceHDR = CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()

    let resolved = ShadowClientSurfaceColorSpaceKit.resolvedOutputColorSpace(
        prefersExtendedDynamicRange: true,
        sdrSourceColorSpace: sdr,
        hdrDisplayColorSpace: hdr,
        hdrSourceColorSpace: sourceHDR,
        renderBackend: .metalYUV
    )

    #expect(resolved.name == sourceHDR.name)
}
