import CoreGraphics
import CoreVideo
import Metal
import Testing
@testable import ShadowClientFeatureHome

@Test("Color pipeline enables EDR and float output for HDR PQ frames")
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

    let configuration = ShadowClientRealtimeSessionColorPipeline.configuration(for: pixelBuffer)
    #expect(configuration.prefersExtendedDynamicRange)
    #expect(configuration.pixelFormat == .rgba16Float)
    #expect(configuration.renderColorSpace.name == CGColorSpace.itur_2100_PQ)
    let displayColorName = configuration.displayColorSpace.name
    #expect(
        displayColorName == CGColorSpace.extendedLinearDisplayP3 ||
            displayColorName == CGColorSpace.extendedLinearITUR_2020
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

    let configuration = ShadowClientRealtimeSessionColorPipeline.configuration(for: pixelBuffer)
    #expect(!configuration.prefersExtendedDynamicRange)
    #expect(configuration.pixelFormat == .bgra8Unorm)
    #expect(configuration.displayColorSpace.name == CGColorSpace.itur_709)
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

    let configuration = ShadowClientRealtimeSessionColorPipeline.configuration(for: pixelBuffer)
    #expect(configuration.renderColorSpace.name == CGColorSpace.itur_2100_PQ)
    #expect(configuration.prefersExtendedDynamicRange)
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
