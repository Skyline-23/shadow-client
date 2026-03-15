import SwiftUI
import Testing
@testable import ShadowUIFoundation

@Test("Remote session HUD foundation components are constructible")
func shadowUIRemoteSessionHUDComponentsInit() {
    let card = ShadowUIRemoteSessionHUDCard(width: 280) { Text("HUD") }
    let chip = ShadowUIRemoteSessionStatChip(label: "FPS", value: "60 fps")

    #expect(String(describing: type(of: card)) == "ShadowUIRemoteSessionHUDCard<Text>")
    #expect(String(describing: type(of: chip)) == "ShadowUIRemoteSessionStatChip")
}
