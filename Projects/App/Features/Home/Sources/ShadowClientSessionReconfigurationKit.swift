import ShadowClientFeatureSession

enum ShadowClientSessionReconfigurationKit {
    static func shouldRelaunchActiveSession(
        hasActiveSession: Bool,
        isLaunching: Bool,
        selectedResolution: ShadowClientStreamingResolutionPreset,
        proposedSettings: ShadowClientGameStreamLaunchSettings,
        lastAppliedSettings: ShadowClientGameStreamLaunchSettings?
    ) -> Bool {
        guard hasActiveSession, !isLaunching else {
            return false
        }

        let audioSettingsChanged = hasAudioSettingsChange(
            proposedSettings: proposedSettings,
            lastAppliedSettings: lastAppliedSettings
        )
        guard selectedResolution == .retinaAuto || audioSettingsChanged else {
            return false
        }

        return lastAppliedSettings != proposedSettings
    }

    private static func hasAudioSettingsChange(
        proposedSettings: ShadowClientGameStreamLaunchSettings,
        lastAppliedSettings: ShadowClientGameStreamLaunchSettings?
    ) -> Bool {
        guard let lastAppliedSettings else {
            return true
        }

        return proposedSettings.enableSurroundAudio != lastAppliedSettings.enableSurroundAudio ||
            proposedSettings.preferredSurroundChannelCount != lastAppliedSettings.preferredSurroundChannelCount
    }
}
