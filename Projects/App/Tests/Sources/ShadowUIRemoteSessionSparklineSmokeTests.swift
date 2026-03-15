import SwiftUI
import Testing
@testable import ShadowUIFoundation

@Test("Remote session sparkline foundation components are constructible")
func shadowUIRemoteSessionSparklineComponentsInit() {
    let sparkline = ShadowUIDiagnosticsSparkline(samples: [1, 2, 3], color: .mint)
    let row = ShadowUIRemoteSessionSparklineRow(title: "Ping", latestValue: "12 ms", samples: [1, 2, 3], color: .mint)

    #expect(String(describing: type(of: sparkline)) == "ShadowUIDiagnosticsSparkline")
    #expect(String(describing: type(of: row)) == "ShadowUIRemoteSessionSparklineRow")
}
