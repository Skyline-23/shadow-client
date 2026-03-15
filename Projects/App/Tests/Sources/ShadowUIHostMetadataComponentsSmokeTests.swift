import SwiftUI
import Testing
@testable import ShadowUIFoundation

@Test("Host metadata foundation components are constructible")
func shadowUIHostMetadataComponentsInit() {
    let field = ShadowUIHostInsetField { Text("Field") }
    let card = ShadowUIHostInsetCard { Text("Card") }

    #expect(String(describing: type(of: field)) == "ShadowUIHostInsetField<Text>")
    #expect(String(describing: type(of: card)) == "ShadowUIHostInsetCard<Text>")
}
