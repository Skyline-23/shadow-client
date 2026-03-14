import Testing
@testable import ShadowClientFeatureHome

@Test("Session diagnostics presentation formats round-trip FPS bitrate and latest samples")
func sessionDiagnosticsPresentationFormatting() {
    #expect(ShadowClientSessionDiagnosticsPresentationKit.roundTripValue(nil) == "--")
    #expect(ShadowClientSessionDiagnosticsPresentationKit.roundTripValue(24) == "24 ms")
    #expect(ShadowClientSessionDiagnosticsPresentationKit.fpsValue(estimatedVideoFPS: 59.7, defaultFPS: 60) == "60 fps")
    #expect(ShadowClientSessionDiagnosticsPresentationKit.fpsValue(estimatedVideoFPS: nil, defaultFPS: 120) == "120 fps")
    #expect(
        ShadowClientSessionDiagnosticsPresentationKit.bitrateValue(
            estimatedVideoBitrateKbps: 18000,
            effectiveBitrateKbps: 20000
        ) == "18000 / 20000 kbps"
    )
    #expect(ShadowClientSessionDiagnosticsPresentationKit.latestValue(samples: [], unit: "%") == "--")
    #expect(ShadowClientSessionDiagnosticsPresentationKit.latestValue(samples: [1.24], unit: "%") == "1.2%")
    #expect(ShadowClientSessionDiagnosticsPresentationKit.latestValue(samples: [11.6], unit: "ms") == "12 ms")
}
