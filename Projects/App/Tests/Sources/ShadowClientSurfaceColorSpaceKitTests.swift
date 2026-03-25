import CoreGraphics
import QuartzCore
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

@Test("Surface color space kit preserves HDR output color space when a P3 screen color space is provided")
func surfaceColorSpaceKitPreservesHDROutputColorSpaceWhenP3ScreenColorSpaceIsProvided() {
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

@Test("Surface color space kit uses linear HDR output for Metal YUV rendering on P3 screens")
func surfaceColorSpaceKitUsesLinearHDROutputForMetalYUVOnP3Screens() {
    let sdr = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
    let hdr = CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
    let screen = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    let resolved = ShadowClientSurfaceColorSpaceKit.resolvedOutputColorSpace(
        prefersExtendedDynamicRange: true,
        sdrSourceColorSpace: sdr,
        hdrDisplayColorSpace: hdr,
        hdrSourceColorSpace: CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB(),
        renderBackend: .metalYUV,
        screenColorSpace: screen
    )

    #expect(resolved.name == CGColorSpace.extendedLinearDisplayP3)
}

@Test("Surface color space kit uses float linear HDR targets for Metal YUV on P3 screens")
func surfaceColorSpaceKitUsesFloatLinearHDRTargetsForMetalYUVOnP3Screens() {
    let hdr = CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
    let colorConfiguration = ShadowClientRealtimeSessionColorConfiguration(
        renderColorSpace: hdr,
        displayColorSpace: hdr,
        pixelFormat: .bgr10a2Unorm,
        prefersExtendedDynamicRange: true,
        videoRangeExpansion: nil
    )
    let screen = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    let configuration = ShadowClientSurfaceColorSpaceKit.renderTargetConfiguration(
        colorConfiguration: colorConfiguration,
        supportsExtendedDynamicRange: true,
        renderBackend: .metalYUV,
        screenColorSpace: screen
    )

    #expect(configuration.prefersExtendedDynamicRange)
    #expect(configuration.targetPixelFormat == .rgba16Float)
    #expect(configuration.outputColorSpace.name == CGColorSpace.extendedLinearDisplayP3)
}

@Test("Surface color space kit maps HDR Metal YUV output to linear Display P3 on P3 screens")
func surfaceColorSpaceKitMapsHDRMetalYUVOutputToLinearDisplayP3OnP3Screens() {
    let hdr = CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
    let colorConfiguration = ShadowClientRealtimeSessionColorConfiguration(
        renderColorSpace: hdr,
        displayColorSpace: hdr,
        pixelFormat: .bgr10a2Unorm,
        prefersExtendedDynamicRange: true,
        videoRangeExpansion: nil
    )
    let screen = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    let configuration = ShadowClientSurfaceColorSpaceKit.renderTargetConfiguration(
        colorConfiguration: colorConfiguration,
        supportsExtendedDynamicRange: true,
        renderBackend: .metalYUV,
        screenColorSpace: screen
    )

    #expect(configuration.prefersExtendedDynamicRange)
    #expect(configuration.targetPixelFormat == .rgba16Float)
    #expect(configuration.outputColorSpace.name == CGColorSpace.extendedLinearDisplayP3)
}

@Test("Surface color space kit creates HDR10 EDR metadata for linear Metal YUV output")
func surfaceColorSpaceKitCreatesHDR10EDRMetadataForLinearMetalYUVOutput() {
    let hdr = CGColorSpace(name: CGColorSpace.displayP3_PQ) ?? CGColorSpaceCreateDeviceRGB()
    let colorConfiguration = ShadowClientRealtimeSessionColorConfiguration(
        renderColorSpace: hdr,
        displayColorSpace: hdr,
        pixelFormat: .bgr10a2Unorm,
        prefersExtendedDynamicRange: true,
        videoRangeExpansion: nil
    )
    let renderTargetConfiguration = ShadowClientSurfaceRenderTargetConfiguration(
        renderBackend: .metalYUV,
        targetPixelFormat: .rgba16Float,
        prefersExtendedDynamicRange: true,
        outputColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3)
            ?? CGColorSpaceCreateDeviceRGB()
    )
    let hdrMetadata = ShadowClientHDRMetadata(
        displayPrimaries: [
            .init(x: 13250, y: 34500),
            .init(x: 7500, y: 3000),
            .init(x: 34000, y: 16000),
        ],
        whitePoint: .init(x: 15635, y: 16450),
        maxDisplayLuminance: 1000,
        minDisplayLuminance: 1,
        maxContentLightLevel: 1200,
        maxFrameAverageLightLevel: 600,
        maxFullFrameLuminance: 400
    )

    let metadata = ShadowClientSurfaceColorSpaceKit.edrMetadata(
        colorConfiguration: colorConfiguration,
        renderTargetConfiguration: renderTargetConfiguration,
        hdrMetadata: hdrMetadata,
        currentHeadroom: 8.0
    )

    #expect(metadata != nil)
}
