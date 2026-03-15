import Testing
import ShadowClientFeatureSession
@testable import ShadowClientFeatureHome

@Test("Session reconfiguration relaunches retina-auto sessions when launch settings change")
func sessionReconfigurationRelaunchesRetinaAutoSessionWhenSettingsChange() {
    let previous = ShadowClientGameStreamLaunchSettings(
        width: 1920,
        height: 1080,
        fps: 60,
        bitrateKbps: 15_000,
        preferredCodec: .auto,
        enableHDR: false,
        enableSurroundAudio: false,
        lowLatencyMode: false
    )
    let proposed = ShadowClientGameStreamLaunchSettings(
        width: 2360,
        height: 1640,
        fps: 60,
        bitrateKbps: 15_000,
        preferredCodec: .auto,
        enableHDR: false,
        enableSurroundAudio: false,
        lowLatencyMode: false
    )

    #expect(
        ShadowClientSessionReconfigurationKit.shouldRelaunchActiveSession(
            hasActiveSession: true,
            isLaunching: false,
            selectedResolution: .retinaAuto,
            proposedSettings: proposed,
            lastAppliedSettings: previous
        )
    )
}

@Test("Session reconfiguration ignores fixed-resolution and already-launching sessions")
func sessionReconfigurationSkipsFixedResolutionAndLaunchingSessions() {
    let settings = ShadowClientGameStreamLaunchSettings(
        width: 1920,
        height: 1080,
        fps: 60,
        bitrateKbps: 15_000,
        preferredCodec: .auto,
        enableHDR: false,
        enableSurroundAudio: false,
        lowLatencyMode: false
    )

    #expect(
        !ShadowClientSessionReconfigurationKit.shouldRelaunchActiveSession(
            hasActiveSession: true,
            isLaunching: true,
            selectedResolution: .retinaAuto,
            proposedSettings: settings,
            lastAppliedSettings: nil
        )
    )
    #expect(
        !ShadowClientSessionReconfigurationKit.shouldRelaunchActiveSession(
            hasActiveSession: true,
            isLaunching: false,
            selectedResolution: .p1080,
            proposedSettings: settings,
            lastAppliedSettings: nil
        )
    )
}
