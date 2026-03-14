import SwiftUI
import Testing
@testable import ShadowClientFeatureHome

@Test("Remote session overlay presentation maps launch tones to distinct overlay styling")
func remoteSessionOverlayPresentationStyleByTone() {
    let launching = ShadowClientRemoteSessionOverlayPresentationKit.overlayStyle(for: .launching)
    let failed = ShadowClientRemoteSessionOverlayPresentationKit.overlayStyle(for: .failed)
    let launched = ShadowClientRemoteSessionOverlayPresentationKit.overlayStyle(for: .launched)

    #expect(launching.backgroundOpacity == 0.56)
    #expect(failed.strokeOpacity == 0.78)
    #expect(launched.backgroundOpacity == 0.45)
    #expect(ShadowClientRemoteSessionOverlayPresentationKit.dimOpacity(for: .failed) > ShadowClientRemoteSessionOverlayPresentationKit.dimOpacity(for: .launching))
}

@Test("Remote session overlay presentation formats diagnostics and connection copy")
func remoteSessionOverlayPresentationCopy() {
    #expect(
        ShadowClientRemoteSessionOverlayPresentationKit.diagnosticsSummary(
            codecLabel: "AV1",
            resolutionValue: "3840x2160",
            audioChannelValue: "5.1"
        ) == "Codec AV1 · Resolution 3840x2160 · Audio 5.1"
    )
    #expect(ShadowClientRemoteSessionOverlayPresentationKit.hudTitle() == "Realtime HUD")
    #expect(ShadowClientRemoteSessionOverlayPresentationKit.bootstrapBadgeText() == "BOOTSTRAP")
    #expect(ShadowClientRemoteSessionOverlayPresentationKit.connectionIssueBadgeText() == "OFFLINE")
}
