import SwiftUI
import Testing
@testable import ShadowClientFeatureHome

@Test("Remote host presentation kit sanitizes identifiers and formats accessibility copy")
func remoteHostPresentationAccessibilityAndIdentifier() {
    let host = ShadowClientRemoteHostDescriptor(
        host: "Desktop.local",
        displayName: "Desktop",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "ONLINE",
        httpsPort: 47984,
        appVersion: nil,
        gfeVersion: nil,
        uniqueID: nil,
        lastError: nil
    )
    let input = ShadowClientRemoteHostPresentationInput(
        host: host,
        issue: nil,
        alias: " Living Room ",
        notes: "Preferred desktop"
    )

    #expect(ShadowClientRemoteHostPresentationKit.sanitizedIdentifier("Desktop.local:47984") == "desktop-local-47984")
    #expect(ShadowClientRemoteHostPresentationKit.spotlightAccessibilityHint(input) == "Opens Living Room in a focused rotating card")
    #expect(
        ShadowClientRemoteHostPresentationKit.accessibilityLabel(input, isSelected: true)
            == "Living Room, Ready. Host: Desktop.local. Currently selected. Preferred desktop"
    )
}
