import ShadowClientStreaming
import ShadowClientUI
import SwiftUI
import ShadowClientFeatureSession

extension ShadowClientAppShellView {
    @MainActor
    func resolvedLaunchSettings(
        hostApp: ShadowClientRemoteAppDescriptor?,
        networkSignal: StreamingNetworkSignal?,
        localHDRDisplayAvailable: Bool
    ) -> ShadowClientGameStreamLaunchSettings {
        ShadowClientLaunchSettingsKit.resolvedLaunchSettings(
            currentSettings: currentSettings,
            selectedResolution: selectedResolution,
            hostApp: hostApp,
            networkSignal: networkSignal,
            localHDRDisplayAvailable: localHDRDisplayAvailable,
            viewportMetrics: launchViewportMetrics,
            displayMetrics: displayMetrics
        )
    }

    @MainActor
    func activeSessionLaunchSettings() -> ShadowClientGameStreamLaunchSettings? {
        guard let activeSession = remoteDesktopRuntime.activeSession else {
            return nil
        }

        let activeApp = remoteDesktopRuntime.apps.first { $0.id == activeSession.appID }
        return resolvedLaunchSettings(
            hostApp: activeApp,
            networkSignal: launchBitrateNetworkSignal,
            localHDRDisplayAvailable: isLocalHDRDisplayAvailable
        )
    }

    @MainActor
    func activeSessionNegotiatedLaunchSettings() async -> ShadowClientGameStreamLaunchSettings? {
        guard let settings = activeSessionLaunchSettings() else {
            return nil
        }
        let maximumOutputChannels = await ShadowClientAudioOutputCapabilityKit.maximumOutputChannels()
        return ShadowClientRemoteDesktopRuntime.normalizeAudioLaunchSettings(
            settings,
            maximumOutputChannels: maximumOutputChannels
        )
    }

    @MainActor
    func scheduleActiveSessionLaunchReconfigurationIfNeeded() {
        guard let proposedSettings = activeSessionLaunchSettings() else {
            return
        }
        if lastActiveSessionReconfigurationSettings == nil {
            lastActiveSessionReconfigurationSettings = proposedSettings
            return
        }
        guard ShadowClientSessionReconfigurationKit.shouldRelaunchActiveSession(
            hasActiveSession: remoteDesktopRuntime.activeSession != nil,
            isLaunching: remoteDesktopRuntime.launchState.isTransitioning,
            selectedResolution: selectedResolution,
            proposedSettings: proposedSettings,
            lastAppliedSettings: lastActiveSessionReconfigurationSettings
        ),
        let activeSession = remoteDesktopRuntime.activeSession
        else {
            return
        }

        activeSessionReconfigurationTask?.cancel()
        activeSessionReconfigurationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled,
                  let latestSettings = activeSessionLaunchSettings(),
                  ShadowClientSessionReconfigurationKit.shouldRelaunchActiveSession(
                    hasActiveSession: remoteDesktopRuntime.activeSession != nil,
                    isLaunching: remoteDesktopRuntime.launchState.isTransitioning,
                    selectedResolution: selectedResolution,
                    proposedSettings: latestSettings,
                    lastAppliedSettings: lastActiveSessionReconfigurationSettings
                  ),
                  let latestActiveSession = remoteDesktopRuntime.activeSession,
                  latestActiveSession.appID == activeSession.appID
            else {
                return
            }

            lastActiveSessionReconfigurationSettings = latestSettings
            remoteDesktopRuntime.launchSelectedApp(
                appID: latestActiveSession.appID,
                appTitle: latestActiveSession.appTitle,
                settings: latestSettings
            )
        }
    }

    @MainActor
    func scheduleActiveSessionAudioReconfigurationIfNeeded() async {
        guard let proposedSettings = await activeSessionNegotiatedLaunchSettings() else {
            return
        }
        if lastActiveSessionReconfigurationSettings == nil {
            lastActiveSessionReconfigurationSettings = proposedSettings
            return
        }
        guard ShadowClientSessionReconfigurationKit.shouldRelaunchActiveSession(
            hasActiveSession: remoteDesktopRuntime.activeSession != nil,
            isLaunching: remoteDesktopRuntime.launchState.isTransitioning,
            selectedResolution: selectedResolution,
            proposedSettings: proposedSettings,
            lastAppliedSettings: lastActiveSessionReconfigurationSettings
        ),
        let activeSession = remoteDesktopRuntime.activeSession
        else {
            return
        }

        activeSessionReconfigurationTask?.cancel()
        activeSessionReconfigurationTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled,
                  let latestSettings = await activeSessionNegotiatedLaunchSettings(),
                  ShadowClientSessionReconfigurationKit.shouldRelaunchActiveSession(
                    hasActiveSession: remoteDesktopRuntime.activeSession != nil,
                    isLaunching: remoteDesktopRuntime.launchState.isTransitioning,
                    selectedResolution: selectedResolution,
                    proposedSettings: latestSettings,
                    lastAppliedSettings: lastActiveSessionReconfigurationSettings
                  ),
                  let latestActiveSession = remoteDesktopRuntime.activeSession,
                  latestActiveSession.appID == activeSession.appID
            else {
                return
            }

            lastActiveSessionReconfigurationSettings = latestSettings
            remoteDesktopRuntime.launchSelectedApp(
                appID: latestActiveSession.appID,
                appTitle: latestActiveSession.appTitle,
                settings: latestSettings
            )
        }
    }

    @MainActor
    func disconnectFromHost() {
        let disconnectingHost = connectionState.host ?? normalizedConnectionHost
        connectionState = .disconnecting(host: disconnectingHost)
        Task {
            let state = await baseDependencies.connectionRuntime.disconnect()
            await MainActor.run {
                connectionState = state
                settingsDiagnosticsModel = nil
                sessionDiagnosticsHistory = .init(
                    maxSamples: ShadowClientUIRuntimeDefaults.diagnosticsHUDSampleHistoryLimit
                )
                refreshRemoteDesktopCatalog(force: true)
            }
        }
    }
}
