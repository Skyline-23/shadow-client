import SwiftUI
import Testing
@testable import ShadowUIFoundation

@Test("Remote session connection issue HUD foundation component is constructible")
func shadowUIRemoteSessionConnectionIssueHUDInit() {
    let hud = ShadowUIRemoteSessionConnectionIssueHUD(
        title: "Host Desktop Paused",
        message: "Windows is showing a secure desktop.",
        badgeText: "OFFLINE",
        footnote: "Remote input is paused until stream reconnects."
    )

    #expect(String(describing: type(of: hud)) == "ShadowUIRemoteSessionConnectionIssueHUD")
}
