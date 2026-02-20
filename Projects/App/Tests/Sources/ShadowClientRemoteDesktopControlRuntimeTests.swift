import Foundation
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

@Test("Remote desktop runtime applies pending host selection after host catalog load")
@MainActor
func remoteDesktopRuntimeAppliesPendingHostSelectionAfterCatalogLoad() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "wifi.skyline23.com": .init(
                host: "wifi.skyline23.com",
                displayName: "Skyline23-PC",
                pairStatus: .paired,
                currentGameID: 881_448_767,
                serverState: "SUNSHINE_SERVER_BUSY",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-12"
            ),
        ],
        appListByHost: [
            "wifi.skyline23.com": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: FakeControlClient()
    )

    runtime.selectHost("wifi.skyline23.com")
    runtime.refreshHosts(candidates: ["wifi.skyline23.com"])
    await waitForControlHostLoaded(runtime)

    #expect(runtime.selectedHostID == "wifi.skyline23.com")
    #expect(runtime.selectedHost?.host == "wifi.skyline23.com")
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
    #expect(calls.first?.forceLaunch == false)

    if case .launched = runtime.launchState {
        #expect(true)
    } else {
        Issue.record("Expected launched state, got \(runtime.launchState)")
    }
}

@Test("Remote desktop runtime connects launched video session URL before reporting success")
@MainActor
func remoteDesktopRuntimeConnectsVideoSessionBeforeLaunchSuccess() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.24": .init(
                host: "192.168.0.24",
                displayName: "Gaming-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-5"
            ),
        ],
        appListByHost: [
            "192.168.0.24": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.24:48010/session", verb: "launch")
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.24"], preferredHost: "192.168.0.24")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 881_448_767,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    #expect(await sessionConnector.connectCalls() == ["rtsp://192.168.0.24:48010/session"])
    if case .launched = runtime.launchState {
        #expect(true)
    } else {
        Issue.record("Expected launched state, got \(runtime.launchState)")
    }
}

@Test("Remote desktop runtime forwards launch remote input key into session configuration")
@MainActor
func remoteDesktopRuntimeForwardsRemoteInputKeyToSessionConfiguration() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.24": .init(
                host: "192.168.0.24",
                displayName: "Gaming-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-KEY"
            ),
        ],
        appListByHost: [
            "192.168.0.24": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let remoteInputKey = Data(repeating: 0xAB, count: 16)
    let control = FakeControlClient(
        simulatedLaunchResult: .init(
            sessionURL: "rtsp://192.168.0.24:48010/session",
            verb: "launch",
            remoteInputKey: remoteInputKey
        )
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.24"], preferredHost: "192.168.0.24")
    await waitForControlHostLoaded(runtime)
    runtime.launchSelectedApp(
        appID: 881_448_767,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    let capturedConfiguration = await sessionConnector.latestVideoConfiguration()
    #expect(capturedConfiguration?.remoteInputKey == remoteInputKey)
}

@Test("Remote desktop runtime preserves host-provided session URL without app-side host rewrite")
@MainActor
func remoteDesktopRuntimePreservesHostProvidedSessionURL() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "wifi.skyline23.com": .init(
                host: "wifi.skyline23.com",
                displayName: "Skyline23-PC",
                pairStatus: .paired,
                currentGameID: 881_448_767,
                serverState: "SUNSHINE_SERVER_BUSY",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-11"
            ),
        ],
        appListByHost: [
            "wifi.skyline23.com": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.52:48010", verb: "resume")
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["wifi.skyline23.com"], preferredHost: "wifi.skyline23.com")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 881_448_767,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    #expect(await sessionConnector.connectCalls() == ["rtsp://192.168.0.52:48010"])
    #expect(runtime.activeSession?.sessionURL == "rtsp://192.168.0.52:48010")
    if case .launched = runtime.launchState {
        #expect(true)
    } else {
        Issue.record("Expected launched state, got \(runtime.launchState)")
    }
}

@Test("Remote desktop runtime retries launch with forceLaunch when resume connect times out")
@MainActor
func remoteDesktopRuntimeRetriesForceLaunchAfterResumeConnectTimeout() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "wifi.skyline23.com": .init(
                host: "wifi.skyline23.com",
                displayName: "Skyline23-PC",
                pairStatus: .paired,
                currentGameID: 881_448_767,
                serverState: "SUNSHINE_SERVER_BUSY",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-13"
            ),
        ],
        appListByHost: [
            "wifi.skyline23.com": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let resumeSessionURL = "rtsp://192.168.0.52:48010/resume"
    let forcedLaunchSessionURL = "rtsp://192.168.0.52:48010/launch"
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: forcedLaunchSessionURL, verb: "launch"),
        simulatedLaunchResults: [
            .init(sessionURL: resumeSessionURL, verb: "resume"),
            .init(sessionURL: forcedLaunchSessionURL, verb: "launch"),
        ]
    )
    let sessionConnector = FakeSessionConnectionClient(
        simulatedFailures: [
            ShadowClientGameStreamError.requestFailed("RTSP UDP video timeout: no video datagram received"),
        ]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["wifi.skyline23.com"], preferredHost: "wifi.skyline23.com")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 881_448_767,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    #expect(await sessionConnector.connectCalls() == [resumeSessionURL, forcedLaunchSessionURL])
    #expect(await sessionConnector.disconnectCalls() >= 1)
    let calls = await control.launchCalls()
    #expect(calls.count == 2)
    #expect(calls[0].forceLaunch == false)
    #expect(calls[1].forceLaunch == true)
    #expect(runtime.activeSession?.sessionURL == forcedLaunchSessionURL)
    if case .launched = runtime.launchState {
        #expect(true)
    } else {
        Issue.record("Expected launched state, got \(runtime.launchState)")
    }
}

@Test("Remote desktop runtime falls back from AV1 to H265 when decoder session creation fails")
@MainActor
func remoteDesktopRuntimeFallsBackCodecAfterDecoderCreationFailure() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.32": .init(
                host: "192.168.0.32",
                displayName: "AV1-Host",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-AV1"
            ),
        ],
        appListByHost: [
            "192.168.0.32": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let sessionURL = "rtsp://192.168.0.32:48010/session"
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: sessionURL, verb: "launch")
    )
    let sessionConnector = FakeSessionConnectionClient(
        simulatedFailures: [
            ShadowClientGameStreamError.requestFailed("Could not create hardware decoder session (OSStatus -8971)."),
        ]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.32"], preferredHost: "192.168.0.32")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(
            preferredCodec: .av1,
            enableHDR: true,
            enableSurroundAudio: true,
            lowLatencyMode: false
        )
    )
    await waitForLaunchState(runtime)

    #expect(await sessionConnector.connectCalls() == [sessionURL, sessionURL])
    #expect(await sessionConnector.disconnectCalls() >= 1)
    let codecHistory = await sessionConnector.videoConfigurations().map(\.preferredCodec)
    #expect(codecHistory == [.av1, .h265])
    let launchCalls = await control.launchCalls()
    #expect(launchCalls.count == 1)
    #expect(launchCalls[0].forceLaunch == false)
    if case .launched = runtime.launchState {
        #expect(true)
    } else {
        Issue.record("Expected launched state, got \(runtime.launchState)")
    }
}

@Test("Remote desktop runtime downgrades codec for forceLaunch after resume decoder failures")
@MainActor
func remoteDesktopRuntimeDowngradesCodecOnForceLaunchAfterResumeDecoderFailures() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "wifi.skyline23.com": .init(
                host: "wifi.skyline23.com",
                displayName: "Skyline23-PC",
                pairStatus: .paired,
                currentGameID: 881_448_767,
                serverState: "SUNSHINE_SERVER_BUSY",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-AV1-RESUME"
            ),
        ],
        appListByHost: [
            "wifi.skyline23.com": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let resumeSessionURL = "rtsp://192.168.0.52:48010/resume"
    let forcedLaunchSessionURL = "rtsp://192.168.0.52:48010/launch"
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: forcedLaunchSessionURL, verb: "launch"),
        simulatedLaunchResults: [
            .init(sessionURL: resumeSessionURL, verb: "resume"),
            .init(sessionURL: forcedLaunchSessionURL, verb: "launch"),
        ]
    )
    let sessionConnector = FakeSessionConnectionClient(
        simulatedFailures: [
            ShadowClientGameStreamError.requestFailed("Could not create hardware decoder session (OSStatus -8971)."),
            ShadowClientGameStreamError.requestFailed("Could not create hardware decoder session (OSStatus -8971)."),
            ShadowClientGameStreamError.requestFailed("Could not create hardware decoder session (OSStatus -8971)."),
        ]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["wifi.skyline23.com"], preferredHost: "wifi.skyline23.com")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 881_448_767,
        settings: .init(
            preferredCodec: .av1,
            enableHDR: true,
            enableSurroundAudio: true,
            lowLatencyMode: false
        )
    )
    await waitForLaunchState(runtime, maxAttempts: 200)

    #expect(await sessionConnector.connectCalls() == [
        resumeSessionURL,
        resumeSessionURL,
        resumeSessionURL,
        forcedLaunchSessionURL,
    ])
    let codecHistory = await sessionConnector.videoConfigurations().map(\.preferredCodec)
    #expect(codecHistory == [.av1, .h265, .h264, .h265])
    let launchCalls = await control.launchCalls()
    #expect(launchCalls.count == 2)
    #expect(launchCalls[0].forceLaunch == false)
    #expect(launchCalls[1].forceLaunch == true)
    #expect(launchCalls[0].settings.preferredCodec == .av1)
    #expect(launchCalls[1].settings.preferredCodec == .h265)
    #expect(runtime.activeSession?.sessionURL == forcedLaunchSessionURL)
    if case .launched = runtime.launchState {
        #expect(true)
    } else {
        Issue.record("Expected launched state, got \(runtime.launchState)")
    }
}

@Test("Remote desktop runtime fails launch when host returns missing video session URL")
@MainActor
func remoteDesktopRuntimeFailsLaunchWhenSessionURLIsMissing() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.25": .init(
                host: "192.168.0.25",
                displayName: "Desk-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-6"
            ),
        ],
        appListByHost: [
            "192.168.0.25": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: nil, verb: "launch")
    )
    let runtime = ShadowClientRemoteDesktopRuntime(metadataClient: metadata, controlClient: control)

    runtime.refreshHosts(candidates: ["192.168.0.25"], preferredHost: "192.168.0.25")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    if case let .failed(message) = runtime.launchState {
        #expect(message.localizedCaseInsensitiveContains("session url"))
    } else {
        Issue.record("Expected failed state, got \(runtime.launchState)")
    }
    #expect(runtime.activeSession == nil)
}

@Test("Remote desktop runtime fails launch when video session endpoint is unreachable")
@MainActor
func remoteDesktopRuntimeFailsLaunchWhenVideoSessionConnectionFails() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.26": .init(
                host: "192.168.0.26",
                displayName: "Guest-Room-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-7"
            ),
        ],
        appListByHost: [
            "192.168.0.26": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.26:48010/session", verb: "launch")
    )
    let sessionConnector = FakeSessionConnectionClient(
        simulatedFailure: ShadowClientGameStreamError.requestFailed("Could not connect to video session endpoint.")
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.26"], preferredHost: "192.168.0.26")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    #expect(await sessionConnector.connectCalls() == ["rtsp://192.168.0.26:48010/session"])
    let launchCalls = await control.launchCalls()
    #expect(launchCalls.count == 1)
    #expect(launchCalls.first?.forceLaunch == false)
    if case let .failed(message) = runtime.launchState {
        #expect(message.localizedCaseInsensitiveContains("could not connect to video session endpoint"))
    } else {
        Issue.record("Expected failed state, got \(runtime.launchState)")
    }
    #expect(runtime.activeSession == nil)
}

@Test("Remote desktop runtime appends AV1 compatibility guidance when decoder session creation fails")
@MainActor
func remoteDesktopRuntimeAddsAV1CompatibilityGuidanceOnDecoderFailure() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.33": .init(
                host: "192.168.0.33",
                displayName: "Decoder-Fail-Host",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-AV1-HINT"
            ),
        ],
        appListByHost: [
            "192.168.0.33": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.33:48010/session", verb: "launch")
    )
    let sessionConnector = FakeSessionConnectionClient(
        simulatedFailures: [
            ShadowClientGameStreamError.requestFailed("Could not create hardware decoder session (OSStatus -8971)."),
            ShadowClientGameStreamError.requestFailed("Could not create hardware decoder session (OSStatus -8971)."),
            ShadowClientGameStreamError.requestFailed("Could not create hardware decoder session (OSStatus -8971)."),
        ]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.33"], preferredHost: "192.168.0.33")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(
            preferredCodec: .av1,
            enableHDR: true,
            enableSurroundAudio: true,
            lowLatencyMode: false
        )
    )
    await waitForLaunchState(runtime)

    if case let .failed(message) = runtime.launchState {
        #expect(message.localizedCaseInsensitiveContains("av1"))
        #expect(message.localizedCaseInsensitiveContains("videotoolbox"))
        #expect(message.localizedCaseInsensitiveContains("h.264"))
    } else {
        Issue.record("Expected failed state, got \(runtime.launchState)")
    }
}

@Test("Remote desktop runtime appends YUV444 guidance when transport fails with YUV444 enabled")
@MainActor
func remoteDesktopRuntimeAddsYUV444GuidanceOnTransportFailure() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.34": .init(
                host: "192.168.0.34",
                displayName: "YUV444-Fail-Host",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-YUV444-HINT"
            ),
        ],
        appListByHost: [
            "192.168.0.34": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.34:48010/session", verb: "launch")
    )
    let sessionConnector = FakeSessionConnectionClient(
        simulatedFailure: ShadowClientGameStreamError.requestFailed("RTSP UDP video timeout: no video datagram received")
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.34"], preferredHost: "192.168.0.34")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(
            preferredCodec: .h265,
            enableHDR: true,
            enableSurroundAudio: true,
            lowLatencyMode: false,
            enableYUV444: true
        )
    )
    await waitForLaunchState(runtime)

    if case let .failed(message) = runtime.launchState {
        #expect(message.localizedCaseInsensitiveContains("yuv 4:4:4"))
        #expect(message.localizedCaseInsensitiveContains("disable"))
    } else {
        Issue.record("Expected failed state, got \(runtime.launchState)")
    }
}

@Test("Remote desktop runtime keeps latest launch state when prior launch is cancelled")
@MainActor
func remoteDesktopRuntimeKeepsLatestLaunchStateWhenPriorLaunchIsCancelled() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.27": .init(
                host: "192.168.0.27",
                displayName: "Den-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-8"
            ),
        ],
        appListByHost: [
            "192.168.0.27": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
                .init(id: 2, title: "Steam", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.27:48010/session", verb: "launch")
    )
    let sessionConnector = BlockingFirstSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.27"], preferredHost: "192.168.0.27")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForSessionConnectCalls(sessionConnector, expectedCount: 1)

    runtime.launchSelectedApp(
        appID: 2,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime, maxAttempts: 200)

    #expect(await sessionConnector.connectCalls().count == 2)
    #expect(runtime.activeSession?.appID == 2)
    if case .launched = runtime.launchState {
        #expect(true)
    } else {
        Issue.record("Expected launched state, got \(runtime.launchState)")
    }
}

@Test("Remote desktop runtime forwards captured input events to active session input client")
@MainActor
func remoteDesktopRuntimeForwardsCapturedInputEventsToActiveSessionInputClient() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.28": .init(
                host: "192.168.0.28",
                displayName: "Loft-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-9"
            ),
        ],
        appListByHost: [
            "192.168.0.28": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.28:48010/session", verb: "launch")
    )
    let sessionConnector = FakeSessionConnectionClient()
    let sessionInput = FakeSessionInputClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector,
        sessionInputClient: sessionInput
    )

    runtime.refreshHosts(candidates: ["192.168.0.28"], preferredHost: "192.168.0.28")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    runtime.sendInput(.keyDown(keyCode: 13, characters: "w"))
    runtime.sendInput(.pointerButton(button: .left, isPressed: true))
    await waitForSessionInputCalls(sessionInput, expectedCount: 2)

    let calls = await sessionInput.inputCalls()
    #expect(calls.count == 2)
    #expect(calls.allSatisfy { $0.host == "192.168.0.28" })
    #expect(calls.allSatisfy { $0.sessionURL == "rtsp://192.168.0.28:48010/session" })
}

@Test("Remote desktop runtime ignores input when active session has no session URL")
@MainActor
func remoteDesktopRuntimeIgnoresInputWhenActiveSessionHasNoSessionURL() async {
    let sessionInput = FakeSessionInputClient()
    let runtimeWithInput = ShadowClientRemoteDesktopRuntime(
        metadataClient: FakeControlTestMetadataClient(serverInfoByHost: [:], appListByHost: [:]),
        controlClient: FakeControlClient(),
        sessionInputClient: sessionInput
    )

    runtimeWithInput.openSessionFlow(host: "192.168.0.29", appTitle: "Remote Desktop")
    runtimeWithInput.sendInput(.keyDown(keyCode: 13, characters: "w"))
    try? await Task.sleep(for: .milliseconds(80))

    #expect(await sessionInput.inputCalls().isEmpty)
}

@Test("Remote desktop runtime disconnects session transport when clearing active session")
@MainActor
func remoteDesktopRuntimeDisconnectsSessionTransportOnClearActiveSession() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.30": .init(
                host: "192.168.0.30",
                displayName: "Studio-Desk",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-10"
            ),
        ],
        appListByHost: [
            "192.168.0.30": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.30:48010/session", verb: "launch")
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.30"], preferredHost: "192.168.0.30")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)
    runtime.clearActiveSession()

    await waitForSessionDisconnectCalls(sessionConnector, expectedCount: 1)
    #expect(runtime.activeSession == nil)
    #expect(runtime.launchState == .idle)
    #expect(await sessionConnector.disconnectCalls() >= 1)
}

@Test("Remote desktop runtime clears in-flight launch and keeps session closed")
@MainActor
func remoteDesktopRuntimeClearsInFlightLaunch() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.31": .init(
                host: "192.168.0.31",
                displayName: "Workstation",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-11"
            ),
        ],
        appListByHost: [
            "192.168.0.31": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.31:48010/session", verb: "launch")
    )
    let sessionConnector = BlockingFirstSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.31"], preferredHost: "192.168.0.31")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForSessionConnectCalls(sessionConnector, expectedCount: 1)

    runtime.clearActiveSession()
    await waitForLaunchState(runtime, maxAttempts: 200)
    await waitForSessionDisconnectCalls(sessionConnector, expectedCount: 1)

    #expect(runtime.activeSession == nil)
    #expect(runtime.launchState == .idle)
    #expect(await sessionConnector.connectCalls().count == 1)
    #expect(await sessionConnector.disconnectCalls() >= 1)
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
        let forceLaunch: Bool
        let settings: ShadowClientGameStreamLaunchSettings
    }

    private var recordedPairCalls: [PairCall] = []
    private var recordedLaunchCalls: [LaunchCall] = []
    private var simulatedPairFailures: [any Error & Sendable]
    private var simulatedLaunchResults: [ShadowClientGameStreamLaunchResult]
    private let defaultLaunchResult: ShadowClientGameStreamLaunchResult
    private let simulatedLaunchFailure: (any Error & Sendable)?

    init(
        simulatedPairFailures: [any Error & Sendable] = [],
        simulatedLaunchResult: ShadowClientGameStreamLaunchResult = .init(sessionURL: "rtsp://example/session", verb: "launch"),
        simulatedLaunchResults: [ShadowClientGameStreamLaunchResult] = [],
        simulatedLaunchFailure: (any Error & Sendable)? = nil
    ) {
        self.simulatedPairFailures = simulatedPairFailures
        self.simulatedLaunchResults = simulatedLaunchResults
        self.defaultLaunchResult = simulatedLaunchResult
        self.simulatedLaunchFailure = simulatedLaunchFailure
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
        forceLaunch: Bool,
        settings: ShadowClientGameStreamLaunchSettings
    ) async throws -> ShadowClientGameStreamLaunchResult {
        recordedLaunchCalls.append(
            LaunchCall(
                host: host,
                httpsPort: httpsPort,
                appID: appID,
                currentGameID: currentGameID,
                forceLaunch: forceLaunch,
                settings: settings
            )
        )

        if let simulatedLaunchFailure {
            throw simulatedLaunchFailure
        }

        if !simulatedLaunchResults.isEmpty {
            return simulatedLaunchResults.removeFirst()
        }

        return defaultLaunchResult
    }

    func pairCalls() -> [PairCall] {
        recordedPairCalls
    }

    func launchCalls() -> [LaunchCall] {
        recordedLaunchCalls
    }
}

private actor FakeSessionConnectionClient: ShadowClientRemoteSessionConnectionClient {
    let presentationMode: ShadowClientRemoteSessionPresentationMode = .embeddedPlayer
    nonisolated let sessionSurfaceContext: ShadowClientRealtimeSessionSurfaceContext = .init()

    private var recordedConnectCalls: [String] = []
    private var recordedVideoConfigurations: [ShadowClientRemoteSessionVideoConfiguration] = []
    private var disconnectCallCount = 0
    private var simulatedFailures: [any Error & Sendable]

    init(
        simulatedFailure: (any Error & Sendable)? = nil,
        simulatedFailures: [any Error & Sendable] = []
    ) {
        self.simulatedFailures = simulatedFailures
        if let simulatedFailure {
            self.simulatedFailures.insert(simulatedFailure, at: 0)
        }
    }

    func connect(
        to sessionURL: String,
        host: String,
        appTitle: String,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration
    ) async throws {
        recordedConnectCalls.append(sessionURL)
        recordedVideoConfigurations.append(videoConfiguration)

        if !simulatedFailures.isEmpty {
            let error = simulatedFailures.removeFirst()
            throw error
        }
    }

    func disconnect() async {
        disconnectCallCount += 1
    }

    func connectCalls() -> [String] {
        recordedConnectCalls
    }

    func disconnectCalls() -> Int {
        disconnectCallCount
    }

    func latestVideoConfiguration() -> ShadowClientRemoteSessionVideoConfiguration? {
        recordedVideoConfigurations.last
    }

    func videoConfigurations() -> [ShadowClientRemoteSessionVideoConfiguration] {
        recordedVideoConfigurations
    }
}

private actor BlockingFirstSessionConnectionClient: ShadowClientRemoteSessionConnectionClient {
    let presentationMode: ShadowClientRemoteSessionPresentationMode = .embeddedPlayer
    nonisolated let sessionSurfaceContext: ShadowClientRealtimeSessionSurfaceContext = .init()

    private var recordedConnectCalls: [String] = []
    private var disconnectCallCount = 0

    func connect(
        to sessionURL: String,
        host: String,
        appTitle: String,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration
    ) async throws {
        recordedConnectCalls.append(sessionURL)

        if recordedConnectCalls.count == 1 {
            try await Task.sleep(for: .seconds(30))
        }
    }

    func disconnect() async {
        disconnectCallCount += 1
    }

    func connectCalls() -> [String] {
        recordedConnectCalls
    }

    func disconnectCalls() -> Int {
        disconnectCallCount
    }
}

private actor FakeSessionInputClient: ShadowClientRemoteSessionInputClient {
    struct InputCall: Equatable {
        let event: ShadowClientRemoteInputEvent
        let host: String
        let sessionURL: String
    }

    private var recordedInputCalls: [InputCall] = []

    func send(event: ShadowClientRemoteInputEvent, host: String, sessionURL: String) async throws {
        recordedInputCalls.append(
            .init(event: event, host: host, sessionURL: sessionURL)
        )
    }

    func inputCalls() -> [InputCall] {
        recordedInputCalls
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

private func waitForSessionConnectCalls(
    _ connector: BlockingFirstSessionConnectionClient,
    expectedCount: Int,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if await connector.connectCalls().count >= expectedCount {
            return
        }

        try? await Task.sleep(for: .milliseconds(20))
    }
}

private func waitForSessionInputCalls(
    _ inputClient: FakeSessionInputClient,
    expectedCount: Int,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if await inputClient.inputCalls().count >= expectedCount {
            return
        }

        try? await Task.sleep(for: .milliseconds(20))
    }
}

private func waitForSessionDisconnectCalls(
    _ connector: FakeSessionConnectionClient,
    expectedCount: Int,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if await connector.disconnectCalls() >= expectedCount {
            return
        }

        try? await Task.sleep(for: .milliseconds(20))
    }
}

private func waitForSessionDisconnectCalls(
    _ connector: BlockingFirstSessionConnectionClient,
    expectedCount: Int,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if await connector.disconnectCalls() >= expectedCount {
            return
        }

        try? await Task.sleep(for: .milliseconds(20))
    }
}
