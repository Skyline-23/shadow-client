import Testing
@testable import ShadowClientNativeAudioDecoding

@Test("Native Opus stereo playback bypasses the playback safety guard")
func nativeOpusStereoPlaybackBypassesSafetyGuard() {
    #expect(!ShadowClientNativeAudioDecodingPlugin.requiresPlaybackSafetyGuard(channels: 2))
}

@Test("Native Opus surround playback keeps the playback safety guard")
func nativeOpusSurroundPlaybackKeepsSafetyGuard() {
    #expect(ShadowClientNativeAudioDecodingPlugin.requiresPlaybackSafetyGuard(channels: 6))
    #expect(ShadowClientNativeAudioDecodingPlugin.requiresPlaybackSafetyGuard(channels: 8))
}

@Test("Native Opus stereo fallback prefers int16 when float energy collapses")
func nativeOpusStereoFallbackPrefersInt16WhenFloatEnergyCollapses() {
    #expect(
        ShadowClientNativeOpusStereoDecodePathHeuristics.shouldPreferInt16PromotedToFloat(
            floatPeak: 0.000_006,
            int16PeakNormalized: 0.18
        )
    )
    #expect(
        !ShadowClientNativeOpusStereoDecodePathHeuristics.shouldPreferFloat32(
            floatPeak: 0.000_006,
            int16PeakNormalized: 0.18
        )
    )
}

@Test("Native Opus stereo fallback keeps float when float energy is healthy")
func nativeOpusStereoFallbackKeepsFloatWhenEnergyIsHealthy() {
    #expect(
        ShadowClientNativeOpusStereoDecodePathHeuristics.shouldPreferFloat32(
            floatPeak: 0.12,
            int16PeakNormalized: 0.11
        )
    )
    #expect(
        !ShadowClientNativeOpusStereoDecodePathHeuristics.shouldPreferInt16PromotedToFloat(
            floatPeak: 0.12,
            int16PeakNormalized: 0.11
        )
    )
}
