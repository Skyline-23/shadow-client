import SwiftUI
import Testing
@testable import ShadowUIFoundation

@Test("Host app row foundation component is constructible")
func shadowUIHostAppRowInit() {
    let row = ShadowUIHostAppRow(
        title: "Desktop",
        subtitle: "App ID: 1 · HDR: N",
        launchTitle: "Launch",
        launchAccessibilityLabel: "Launch Desktop",
        launchAccessibilityHint: "Launches the selected remote app and enters remote session view",
        launchAccessibilityIdentifier: "shadow.home.applist.launch.1",
        launchDisabled: false,
        onLaunch: {}
    )

    #expect(String(describing: type(of: row)) == "ShadowUIHostAppRow")
}
