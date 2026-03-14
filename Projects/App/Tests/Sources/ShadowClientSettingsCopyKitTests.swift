import Testing
@testable import ShadowClientFeatureHome

@Test("Settings copy kit exposes bitrate HDR and audio footnotes")
func settingsCopyKitStaticFootnotes() {
    #expect(ShadowClientSettingsCopyKit.autoBitrateFootnote() == "Estimated from resolution, frame rate, codec, HDR, and YUV444.")
    #expect(ShadowClientSettingsCopyKit.hdrUnavailableFootnote() == "HDR requires a real HDR/EDR display on this device.")
    #expect(ShadowClientSettingsCopyKit.mobileAudioRouteFootnote().localizedCaseInsensitiveContains("selection is the ceiling"))
    #expect(ShadowClientSettingsCopyKit.clientPlaybackUnavailableFootnote().localizedCaseInsensitiveContains("Audio is currently routed to the host device."))
}
