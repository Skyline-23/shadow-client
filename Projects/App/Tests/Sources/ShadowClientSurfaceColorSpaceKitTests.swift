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

@Test("Surface color space kit preserves HDR output color space even when a screen color space is provided")
func surfaceColorSpaceKitPreservesHDROutputColorSpaceWhenScreenColorSpaceIsProvided() {
    let sdr = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
    let hdr = CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
    let screen = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    let resolved = ShadowClientSurfaceColorSpaceKit.resolvedOutputColorSpace(
        prefersExtendedDynamicRange: true,
        sdrSourceColorSpace: sdr,
        hdrDisplayColorSpace: hdr,
        screenColorSpace: screen
    )

    #expect(resolved.name == hdr.name)
}

@Test("Surface color space kit uses display HDR color space for Metal YUV rendering")
func surfaceColorSpaceKitUsesDisplayHDRColorSpaceForMetalYUV() {
    let sdr = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
    let hdr = CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()

    let resolved = ShadowClientSurfaceColorSpaceKit.resolvedOutputColorSpace(
        prefersExtendedDynamicRange: true,
        sdrSourceColorSpace: sdr,
        hdrDisplayColorSpace: hdr,
        hdrSourceColorSpace: CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB(),
        renderBackend: .metalYUV
    )

    #expect(resolved.name == hdr.name)
}

@Test("Surface color space kit keeps direct HDR presentation enabled for Metal YUV targets")
func surfaceColorSpaceKitKeepsDirectHDRPresentationEnabledForMetalYUVTargets() {
    let hdr = CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
    let colorConfiguration = ShadowClientRealtimeSessionColorConfiguration(
        renderColorSpace: hdr,
        displayColorSpace: hdr,
        pixelFormat: .bgr10a2Unorm,
        prefersExtendedDynamicRange: true,
        videoRangeExpansion: nil
    )

    let configuration = ShadowClientSurfaceColorSpaceKit.renderTargetConfiguration(
        colorConfiguration: colorConfiguration,
        supportsExtendedDynamicRange: true,
        renderBackend: .metalYUV,
        screenColorSpace: nil
    )

    #expect(configuration.prefersExtendedDynamicRange)
    #expect(configuration.targetPixelFormat == .bgr10a2Unorm)
    #expect(configuration.outputColorSpace.name == hdr.name)
}
