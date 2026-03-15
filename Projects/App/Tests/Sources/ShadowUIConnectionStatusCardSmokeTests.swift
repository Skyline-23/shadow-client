import SwiftUI
import Testing
@testable import ShadowUIFoundation

@Test("Connection status card initializes with title text and indicator color")
func shadowUIConnectionStatusCardInit() {
    let view = ShadowUIConnectionStatusCard(
        title: "Client Connection",
        statusText: "Status: Connected to desktop.local",
        indicatorColor: .green
    )

    #expect(String(describing: type(of: view)) == "ShadowUIConnectionStatusCard")
}
