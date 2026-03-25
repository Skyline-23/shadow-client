import CoreGraphics
import CoreVideo
import Testing
@testable import ShadowClientFeatureHome

@Test("YUV Metal pipeline preserves encoded HDR PQ output for HDR PQ frames")
func yuvMetalPipelinePreservesEncodedHDRPQOutputForHDRPQFrames() throws {
    let pixelBuffer = try makeMetalColorProcessingPixelBuffer(
        pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
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

    let descriptor = ShadowClientRealtimeSessionYUVMetalPipeline.colorProcessingDescriptor(
        for: pixelBuffer,
        outputColorSpace: CGColorSpace(name: CGColorSpace.itur_2100_PQ) ?? CGColorSpaceCreateDeviceRGB(),
        prefersExtendedDynamicRange: true
    )

    #expect(descriptor.transferFunction == .pq)
    #expect(!descriptor.decodesTransfer)
    #expect(!descriptor.appliesToneMapToSDR)
    #expect(!descriptor.appliesGamutTransform)
    #expect(descriptor.toneMapSourceHeadroom == 100.0)
}

@Test("YUV Metal pipeline preserves encoded Display P3 PQ output for direct HDR presentation")
func yuvMetalPipelinePreservesEncodedDisplayP3PQOutputForDirectHDRPresentation() throws {
    let pixelBuffer = try makeMetalColorProcessingPixelBuffer(
        pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
    )
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

    let descriptor = ShadowClientRealtimeSessionYUVMetalPipeline.colorProcessingDescriptor(
        for: pixelBuffer,
        outputColorSpace: CGColorSpace(name: CGColorSpace.displayP3_PQ) ?? CGColorSpaceCreateDeviceRGB(),
        prefersExtendedDynamicRange: true
    )

    #expect(descriptor.transferFunction == .pq)
    #expect(!descriptor.decodesTransfer)
    #expect(!descriptor.appliesToneMapToSDR)
    #expect(!descriptor.appliesGamutTransform)
}

@Test("YUV Metal pipeline tone-maps HDR PQ frames when rendering to SDR")
func yuvMetalPipelineToneMapsHDRPQFramesWhenRenderingToSDR() throws {
    let pixelBuffer = try makeMetalColorProcessingPixelBuffer(
        pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
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

    let descriptor = ShadowClientRealtimeSessionYUVMetalPipeline.colorProcessingDescriptor(
        for: pixelBuffer,
        outputColorSpace: CGColorSpace(name: CGColorSpace.itur_709) ?? CGColorSpaceCreateDeviceRGB(),
        prefersExtendedDynamicRange: false
    )

    #expect(descriptor.transferFunction == .pq)
    #expect(descriptor.decodesTransfer)
    #expect(descriptor.appliesToneMapToSDR)
    #expect(descriptor.toneMapSourceHeadroom == 100.0)
}

@Test("YUV Metal pipeline decodes PQ and applies gamut mapping for linear Display P3 HDR output")
func yuvMetalPipelineDecodesPQForLinearDisplayP3HDROutput() throws {
    let pixelBuffer = try makeMetalColorProcessingPixelBuffer(
        pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
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
    CVBufferSetAttachment(
        pixelBuffer,
        kCVImageBufferYCbCrMatrixKey,
        kCVImageBufferYCbCrMatrix_ITU_R_2020,
        .shouldPropagate
    )

    let descriptor = ShadowClientRealtimeSessionYUVMetalPipeline.colorProcessingDescriptor(
        for: pixelBuffer,
        outputColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) ?? CGColorSpaceCreateDeviceRGB(),
        prefersExtendedDynamicRange: true
    )

    #expect(descriptor.transferFunction == .pq)
    #expect(descriptor.decodesTransfer)
    #expect(!descriptor.appliesToneMapToSDR)
    #expect(descriptor.appliesGamutTransform)
    #expect(descriptor.toneMapSourceHeadroom == 100.0)
}

@Test("YUV Metal pipeline preserves the encoded YCbCr matrix for Display P3 PQ frames rendered to linear HDR output")
func yuvMetalPipelinePreservesEncodedCSCMatrixForDisplayP3PQFramesUsingBT709Matrix() throws {
    let pixelBuffer = try makeMetalColorProcessingPixelBuffer(
        pixelFormat: kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
    )
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

    let effectiveMatrix = ShadowClientRealtimeSessionYUVMetalPipeline.effectiveMatrixStandard(
        for: pixelBuffer,
        outputColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) ?? CGColorSpaceCreateDeviceRGB(),
        prefersExtendedDynamicRange: true
    )

    #expect(effectiveMatrix == .rec709)
}

private func makeMetalColorProcessingPixelBuffer(pixelFormat: OSType) throws -> CVPixelBuffer {
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
