import SwiftUI
import Testing
@testable import ShadowUIFoundation

@Test("Host panel foundation components are constructible")
func shadowUIHostPanelComponentsInit() {
    let callout = ShadowUIHostCalloutRow(title: "Ready", message: "Paired", accent: .mint)

    #expect(String(describing: type(of: callout)) == "ShadowUIHostCalloutRow")
    #expect(ShadowUIHostPanelPalette.panelInsetSurface.opacity(1) != Color.clear)
}
