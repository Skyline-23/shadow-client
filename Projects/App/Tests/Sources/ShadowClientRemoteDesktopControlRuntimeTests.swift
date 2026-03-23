import Foundation
import Testing
import ShadowClientFeatureSession
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
            "stream-host.example.invalid": .init(
                host: "stream-host.example.invalid",
                displayName: "Example-PC",
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
            "stream-host.example.invalid": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: FakeControlClient()
    )

    runtime.selectHost("stream-host.example.invalid")
    runtime.refreshHosts(candidates: ["stream-host.example.invalid"])
    await waitForControlHostLoaded(runtime)

    #expect(runtime.selectedHostID == "uniqueid:host-12")
    #expect(runtime.selectedHost?.host == "stream-host.example.invalid")
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

@Test("Remote desktop runtime wakes the selected host through injected WOL client")
@MainActor
func remoteDesktopRuntimeWakesSelectedHost() async {
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
                uniqueID: "HOST-WOL-1",
                macAddress: "AA:BB:CC:DD:EE:FF"
            ),
        ],
        appListByHost: [:]
    )
    let wakeOnLANClient = FakeWakeOnLANClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: FakeControlClient(),
        wakeOnLANClient: wakeOnLANClient
    )

    runtime.refreshHosts(candidates: ["192.168.0.20"], preferredHost: "192.168.0.20")
    await waitForControlHostLoaded(runtime)

    runtime.wakeSelectedHost(macAddress: "AA:BB:CC:DD:EE:FF", port: 9)
    await waitForWakeState(runtime)

    #expect(await wakeOnLANClient.calls() == [
        .init(macAddress: "AA:BB:CC:DD:EE:FF", port: 9),
    ])
    #expect(runtime.selectedHostWakeState == .sent("Sent 3 magic packets on UDP 9."))
}

@Test("Remote desktop runtime prefers local route for app queries when a manual route is also present")
@MainActor
func remoteDesktopRuntimePrefersLocalRouteForAppQueries() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "wifi-route.example.invalid": .init(
                host: "wifi-route.example.invalid",
                localHost: "192.168.0.20",
                remoteHost: "wifi-route.example.invalid",
                manualHost: "wifi-route.example.invalid",
                displayName: "LivingRoom-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-LOCAL-FIRST"
            ),
            "192.168.0.20": .init(
                host: "192.168.0.20",
                localHost: "192.168.0.20",
                remoteHost: "wifi-route.example.invalid",
                manualHost: "wifi-route.example.invalid",
                displayName: "LivingRoom-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-LOCAL-FIRST"
            ),
        ],
        appListByHost: [
            "192.168.0.20": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: FakeControlClient()
    )

    runtime.refreshHosts(
        candidates: ["wifi-route.example.invalid", "192.168.0.20"],
        preferredHost: "wifi-route.example.invalid"
    )
    await waitForControlHostLoaded(runtime)
    runtime.refreshSelectedHostApps()
    await waitForAppCatalogLoaded(runtime)

    #expect(runtime.selectedHost?.host == "192.168.0.20")
    #expect(await metadata.recordedAppListHosts().last == "192.168.0.20")
}

@Test("Remote desktop runtime loads Apollo admin profile for the selected host")
@MainActor
func remoteDesktopRuntimeLoadsApolloAdminProfileForSelectedHost() async {
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
    let adminClient = FakeApolloAdminClient(
        profile: .init(
            name: "Current Device",
            uuid: "CURRENT-UUID",
            displayModeOverride: "2560x1440x120",
            permissions: 65535,
            enableLegacyOrdering: true,
            allowClientCommands: true,
            alwaysUseVirtualDisplay: true,
            connected: true
        )
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: FakeControlClient(),
        apolloAdminClient: adminClient
    )

    runtime.refreshHosts(candidates: ["192.168.0.20"], preferredHost: "192.168.0.20")
    await waitForControlHostLoaded(runtime)

    runtime.refreshSelectedHostApolloAdmin(username: "apollo", password: "secret")
    await waitForApolloAdminState(runtime)

    #expect(runtime.selectedHostApolloAdminState == .loaded)
    #expect(
        runtime.selectedHostApolloAdminProfile == .init(
            name: "Current Device",
            uuid: "CURRENT-UUID",
            displayModeOverride: "2560x1440x120",
            permissions: 65535,
            enableLegacyOrdering: true,
            allowClientCommands: true,
            alwaysUseVirtualDisplay: true,
            connected: true
        )
    )
}

@Test("Remote desktop runtime updates Apollo admin profile for the selected host")
@MainActor
func remoteDesktopRuntimeUpdatesApolloAdminProfileForSelectedHost() async {
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
    let initialProfile = ShadowClientApolloAdminClientProfile(
        name: "Current Device",
        uuid: "CURRENT-UUID",
        displayModeOverride: "",
        permissions: 65535,
        enableLegacyOrdering: true,
        allowClientCommands: true,
        alwaysUseVirtualDisplay: false,
        connected: true
    )
    let adminClient = FakeApolloAdminClient(profile: initialProfile)
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: FakeControlClient(),
        apolloAdminClient: adminClient
    )

    runtime.refreshHosts(candidates: ["192.168.0.20"], preferredHost: "192.168.0.20")
    await waitForControlHostLoaded(runtime)

    runtime.refreshSelectedHostApolloAdmin(username: "apollo", password: "secret")
    await waitForApolloAdminState(runtime)

    runtime.updateSelectedHostApolloAdmin(
        username: "apollo",
        password: "secret",
        displayModeOverride: "2560x1440x120",
        alwaysUseVirtualDisplay: true,
        permissions: 65535
    )
    await waitForApolloAdminState(runtime)

    #expect(runtime.selectedHostApolloAdminState == .loaded)
    #expect(
        runtime.selectedHostApolloAdminProfile == .init(
            name: "Current Device",
            uuid: "CURRENT-UUID",
            displayModeOverride: "2560x1440x120",
            permissions: 65535,
            enableLegacyOrdering: true,
            allowClientCommands: true,
            alwaysUseVirtualDisplay: true,
            connected: true
        )
    )
}

@Test("Remote desktop runtime disconnects the selected Apollo client")
@MainActor
func remoteDesktopRuntimeDisconnectsSelectedApolloClient() async {
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
    let initialProfile = ShadowClientApolloAdminClientProfile(
        name: "Current Device",
        uuid: "CURRENT-UUID",
        displayModeOverride: "",
        permissions: 65535,
        enableLegacyOrdering: true,
        allowClientCommands: true,
        alwaysUseVirtualDisplay: false,
        connected: true
    )
    let adminClient = FakeApolloAdminClient(profile: initialProfile)
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: FakeControlClient(),
        apolloAdminClient: adminClient
    )

    runtime.refreshHosts(candidates: ["192.168.0.20"], preferredHost: "192.168.0.20")
    await waitForControlHostLoaded(runtime)
    runtime.refreshSelectedHostApolloAdmin(username: "apollo", password: "secret")
    await waitForApolloAdminState(runtime)

    runtime.disconnectSelectedHostApolloAdmin(username: "apollo", password: "secret")
    await waitForApolloAdminState(runtime)

    #expect(runtime.selectedHostApolloAdminState == .loaded)
    #expect(runtime.selectedHostApolloAdminProfile?.connected == false)
}

@Test("Remote desktop runtime unpairs the selected Apollo client")
@MainActor
func remoteDesktopRuntimeUnpairsSelectedApolloClient() async {
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
    let initialProfile = ShadowClientApolloAdminClientProfile(
        name: "Current Device",
        uuid: "CURRENT-UUID",
        displayModeOverride: "",
        permissions: 65535,
        enableLegacyOrdering: true,
        allowClientCommands: true,
        alwaysUseVirtualDisplay: false,
        connected: true
    )
    let adminClient = FakeApolloAdminClient(profile: initialProfile)
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: FakeControlClient(),
        apolloAdminClient: adminClient
    )

    runtime.refreshHosts(candidates: ["192.168.0.20"], preferredHost: "192.168.0.20")
    await waitForControlHostLoaded(runtime)
    runtime.refreshSelectedHostApolloAdmin(username: "apollo", password: "secret")
    await waitForApolloAdminState(runtime)

    runtime.unpairSelectedHostApolloAdmin(username: "apollo", password: "secret")
    await waitForHostCatalogReadyAfterUnpair(runtime)

    #expect(runtime.selectedHostApolloAdminProfile == nil)
}

@Test("Remote desktop runtime surfaces Apollo launch permission denial")
@MainActor
func remoteDesktopRuntimeSurfacesApolloLaunchPermissionDenial() async {
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
    let control = FakeControlClient(
        simulatedLaunchFailure: ShadowClientGameStreamError.responseRejected(
            code: 403,
            message: "Permission denied"
        )
    )
    let runtime = ShadowClientRemoteDesktopRuntime(metadataClient: metadata, controlClient: control)

    runtime.refreshHosts(candidates: ["192.168.0.20"], preferredHost: "192.168.0.20")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    if case let .failed(message) = runtime.launchState {
        #expect(message == "Apollo denied Launch Apps permission for this paired client.")
    } else {
        Issue.record("Expected failed launch state, got \(runtime.launchState)")
    }
}

@Test("Remote desktop runtime forwards server app version into session video configuration")
@MainActor
func remoteDesktopRuntimeForwardsServerAppVersionToSessionConfiguration() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.24": .init(
                host: "192.168.0.24",
                displayName: "Versioned-Host",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.1.450.0",
                gfeVersion: nil,
                uniqueID: "HOST-VERSION"
            ),
        ],
        appListByHost: [
            "192.168.0.24": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(
            sessionURL: "rtsp://192.168.0.24:48010/session",
            verb: "launch"
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
        appID: 1,
        settings: .init(
            preferredCodec: .auto,
            enableHDR: true,
            enableSurroundAudio: true,
            lowLatencyMode: false
        )
    )
    await waitForLaunchState(runtime)

    let latestConfiguration = await sessionConnector.latestVideoConfiguration()
    #expect(latestConfiguration?.serverAppVersion == "7.1.450.0")
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
    let remoteInputKeyID: UInt32 = 0x1234_ABCD
    let control = FakeControlClient(
        simulatedLaunchResult: .init(
            sessionURL: "rtsp://192.168.0.24:48010/session",
            verb: "launch",
            remoteInputKey: remoteInputKey,
            remoteInputKeyID: remoteInputKeyID
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
    #expect(capturedConfiguration?.remoteInputKeyID == remoteInputKeyID)
}

@Test("Remote desktop runtime rewrites private host-provided session URL to the active WAN host")
@MainActor
func remoteDesktopRuntimeRewritesPrivateHostProvidedSessionURLForWANRoute() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "stream-host.example.invalid": .init(
                host: "stream-host.example.invalid",
                displayName: "Example-PC",
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
            "stream-host.example.invalid": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.10.52:48010", verb: "resume")
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["stream-host.example.invalid"], preferredHost: "stream-host.example.invalid")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 881_448_767,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    #expect(await sessionConnector.connectCalls() == ["rtsp://stream-host.example.invalid:48010"])
    #expect(runtime.activeSession?.sessionURL == "rtsp://stream-host.example.invalid:48010")
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
            "stream-host.example.invalid": .init(
                host: "stream-host.example.invalid",
                displayName: "Example-PC",
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
            "stream-host.example.invalid": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let resumeSessionURL = "rtsp://192.168.10.52:48010/resume"
    let forcedLaunchSessionURL = "rtsp://192.168.10.52:48010/launch"
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

    runtime.refreshHosts(candidates: ["stream-host.example.invalid"], preferredHost: "stream-host.example.invalid")
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

@Test("Remote desktop runtime preserves raw RTSP session URL while connecting through the active route")
@MainActor
func remoteDesktopRuntimePreservesRawRTSPSessionURLWhileConnectingThroughActiveRoute() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "test-wan.example.invalid": .init(
                host: "test-wan.example.invalid",
                localHost: "192.168.10.52",
                remoteHost: "test-wan.example.invalid",
                manualHost: "test-wan.example.invalid",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-RTSP-ROUTE"
            ),
            "192.168.10.52": .init(
                host: "192.168.10.52",
                localHost: "192.168.10.52",
                remoteHost: "test-wan.example.invalid",
                manualHost: "test-wan.example.invalid",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-RTSP-ROUTE"
            ),
        ],
        appListByHost: [
            "test-wan.example.invalid": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.10.52:48010", verb: "launch")
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(
        candidates: ["test-wan.example.invalid", "192.168.10.52"],
        preferredHost: "test-wan.example.invalid"
    )
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 881_448_767,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    #expect(await sessionConnector.connectCalls() == ["rtsp://192.168.10.52:48010"])
    #expect(await sessionConnector.connectHosts() == ["test-wan.example.invalid"])
    #expect(runtime.activeSession?.sessionURL == "rtsp://192.168.10.52:48010")
}

@Test("Remote desktop runtime does not forceLaunch retry for deterministic RTSP setup 404 failure")
@MainActor
func remoteDesktopRuntimeDoesNotForceLaunchRetryForRTSPSetup404() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "stream-host.example.invalid": .init(
                host: "stream-host.example.invalid",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 881_448_767,
                serverState: "SUNSHINE_SERVER_BUSY",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-RTSP-404"
            ),
        ],
        appListByHost: [
            "stream-host.example.invalid": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let resumeSessionURL = "rtsp://192.168.10.52:48010/resume"
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: resumeSessionURL, verb: "resume")
    )
    let sessionConnector = FakeSessionConnectionClient(
        simulatedFailures: [
            ShadowClientGameStreamError.requestFailed("RTSP SETUP failed (404):"),
        ]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["stream-host.example.invalid"], preferredHost: "stream-host.example.invalid")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 881_448_767,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    #expect(await sessionConnector.connectCalls() == [resumeSessionURL])
    let calls = await control.launchCalls()
    #expect(calls.count == 1)
    #expect(calls[0].forceLaunch == false)
    if case .failed = runtime.launchState {
        #expect(true)
    } else {
        Issue.record("Expected failed state without forceLaunch retry, got \(runtime.launchState)")
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

@Test("Remote desktop runtime falls back from AV1 to H265 when AV1 runtime recovery is exhausted")
@MainActor
func remoteDesktopRuntimeFallsBackCodecAfterAv1RuntimeRecoveryFailure() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.33": .init(
                host: "192.168.0.33",
                displayName: "AV1-Runtime-Host",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-AV1-RUNTIME"
            ),
        ],
        appListByHost: [
            "192.168.0.33": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let sessionURL = "rtsp://192.168.0.33:48010/session"
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: sessionURL, verb: "launch")
    )
    let sessionConnector = FakeSessionConnectionClient(
        simulatedFailures: [
            ShadowClientGameStreamError.requestFailed(
                "AV1 decode failed (decoder recovery exhausted). Runtime recovery exhausted; retry with fallback codec."
            ),
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

    #expect(await sessionConnector.connectCalls() == [sessionURL, sessionURL])
    #expect(await sessionConnector.disconnectCalls() >= 1)
    let codecHistory = await sessionConnector.videoConfigurations().map(\.preferredCodec)
    #expect(codecHistory == [.av1, .h265])
    if case .launched = runtime.launchState {
        #expect(true)
    } else {
        Issue.record("Expected launched state, got \(runtime.launchState)")
    }
}

@Test("Remote desktop runtime retries launch on reachable local route after external connection refused")
@MainActor
func remoteDesktopRuntimeRetriesLaunchOnReachableLocalRoute() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "external-route.example.invalid": .init(
                host: "external-route.example.invalid",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-ROUTE"
            ),
            "192.168.10.52": .init(
                host: "192.168.10.52",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-ROUTE"
            ),
        ],
        appListByHost: [
            "external-route.example.invalid": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
            "192.168.10.52": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.10.52:48010/session", verb: "launch"),
        simulatedLaunchFailures: [
            ShadowClientGameStreamError.requestFailed("Connection refused")
        ]
    )
    let sessionConnector = FakeSessionConnectionClient()
    let pairingRouteStore = ShadowClientPairingRouteStore(
        defaultsSuiteName: "shadow-client.control.route-fallback.\(UUID().uuidString)"
    )
    await pairingRouteStore.setPreferredHost("external-route.example.invalid", for: "uniqueid:host-route")

    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector,
        pairingRouteStore: pairingRouteStore
    )

    runtime.refreshHosts(
        candidates: ["external-route.example.invalid", "192.168.10.52"],
        preferredHost: "external-route.example.invalid"
    )
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 881_448_767,
        settings: .init(enableHDR: false, enableSurroundAudio: false, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    let launchCalls = await control.launchCalls()
    #expect(launchCalls.count == 2)
    #expect(launchCalls[0].host == "external-route.example.invalid")
    #expect(launchCalls[1].host == "192.168.10.52")
    if case .launched = runtime.launchState {
        #expect(true)
    } else {
        Issue.record("Expected launched state after local route retry, got \(runtime.launchState)")
    }
}

@Test("Remote desktop runtime auto-relaunches with downgraded codec after post-launch decoder failure")
@MainActor
func remoteDesktopRuntimeAutoRelaunchesCodecAfterPostLaunchDecoderFailure() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.133": .init(
                host: "192.168.0.133",
                displayName: "Codec-Recovery-Host",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-CODEC-RECOVERY"
            ),
        ],
        appListByHost: [
            "192.168.0.133": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let sessionURL = "rtsp://192.168.0.133:48010/session"
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: sessionURL, verb: "launch")
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.133"], preferredHost: "192.168.0.133")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(
            preferredCodec: .auto,
            enableHDR: true,
            enableSurroundAudio: true,
            lowLatencyMode: false
        )
    )
    await waitForLaunchState(runtime)

    runtime.handleSessionRenderStateTransition(
        .failed("AV1 decode failed (decoder recovery exhausted). Runtime recovery exhausted; retry with fallback codec.")
    )

    await waitForLaunchCalls(control, expectedCount: 2)
    await waitForLaunchState(runtime, maxAttempts: 200)

    let launchCalls = await control.launchCalls()
    #expect(launchCalls.count == 2)
    #expect(launchCalls[0].settings.preferredCodec == .auto)
    #expect(launchCalls[1].settings.preferredCodec == .h264)
    #expect(launchCalls[1].forceLaunch == true)

    let codecHistory = await sessionConnector.videoConfigurations().map(\.preferredCodec)
    #expect(codecHistory == [.auto, .h264])
}

@Test("Remote desktop runtime auto-reconnects stream after runtime transport inactivity without codec downgrade")
@MainActor
func remoteDesktopRuntimeAutoReconnectsStreamAfterTransportInactivity() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.153": .init(
                host: "192.168.0.153",
                displayName: "Transport-Reconnect-Host",
                pairStatus: .paired,
                currentGameID: 881_448_767,
                serverState: "SUNSHINE_SERVER_BUSY",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-TRANSPORT-RECOVERY"
            ),
        ],
        appListByHost: [
            "192.168.0.153": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let sessionURL = "rtsp://192.168.0.153:48010/session"
    let control = FakeControlClient(
        simulatedLaunchResults: [
            .init(sessionURL: sessionURL, verb: "launch"),
            .init(sessionURL: sessionURL, verb: "resume"),
        ]
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.153"], preferredHost: "192.168.0.153")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 881_448_767,
        settings: .init(
            preferredCodec: .h265,
            enableHDR: true,
            enableSurroundAudio: true,
            lowLatencyMode: true
        )
    )
    await waitForLaunchState(runtime)

    runtime.handleSessionRenderStateTransition(
        .failed("RTSP UDP video receive inactive; reconnect required")
    )

    await waitForLaunchCalls(control, expectedCount: 2)
    await waitForLaunchState(runtime, maxAttempts: 200)

    let launchCalls = await control.launchCalls()
    #expect(launchCalls.count == 2)
    #expect(launchCalls[0].forceLaunch == false)
    #expect(launchCalls[1].forceLaunch == false)
    #expect(launchCalls[0].settings.preferredCodec == .h265)
    #expect(launchCalls[1].settings.preferredCodec == .h265)

    let codecHistory = await sessionConnector.videoConfigurations().map(\.preferredCodec)
    #expect(codecHistory == [.h265, .h265])
}

@Test("Remote desktop runtime reconnects HEVC after runtime recovery exhaustion without codec downgrade")
@MainActor
func remoteDesktopRuntimeReconnectsHEVCAfterRuntimeRecoveryExhaustion() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.155": .init(
                host: "192.168.0.155",
                displayName: "HEVC-Recovery-Reconnect-Host",
                pairStatus: .paired,
                currentGameID: 881_448_767,
                serverState: "SUNSHINE_SERVER_BUSY",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-HEVC-RECOVERY-RECONNECT"
            ),
        ],
        appListByHost: [
            "192.168.0.155": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let sessionURL = "rtsp://192.168.0.155:48010/session"
    let control = FakeControlClient(
        simulatedLaunchResults: [
            .init(sessionURL: sessionURL, verb: "launch"),
            .init(sessionURL: sessionURL, verb: "resume"),
        ]
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.155"], preferredHost: "192.168.0.155")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 881_448_767,
        settings: .init(
            preferredCodec: .h265,
            enableHDR: true,
            enableSurroundAudio: true,
            lowLatencyMode: true
        )
    )
    await waitForLaunchState(runtime)

    runtime.handleSessionRenderStateTransition(
        .failed("HEVC runtime recovery exhausted (decoder-output-stall-exhausted). Runtime recovery exhausted; retry with H.264.")
    )

    await waitForLaunchCalls(control, expectedCount: 2)
    await waitForLaunchState(runtime, maxAttempts: 200)

    let launchCalls = await control.launchCalls()
    #expect(launchCalls.count == 2)
    #expect(launchCalls[0].forceLaunch == false)
    #expect(launchCalls[1].forceLaunch == false)
    #expect(launchCalls[0].settings.preferredCodec == .h265)
    #expect(launchCalls[1].settings.preferredCodec == .h265)

    let codecHistory = await sessionConnector.videoConfigurations().map(\.preferredCodec)
    #expect(codecHistory == [.h265, .h265])
}

@Test("Remote desktop runtime downgrades codec instead of reconnecting on startup UDP video timeout")
@MainActor
func remoteDesktopRuntimeDowngradesCodecOnStartupUDPVideoTimeout() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.154": .init(
                host: "192.168.0.154",
                displayName: "AV1-Startup-Timeout-Host",
                pairStatus: .paired,
                currentGameID: 1,
                serverState: "SUNSHINE_SERVER_BUSY",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-AV1-STARTUP-TIMEOUT"
            ),
        ],
        appListByHost: [
            "192.168.0.154": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let sessionURL = "rtsp://192.168.0.154:48010/session"
    let control = FakeControlClient(
        simulatedLaunchResults: [
            .init(sessionURL: sessionURL, verb: "launch"),
            .init(sessionURL: sessionURL, verb: "launch"),
        ]
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.154"], preferredHost: "192.168.0.154")
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

    runtime.handleSessionRenderStateTransition(
        .failed("RTSP UDP video timeout: prolonged datagram inactivity after startup")
    )

    await waitForLaunchCalls(control, expectedCount: 2)
    await waitForLaunchState(runtime, maxAttempts: 200)

    let launchCalls = await control.launchCalls()
    #expect(launchCalls.count == 2)
    #expect(launchCalls[0].forceLaunch == false)
    #expect(launchCalls[1].forceLaunch == true)
    #expect(launchCalls[0].settings.preferredCodec == .av1)
    #expect(launchCalls[1].settings.preferredCodec == .h265)
}

@Test("Remote desktop runtime persists runtime fallback codec for subsequent auto launches")
@MainActor
func remoteDesktopRuntimePersistsRuntimeFallbackCodecForSubsequentAutoLaunches() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.143": .init(
                host: "192.168.0.143",
                displayName: "Codec-Recovery-Persist-Host",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-CODEC-PERSIST"
            ),
        ],
        appListByHost: [
            "192.168.0.143": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let sessionURL = "rtsp://192.168.0.143:48010/session"
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: sessionURL, verb: "launch")
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.143"], preferredHost: "192.168.0.143")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(
            preferredCodec: .auto,
            enableHDR: true,
            enableSurroundAudio: true,
            lowLatencyMode: false
        )
    )
    await waitForLaunchState(runtime)

    runtime.handleSessionRenderStateTransition(
        .failed("AV1 decode failed (decoder recovery exhausted). Runtime recovery exhausted; retry with fallback codec.")
    )
    await waitForLaunchCalls(control, expectedCount: 2)
    await waitForLaunchState(runtime, maxAttempts: 200)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(
            preferredCodec: .auto,
            enableHDR: true,
            enableSurroundAudio: true,
            lowLatencyMode: false
        )
    )
    await waitForLaunchCalls(control, expectedCount: 3)
    await waitForLaunchState(runtime, maxAttempts: 200)

    let codecHistory = await sessionConnector.videoConfigurations().map(\.preferredCodec)
    #expect(codecHistory == [.auto, .h264, .h264])
}

@Test("Remote desktop runtime downgrades codec for forceLaunch after resume decoder failures")
@MainActor
func remoteDesktopRuntimeDowngradesCodecOnForceLaunchAfterResumeDecoderFailures() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "stream-host.example.invalid": .init(
                host: "stream-host.example.invalid",
                displayName: "Example-PC",
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
            "stream-host.example.invalid": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let resumeSessionURL = "rtsp://192.168.10.52:48010/resume"
    let forcedLaunchSessionURL = "rtsp://192.168.10.52:48010/launch"
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

    runtime.refreshHosts(candidates: ["stream-host.example.invalid"], preferredHost: "stream-host.example.invalid")
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

@Test("Remote desktop runtime downgrades codec for forceLaunch after resume first-frame timeout")
@MainActor
func remoteDesktopRuntimeDowngradesCodecOnForceLaunchAfterResumeFirstFrameTimeout() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "stream-host.example.invalid": .init(
                host: "stream-host.example.invalid",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 881_448_767,
                serverState: "SUNSHINE_SERVER_BUSY",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-AV1-RESUME-TIMEOUT"
            ),
        ],
        appListByHost: [
            "stream-host.example.invalid": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let resumeSessionURL = "rtsp://192.168.10.52:48010/resume"
    let forcedLaunchSessionURL = "rtsp://192.168.10.52:48010/launch"
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: forcedLaunchSessionURL, verb: "launch"),
        simulatedLaunchResults: [
            .init(sessionURL: resumeSessionURL, verb: "resume"),
            .init(sessionURL: forcedLaunchSessionURL, verb: "launch"),
        ]
    )
    let sessionConnector = FakeSessionConnectionClient(
        simulatedFailures: [
            ShadowClientGameStreamError.requestFailed("Timed out waiting for first frame."),
        ]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["stream-host.example.invalid"], preferredHost: "stream-host.example.invalid")
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
        forcedLaunchSessionURL,
    ])
    let codecHistory = await sessionConnector.videoConfigurations().map(\.preferredCodec)
    #expect(codecHistory == [.av1, .h265])
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

@Test("Remote desktop runtime downgrades codec for forceLaunch after launch startup UDP timeout")
@MainActor
func remoteDesktopRuntimeDowngradesCodecOnForceLaunchAfterLaunchStartupUDPTimeout() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "stream-host.example.invalid": .init(
                host: "stream-host.example.invalid",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-AV1-LAUNCH-STARTUP-TIMEOUT"
            ),
        ],
        appListByHost: [
            "stream-host.example.invalid": [
                .init(id: 881_448_767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let initialSessionURL = "rtsp://192.168.10.52:48010/launch-initial"
    let forcedLaunchSessionURL = "rtsp://192.168.10.52:48010/launch-fallback"
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: forcedLaunchSessionURL, verb: "launch"),
        simulatedLaunchResults: [
            .init(sessionURL: initialSessionURL, verb: "launch"),
            .init(sessionURL: forcedLaunchSessionURL, verb: "launch"),
        ]
    )
    let sessionConnector = FakeSessionConnectionClient(
        simulatedFailure: ShadowClientRealtimeSessionRuntimeError.transportFailure(
            .udpVideoNoStartupDatagrams
        )
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["stream-host.example.invalid"], preferredHost: "stream-host.example.invalid")
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
        initialSessionURL,
        forcedLaunchSessionURL,
    ])
    let codecHistory = await sessionConnector.videoConfigurations().map(\.preferredCodec)
    #expect(codecHistory == [.av1, .h265])
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

@Test("Remote desktop runtime appends AV1 compatibility guidance when first frame never renders")
@MainActor
func remoteDesktopRuntimeAddsAV1CompatibilityGuidanceOnFirstFrameTimeout() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.45": .init(
                host: "192.168.0.45",
                displayName: "AV1-Timeout-Host",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-AV1-TIMEOUT-HINT"
            ),
        ],
        appListByHost: [
            "192.168.0.45": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.45:48010/session", verb: "launch")
    )
    let sessionConnector = FakeSessionConnectionClient(
        simulatedFailure: ShadowClientGameStreamError.requestFailed("Timed out waiting for first frame.")
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.45"], preferredHost: "192.168.0.45")
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
        #expect(message.localizedCaseInsensitiveContains("first frame"))
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

@Test("Remote desktop runtime serializes relaunch after cancelling prior launch")
@MainActor
func remoteDesktopRuntimeSerializesRelaunchAfterCancellingPriorLaunch() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.36": .init(
                host: "192.168.0.36",
                displayName: "Arcade-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-12"
            ),
        ],
        appListByHost: [
            "192.168.0.36": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
                .init(id: 2, title: "Steam", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResults: [
            .init(sessionURL: "rtsp://192.168.0.36:48010/session-a", verb: "launch"),
            .init(sessionURL: "rtsp://192.168.0.36:48010/session-b", verb: "launch"),
        ]
    )
    let sessionConnector = SerializingLaunchSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.36"], preferredHost: "192.168.0.36")
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

    let disconnectCountsAtConnectStart = await sessionConnector.disconnectCountAtConnectStart()
    #expect(disconnectCountsAtConnectStart.count == 2)
    #expect(disconnectCountsAtConnectStart[0] == 1)
    #expect(disconnectCountsAtConnectStart[1] >= 3)
    #expect(await sessionConnector.disconnectCalls() >= 3)
    #expect(runtime.activeSession?.appID == 2)
}

@Test("Remote desktop runtime ignores duplicate launch requests while launch is already transitioning")
@MainActor
func remoteDesktopRuntimeIgnoresDuplicateLaunchRequestWhileTransitioning() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.37": .init(
                host: "192.168.0.37",
                displayName: "Den-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-13"
            ),
        ],
        appListByHost: [
            "192.168.0.37": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.37:48010/session", verb: "launch")
    )
    let sessionConnector = BlockingFirstSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.37"], preferredHost: "192.168.0.37")
    await waitForControlHostLoaded(runtime)

    let settings = ShadowClientGameStreamLaunchSettings(
        enableHDR: true,
        enableSurroundAudio: true,
        lowLatencyMode: false
    )
    runtime.launchSelectedApp(appID: 1, settings: settings)
    await waitForSessionConnectCalls(sessionConnector, expectedCount: 1)

    runtime.launchSelectedApp(appID: 1, settings: settings)
    try? await Task.sleep(for: .milliseconds(200))

    #expect(await control.launchCalls().count == 1)
    #expect(await sessionConnector.connectCalls().count == 1)
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

@Test("Remote desktop runtime uses Apollo clipboard action while a session is active")
@MainActor
func remoteDesktopRuntimeUsesClipboardActionForActiveSession() async {
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
                uniqueID: "HOST-CLIPBOARD"
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

    runtime.syncClipboard("hello apollo")
    await waitForClipboardCalls(control, expectedCount: 1)

    let clipboardCalls = await control.clipboardCalls()
    #expect(clipboardCalls == [
        .init(host: "192.168.0.28", httpsPort: 47984, text: "hello apollo")
    ])
    #expect(await sessionInput.inputCalls().isEmpty)
}

@Test("Remote desktop runtime cancels the active host session when clearing an active session")
@MainActor
func remoteDesktopRuntimeCancelsHostSessionWhenClearingActiveSession() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.28": .init(
                host: "192.168.0.28",
                displayName: "Loft-PC",
                pairStatus: .paired,
                currentGameID: 1,
                serverState: "SUNSHINE_SERVER_BUSY",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-CANCEL-1"
            ),
        ],
        appListByHost: [
            "192.168.0.28": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.28:48010/session", verb: "resume")
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.28"], preferredHost: "192.168.0.28")
    await waitForControlHostLoaded(runtime)
    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    runtime.clearActiveSession()
    await waitForCancelCalls(control, expectedCount: 1)

    #expect(await control.cancelCalls() == [
        .init(host: "192.168.0.28", httpsPort: 47984),
    ])
}

@Test("Remote desktop runtime still cancels the active host session when metadata already reports no running game")
@MainActor
func remoteDesktopRuntimeCancelsHostSessionWhenMetadataAlreadyLooksIdle() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.29": .init(
                host: "192.168.0.29",
                displayName: "Loft-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-CANCEL-2"
            ),
        ],
        appListByHost: [
            "192.168.0.29": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.29:48010/session", verb: "launch")
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.29"], preferredHost: "192.168.0.29")
    await waitForControlHostLoaded(runtime)
    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    runtime.clearActiveSession()
    await waitForCancelCalls(control, expectedCount: 1)

    #expect(await control.cancelCalls() == [
        .init(host: "192.168.0.29", httpsPort: 47984),
    ])
}

@Test("Remote desktop runtime does not fall back to text input when Apollo clipboard action fails")
@MainActor
func remoteDesktopRuntimeDoesNotFallbackToTextInputWhenClipboardActionFails() async {
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
                uniqueID: "HOST-CLIPBOARD"
            ),
        ],
        appListByHost: [
            "192.168.0.28": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.28:48010/session", verb: "launch"),
        simulatedClipboardFailure: ShadowClientGameStreamError.requestFailed("clipboard forbidden")
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

    runtime.syncClipboard("fallback text")
    await waitForClipboardCalls(control, expectedCount: 1)

    let clipboardCalls = await control.clipboardCalls()
    #expect(clipboardCalls.count == 1)
    let inputCalls = await sessionInput.inputCalls()
    #expect(inputCalls.isEmpty)
}

@Test("Remote desktop runtime surfaces clipboard write permission denial")
@MainActor
func remoteDesktopRuntimeSurfacesClipboardWritePermissionDenial() async {
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
                uniqueID: "HOST-CLIPBOARD"
            ),
        ],
        appListByHost: [
            "192.168.0.28": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.28:48010/session", verb: "launch"),
        simulatedClipboardFailure: ShadowClientGameStreamError.responseRejected(
            code: 401,
            message: "forbidden"
        )
    )
    let sessionConnector = FakeSessionConnectionClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector
    )

    runtime.refreshHosts(candidates: ["192.168.0.28"], preferredHost: "192.168.0.28")
    await waitForControlHostLoaded(runtime)
    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)

    runtime.syncClipboard("denied")
    await waitForClipboardCalls(control, expectedCount: 1)

    #expect(
        runtime.sessionIssue == .init(
            title: "Clipboard Permission Required",
            message: "Grant Clipboard Set permission for this paired Apollo client."
        )
    )
}

@Test("Remote desktop runtime copies Apollo host clipboard into the local clipboard")
@MainActor
func remoteDesktopRuntimePullsClipboardIntoLocalClipboard() async {
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
                uniqueID: "HOST-CLIPBOARD"
            ),
        ],
        appListByHost: [
            "192.168.0.28": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.28:48010/session", verb: "launch"),
        simulatedClipboardText: "copied from host"
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

    await MainActor.run {
        ShadowClientClipboardBridge.setString("")
    }
    runtime.pullClipboard()
    await waitForSessionInputCalls(sessionInput, expectedCount: 4)

    let clipboardText = await MainActor.run {
        ShadowClientClipboardBridge.currentString()
    }
    #expect(clipboardText == "copied from host")
}

@Test("Remote desktop runtime surfaces clipboard read permission denial")
@MainActor
func remoteDesktopRuntimeSurfacesClipboardReadPermissionDenial() async {
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
                uniqueID: "HOST-CLIPBOARD"
            ),
        ],
        appListByHost: [
            "192.168.0.28": [
                .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
            ],
        ]
    )
    let control = FakeControlClient(
        simulatedLaunchResult: .init(sessionURL: "rtsp://192.168.0.28:48010/session", verb: "launch"),
        simulatedClipboardFailure: ShadowClientGameStreamError.responseRejected(
            code: 401,
            message: "forbidden"
        )
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

    runtime.pullClipboard()
    await waitForSessionInputCalls(sessionInput, expectedCount: 4)

    #expect(
        runtime.sessionIssue == .init(
            title: "Clipboard Permission Required",
            message: "Grant Clipboard Read permission for this paired Apollo client."
        )
    )
}

@Test("Remote desktop runtime surfaces Apollo host termination as a recovery issue")
@MainActor
func remoteDesktopRuntimeSurfacesApolloHostTerminationIssue() async {
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: FakeControlTestMetadataClient(serverInfoByHost: [:], appListByHost: [:]),
        controlClient: FakeControlClient()
    )

    runtime.handleSessionRenderStateTransition(
        .disconnected("Apollo paused or closed the desktop session (0x80030023). This often happens when Windows shows a secure desktop, password prompt, or UAC dialog.")
    )

    #expect(
        runtime.sessionIssue == .init(
            title: "Host Desktop Paused",
            message: "Apollo paused or closed the desktop session (0x80030023). This often happens when Windows shows a secure desktop, password prompt, or UAC dialog.\nReturn to the normal Windows desktop, dismiss the secure prompt or popup, then launch the session again."
        )
    )
}

@Test("Remote desktop runtime sends keepalive when input stays idle during launched session")
@MainActor
func remoteDesktopRuntimeSendsInputKeepAliveWhenIdle() async {
    let metadata = FakeControlTestMetadataClient(
        serverInfoByHost: [
            "192.168.0.33": .init(
                host: "192.168.0.33",
                displayName: "Idle-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "7.0.0",
                gfeVersion: nil,
                uniqueID: "HOST-IDLE"
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
    let sessionConnector = FakeSessionConnectionClient()
    let sessionInput = FakeSessionInputClient()
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadata,
        controlClient: control,
        sessionConnectionClient: sessionConnector,
        sessionInputClient: sessionInput,
        inputKeepAliveInterval: .milliseconds(40)
    )

    runtime.refreshHosts(candidates: ["192.168.0.33"], preferredHost: "192.168.0.33")
    await waitForControlHostLoaded(runtime)

    runtime.launchSelectedApp(
        appID: 1,
        settings: .init(enableHDR: true, enableSurroundAudio: true, lowLatencyMode: false)
    )
    await waitForLaunchState(runtime)
    await waitForSessionInputKeepAliveCalls(sessionInput, expectedCount: 2, maxAttempts: 120)

    let keepAliveCalls = await sessionInput.keepAliveCalls()
    #expect(keepAliveCalls.count >= 2)
    #expect(keepAliveCalls.allSatisfy { $0.host == "192.168.0.33" })
    #expect(keepAliveCalls.allSatisfy { $0.sessionURL == "rtsp://192.168.0.33:48010/session" })
}

@Test("Remote desktop runtime forwards input in session flow using normalized RTSP URL")
@MainActor
func remoteDesktopRuntimeForwardsInputInSessionFlowWithNormalizedURL() async {
    let sessionInput = FakeSessionInputClient()
    let runtimeWithInput = ShadowClientRemoteDesktopRuntime(
        metadataClient: FakeControlTestMetadataClient(serverInfoByHost: [:], appListByHost: [:]),
        controlClient: FakeControlClient(),
        sessionInputClient: sessionInput
    )

    runtimeWithInput.openSessionFlow(host: "192.168.0.29", appTitle: "Remote Desktop")
    runtimeWithInput.sendInput(.keyDown(keyCode: 13, characters: "w"))
    await waitForSessionInputCalls(sessionInput, expectedCount: 1)

    let calls = await sessionInput.inputCalls()
    #expect(calls.count == 1)
    #expect(calls[0].host == "192.168.0.29")
    #expect(calls[0].sessionURL == "rtsp://192.168.0.29")
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

@Test("Remote desktop runtime tears down the local session on RTSP timeout failures")
@MainActor
func remoteDesktopRuntimeTearsDownLocalSessionOnRTSPTimeoutFailure() async {
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
                uniqueID: "HOST-RTSP-TIMEOUT"
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

    runtime.handleSessionRenderStateTransition(
        .failed("RTSP UDP video timeout: no video datagram received")
    )

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
    private var appListHosts: [String] = []

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
        appListHosts.append(host)
        return appListByHost[host] ?? []
    }

    func recordedAppListHosts() -> [String] {
        appListHosts
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

    struct ClipboardCall: Equatable {
        let host: String
        let httpsPort: Int
        let text: String
    }

    struct CancelCall: Equatable {
        let host: String
        let httpsPort: Int
    }

    private var recordedPairCalls: [PairCall] = []
    private var recordedLaunchCalls: [LaunchCall] = []
    private var recordedClipboardCalls: [ClipboardCall] = []
    private var recordedCancelCalls: [CancelCall] = []
    private var simulatedPairFailures: [any Error & Sendable]
    private var simulatedLaunchResults: [ShadowClientGameStreamLaunchResult]
    private var simulatedLaunchFailures: [any Error & Sendable]
    private let simulatedClipboardText: String?
    private let simulatedClipboardFailure: (any Error & Sendable)?
    private let defaultLaunchResult: ShadowClientGameStreamLaunchResult
    private let simulatedLaunchFailure: (any Error & Sendable)?

    init(
        simulatedPairFailures: [any Error & Sendable] = [],
        simulatedLaunchResult: ShadowClientGameStreamLaunchResult = .init(sessionURL: "rtsp://example/session", verb: "launch"),
        simulatedLaunchResults: [ShadowClientGameStreamLaunchResult] = [],
        simulatedLaunchFailures: [any Error & Sendable] = [],
        simulatedClipboardText: String? = nil,
        simulatedClipboardFailure: (any Error & Sendable)? = nil,
        simulatedLaunchFailure: (any Error & Sendable)? = nil
    ) {
        self.simulatedPairFailures = simulatedPairFailures
        self.simulatedLaunchResults = simulatedLaunchResults
        self.simulatedLaunchFailures = simulatedLaunchFailures
        self.simulatedClipboardText = simulatedClipboardText
        self.simulatedClipboardFailure = simulatedClipboardFailure
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

        if !simulatedLaunchFailures.isEmpty {
            let nextError = simulatedLaunchFailures.removeFirst()
            throw nextError
        }

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

    func setClipboard(
        host: String,
        httpsPort: Int,
        text: String
    ) async throws {
        recordedClipboardCalls.append(
            .init(host: host, httpsPort: httpsPort, text: text)
        )

        if let simulatedClipboardFailure {
            throw simulatedClipboardFailure
        }
    }

    func clipboardCalls() -> [ClipboardCall] {
        recordedClipboardCalls
    }

    func cancelActiveSession(
        host: String,
        httpsPort: Int
    ) async throws {
        recordedCancelCalls.append(.init(host: host, httpsPort: httpsPort))
    }

    func cancelCalls() -> [CancelCall] {
        recordedCancelCalls
    }

    func getClipboard(
        host: String,
        httpsPort: Int
    ) async throws -> String {
        if let simulatedClipboardFailure {
            throw simulatedClipboardFailure
        }
        return simulatedClipboardText ?? ""
    }
}

private actor FakeWakeOnLANClient: ShadowClientWakeOnLANClient {
    struct Call: Equatable {
        let macAddress: String
        let port: UInt16
    }

    private var recordedCalls: [Call] = []
    private let simulatedResultCount: Int

    init(simulatedResultCount: Int = 3) {
        self.simulatedResultCount = simulatedResultCount
    }

    func sendMagicPacket(macAddress: String, port: UInt16) async throws -> Int {
        recordedCalls.append(.init(macAddress: macAddress, port: port))
        return simulatedResultCount
    }

    func calls() -> [Call] {
        recordedCalls
    }
}

private actor FakeClipboardClient: ShadowClientClipboardClient {
    private var text: String?

    func currentString() async -> String? {
        text
    }

    func setString(_ value: String) async {
        text = value
    }
}

private actor FakeApolloAdminClient: ShadowClientApolloAdminClient {
    private var profile: ShadowClientApolloAdminClientProfile?

    init(profile: ShadowClientApolloAdminClientProfile?) {
        self.profile = profile
    }

    func fetchCurrentClientProfile(
        host: String,
        httpsPort: Int,
        username: String,
        password: String
    ) async throws -> ShadowClientApolloAdminClientProfile? {
        _ = host
        _ = httpsPort
        _ = username
        _ = password
        return profile
    }

    func updateCurrentClientProfile(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        profile: ShadowClientApolloAdminClientProfile
    ) async throws -> ShadowClientApolloAdminClientProfile {
        _ = host
        _ = httpsPort
        _ = username
        _ = password
        self.profile = profile
        return profile
    }

    func disconnectCurrentClient(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        uuid: String
    ) async throws {
        _ = host
        _ = httpsPort
        _ = username
        _ = password
        guard let profile, profile.uuid == uuid else {
            return
        }
        self.profile = .init(
            name: profile.name,
            uuid: profile.uuid,
            displayModeOverride: profile.displayModeOverride,
            permissions: profile.permissions,
            enableLegacyOrdering: profile.enableLegacyOrdering,
            allowClientCommands: profile.allowClientCommands,
            alwaysUseVirtualDisplay: profile.alwaysUseVirtualDisplay,
            connected: false,
            doCommands: profile.doCommands,
            undoCommands: profile.undoCommands
        )
    }

    func unpairCurrentClient(
        host: String,
        httpsPort: Int,
        username: String,
        password: String,
        uuid: String
    ) async throws {
        _ = host
        _ = httpsPort
        _ = username
        _ = password
        if profile?.uuid == uuid {
            profile = nil
        }
    }
}

private actor FakeSessionConnectionClient: ShadowClientRemoteSessionConnectionClient {
    let presentationMode: ShadowClientRemoteSessionPresentationMode = .embeddedPlayer
    nonisolated let sessionSurfaceContext: ShadowClientRealtimeSessionSurfaceContext = .init()

    private var recordedConnectCalls: [String] = []
    private var recordedConnectHosts: [String] = []
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
        recordedConnectHosts.append(host)
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

    func connectHosts() -> [String] {
        recordedConnectHosts
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

private actor SerializingLaunchSessionConnectionClient: ShadowClientRemoteSessionConnectionClient {
    let presentationMode: ShadowClientRemoteSessionPresentationMode = .embeddedPlayer
    nonisolated let sessionSurfaceContext: ShadowClientRealtimeSessionSurfaceContext = .init()

    private var connectCallCount = 0
    private var disconnectCallCount = 0
    private var disconnectCountSnapshotsAtConnectStart: [Int] = []

    func connect(
        to sessionURL: String,
        host: String,
        appTitle: String,
        videoConfiguration: ShadowClientRemoteSessionVideoConfiguration
    ) async throws {
        connectCallCount += 1
        disconnectCountSnapshotsAtConnectStart.append(disconnectCallCount)

        if connectCallCount == 1 {
            try await Task.sleep(for: .seconds(30))
        }
    }

    func disconnect() async {
        disconnectCallCount += 1
    }

    func connectCalls() -> Int {
        connectCallCount
    }

    func disconnectCalls() -> Int {
        disconnectCallCount
    }

    func disconnectCountAtConnectStart() -> [Int] {
        disconnectCountSnapshotsAtConnectStart
    }
}

private actor FakeSessionInputClient: ShadowClientRemoteSessionInputClient {
    struct InputCall: Equatable {
        let event: ShadowClientRemoteInputEvent
        let host: String
        let sessionURL: String
    }

    struct KeepAliveCall: Equatable {
        let host: String
        let sessionURL: String
    }

    private var recordedInputCalls: [InputCall] = []
    private var recordedKeepAliveCalls: [KeepAliveCall] = []

    func send(event: ShadowClientRemoteInputEvent, host: String, sessionURL: String) async throws {
        recordedInputCalls.append(
            .init(event: event, host: host, sessionURL: sessionURL)
        )
    }

    func sendKeepAlive(host: String, sessionURL: String) async throws {
        recordedKeepAliveCalls.append(
            .init(host: host, sessionURL: sessionURL)
        )
    }

    func inputCalls() -> [InputCall] {
        recordedInputCalls
    }

    func keepAliveCalls() -> [KeepAliveCall] {
        recordedKeepAliveCalls
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
        if runtime.pairingState.isInProgress {
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

private func waitForWakeState(
    _ runtime: ShadowClientRemoteDesktopRuntime,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        switch runtime.selectedHostWakeState {
        case .sent, .failed:
            return
        case .idle, .sending:
            break
        }
        await Task.yield()
    }
}

@MainActor
private func waitForAppCatalogLoaded(
    _ runtime: ShadowClientRemoteDesktopRuntime,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if runtime.appState == .loaded {
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

private func waitForSessionConnectCalls(
    _ connector: SerializingLaunchSessionConnectionClient,
    expectedCount: Int,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if await connector.connectCalls() >= expectedCount {
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

private func waitForClipboardCalls(
    _ controlClient: FakeControlClient,
    expectedCount: Int,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if await controlClient.clipboardCalls().count >= expectedCount {
            return
        }

        try? await Task.sleep(for: .milliseconds(20))
    }
}

private func waitForCancelCalls(
    _ controlClient: FakeControlClient,
    expectedCount: Int,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if await controlClient.cancelCalls().count >= expectedCount {
            return
        }

        try? await Task.sleep(for: .milliseconds(20))
    }
}

private func waitForClipboardText(
    _ clipboardClient: FakeClipboardClient,
    expected: String,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if await clipboardClient.currentString() == expected {
            return
        }
        try? await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
private func waitForApolloAdminState(
    _ runtime: ShadowClientRemoteDesktopRuntime,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        switch runtime.selectedHostApolloAdminState {
        case .loading, .saving:
            break
        case .idle, .loaded, .failed:
            return
        }

        try? await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
private func waitForHostCatalogReadyAfterUnpair(
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

private func waitForSessionInputKeepAliveCalls(
    _ inputClient: FakeSessionInputClient,
    expectedCount: Int,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if await inputClient.keepAliveCalls().count >= expectedCount {
            return
        }

        try? await Task.sleep(for: .milliseconds(20))
    }
}

private func waitForLaunchCalls(
    _ control: FakeControlClient,
    expectedCount: Int,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if await control.launchCalls().count >= expectedCount {
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
