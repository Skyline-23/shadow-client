import Testing
@testable import ShadowClientFeatureHome

@Test("Remote desktop runtime normalizes surround launch settings to stereo when output is stereo only")
func remoteDesktopRuntimeNormalizesSurroundLaunchSettingsToStereo() {
    let normalized = ShadowClientRemoteDesktopRuntime.normalizeAudioLaunchSettings(
        .init(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateKbps: 15_000,
            preferredCodec: .auto,
            enableHDR: false,
            enableSurroundAudio: true,
            preferredSurroundChannelCount: 8,
            lowLatencyMode: false
        ),
        maximumOutputChannels: 2
    )

    #expect(normalized.enableSurroundAudio == false)
    #expect(normalized.preferredSurroundChannelCount == 2)
}

@Test("Remote desktop runtime keeps surround launch settings when output can support the requested ceiling")
func remoteDesktopRuntimeKeepsSurroundLaunchSettingsWhenOutputSupportsIt() {
    let normalized = ShadowClientRemoteDesktopRuntime.normalizeAudioLaunchSettings(
        .init(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateKbps: 15_000,
            preferredCodec: .auto,
            enableHDR: false,
            enableSurroundAudio: true,
            preferredSurroundChannelCount: 6,
            lowLatencyMode: false
        ),
        maximumOutputChannels: 8
    )

    #expect(normalized.enableSurroundAudio == true)
    #expect(normalized.preferredSurroundChannelCount == 6)
}
