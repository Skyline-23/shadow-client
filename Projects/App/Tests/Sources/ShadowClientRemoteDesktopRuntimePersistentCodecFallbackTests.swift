import Testing
@testable import ShadowClientFeatureHome

@Test("Persistent codec fallback is consumed after one auto launch")
func persistentCodecFallbackIsConsumedAfterOneAutoLaunch() {
    let result = ShadowClientRemoteDesktopRuntime.resolvedSettingsApplyingPersistentFallback(
        .init(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateKbps: 15_000,
            preferredCodec: .auto,
            enableHDR: false,
            enableSurroundAudio: false,
            lowLatencyMode: false
        ),
        persistentFallback: .h264
    )

    #expect(result.settings.preferredCodec == .h264)
    #expect(result.remainingFallback == nil)
}

@Test("Manual codec selections clear any persistent codec fallback")
func manualCodecSelectionsClearPersistentCodecFallback() {
    let result = ShadowClientRemoteDesktopRuntime.resolvedSettingsApplyingPersistentFallback(
        .init(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateKbps: 15_000,
            preferredCodec: .h265,
            enableHDR: false,
            enableSurroundAudio: false,
            lowLatencyMode: false
        ),
        persistentFallback: .h264
    )

    #expect(result.settings.preferredCodec == .h265)
    #expect(result.remainingFallback == nil)
}
