import CoreVideo
import Testing
@testable import ShadowClientFeatureHome

@Test("VideoToolbox decoder requests uncompressed full-range bi-planar output for H264")
func videoToolboxDecoderRequestsUncompressedBiPlanarOutputForH264() {
    #expect(
        ShadowClientVideoToolboxDecoder.preferredPixelBufferFormat(
            for: .h264,
            hdrEnabled: false
        ) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange
    )
}

@Test("VideoToolbox decoder requests uncompressed 10-bit bi-planar output for HDR HEVC")
func videoToolboxDecoderRequestsUncompressedTenBitBiPlanarOutputForHDRHEVC() {
    #expect(
        ShadowClientVideoToolboxDecoder.preferredPixelBufferFormat(
            for: .h265,
            hdrEnabled: true
        ) == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
    )
}

@Test("VideoToolbox decoder requests uncompressed 10-bit bi-planar output for HDR AV1")
func videoToolboxDecoderRequestsUncompressedTenBitBiPlanarOutputForHDRAV1() {
    #expect(
        ShadowClientVideoToolboxDecoder.preferredPixelBufferFormat(
            for: .av1,
            hdrEnabled: true
        ) == kCVPixelFormatType_420YpCbCr10BiPlanarFullRange
    )
}
