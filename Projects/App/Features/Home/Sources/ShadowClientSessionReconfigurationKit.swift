import ShadowClientFeatureSession

enum ShadowClientSessionReconfigurationKit {
    static func shouldRelaunchActiveSession(
        hasActiveSession: Bool,
        isLaunching: Bool,
        selectedResolution: ShadowClientStreamingResolutionPreset,
        proposedSettings: ShadowClientGameStreamLaunchSettings,
        lastAppliedSettings: ShadowClientGameStreamLaunchSettings?
    ) -> Bool {
        guard hasActiveSession, !isLaunching, selectedResolution == .retinaAuto else {
            return false
        }

        return lastAppliedSettings != proposedSettings
    }
}
