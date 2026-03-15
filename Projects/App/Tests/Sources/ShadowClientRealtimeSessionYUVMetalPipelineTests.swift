import CoreVideo
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
