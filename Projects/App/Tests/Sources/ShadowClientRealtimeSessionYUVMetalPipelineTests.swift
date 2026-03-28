import CoreVideo
import Metal
import Testing
@testable import ShadowClientFeatureHome

@Test("YUV Metal pipeline supports compressed bi-planar HDR decode formats")
func yuvMetalPipelineSupportsCompressedBiPlanarHDRDecodeFormats() {
    #expect(
        ShadowClientRealtimeSessionYUVMetalPipeline.supportsPixelFormat(
            kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarVideoRange
        )
    )
    #expect(
        ShadowClientRealtimeSessionYUVMetalPipeline.supportsPixelFormat(
            kCVPixelFormatType_Lossless_420YpCbCr10PackedBiPlanarFullRange
        )
    )
    #expect(
        ShadowClientRealtimeSessionYUVMetalPipeline.supportsPixelFormat(
            kCVPixelFormatType_Lossy_420YpCbCr10PackedBiPlanarVideoRange
        )
    )
}

@Test("YUV Metal pipeline maps overlay region into drawable scissor rect with aspect fit letterboxing")
func yuvMetalPipelineMapsOverlayRegionIntoDrawableScissorRect() {
    let scissorRect = ShadowClientRealtimeSessionYUVMetalPipeline.drawableScissorRect(
        for: .init(
            x: 480,
            y: 270,
            width: 960,
            height: 540,
            metadata: nil
        ),
        videoSize: CGSize(width: 1920, height: 1080),
        drawableSize: CGSize(width: 1600, height: 1200)
    )

    #expect(scissorRect?.x == 400)
    #expect(scissorRect?.y == 375)
    #expect(scissorRect?.width == 800)
    #expect(scissorRect?.height == 450)
}
