import Testing
@testable import ShadowClientFeatureHome

@Test("Remote desktop runtime pairs selected host through injected control client")
@MainActor
func remoteDesktopRuntimePairsSelectedHost() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.20": .init(
                host: "192.168.0.20",
                displayName: "LivingRoom-PC",
                pairStatus: .notPaired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-1"
            ),
        ],
        appListByHost: [:]
    )
    let control = FakeControlClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        pinProvider: FixedPairingPINProvider(pin: "1234")
    )

    runtime.refreshHosts(candidates: ["192.168.0.20"], preferredHost: "192.168.0.20")
    await waitForControlHostLoaded(runtime)

    runtime.pairSelectedHost()
    await waitForPairingState(runtime)

    #expect(await control.pairCalls() == [
        .init(host: "192.168.0.20", pin: "1234", appVersion: "7.0.0", httpsPort: 47984),
    ])

    if case .paired = runtime.pairingState {
        #expect(true)
    } else {
        Issue.record("Expected paired state, got \(runtime.pairingState)")
    }
}

@Test("Remote desktop runtime retries transient pairing timeout and eventually pairs")
@MainActor
func remoteDesktopRuntimeRetriesTransientPairingTimeout() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.21": .init(
                host: "192.168.0.21",
                displayName: "Office-PC",
                pairStatus: .notPaired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-2"
            ),
        ],
        appListByHost: [:]
    )
    let control = FakeControlClient(
        simulatedPairFailures: [ShadowClientGameStreamError.requestFailed("The request timed out.")]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        pinProvider: FixedPairingPINProvider(pin: "1234")
    )

    runtime.refreshHosts(candidates: ["192.168.0.21"], preferredHost: "192.168.0.21")
    await waitForControlHostLoaded(runtime)

    runtime.pairSelectedHost()
    await waitForPairingState(runtime, maxAttempts: 200)

    let calls = await control.pairCalls()
    #expect(calls.count >= 2)

    if case .paired = runtime.pairingState {
        #expect(true)
    } else {
        Issue.record("Expected paired state after retry, got \(runtime.pairingState)")
    }
}

@Test("Remote desktop runtime stops retrying when pairing challenge is rejected")
@MainActor
func remoteDesktopRuntimeDoesNotRetryRejectedChallenge() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.22": .init(
                host: "192.168.0.22",
                displayName: "Guest-PC",
                pairStatus: .notPaired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-3"
            ),
        ],
        appListByHost: [:]
    )
    let control = FakeControlClient(
        simulatedPairFailures: [ShadowClientGameStreamControlError.challengeRejected]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        pinProvider: FixedPairingPINProvider(pin: "1234")
    )

    runtime.refreshHosts(candidates: ["192.168.0.22"], preferredHost: "192.168.0.22")
    await waitForControlHostLoaded(runtime)

    runtime.pairSelectedHost()
    await waitForPairingState(runtime)

    #expect(await control.pairCalls().count == 1)
    if case let .failed(message) = runtime.pairingState {
        #expect(message.contains("Pairing challenge was rejected"))
    } else {
        Issue.record("Expected failed state, got \(runtime.pairingState)")
    }
}

@Test("Remote desktop runtime does not retry certificate-required pairing failure")
@MainActor
func remoteDesktopRuntimeDoesNotRetryCertificateRequiredFailure() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.23": .init(
                host: "192.168.0.23",
                displayName: "Studio-PC",
                pairStatus: .notPaired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-4"
            ),
        ],
        appListByHost: [:]
    )
    let control = FakeControlClient(
        simulatedPairFailures: [
            ShadowClientGameStreamError.requestFailed("TLSV1_ALERT_CERTIFICATE_REQUIRED: certificate required"),
        ]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        pinProvider: FixedPairingPINProvider(pin: "1234")
    )

    runtime.refreshHosts(candidates: ["192.168.0.23"], preferredHost: "192.168.0.23")
    await waitForControlHostLoaded(runtime)

    runtime.pairSelectedHost()
    await waitForPairingState(runtime)

    #expect(await control.pairCalls().count == 1)
    if case let .failed(message) = runtime.pairingState {
        #expect(message.localizedCaseInsensitiveContains("certificate required"))
    } else {
        Issue.record("Expected failed state, got \(runtime.pairingState)")
    }
}

@Test("Remote desktop runtime launches selected app through injected control client")
@MainActor
func remoteDesktopRuntimeLaunchesSelectedApp() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.20": .init(
                host: "192.168.0.20",
                displayName: "LivingRoom-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-1"
            ),
        ],
        appListByHost: [
            "192.168.0.20": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient()
    let runtime = ShadowClientRemoteDesktopRuntime(metadataClient: metadata, controlClient: control)

    runtime.refreshHosts(candidates: ["192.168.0.20"], preferredHost: "192.168.0.20")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    let calls = await control.launchCalls()
    #expect(calls.count == 1)
    #expect(calls.first?.host == "192.168.0.20")
    #expect(calls.first?.httpsPort == 47984)
    #expect(calls.first?.appID == 1)

    if case .launched = runtime.launchState {
        #expect(true)
    } else {
        Issue.record("Expected launched state, got \(runtime.launchState)")
    }
}

private actor FakeControlTestMetadataClient: ShadowClientGameStreamMetadataClient {
    private let serverInfoByHost: [String: ShadowClientGameStreamServerInfo]
    private let appListByHost: [String: [ShadowClientRemoteAppDescriptor]]

    init(
        serverInfoByHost: [String: ShadowClientGameStreamServerInfo],
        appListByHost: [String: [ShadowClientRemoteAppDescriptor]]
    ) {
        self.serverInfoByHost = serverInfoByHost
        self.appListByHost = appListByHost
    }

    func fetchServerInfo(host: String) async throws -> ShadowClientGameStreamServerInfo {
        guard let info = serverInfoByHost[host] else {
            throw ShadowClientGameStreamError.requestFailed("missing host")
        }

        return info
    }

    func fetchAppList(host: String, httpsPort: Int?) async throws -> [ShadowClientRemoteAppDescriptor] {
        appListByHost[host] ?? []
    }
}

private actor FakeControlClient: ShadowClientGameStreamControlClient {
    struct PairCall: Equatable {
        let host: String
        let pin: String
        let appVersion: String?
        let httpsPort: Int?
    }

    struct LaunchCall: Equatable {
        let host: String
        let httpsPort: Int
        let appID: Int
        let currentGameID: Int
        let settings: ShadowClientGameStreamLaunchSettings
    }

    private var recordedPairCalls: [PairCall] = []
    private var recordedLaunchCalls: [LaunchCall] = []
    private var simulatedPairFailures: [any Error & Sendable]

    init(simulatedPairFailures: [any Error & Sendable] = []) {
        self.simulatedPairFailures = simulatedPairFailures
    }

    func pair(
        host: String,
        pin: String,
        appVersion: String?,
        httpsPort: Int?
    ) async throws -> ShadowClientGameStreamPairingResult {
        recordedPairCalls.append(
            PairCall(host: host, pin: pin, appVersion: appVersion, httpsPort: httpsPort)
        )

        if !simulatedPairFailures.isEmpty {
            let nextError = simulatedPairFailures.removeFirst()
            throw nextError
        }

        return .init(host: host)
    }

    func launch(
        host: String,
        httpsPort: Int,
        appID: Int,
        currentGameID: Int,
        settings: ShadowClientGameStreamLaunchSettings
    ) async throws -> ShadowClientGameStreamLaunchResult {
        recordedLaunchCalls.append(
            LaunchCall(
                host: host,
                httpsPort: httpsPort,
                appID: appID,
                currentGameID: currentGameID,
                settings: settings
            )
        )

        return .init(sessionURL: "rtsp://example/session", verb: "launch")
    }

    func pairCalls() -> [PairCall] {
        recordedPairCalls
    }

    func launchCalls() -> [LaunchCall] {
        recordedLaunchCalls
    }
}

@MainActor
private func waitForControlHostLoaded(
    _ runtime: ShadowClientRemoteDesktopRuntime,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if runtime.hostState == .loaded {
            return
        }

        try? await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
private func waitForPairingState(
    _ runtime: ShadowClientRemoteDesktopRuntime,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if case .pairing = runtime.pairingState {
            try? await Task.sleep(for: .milliseconds(20))
            continue
        } else {
            return
        }
    }
}

private struct FixedPairingPINProvider: ShadowClientPairingPINProviding {
    let pin: String

    func nextPIN() -> String {
        pin
    }
}

@MainActor
private func waitForLaunchState(
    _ runtime: ShadowClientRemoteDesktopRuntime,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if runtime.launchState != .launching {
            return
        }

        try? await Task.sleep(for: .milliseconds(20))
    }
}
