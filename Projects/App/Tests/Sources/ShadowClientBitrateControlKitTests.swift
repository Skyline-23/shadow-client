import ShadowClientStreaming
import Testing
import ShadowClientFeatureSession
@testable import ShadowClientFeatureHome

@Test("Bitrate control kit clamps slider values to the configured step and range")
func bitrateControlKitClampsSliderValues() {
    #expect(ShadowClientBitrateControlKit.clampedBitrateKbps(sliderValue: 499.0, maxBitrateKbps: 50000) == ShadowClientStreamingLaunchBounds.minimumBitrateKbps)
    #expect(ShadowClientBitrateControlKit.clampedBitrateKbps(sliderValue: 12345, maxBitrateKbps: 50000) % ShadowClientAppSettingsDefaults.bitrateStepKbps == 0)
    #expect(ShadowClientBitrateControlKit.clampedBitrateKbps(sliderValue: 999999, maxBitrateKbps: 60000) == 60000)
}

@Test("Bitrate control kit resolves effective bitrate through app settings")
func bitrateControlKitResolvesEffectiveBitrate() {
    let settings = ShadowClientAppSettings(bitrateKbps: 18000, autoBitrate: false)
    #expect(ShadowClientBitrateControlKit.effectiveBitrateKbps(settings: settings, networkSignal: nil) == 18000)
}
