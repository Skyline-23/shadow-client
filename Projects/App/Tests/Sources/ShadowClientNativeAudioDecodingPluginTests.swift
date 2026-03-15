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
