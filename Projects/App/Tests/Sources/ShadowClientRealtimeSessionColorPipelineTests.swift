import CoreGraphics
import CoreVideo
import Metal
import Testing
@testable import ShadowClientFeatureHome

@Test("Color pipeline preserves HDR PQ output for HDR PQ frames")
func colorPipelineEnablesEDRForHDRPQFrames() throws {
    let pixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferColorPrimariesKey,
        kCVImageBufferColorPrimaries_ITU_R_2020,
        .shouldPropagate
    )
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferTransferFunctionKey,
        kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ,
        .shouldPropagate
    )

    let configuration = ShadowClientRealtimeSessionColorPipeline.configuration(
        for: pixelBuffer,
        allowExtendedDynamicRange: true
    )
    #expect(configuration.prefersExtendedDynamicRange)
    #expect(configuration.pixelFormat == .bgr10a2Unorm)
    #expect(configuration.renderColorSpace.name == CGColorSpace.itur_2100_PQ)
    #expect(configuration.videoRangeExpansion == nil)
    #expect(configuration.displayColorSpace.name == CGColorSpace.itur_2100_PQ)
}

@Test("Color pipeline preserves Display P3 HDR metadata for PQ frames")
func colorPipelinePreservesDisplayP3HDRMetadataForPQFrames() throws {
    let pixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferColorPrimariesKey,
        kCVImageBufferColorPrimaries_P3_D65,
        .shouldPropagate
    )
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferTransferFunctionKey,
        kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ,
        .shouldPropagate
    )
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferYCbCrMatrixKey,
        kCVImageBufferYCbCrMatrix_ITU_R_2020,
        .shouldPropagate
    )

    let configuration = ShadowClientRealtimeSessionColorPipeline.configuration(
        for: pixelBuffer,
        allowExtendedDynamicRange: true
    )
    #expect(configuration.prefersExtendedDynamicRange)
    #expect(configuration.renderColorSpace.name == CGColorSpace.displayP3_PQ)
    #expect(configuration.displayColorSpace.name == CGColorSpace.displayP3_PQ)
    #expect(
        ShadowClientRealtimeSessionColorPipeline.sourceStandard(for: pixelBuffer) == .displayP3
    )
    #expect(
        ShadowClientRealtimeSessionColorPipeline.matrixStandard(for: pixelBuffer) == .rec2020
    )
}

@Test("Color pipeline preserves Display P3 HDR metadata when PQ frames use a BT.709 matrix")
func colorPipelinePreservesDisplayP3HDRMetadataForPQFramesUsingBT709Matrix() throws {
    let pixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferColorPrimariesKey,
        kCVImageBufferColorPrimaries_P3_D65,
        .shouldPropagate
    )
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferTransferFunctionKey,
        kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ,
        .shouldPropagate
    )
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferYCbCrMatrixKey,
        kCVImageBufferYCbCrMatrix_ITU_R_709_2,
        .shouldPropagate
    )

    let configuration = ShadowClientRealtimeSessionColorPipeline.configuration(
        for: pixelBuffer,
        allowExtendedDynamicRange: true
    )
    #expect(configuration.prefersExtendedDynamicRange)
    #expect(configuration.renderColorSpace.name == CGColorSpace.displayP3_PQ)
    #expect(configuration.displayColorSpace.name == CGColorSpace.displayP3_PQ)
    #expect(
        attachmentStringValue(
            forKey: kCVImageBufferColorPrimariesKey,
            pixelBuffer: pixelBuffer
        ) == (kCVImageBufferColorPrimaries_P3_D65 as String)
    )
    #expect(
        attachmentStringValue(
            forKey: kCVImageBufferYCbCrMatrixKey,
            pixelBuffer: pixelBuffer
        ) == (kCVImageBufferYCbCrMatrix_ITU_R_709_2 as String)
    )
    #expect(
        ShadowClientRealtimeSessionColorPipeline.sourceStandard(for: pixelBuffer) == .displayP3
    )
    #expect(
        ShadowClientRealtimeSessionColorPipeline.matrixStandard(for: pixelBuffer) == .rec709
    )
}

@Test("Color pipeline keeps SDR output for BT.709 frames")
func colorPipelineKeepsSDRForBT709Frames() throws {
    let pixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferColorPrimariesKey,
        kCVImageBufferColorPrimaries_ITU_R_709_2,
        .shouldPropagate
    )
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferTransferFunctionKey,
        kCVImageBufferTransferFunction_ITU_R_709_2,
        .shouldPropagate
    )

    let configuration = ShadowClientRealtimeSessionColorPipeline.configuration(
        for: pixelBuffer,
        allowExtendedDynamicRange: false
    )
    #expect(!configuration.prefersExtendedDynamicRange)
    #expect(configuration.pixelFormat == .bgra8Unorm)
    #expect(configuration.displayColorSpace.name == CGColorSpace.itur_709)
    #expect(
        configuration.videoRangeExpansion == .init(
            scale: CGFloat(255.0 / 219.0),
            bias: CGFloat(-16.0 / 219.0)
        )
    )
}

@Test("Color pipeline prefers PQ transfer metadata over attached base color space")
func colorPipelinePrefersPQTransferOverAttachedColorSpace() throws {
    let pixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
    let attachedColorSpace = CGColorSpace(name: CGColorSpace.itur_2020) ?? CGColorSpaceCreateDeviceRGB()
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferCGColorSpaceKey,
        attachedColorSpace,
        .shouldPropagate
    )
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferColorPrimariesKey,
        kCVImageBufferColorPrimaries_ITU_R_2020,
        .shouldPropagate
    )
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferTransferFunctionKey,
        kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ,
        .shouldPropagate
    )

    let configuration = ShadowClientRealtimeSessionColorPipeline.configuration(
        for: pixelBuffer,
        allowExtendedDynamicRange: true
    )
    #expect(configuration.renderColorSpace.name == CGColorSpace.itur_2100_PQ)
    #expect(configuration.prefersExtendedDynamicRange)
}

@Test("Color pipeline keeps SDR for BT.2020 10-bit frames when transfer metadata is missing")
func colorPipelineKeepsSDRForBT202010BitWithoutTransferMetadata() throws {
    let pixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferColorPrimariesKey,
        kCVImageBufferColorPrimaries_ITU_R_2020,
        .shouldPropagate
    )

    let configuration = ShadowClientRealtimeSessionColorPipeline.configuration(
        for: pixelBuffer,
        allowExtendedDynamicRange: false
    )
    #expect(!configuration.prefersExtendedDynamicRange)
    #expect(configuration.renderColorSpace.name == CGColorSpace.itur_2020)
    #expect(configuration.pixelFormat == .bgra8Unorm)
    #expect(
        attachmentStringValue(
            forKey: kCVImageBufferTransferFunctionKey,
            pixelBuffer: pixelBuffer
        ) == nil
    )
    #expect(
        attachmentStringValue(
            forKey: kCVImageBufferYCbCrMatrixKey,
            pixelBuffer: pixelBuffer
        ) == nil
    )
}

@Test("Color pipeline keeps SDR when BT.2020 metadata is present without HDR transfer on 8-bit frames")
func colorPipelineKeepsSDRForBT20208BitWithoutTransferMetadata() throws {
    let pixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferColorPrimariesKey,
        kCVImageBufferColorPrimaries_ITU_R_2020,
        .shouldPropagate
    )

    let configuration = ShadowClientRealtimeSessionColorPipeline.configuration(
        for: pixelBuffer,
        allowExtendedDynamicRange: false
    )
    #expect(!configuration.prefersExtendedDynamicRange)
    #expect(configuration.pixelFormat == .bgra8Unorm)
    #expect(
        configuration.videoRangeExpansion == .init(
            scale: CGFloat(255.0 / 219.0),
            bias: CGFloat(-16.0 / 219.0)
        )
    )
}

@Test("Color pipeline leaves YUV surfaces to Core Image attachment-based color handling")
func colorPipelineSkipsExplicitSourceColorSpaceForTenBitYUV() throws {
    let pixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
    #expect(
        !ShadowClientRealtimeSessionColorPipeline.shouldAttachExplicitSourceColorSpace(
            for: pixelBuffer
        )
    )
}

@Test("Color pipeline keeps explicit source color space disabled for unsupported formats")
func colorPipelineSkipsExplicitSourceColorSpaceForUnsupportedFormat() throws {
    let pixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_OneComponent8)
    #expect(
        !ShadowClientRealtimeSessionColorPipeline.shouldAttachExplicitSourceColorSpace(
            for: pixelBuffer
        )
    )
}

@Test("Color pipeline keeps HDR transfer metadata out of SDR rendering mode")
func colorPipelineKeepsHDRTransferMetadataOutOfSDRMode() throws {
    let pixelBuffer = try makePixelBuffer(pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange)
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferColorPrimariesKey,
        kCVImageBufferColorPrimaries_ITU_R_2020,
        .shouldPropagate
    )
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferTransferFunctionKey,
        kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ,
        .shouldPropagate
    )

    let configuration = ShadowClientRealtimeSessionColorPipeline.configuration(
        for: pixelBuffer,
        allowExtendedDynamicRange: false
    )
    #expect(!configuration.prefersExtendedDynamicRange)
    #expect(configuration.pixelFormat == .bgra8Unorm)
    #expect(configuration.displayColorSpace.name == CGColorSpace.itur_709)
    #expect(configuration.videoRangeExpansion == nil)
}

@Test("Color pipeline uses stronger SDR tone-map headroom for HDR content")
func colorPipelineUsesStrongerSDRToneMapHeadroomForHDRContent() {
    #expect(ShadowClientRealtimeSessionColorPipeline.hdrToSdrToneMapSourceHeadroom == 4.0)
    #expect(ShadowClientRealtimeSessionColorPipeline.hdrToSdrToneMapTargetHeadroom == 1.0)
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

private func attachmentStringValue(
    forKey key: CFString,
    pixelBuffer: CVPixelBuffer
) -> String? {
    guard let attachment = CVBufferCopyAttachment(pixelBuffer, key, nil) else {
        return nil
    }
    return attachment as? String
}

private struct TestError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}
