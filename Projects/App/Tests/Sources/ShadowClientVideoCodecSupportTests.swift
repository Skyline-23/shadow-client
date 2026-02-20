import CoreMedia
import Testing
@testable import ShadowClientFeatureHome

@Test("Codec support keeps auto when AV1 hardware decode is available")
func videoCodecSupportKeepsAutoWhenAV1Supported() {
    let support = ShadowClientVideoCodecSupport { codecType in
        codecType == kCMVideoCodecType_AV1 || codecType == kCMVideoCodecType_HEVC
    }

    #expect(support.resolvePreferredCodec(.auto) == .auto)
}

@Test("Codec support falls back to H265 when AV1 is unavailable but HEVC is available")
func videoCodecSupportFallsBackToH265WhenAV1Unavailable() {
    let support = ShadowClientVideoCodecSupport { codecType in
        codecType == kCMVideoCodecType_HEVC
    }

    #expect(support.resolvePreferredCodec(.auto) == .h265)
    #expect(support.resolvePreferredCodec(.av1) == .h265)
}

@Test("Codec support falls back to H264 when AV1 and HEVC are unavailable")
func videoCodecSupportFallsBackToH264WhenHEVCUnavailable() {
    let support = ShadowClientVideoCodecSupport { _ in
        false
    }

    #expect(support.resolvePreferredCodec(.auto) == .h264)
    #expect(support.resolvePreferredCodec(.av1) == .h264)
}

@Test("Codec support keeps explicit H264 and H265 selections")
func videoCodecSupportKeepsExplicitSelections() {
    let support = ShadowClientVideoCodecSupport { _ in
        false
    }

    #expect(support.resolvePreferredCodec(.h264) == .h264)
    #expect(support.resolvePreferredCodec(.h265) == .h265)
}

@Test("Codec support avoids AV1 when HDR is enabled")
func videoCodecSupportAvoidsAV1WhenHDREnabled() {
    let support = ShadowClientVideoCodecSupport { codecType in
        codecType == kCMVideoCodecType_AV1 || codecType == kCMVideoCodecType_HEVC
    }

    #expect(support.resolvePreferredCodec(.auto, enableHDR: true) == .h265)
    #expect(support.resolvePreferredCodec(.av1, enableHDR: true) == .h265)
}

@Test("Codec support avoids AV1 when YUV444 is enabled")
func videoCodecSupportAvoidsAV1WhenYUV444Enabled() {
    let support = ShadowClientVideoCodecSupport { codecType in
        codecType == kCMVideoCodecType_AV1 || codecType == kCMVideoCodecType_HEVC
    }

    #expect(support.resolvePreferredCodec(.auto, enableYUV444: true) == .h265)
    #expect(support.resolvePreferredCodec(.av1, enableYUV444: true) == .h265)
}
