import CoreGraphics
import CoreVideo
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

@Test("Surface color space kit preserves direct PQ HDR output for Metal YUV rendering on P3 screens")
func surfaceColorSpaceKitPreservesDirectPQHDROutputForMetalYUVOnP3Screens() {
    let sdr = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
    let hdr = CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB()
    let screen = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    let resolved = ShadowClientSurfaceColorSpaceKit.resolvedOutputColorSpace(
        prefersExtendedDynamicRange: true,
        sdrSourceColorSpace: sdr,
        hdrDisplayColorSpace: hdr,
        screenColorSpace: screen,
        hdrSourceColorSpace: CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB(),
        renderBackend: .metalYUV
    )

    #expect(resolved.name == CGColorSpace.itur_2100_PQ)
}

@Test("Surface color space kit preserves direct Display P3 PQ output for Metal YUV rendering")
func surfaceColorSpaceKitPreservesDirectDisplayP3PQOutputForMetalYUV() {
    let sdr = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
    let hdr = CGColorSpace(name: CGColorSpace.displayP3_PQ) ?? CGColorSpaceCreateDeviceRGB()
    let screen = CGColorSpace(name: CGColorSpace.displayP3_PQ) ?? CGColorSpaceCreateDeviceRGB()

    let resolved = ShadowClientSurfaceColorSpaceKit.resolvedOutputColorSpace(
        prefersExtendedDynamicRange: true,
        sdrSourceColorSpace: sdr,
        hdrDisplayColorSpace: hdr,
        screenColorSpace: screen,
        hdrSourceColorSpace: hdr,
        renderBackend: .metalYUV
    )

    #expect(resolved.name == CGColorSpace.displayP3_PQ)
}

@Test("Surface color space kit preserves direct Display P3 PQ output on P3 screens")
func surfaceColorSpaceKitPreservesDirectDisplayP3PQOutputOnP3Screens() {
    let sdr = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
    let hdr = CGColorSpace(name: CGColorSpace.displayP3_PQ) ?? CGColorSpaceCreateDeviceRGB()
    let screen = CGColorSpace(name: CGColorSpace.displayP3) ?? CGColorSpaceCreateDeviceRGB()

    let resolved = ShadowClientSurfaceColorSpaceKit.resolvedOutputColorSpace(
        prefersExtendedDynamicRange: true,
        sdrSourceColorSpace: sdr,
        hdrDisplayColorSpace: hdr,
        screenColorSpace: screen,
        hdrSourceColorSpace: hdr,
        renderBackend: .metalYUV
    )

    #expect(resolved.name == CGColorSpace.displayP3_PQ)
}

@Test("Surface color space kit preserves direct Display P3 PQ output when screen transfer is unknown")
func surfaceColorSpaceKitPreservesDirectDisplayP3PQOutputWhenScreenTransferIsUnknown() {
    let sdr = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
    let hdr = CGColorSpace(name: CGColorSpace.displayP3_PQ) ?? CGColorSpaceCreateDeviceRGB()

    let resolved = ShadowClientSurfaceColorSpaceKit.resolvedOutputColorSpace(
        prefersExtendedDynamicRange: true,
        sdrSourceColorSpace: sdr,
        hdrDisplayColorSpace: hdr,
        screenColorSpace: nil,
        hdrSourceColorSpace: hdr,
        renderBackend: .metalYUV
    )

    #expect(resolved.name == CGColorSpace.displayP3_PQ)
}

@Test("Surface color space kit preserves direct 10-bit PQ targets for Metal YUV on P3 screens")
func surfaceColorSpaceKitPreservesDirectPQTargetsForMetalYUVOnP3Screens() {
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
    #expect(configuration.targetPixelFormat == .bgr10a2Unorm)
    #expect(configuration.outputColorSpace.name == CGColorSpace.itur_2100_PQ)
}

@Test("Surface color space kit preserves 10-bit PQ targets for Display P3 HDR Metal YUV output")
func surfaceColorSpaceKitPreservesDirectDisplayP3PQTargetsForMetalYUV() {
    let hdr = CGColorSpace(name: CGColorSpace.displayP3_PQ) ?? CGColorSpaceCreateDeviceRGB()
    let colorConfiguration = ShadowClientRealtimeSessionColorConfiguration(
        renderColorSpace: hdr,
        displayColorSpace: hdr,
        pixelFormat: .bgr10a2Unorm,
        prefersExtendedDynamicRange: true,
        videoRangeExpansion: nil
    )
    let screen = CGColorSpace(name: CGColorSpace.displayP3_PQ) ?? CGColorSpaceCreateDeviceRGB()

    let configuration = ShadowClientSurfaceColorSpaceKit.renderTargetConfiguration(
        colorConfiguration: colorConfiguration,
        supportsExtendedDynamicRange: true,
        renderBackend: .metalYUV,
        screenColorSpace: screen
    )

    #expect(configuration.prefersExtendedDynamicRange)
    #expect(configuration.targetPixelFormat == .bgr10a2Unorm)
    #expect(configuration.outputColorSpace.name == CGColorSpace.displayP3_PQ)
}

@Test("Surface color space kit preserves direct HDR Metal YUV output on P3 screens")
func surfaceColorSpaceKitPreservesDirectHDRMetalYUVOutputOnP3Screens() {
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
    #expect(configuration.targetPixelFormat == .bgr10a2Unorm)
    #expect(configuration.outputColorSpace.name == CGColorSpace.itur_2100_PQ)
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

@Test("Surface color space kit skips system tone-mapping metadata for direct PQ Metal YUV output")
func surfaceColorSpaceKitSkipsEDRMetadataForDirectPQMetalYUVOutput() {
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
        targetPixelFormat: .bgr10a2Unorm,
        prefersExtendedDynamicRange: true,
        outputColorSpace: hdr
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
    let summary = ShadowClientSurfaceColorSpaceKit.edrMetadataDebugSummary(
        colorConfiguration: colorConfiguration,
        renderTargetConfiguration: renderTargetConfiguration,
        hdrMetadata: hdrMetadata,
        currentHeadroom: 8.0
    )

    #expect(metadata == nil)
    #expect(summary.contains("source=direct-color-space"))
}

@Test("Surface color space kit reads static HDR attachments from HDR frames")
func surfaceColorSpaceKitReadsStaticHDRAttachmentsForHDRFrames() throws {
    let hdr = CGColorSpace(name: CGColorSpace.displayP3_PQ) ?? CGColorSpaceCreateDeviceRGB()
    let colorConfiguration = ShadowClientRealtimeSessionColorConfiguration(
        renderColorSpace: hdr,
        displayColorSpace: hdr,
        pixelFormat: .bgr10a2Unorm,
        prefersExtendedDynamicRange: true,
        videoRangeExpansion: nil
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
    let pixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferMasteringDisplayColorVolumeKey,
        hdrMetadata.hdr10DisplayInfoData as CFData,
        .shouldPropagate
    )
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferContentLightLevelInfoKey,
        hdrMetadata.hdr10ContentInfoData as CFData,
        .shouldPropagate
    )

    let renderedMetadata = ShadowClientSurfaceColorSpaceKit.renderedFrameHDRMetadata(
        colorConfiguration: colorConfiguration,
        pixelBuffer: pixelBuffer
    )

    #expect(renderedMetadata == hdrMetadata)
}

@Test("Surface color space kit ignores static HDR attachments for SDR frames")
func surfaceColorSpaceKitIgnoresStaticHDRAttachmentsForSDRFrames() throws {
    let sdr = CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB()
    let colorConfiguration = ShadowClientRealtimeSessionColorConfiguration(
        renderColorSpace: sdr,
        displayColorSpace: sdr,
        pixelFormat: .bgra8Unorm,
        prefersExtendedDynamicRange: false,
        videoRangeExpansion: nil
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
    let pixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferMasteringDisplayColorVolumeKey,
        hdrMetadata.hdr10DisplayInfoData as CFData,
        .shouldPropagate
    )
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferContentLightLevelInfoKey,
        hdrMetadata.hdr10ContentInfoData as CFData,
        .shouldPropagate
    )

    let renderedMetadata = ShadowClientSurfaceColorSpaceKit.renderedFrameHDRMetadata(
        colorConfiguration: colorConfiguration,
        pixelBuffer: pixelBuffer
    )

    #expect(renderedMetadata == nil)
}

private func makePixelBuffer(pixelFormat: OSType) throws -> CVPixelBuffer {
    var pixelBuffer: CVPixelBuffer?
    let attributes: [CFString: Any] = [
        kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
    ]
    let status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        4,
        4,
        pixelFormat,
        attributes as CFDictionary,
        &pixelBuffer
    )
    #expect(status == kCVReturnSuccess)
    guard let pixelBuffer else {
        throw TestError("Failed to create test pixel buffer.")
    }
    return pixelBuffer
}

private struct TestError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
