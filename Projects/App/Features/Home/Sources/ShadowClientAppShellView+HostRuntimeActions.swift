import ShadowClientStreaming
import ShadowClientUI
import OSLog
import SwiftUI
import ShadowClientFeatureConnection

extension ShadowClientAppShellView {
    @MainActor
    func restartSettingsTelemetrySubscription(for settings: ShadowClientAppSettings) {
        settingsTelemetryTask?.cancel()
        settingsTelemetryTask = Task {
            let telemetryStream = await baseDependencies.makeTelemetryStream()
            for await snapshot in telemetryStream {
                if Task.isCancelled {
                    return
                }
                let model = await settingsTelemetryRuntime.ingest(
                    snapshot: snapshot,
                    settings: settings
                )

                await MainActor.run {
                    settingsDiagnosticsModel = model
                    if remoteDesktopRuntime.activeSession != nil {
                        sessionDiagnosticsHistory.append(model)
                    }
                }
            }
        }
    }

    @MainActor
    func stopSettingsTelemetrySubscription() {
        settingsTelemetryTask?.cancel()
        settingsTelemetryTask = nil
    }

    @MainActor
    func syncConnectionStateFromRuntime() async {
        connectionState = await baseDependencies.connectionRuntime.currentState()
    }

    @MainActor
    func startHostDiscovery() {
        guard autoFindHosts else {
            hostDiscoveryRuntime.stop()
            return
        }
        hostDiscoveryRuntime.start()
    }

    @MainActor
    func refreshRemoteDesktopCatalog(force: Bool = false) {
        if !force,
           (remoteDesktopRuntime.launchState.isTransitioning || remoteDesktopRuntime.activeSession != nil) {
            return
        }
        if !force,
           isShowingManualHostEntry,
           (manualHostFocusedField != nil || !manualHostDraft.isEmpty || !manualHostPortDraft.isEmpty) {
            return
        }
        let liveDiscoveredCandidates = hostDiscoveryRuntime.hosts
            .map(\.probeCandidate)
        clearHiddenRemoteHostCandidates(matchingAny: liveDiscoveredCandidates)

        let hiddenCandidates = hiddenRemoteHostCandidates
        let discoveredCandidates = liveDiscoveredCandidates
            .filter { !hiddenCandidates.contains(normalizedStoredConnectionCandidate($0)) }
        let cachedCandidates = ShadowClientHostCatalogKit.cachedCandidateHosts(
            from: remoteDesktopRuntime.hosts
        )
        .filter { !hiddenCandidates.contains(normalizedStoredConnectionCandidate($0)) }
        let manualHost = normalizedConnectionHost.isEmpty ? nil : normalizedConnectionHost
        let visibleManualHost = manualHost.flatMap {
            let normalized = normalizedStoredConnectionCandidate($0)
            return hiddenCandidates.contains(normalized) ? nil : $0
        }
        let refreshPlan = ShadowClientHostRefreshPlanKit.makeCatalogRefreshPlan(
            autoFindHosts: autoFindHosts,
            discoveredHosts: hostDiscoveryRuntime.hosts,
            cachedHosts: cachedCandidates,
            preferredHost: visibleManualHost,
            hiddenCandidates: hiddenCandidates
        )
        let discoveredProbeCandidates = discoveredCandidates.joined(separator: ",")
        let candidateSummary = refreshPlan.refreshCandidates.joined(separator: ",")
        Self.catalogLogger.notice(
            "Catalog refresh auto-find=\(autoFindHosts, privacy: .public) discovered=\(discoveredProbeCandidates, privacy: .public) candidates=\(candidateSummary, privacy: .public) preferred=\((refreshPlan.preferredRefreshCandidate ?? "nil"), privacy: .public) authority=\((refreshPlan.preferredAuthorityHost ?? "nil"), privacy: .public) control-port=\((refreshPlan.preferredControlHTTPSPort.map(String.init) ?? "nil"), privacy: .public)"
        )
        let signature = refreshPlan.signature
        if !force, signature == lastRemoteDesktopCatalogSignature {
            return
        }
        lastRemoteDesktopCatalogSignature = signature

        remoteDesktopRuntime.refreshHosts(
            candidates: refreshPlan.refreshCandidates,
            preferredHost: refreshPlan.preferredRefreshCandidate,
            preferredAuthorityHost: refreshPlan.preferredAuthorityHost,
            preferredControlHTTPSPort: refreshPlan.preferredControlHTTPSPort
        )
    }

    @MainActor
    func stopHostDiscovery() {
        hostDiscoveryRuntime.stop()
    }

    @MainActor
    func presentManualHostEntry() {
        manualHostFocusedField = nil
        manualHostDraft = ""
        manualHostPortDraft = ""
        isShowingManualHostEntry = true
    }

    @MainActor
    func cancelManualHostEntry() {
        manualHostFocusedField = nil
        manualHostDraft = ""
        manualHostPortDraft = ""
        isShowingManualHostEntry = false
    }

    @MainActor
    func addManualHostToCatalog() {
        let host = manualSubmissionHostCandidate
        guard !host.isEmpty else {
            return
        }

        manualHostFocusedField = nil
        manualHostDraft = ""
        manualHostPortDraft = ""
        isShowingManualHostEntry = false

        Task { @MainActor [host] in
            clearHiddenRemoteHostCandidates(matching: host)
            remoteDesktopRuntime.saveHostCandidate(host)
            connectionHost = host
            refreshRemoteDesktopCatalog(force: true)
        }
    }

    @MainActor
    func deleteStoredHost(_ host: ShadowClientRemoteHostDescriptor) {
        let normalizedStoredConnectionHost = normalizedConnectionHost.lowercased()
        suppressStoredHostCandidates(for: host)
        if !normalizedStoredConnectionHost.isEmpty,
           storedConnectionCandidates(for: host).contains(normalizedStoredConnectionHost) {
            connectionHost = ""
        }
        hostCustomizationStore.removeHost(host.id)
        lumenDisplayModeDrafts.removeValue(forKey: host.id)
        lumenAlwaysUseVirtualDisplayDrafts.removeValue(forKey: host.id)
        remoteDesktopRuntime.deleteHost(host.id)
    }

    @MainActor
    func presentHostSpotlight(for host: ShadowClientRemoteHostDescriptor) {
        remoteDesktopRuntime.selectHost(host.id)
        spotlightedHostSourceFrame = remoteDesktopHostFrames[host.id] ?? .zero
        hostSpotlightTask?.cancel()
        hostSpotlightTask = Task {
            await runHostSpotlightPresentation(forHostID: host.id)
        }
    }

    @MainActor
    func dismissHostSpotlight() {
        hostSpotlightTask?.cancel()
        let dismissingHostID = spotlightedHostID
        hostSpotlightTask = Task {
            await runHostSpotlightDismissal(forHostID: dismissingHostID)
        }
    }

    @MainActor
    func runHostSpotlightPresentation(forHostID hostID: String) async {
        spotlightAnimationProgress = 0
        spotlightCardSettled = false
        spotlightedHostID = hostID
        await Task.yield()

        guard spotlightedHostID == hostID else {
            return
        }

        if accessibilityReduceMotion {
            spotlightAnimationProgress = 1
            spotlightCardSettled = true
            return
        }

        await animateAsync(hostSpotlightPresentationAnimation) {
            spotlightAnimationProgress = 1
        }

        guard spotlightedHostID == hostID else {
            return
        }
        spotlightCardSettled = true
    }

    @MainActor
    func runHostSpotlightDismissal(forHostID hostID: String?) async {
        guard spotlightedHostID == hostID else {
            return
        }

        spotlightCardSettled = false

        if accessibilityReduceMotion {
            spotlightAnimationProgress = 0
            spotlightedHostID = nil
            return
        }

        await animateAsync(hostSpotlightDismissalAnimation) {
            spotlightAnimationProgress = 0
        }

        guard spotlightedHostID == hostID else {
            return
        }

        spotlightedHostID = nil
    }

    @MainActor
    func animateAsync(
        _ animation: Animation?,
        completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
        _ changes: @escaping @MainActor () -> Void
    ) async {
        await withCheckedContinuation { continuation in
            withAnimation(animation, completionCriteria: completionCriteria, {
                changes()
            }, completion: {
                continuation.resume()
            })
        }
    }

    @MainActor
    func connectToHost(
        connectHost: String? = nil,
        autoLaunchAfterConnect: Bool = false,
        preferredHostID: String? = nil
    ) {
        let explicitConnectHost = connectHost?.trimmingCharacters(in: .whitespacesAndNewlines)
        let host = if let explicitConnectHost, !explicitConnectHost.isEmpty {
            explicitConnectHost
        } else {
            normalizedConnectionHost
        }
        guard !host.isEmpty else {
            return
        }

        let normalizedTargetHost = host.lowercased()
        let alreadyConnectedToTarget: Bool = {
            guard case let .connected(connectedHost) = connectionState else {
                return false
            }
            return connectedHost
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == normalizedTargetHost
        }()

        if alreadyConnectedToTarget {
            if autoLaunchAfterConnect {
                Task {
                    await autoLaunchPreferredRemoteApp(preferredHostID: preferredHostID)
                }
            }
            return
        }

        connectionState = .connecting(host: host)
        refreshRemoteDesktopCatalog(force: true)

        Task {
            let state = await baseDependencies.connectionRuntime.connect(to: host)
            await MainActor.run {
                connectionState = state
                refreshRemoteDesktopCatalog(force: true)
            }

            if autoLaunchAfterConnect, state.isConnected {
                await autoLaunchPreferredRemoteApp(preferredHostID: preferredHostID)
            }
        }
    }

    @MainActor
    func connectToDiscoveredHost(_ discoveredHost: ShadowClientDiscoveredHost) {
        connectToHost(
            connectHost: discoveredHost.probeCandidate,
            autoLaunchAfterConnect: true
        )
    }

    @MainActor
    func startRemoteHostSession(_ host: ShadowClientRemoteHostDescriptor) {
        remoteDesktopRuntime.selectHost(host.id)
        connectToHost(
            connectHost: runtimeConnectCandidate(for: host),
            autoLaunchAfterConnect: true,
            preferredHostID: host.id
        )
    }

    var hostSpotlightPresentationAnimation: Animation {
        .spring(response: 0.52, dampingFraction: 0.84)
    }

    var hostSpotlightDismissalAnimation: Animation {
        .spring(response: 0.38, dampingFraction: 0.92)
    }

    @MainActor
    func autoLaunchPreferredRemoteApp(preferredHostID: String?) async {
        if let preferredHostID {
            remoteDesktopRuntime.selectHost(preferredHostID)
        }

        remoteDesktopRuntime.refreshSelectedHostApps()

        for _ in 0..<ShadowClientUIRuntimeDefaults.appListPollingAttempts {
            if case .loaded = remoteDesktopRuntime.appState {
                if let preferred = ShadowClientLaunchPresentationKit.preferredLaunchApp(from: remoteDesktopRuntime.apps) {
                    launchRemoteApp(preferred)
                    return
                }
                await launchDesktopFallbackIfNeeded()
                return
            }

            if case .failed = remoteDesktopRuntime.appState {
                await launchDesktopFallbackIfNeeded()
                return
            }

            try? await Task.sleep(for: ShadowClientUIRuntimeDefaults.pollingInterval)
        }

        if let preferred = ShadowClientLaunchPresentationKit.preferredLaunchApp(from: remoteDesktopRuntime.apps) {
            launchRemoteApp(preferred)
            return
        }

        await launchDesktopFallbackIfNeeded()
    }

    @MainActor
    func launchRemoteApp(_ app: ShadowClientRemoteAppDescriptor) {
        let settings = resolvedLaunchSettings(
            hostApp: app,
            networkSignal: launchBitrateNetworkSignal,
            localHDRDisplayAvailable: isLocalHDRDisplayAvailable
        )

        remoteDesktopRuntime.launchSelectedApp(
            appID: app.id,
            appTitle: app.title,
            settings: settings
        )
    }

    @MainActor
    func launchDesktopFallbackIfNeeded() async {
        guard let selectedHost = remoteDesktopRuntime.selectedHost else {
            return
        }
        guard selectedHost.authenticationState.canConnect else {
            return
        }
        guard !remoteDesktopRuntime.launchState.isTransitioning,
              remoteDesktopRuntime.activeSession == nil
        else {
            return
        }

        let settings = resolvedLaunchSettings(
            hostApp: nil,
            networkSignal: launchBitrateNetworkSignal,
            localHDRDisplayAvailable: isLocalHDRDisplayAvailable
        )
        let fallbackApp = ShadowClientLaunchPresentationKit.fallbackDesktopApp(
            selectedHost: selectedHost,
            apps: remoteDesktopRuntime.apps
        )
        guard let fallbackApp else {
            return
        }

        remoteDesktopRuntime.launchSelectedApp(
            appID: fallbackApp.id,
            appTitle: fallbackApp.title,
            settings: settings
        )

        for _ in 0..<ShadowClientUIRuntimeDefaults.launchStatePollingAttempts {
            if case .launched = remoteDesktopRuntime.launchState {
                return
            }
            if case .failed = remoteDesktopRuntime.launchState {
                break
            }
            try? await Task.sleep(for: ShadowClientUIRuntimeDefaults.pollingInterval)
        }
    }
}
