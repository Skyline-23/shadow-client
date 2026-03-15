import CoreGraphics
import CoreVideo
import Testing
@testable import ShadowClientFeatureHome

@Test("YUV Metal pipeline uses PQ transfer and Rec.2020 to Display P3 gamut transform for HDR PQ frames")
func yuvMetalPipelineUsesPQTransferAndGamutTransformForHDRPQFrames() throws {
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
        outputColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearDisplayP3) ?? CGColorSpaceCreateDeviceRGB(),
        prefersExtendedDynamicRange: true
    )

    #expect(descriptor.transferFunction == .pq)
    #expect(!descriptor.appliesToneMapToSDR)
    #expect(descriptor.appliesGamutTransform)
    #expect(descriptor.toneMapSourceHeadroom == 100.0)
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
    #expect(descriptor.appliesToneMapToSDR)
    #expect(descriptor.toneMapSourceHeadroom == 100.0)
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
