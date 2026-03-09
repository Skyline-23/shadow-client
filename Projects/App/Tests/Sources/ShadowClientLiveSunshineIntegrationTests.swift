import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Live Sunshine metadata client fetches server info and app list")
func liveSunshineFetchesServerInfoAndAppList() async throws {
    guard let config = LiveSunshineIntegrationConfiguration.enabledFromEnvironment() else {
        return
    }

    let metadataClient = NativeGameStreamMetadataClient()
    let serverInfo = try await metadataClient.fetchServerInfo(host: config.host)
    let appListPort = serverInfo.httpsPort > 0 ? serverInfo.httpsPort : config.fallbackHTTPSPort
    let apps = try await metadataClient.fetchAppList(host: config.host, httpsPort: appListPort)

    #expect(!serverInfo.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    #expect(!serverInfo.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    #expect(serverInfo.httpsPort > 0)
    #expect(apps.contains { app in
        app.id > 0 && !app.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    })

    if config.requirePairedHost, serverInfo.pairStatus != .paired {
        throw LiveSunshineIntegrationError.unpairedHost(
            host: config.host,
            pairStatus: "\(serverInfo.pairStatus)"
        )
    }
}

@Test("Live Sunshine control client launch returns non-empty RTSP session URL")
func liveSunshineLaunchReturnsRTSPSessionURL() async throws {
    guard let config = LiveSunshineIntegrationConfiguration.enabledFromEnvironment() else {
        return
    }

    let launchContext = try await liveLaunchContext(config: config)
    let sessionURL = launchContext.launchResult.sessionURL?.trimmingCharacters(in: .whitespacesAndNewlines)

    #expect(!(sessionURL ?? "").isEmpty)
    #expect((sessionURL ?? "").lowercased().hasPrefix("rtsp://"))

    if config.requireRemoteInputMaterial {
        guard let remoteInputKey = launchContext.launchResult.remoteInputKey, !remoteInputKey.isEmpty else {
            throw LiveSunshineIntegrationError.missingRemoteInputKey(
                host: config.host,
                appID: launchContext.app.id
            )
        }
        guard let remoteInputKeyID = launchContext.launchResult.remoteInputKeyID, remoteInputKeyID > 0 else {
            throw LiveSunshineIntegrationError.missingRemoteInputKeyID(
                host: config.host,
                appID: launchContext.app.id
            )
        }
    }
}

@Test("Live Sunshine realtime session reaches rendering with active audio and negotiated codec")
func liveSunshineRealtimeSessionReachesRenderingWithAudioAndCodec() async throws {
    guard let config = LiveSunshineIntegrationConfiguration.enabledFromEnvironment() else {
        return
    }

    let launchContext = try await liveLaunchContext(config: config)
    guard let rawSessionURL = launchContext.launchResult.sessionURL else {
        let message = "Live launch returned nil session URL"
        Issue.record("\(message). host=\(config.host), appID=\(launchContext.app.id), verb=\(launchContext.launchResult.verb)")
        throw LiveSunshineIntegrationError.missingSessionURL(
            host: config.host,
            appID: launchContext.app.id,
            verb: launchContext.launchResult.verb,
            message: message
        )
    }

    let sessionURL = rawSessionURL.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !sessionURL.isEmpty else {
        let message = "Live launch returned empty session URL"
        Issue.record("\(message). host=\(config.host), appID=\(launchContext.app.id), verb=\(launchContext.launchResult.verb)")
        throw LiveSunshineIntegrationError.emptySessionURL(
            host: config.host,
            appID: launchContext.app.id,
            verb: launchContext.launchResult.verb,
            message: message
        )
    }

    let runtime = ShadowClientRealtimeRTSPSessionRuntime(connectTimeout: config.rtspConnectTimeout)
    let surfaceContext = await runtime.surfaceContext

    do {
        try await runtime.connect(
            sessionURL: sessionURL,
            host: config.host,
            appTitle: launchContext.app.title,
            videoConfiguration: config.runtimeVideoConfiguration(remoteInputKey: launchContext.launchResult.remoteInputKey)
        )

        let result = await waitForRendering(
            in: surfaceContext,
            timeout: config.renderTimeout,
            pollInterval: config.pollInterval
        )

        switch result {
        case let .rendering(stateTrace):
            #expect(!stateTrace.isEmpty)
            let activeVideoCodec = await MainActor.run {
                surfaceContext.activeVideoCodec
            }
            guard activeVideoCodec != nil else {
                try? await runtime.disconnect()
                throw LiveSunshineIntegrationError.missingNegotiatedVideoCodec(
                    host: config.host,
                    appID: launchContext.app.id
                )
            }

            if config.requireAudioPlayback {
                let audioResult = await waitForAudioPlayback(
                    in: surfaceContext,
                    timeout: config.audioPlaybackTimeout,
                    pollInterval: config.pollInterval
                )
                switch audioResult {
                case .playing:
                    break
                case let .failed(message, stateTrace):
                    try? await runtime.disconnect()
                    throw LiveSunshineIntegrationError.audioPipelineFailed(
                        host: config.host,
                        appID: launchContext.app.id,
                        message: message,
                        stateTrace: stateTrace
                    )
                case let .timedOut(lastState, stateTrace):
                    try? await runtime.disconnect()
                    throw LiveSunshineIntegrationError.audioPipelineTimedOut(
                        host: config.host,
                        appID: launchContext.app.id,
                        lastState: lastState,
                        stateTrace: stateTrace
                    )
                }
            }
            try? await runtime.disconnect()
        case let .failed(message, stateTrace):
            Issue.record(
                "Live realtime session entered failed state. host=\(config.host), appID=\(launchContext.app.id), message=\(message), states=\(stateTrace.joined(separator: " -> "))"
            )
            try? await runtime.disconnect()
            throw LiveSunshineIntegrationError.renderingFailed(
                host: config.host,
                appID: launchContext.app.id,
                message: message,
                stateTrace: stateTrace
            )
        case let .timedOut(lastState, stateTrace):
            Issue.record(
                "Live realtime session timed out waiting for rendering. host=\(config.host), appID=\(launchContext.app.id), sessionURL=\(sessionURL), lastState=\(lastState), states=\(stateTrace.joined(separator: " -> "))"
            )
            try? await runtime.disconnect()
            throw LiveSunshineIntegrationError.renderingTimedOut(
                host: config.host,
                appID: launchContext.app.id,
                lastState: lastState,
                stateTrace: stateTrace
            )
        }
    } catch {
        let state = await MainActor.run {
            describeRenderState(surfaceContext.renderState)
        }
        Issue.record(
            "Live realtime session connect threw error. host=\(config.host), appID=\(launchContext.app.id), sessionURL=\(sessionURL), state=\(state), error=\(error.localizedDescription)"
        )
        try? await runtime.disconnect()
        throw error
    }
}

private struct LiveSunshineLaunchContext: Sendable {
    let serverInfo: ShadowClientGameStreamServerInfo
    let app: ShadowClientRemoteAppDescriptor
    let launchResult: ShadowClientGameStreamLaunchResult
}

private struct LiveSunshineIntegrationConfiguration: Sendable {
    let host: String
    let preferredAppID: Int
    let fallbackHTTPSPort: Int
    let rtspConnectTimeout: Duration
    let renderTimeout: Duration
    let audioPlaybackTimeout: Duration
    let pollInterval: Duration
    let requirePairedHost: Bool
    let requireRemoteInputMaterial: Bool
    let requireAudioPlayback: Bool

    static func enabledFromEnvironment() -> Self? {
        let environment = ProcessInfo.processInfo.environment
        guard Self.boolFlag(environment["SHADOWCLIENT_LIVE_INTEGRATION"]) else {
            return nil
        }

        let host = Self.stringValue(
            environment["SHADOWCLIENT_LIVE_HOST"],
            fallback: "stream-host.example.invalid"
        )
        let preferredAppID = Self.intValue(
            environment["SHADOWCLIENT_LIVE_APP_ID"],
            fallback: 881_448_767
        )
        let fallbackHTTPSPort = Self.intValue(
            environment["SHADOWCLIENT_LIVE_HTTPS_PORT"],
            fallback: ShadowClientGameStreamNetworkDefaults.defaultHTTPSPort
        )
        let rtspConnectTimeoutSeconds = Self.intValue(
            environment["SHADOWCLIENT_LIVE_RTSP_CONNECT_TIMEOUT_SECONDS"],
            fallback: 12
        )
        let renderTimeoutSeconds = Self.intValue(
            environment["SHADOWCLIENT_LIVE_RENDER_TIMEOUT_SECONDS"],
            fallback: 30
        )
        let audioPlaybackTimeoutSeconds = Self.intValue(
            environment["SHADOWCLIENT_LIVE_AUDIO_TIMEOUT_SECONDS"],
            fallback: 12
        )
        let pollIntervalMilliseconds = Self.intValue(
            environment["SHADOWCLIENT_LIVE_RENDER_POLL_INTERVAL_MS"],
            fallback: 250
        )
        let requirePairedHost = Self.boolFlag(
            environment["SHADOWCLIENT_LIVE_REQUIRE_PAIRED_HOST"],
            fallback: true
        )
        let requireRemoteInputMaterial = Self.boolFlag(
            environment["SHADOWCLIENT_LIVE_REQUIRE_REMOTE_INPUT_KEY"],
            fallback: true
        )
        let requireAudioPlayback = Self.boolFlag(
            environment["SHADOWCLIENT_LIVE_REQUIRE_AUDIO_PLAYBACK"],
            fallback: true
        )

        return .init(
            host: host,
            preferredAppID: preferredAppID,
            fallbackHTTPSPort: fallbackHTTPSPort,
            rtspConnectTimeout: .seconds(rtspConnectTimeoutSeconds),
            renderTimeout: .seconds(renderTimeoutSeconds),
            audioPlaybackTimeout: .seconds(audioPlaybackTimeoutSeconds),
            pollInterval: .milliseconds(pollIntervalMilliseconds),
            requirePairedHost: requirePairedHost,
            requireRemoteInputMaterial: requireRemoteInputMaterial,
            requireAudioPlayback: requireAudioPlayback
        )
    }

    func launchSettings() -> ShadowClientGameStreamLaunchSettings {
        .init(
            width: ShadowClientStreamingLaunchBounds.defaultWidth,
            height: ShadowClientStreamingLaunchBounds.defaultHeight,
            fps: ShadowClientStreamingLaunchBounds.defaultFPS,
            bitrateKbps: ShadowClientStreamingLaunchBounds.defaultBitrateKbps,
            preferredCodec: .auto,
            enableHDR: false,
            enableSurroundAudio: false,
            lowLatencyMode: true
        )
    }

    func runtimeVideoConfiguration(remoteInputKey: Data?) -> ShadowClientRemoteSessionVideoConfiguration {
        let settings = launchSettings()
        return .init(
            width: settings.width,
            height: settings.height,
            fps: settings.fps,
            bitrateKbps: settings.bitrateKbps,
            preferredCodec: settings.preferredCodec,
            enableHDR: settings.enableHDR,
            enableSurroundAudio: settings.enableSurroundAudio,
            enableYUV444: settings.enableYUV444,
            remoteInputKey: remoteInputKey
        )
    }

    private static func boolFlag(
        _ value: String?,
        fallback: Bool = false
    ) -> Bool {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        case "0", "false", "no", "off":
            return false
        default:
            return fallback
        }
    }

    private static func stringValue(_ value: String?, fallback: String) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func intValue(_ value: String?, fallback: Int) -> Int {
        guard
            let value,
            let parsed = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)),
            parsed > 0
        else {
            return fallback
        }

        return parsed
    }
}

private enum LiveRenderWaitResult: Sendable {
    case rendering([String])
    case failed(message: String, stateTrace: [String])
    case timedOut(lastState: String, stateTrace: [String])
}

private enum LiveAudioWaitResult: Sendable {
    case playing([String])
    case failed(message: String, stateTrace: [String])
    case timedOut(lastState: String, stateTrace: [String])
}

private func liveLaunchContext(config: LiveSunshineIntegrationConfiguration) async throws -> LiveSunshineLaunchContext {
    let metadataClient = NativeGameStreamMetadataClient()
    let controlClient = NativeGameStreamControlClient()

    let serverInfo = try await metadataClient.fetchServerInfo(host: config.host)
    let appListPort = serverInfo.httpsPort > 0 ? serverInfo.httpsPort : config.fallbackHTTPSPort
    let apps = try await metadataClient.fetchAppList(host: config.host, httpsPort: appListPort)

    guard !apps.isEmpty else {
        Issue.record("Live app list was empty. host=\(config.host), httpsPort=\(appListPort)")
        throw LiveSunshineIntegrationError.emptyAppList
    }

    let app = apps.first(where: { $0.id == config.preferredAppID }) ?? apps[0]

    let launchResult = try await controlClient.launch(
        host: config.host,
        httpsPort: appListPort,
        appID: app.id,
        currentGameID: serverInfo.currentGameID,
        forceLaunch: false,
        settings: config.launchSettings()
    )

    return LiveSunshineLaunchContext(
        serverInfo: serverInfo,
        app: app,
        launchResult: launchResult
    )
}

@MainActor
private func waitForRendering(
    in surfaceContext: ShadowClientRealtimeSessionSurfaceContext,
    timeout: Duration,
    pollInterval: Duration
) async -> LiveRenderWaitResult {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    var stateTrace: [String] = []

    while clock.now < deadline {
        let state = surfaceContext.renderState
        let summary = describeRenderState(state)
        if stateTrace.last != summary {
            stateTrace.append(summary)
        }

        switch state {
        case .rendering:
            return .rendering(stateTrace)
        case let .disconnected(message):
            return .failed(message: "disconnected: \(message)", stateTrace: stateTrace)
        case let .failed(message):
            return .failed(message: message, stateTrace: stateTrace)
        case .idle, .connecting, .waitingForFirstFrame:
            break
        }

        try? await Task.sleep(for: pollInterval)
    }

    let finalState = describeRenderState(surfaceContext.renderState)
    if stateTrace.last != finalState {
        stateTrace.append(finalState)
    }

    return .timedOut(lastState: finalState, stateTrace: stateTrace)
}

@MainActor
private func waitForAudioPlayback(
    in surfaceContext: ShadowClientRealtimeSessionSurfaceContext,
    timeout: Duration,
    pollInterval: Duration
) async -> LiveAudioWaitResult {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    var stateTrace: [String] = []

    while clock.now < deadline {
        let state = surfaceContext.audioOutputState
        let summary = describeAudioState(state)
        if stateTrace.last != summary {
            stateTrace.append(summary)
        }

        switch state {
        case .playing:
            return .playing(stateTrace)
        case let .deviceUnavailable(message):
            return .failed(message: "deviceUnavailable: \(message)", stateTrace: stateTrace)
        case let .decoderFailed(message):
            return .failed(message: "decoderFailed: \(message)", stateTrace: stateTrace)
        case let .disconnected(message):
            return .failed(message: "disconnected: \(message)", stateTrace: stateTrace)
        case .idle, .starting:
            break
        }

        try? await Task.sleep(for: pollInterval)
    }

    let finalState = describeAudioState(surfaceContext.audioOutputState)
    if stateTrace.last != finalState {
        stateTrace.append(finalState)
    }
    return .timedOut(lastState: finalState, stateTrace: stateTrace)
}

private func describeRenderState(_ state: ShadowClientRealtimeSessionSurfaceContext.RenderState) -> String {
    switch state {
    case .idle:
        return "idle"
    case .connecting:
        return "connecting"
    case .waitingForFirstFrame:
        return "waitingForFirstFrame"
    case .rendering:
        return "rendering"
    case let .disconnected(message):
        return "disconnected(\(message))"
    case let .failed(message):
        return "failed(\(message))"
    }
}

private func describeAudioState(_ state: ShadowClientRealtimeAudioOutputState) -> String {
    switch state {
    case .idle:
        return "idle"
    case .starting:
        return "starting"
    case let .playing(codec, sampleRate, channels):
        return "playing(codec=\(codec.label), sampleRate=\(sampleRate), channels=\(channels))"
    case let .deviceUnavailable(message):
        return "deviceUnavailable(\(message))"
    case let .decoderFailed(message):
        return "decoderFailed(\(message))"
    case let .disconnected(message):
        return "disconnected(\(message))"
    }
}

private enum LiveSunshineIntegrationError: Error {
    case emptyAppList
    case unpairedHost(host: String, pairStatus: String)
    case missingSessionURL(host: String, appID: Int, verb: String, message: String)
    case emptySessionURL(host: String, appID: Int, verb: String, message: String)
    case missingRemoteInputKey(host: String, appID: Int)
    case missingRemoteInputKeyID(host: String, appID: Int)
    case missingNegotiatedVideoCodec(host: String, appID: Int)
    case renderingFailed(host: String, appID: Int, message: String, stateTrace: [String])
    case renderingTimedOut(host: String, appID: Int, lastState: String, stateTrace: [String])
    case audioPipelineFailed(host: String, appID: Int, message: String, stateTrace: [String])
    case audioPipelineTimedOut(host: String, appID: Int, lastState: String, stateTrace: [String])
}
