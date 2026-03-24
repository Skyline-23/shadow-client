import Testing
@testable import ShadowClientFeatureHome

@Test("Remote desktop runtime falls back from AV1 to HEVC when the host does not advertise AV1 support")
func remoteDesktopRuntimeFallsBackFromAV1ToHEVCWhenHostLacksAV1() {
    let normalized = ShadowClientRemoteDesktopRuntime.normalizeCodecLaunchSettings(
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
        serverCodecModeSupport: ShadowClientServerCodecModeSupport.hevc
    )

    #expect(normalized.preferredCodec == .h265)
}

@Test("Remote desktop runtime falls back to H264 when the host only advertises H264")
func remoteDesktopRuntimeFallsBackToH264WhenHostOnlyAdvertisesH264() {
    let normalized = ShadowClientRemoteDesktopRuntime.normalizeCodecLaunchSettings(
        .init(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateKbps: 15_000,
            preferredCodec: .av1,
            enableHDR: false,
            enableSurroundAudio: false,
            lowLatencyMode: false
        ),
        serverCodecModeSupport: ShadowClientServerCodecModeSupport.h264
    )

    #expect(normalized.preferredCodec == .h264)
}

@Test("Remote desktop runtime keeps auto when host codec support is unknown instead of forcing H264")
func remoteDesktopRuntimeKeepsAutoWhenHostCodecSupportIsUnknown() {
    let normalized = ShadowClientRemoteDesktopRuntime.normalizeCodecLaunchSettings(
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
        serverCodecModeSupport: 0
    )

    #expect(normalized.preferredCodec == .auto || normalized.preferredCodec == .h265)
}

@Test("Remote desktop runtime preserves experimental ProRes selection during codec normalization")
func remoteDesktopRuntimePreservesExperimentalProResSelection() {
    let normalized = ShadowClientRemoteDesktopRuntime.normalizeCodecLaunchSettings(
        .init(
            width: 1920,
            height: 1080,
            fps: 60,
            bitrateKbps: 15_000,
            preferredCodec: .prores,
            enableHDR: false,
            enableSurroundAudio: false,
            lowLatencyMode: false
        ),
        serverCodecModeSupport: ShadowClientServerCodecModeSupport.hevc
    )

    #expect(normalized.preferredCodec == .prores)
}
