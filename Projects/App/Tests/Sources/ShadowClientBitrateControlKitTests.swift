import Testing
import ShadowClientFeatureSession
@testable import ShadowClientFeatureHome

@Test("Bitrate control kit resolves effective bitrate through app settings")
func bitrateControlKitResolvesEffectiveBitrate() {
    let settings = ShadowClientAppSettings(
        resolution: .p2160,
        frameRate: .fps60,
        videoCodec: .av1
    )
    #expect(
        ShadowClientBitrateControlKit.effectiveBitrateKbps(settings: settings, networkSignal: nil) ==
            settings.resolvedBitrateKbps
    )
}
