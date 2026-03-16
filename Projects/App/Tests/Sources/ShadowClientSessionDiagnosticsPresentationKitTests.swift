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
        ) == "18000\n/ 20000 kbps"
    )
    #expect(ShadowClientSessionDiagnosticsPresentationKit.latestValue(samples: [], unit: "%") == "--")
    #expect(ShadowClientSessionDiagnosticsPresentationKit.latestValue(samples: [1.24], unit: "%") == "1.2%")
    #expect(ShadowClientSessionDiagnosticsPresentationKit.latestValue(samples: [11.6], unit: "ms") == "12 ms")
}

@Test("Session diagnostics presentation estimates input latency from RTT buffer and FPS")
func sessionDiagnosticsPresentationEstimatesInputLatency() {
    let timingBudget = ShadowClientAudioOutputTimingBudget(
        outputLatencySeconds: 0.163,
        ioBufferDurationSeconds: 0.005
    )

    #expect(
        ShadowClientSessionDiagnosticsPresentationKit.estimatedInputLatencyMs(
            controlRoundTripMs: 20,
            targetBufferMs: 40,
            audioPendingDurationMs: 0,
            estimatedVideoFPS: 60,
            defaultFPS: 60,
            timingBudget: timingBudget
        ) == 77
    )
    #expect(
        ShadowClientSessionDiagnosticsPresentationKit.estimatedInputLatencyMs(
            controlRoundTripMs: 20,
            targetBufferMs: 40,
            audioPendingDurationMs: 0,
            estimatedVideoFPS: nil,
            defaultFPS: 60,
            timingBudget: timingBudget
        ) == 77
    )
    #expect(
        ShadowClientSessionDiagnosticsPresentationKit.estimatedInputLatencyValue(
            controlRoundTripMs: nil,
            targetBufferMs: 40,
            audioPendingDurationMs: 0,
            estimatedVideoFPS: 60,
            defaultFPS: 60,
            timingBudget: timingBudget
        ) == "--"
    )
}
