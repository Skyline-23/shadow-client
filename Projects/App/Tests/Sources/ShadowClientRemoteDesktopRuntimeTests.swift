import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("GameStream parser maps serverinfo XML into host descriptor source")
func gameStreamParserMapsServerInfoXML() throws {
    let xml = """
    <root status_code="200" status_message="OK">
      <hostname>LivingRoom-PC</hostname>
      <PairStatus>1</PairStatus>
      <currentgame>0</currentgame>
      <state>SUNSHINE_SERVER_FREE</state>
      <HttpsPort>47984</HttpsPort>
      <appversion>1.2.3</appversion>
      <GfeVersion>3.26.0.131</GfeVersion>
      <uniqueid>HOST-123</uniqueid>
    </root>
    """

    let info = try ShadowClientGameStreamXMLParsers.parseServerInfo(
        xml: xml,
        host: "192.168.0.10",
        fallbackHTTPSPort: 47984
    )

    #expect(info.host == "192.168.0.10")
    #expect(info.displayName == "LivingRoom-PC")
    #expect(info.pairStatus == .paired)
    #expect(info.currentGameID == 0)
    #expect(info.serverState == "SUNSHINE_SERVER_FREE")
    #expect(info.httpsPort == 47984)
    #expect(info.appVersion == "1.2.3")
    #expect(info.gfeVersion == "3.26.0.131")
    #expect(info.uniqueID == "HOST-123")
}

@Test("GameStream parser normalizes stale currentgame when server state is free")
func gameStreamParserNormalizesStaleCurrentGameInFreeState() throws {
    let xml = """
    <root status_code="200" status_message="OK">
      <hostname>Example-PC</hostname>
      <PairStatus>1</PairStatus>
      <currentgame>881448767</currentgame>
      <state>SUNSHINE_SERVER_FREE</state>
      <HttpsPort>47984</HttpsPort>
    </root>
    """

    let info = try ShadowClientGameStreamXMLParsers.parseServerInfo(
        xml: xml,
        host: "192.168.0.10",
        fallbackHTTPSPort: 47984
    )

    #expect(info.currentGameID == 0)
}

@Test("GameStream parser falls back to host when hostname is unknown placeholder")
func gameStreamParserFallsBackToHostForUnknownPlaceholderName() throws {
    let xml = """
    <root status_code="200" status_message="OK">
      <hostname>Unknown name</hostname>
      <PairStatus>1</PairStatus>
      <currentgame>0</currentgame>
      <state>SUNSHINE_SERVER_FREE</state>
      <HttpsPort>47984</HttpsPort>
    </root>
    """

    let info = try ShadowClientGameStreamXMLParsers.parseServerInfo(
        xml: xml,
        host: "192.168.0.22",
        fallbackHTTPSPort: 47984
    )

    #expect(info.displayName == "192.168.0.22")
}

@Test("GameStream parser preserves currentgame when server state is busy")
func gameStreamParserPreservesCurrentGameInBusyState() throws {
    let xml = """
    <root status_code="200" status_message="OK">
      <hostname>Example-PC</hostname>
      <PairStatus>1</PairStatus>
      <currentgame>881448767</currentgame>
      <state>SUNSHINE_SERVER_BUSY</state>
      <HttpsPort>47984</HttpsPort>
    </root>
    """

    let info = try ShadowClientGameStreamXMLParsers.parseServerInfo(
        xml: xml,
        host: "192.168.0.10",
        fallbackHTTPSPort: 47984
    )

    #expect(info.currentGameID == 881_448_767)
}

@Test("GameStream parser rejects non-200 root status")
func gameStreamParserRejectsRejectedResponseXML() {
    let xml = """
    <root status_code="401" status_message="Not paired"></root>
    """

    do {
        _ = try ShadowClientGameStreamXMLParsers.parseServerInfo(
            xml: xml,
            host: "192.168.0.11",
            fallbackHTTPSPort: 47984
        )
        Issue.record("Expected parse failure for non-200 response")
    } catch let error as ShadowClientGameStreamError {
        #expect(error == .responseRejected(code: 401, message: "Not paired"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}

@Test("GameStream parser maps applist XML")
func gameStreamParserMapsAppListXML() throws {
    let xml = """
    <root status_code="200" status_message="OK">
      <App>
        <AppTitle>Desktop</AppTitle>
        <ID>1</ID>
        <IsHdrSupported>1</IsHdrSupported>
        <IsAppCollectorGame>0</IsAppCollectorGame>
      </App>
      <App>
        <AppTitle>Steam Big Picture</AppTitle>
        <ID>2</ID>
        <IsHdrSupported>0</IsHdrSupported>
        <IsAppCollectorGame>1</IsAppCollectorGame>
      </App>
    </root>
    """

    let apps = try ShadowClientGameStreamXMLParsers.parseAppList(xml: xml)

    #expect(apps.count == 2)
    #expect(apps[0] == .init(id: 1, title: "Desktop", hdrSupported: true, isAppCollectorGame: false))
    #expect(apps[1] == .init(id: 2, title: "Steam Big Picture", hdrSupported: false, isAppCollectorGame: true))
}

@Test("GameStream parser maps applist XML when App payload uses attributes")
func gameStreamParserMapsAttributeBasedAppListXML() throws {
    let xml = """
    <root status_code="200" status_message="OK">
      <App AppTitle="Desktop" ID="881448767" IsHdrSupported="1" IsAppCollectorGame="0" />
      <App AppTitle="Steam Big Picture" ID="1093255277" IsHdrSupported="1" />
    </root>
    """

    let apps = try ShadowClientGameStreamXMLParsers.parseAppList(xml: xml)

    #expect(apps.count == 2)
    #expect(apps[0] == .init(id: 881448767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false))
    #expect(apps[1] == .init(id: 1093255277, title: "Steam Big Picture", hdrSupported: true, isAppCollectorGame: false))
}

@Test("GameStream parser maps Sunshine applist XML without status_message")
func gameStreamParserMapsSunshineAppListWithoutStatusMessage() throws {
    let xml = """
    <?xml version="1.0" encoding="utf-8"?>
    <root status_code="200">
      <App>
        <IsHdrSupported>1</IsHdrSupported>
        <AppTitle>Desktop</AppTitle>
        <ID>881448767</ID>
      </App>
      <App>
        <IsHdrSupported>1</IsHdrSupported>
        <AppTitle>Steam Big Picture</AppTitle>
        <ID>1093255277</ID>
      </App>
    </root>
    """

    let apps = try ShadowClientGameStreamXMLParsers.parseAppList(xml: xml)

    #expect(apps.count == 2)
    #expect(apps[0] == .init(id: 881448767, title: "Desktop", hdrSupported: true, isAppCollectorGame: false))
    #expect(apps[1] == .init(id: 1093255277, title: "Steam Big Picture", hdrSupported: true, isAppCollectorGame: false))
}

@Test("Metadata client uses HTTP first for unpinned hosts")
func metadataClientUsesHTTPFirstForUnpinnedHosts() async throws {
    let defaultsSuite = "shadow-client.metadata.serverinfo.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let transport = ScriptedRequestTransport(
        script: [
            .init(
                scheme: "http",
                command: "serverinfo",
                result: .success(
                    """
                    <root status_code="200">
                        <hostname>Example-PC</hostname>
                        <PairStatus>0</PairStatus>
                        <currentgame>0</currentgame>
                        <state>SUNSHINE_SERVER_FREE</state>
                        <HttpsPort>47984</HttpsPort>
                    </root>
                    """
                )
            ),
        ]
    )

    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: defaultsSuite),
        pinnedCertificateStore: .init(defaultsSuiteName: defaultsSuite),
        transport: transport
    )

    let info = try await client.fetchServerInfo(host: "stream-host.example.invalid")
    #expect(info.displayName == "Example-PC")
    #expect(info.pairStatus == .notPaired)

    #expect(
        await transport.calls() == [
            .init(scheme: "http", command: "serverinfo"),
        ]
    )
}

@Test("Metadata client uses HTTPS first for pinned hosts")
func metadataClientUsesHTTPSFirstForPinnedHosts() async throws {
    let defaultsSuite = "shadow-client.metadata.serverinfo.pinned-https-success.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pinnedStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: defaultsSuite)
    await pinnedStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "stream-host.example.invalid")

    let transport = ScriptedRequestTransport(
        script: [
            .init(
                scheme: "https",
                command: "serverinfo",
                result: .success(
                    """
                    <root status_code="200">
                        <hostname>Example-PC</hostname>
                        <PairStatus>1</PairStatus>
                        <currentgame>0</currentgame>
                        <state>SUNSHINE_SERVER_FREE</state>
                        <HttpsPort>47984</HttpsPort>
                    </root>
                    """
                )
            ),
        ]
    )

    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: defaultsSuite),
        pinnedCertificateStore: pinnedStore,
        transport: transport
    )

    let info = try await client.fetchServerInfo(host: "stream-host.example.invalid")
    #expect(info.displayName == "Example-PC")
    #expect(info.pairStatus == .paired)
    #expect(
        await transport.calls() == [
            .init(scheme: "https", command: "serverinfo"),
        ]
    )
}

@Test("Metadata client synthesizes unpaired host when HTTPS is unauthorized and HTTP fallback is ATS blocked")
func metadataClientReturnsUnpairedHostWhenHTTPFallbackIsBlockedByATS() async throws {
    let defaultsSuite = "shadow-client.metadata.applist.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let transport = ScriptedRequestTransport(
        script: [
            .init(
                scheme: "https",
                command: "serverinfo",
                result: .success(#"<root status_code="401" status_message="The client is not authorized. Certificate verification failed."/>"#)
            ),
            .init(
                scheme: "http",
                command: "serverinfo",
                result: .failure(.requestFailed("Insecure HTTP is blocked by App Transport Security for this request."))
            ),
        ]
    )

    let pinnedStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: defaultsSuite)
    await pinnedStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "stream-host.example.invalid")
    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: defaultsSuite),
        pinnedCertificateStore: pinnedStore,
        transport: transport
    )

    let info = try await client.fetchServerInfo(host: "stream-host.example.invalid")
    #expect(info.host == "stream-host.example.invalid")
    #expect(info.displayName == "stream-host.example.invalid")
    #expect(info.pairStatus == .notPaired)
    #expect(info.httpsPort == 47984)
    #expect(
        await transport.calls() == [
            .init(scheme: "https", command: "serverinfo"),
            .init(scheme: "http", command: "serverinfo"),
        ]
    )
}

@Test("Metadata client synthesizes unpaired host when pinned HTTPS certificate mismatches")
func metadataClientReturnsUnpairedHostWhenHTTPSCertificateMismatches() async throws {
    let defaultsSuite = "shadow-client.metadata.serverinfo.mismatch.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let transport = ScriptedRequestTransport(
        script: [
            .init(
                scheme: "https",
                command: "serverinfo",
                result: .failure(.responseRejected(code: 401, message: "Server certificate mismatch"))
            ),
            .init(
                scheme: "http",
                command: "serverinfo",
                result: .failure(.requestFailed("Insecure HTTP is blocked by App Transport Security for this request."))
            ),
        ]
    )

    let pinnedStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: defaultsSuite)
    await pinnedStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "stream-host.example.invalid")
    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: defaultsSuite),
        pinnedCertificateStore: pinnedStore,
        transport: transport
    )

    let info = try await client.fetchServerInfo(host: "stream-host.example.invalid")
    #expect(info.host == "stream-host.example.invalid")
    #expect(info.displayName == "stream-host.example.invalid")
    #expect(info.pairStatus == .notPaired)
    #expect(info.httpsPort == 47984)
    #expect(
        await transport.calls() == [
            .init(scheme: "https", command: "serverinfo"),
            .init(scheme: "http", command: "serverinfo"),
        ]
    )
}

@Test("Metadata client synthesizes unpaired host when HTTPS fails with self-signed TLS trust error and HTTP fallback is ATS blocked")
func metadataClientReturnsUnpairedHostWhenHTTPSSelfSignedTrustFails() async throws {
    let defaultsSuite = "shadow-client.metadata.serverinfo.self-signed.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let transport = ScriptedRequestTransport(
        script: [
            .init(
                scheme: "https",
                command: "serverinfo",
                result: .failure(.requestFailed("A TLS error caused the secure connection to fail."))
            ),
            .init(
                scheme: "http",
                command: "serverinfo",
                result: .failure(.requestFailed("Insecure HTTP is blocked by App Transport Security for this request."))
            ),
        ]
    )

    let pinnedStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: defaultsSuite)
    await pinnedStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "stream-host.example.invalid")
    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: defaultsSuite),
        pinnedCertificateStore: pinnedStore,
        transport: transport
    )

    let info = try await client.fetchServerInfo(host: "stream-host.example.invalid")
    #expect(info.host == "stream-host.example.invalid")
    #expect(info.displayName == "stream-host.example.invalid")
    #expect(info.pairStatus == .notPaired)
    #expect(info.httpsPort == 47984)
    #expect(
        await transport.calls() == [
            .init(scheme: "https", command: "serverinfo"),
            .init(scheme: "http", command: "serverinfo"),
        ]
    )
}

@Test("Metadata client does not downgrade app list query to HTTP for unauthorized HTTPS 401 responses")
func metadataClientKeepsAppListOnHTTPSOnly() async {
    let defaultsSuite = "shadow-client.metadata.applist.https-only.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let transport = ScriptedRequestTransport(
        script: [
            .init(
                scheme: "https",
                command: "applist",
                result: .success(
                    #"<root status_code="401" status_message="The client is not authorized. Certificate verification failed."/>"#
                )
            ),
        ]
    )

    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: defaultsSuite),
        pinnedCertificateStore: .init(defaultsSuiteName: defaultsSuite),
        transport: transport
    )

    do {
        _ = try await client.fetchAppList(host: "stream-host.example.invalid", httpsPort: 47984)
        Issue.record("Expected app list HTTPS error")
    } catch let error as ShadowClientGameStreamError {
        #expect(
            error == .responseRejected(
                code: 401,
                message: "The client is not authorized. Certificate verification failed."
            )
        )
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(
        await transport.calls() == [
            .init(scheme: "https", command: "applist"),
        ]
    )
}

@Test("Metadata client keeps app list query on HTTPS when transport failure occurs")
func metadataClientKeepsAppListOnHTTPSWhenTransportFails() async {
    let defaultsSuite = "shadow-client.metadata.applist.https-transport-only.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let transport = ScriptedRequestTransport(
        script: [
            .init(
                scheme: "https",
                command: "applist",
                expectedPort: 47984,
                result: .failure(.requestFailed("The network connection was lost."))
            ),
        ]
    )

    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: defaultsSuite),
        pinnedCertificateStore: .init(defaultsSuiteName: defaultsSuite),
        transport: transport
    )

    do {
        _ = try await client.fetchAppList(
            host: "stream-host.example.invalid:48010",
            httpsPort: 47984
        )
        Issue.record("Expected HTTPS transport failure")
    } catch let error as ShadowClientGameStreamError {
        #expect(error == .requestFailed("The network connection was lost."))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(
        await transport.calls() == [
            .init(scheme: "https", command: "applist"),
        ]
    )
    #expect(
        await transport.callsWithPort() == [
            .init(scheme: "https", command: "applist", port: 47984),
        ]
    )
}

@Test("Metadata client does not hit HTTPS app list when no pinned certificate is available")
func metadataClientSkipsAppListHTTPSWithoutPinnedCertificate() async {
    let defaultsSuite = "shadow-client.metadata.applist.no-pin.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let transport = ScriptedRequestTransport(script: [])
    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: defaultsSuite),
        pinnedCertificateStore: .init(defaultsSuiteName: defaultsSuite),
        transport: transport
    )

    do {
        _ = try await client.fetchAppList(host: "stream-host.example.invalid", httpsPort: 47984)
        Issue.record("Expected pinned certificate requirement failure")
    } catch let error as ShadowClientGameStreamError {
        #expect(error == .requestFailed("Host requires a paired HTTPS certificate before app list queries."))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await transport.calls().isEmpty)
}

@Test("Remote desktop runtime refreshes hosts and loads selected host apps")
@MainActor
func remoteDesktopRuntimeRefreshesHostsAndLoadsApps() async {
    let client = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "192.168.0.20": .init(
                host: "192.168.0.20",
                displayName: "LivingRoom-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "A"
            ),
            "192.168.0.30": .init(
                host: "192.168.0.30",
                displayName: "Office-PC",
                pairStatus: .notPaired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "B"
            ),
        ],
        appListByHost: [
            "192.168.0.20": [
                .init(id: 10, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
                .init(id: 11, title: "Steam", hdrSupported: false, isAppCollectorGame: true),
            ],
        ]
    )

    let runtime = ShadowClientRemoteDesktopRuntime(metadataClient: client)
    runtime.refreshHosts(
        candidates: ["192.168.0.30", "192.168.0.20"],
        preferredHost: "192.168.0.20"
    )

    await waitForHostCatalogReady(runtime)
    await waitForAppCatalogReady(runtime)

    #expect(runtime.hostState == .loaded)
    #expect(runtime.selectedHost?.host == "192.168.0.20")
    #expect(runtime.apps.count == 2)
    #expect(runtime.appState == .loaded)

    runtime.selectHost("192.168.0.30")
    await waitForAppCatalogReady(runtime)

    #expect(runtime.selectedHost?.host == "192.168.0.30")
    #expect(runtime.apps.isEmpty)
    if case let .failed(message) = runtime.appState {
        #expect(message == "Host requires pairing before app list queries.")
    } else {
        Issue.record("Expected failed app state for unpaired host, got \(runtime.appState)")
    }
}

@Test("Remote desktop runtime synthesizes current session fallback app when paired host app list is empty")
@MainActor
func remoteDesktopRuntimeSynthesizesFallbackAppsForEmptyCatalog() async {
    let client = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "192.168.0.40": .init(
                host: "192.168.0.40",
                displayName: "Studio-PC",
                pairStatus: .paired,
                currentGameID: 881_448_767,
                serverState: "SUNSHINE_SERVER_BUSY",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "C"
            ),
        ],
        appListByHost: [
            "192.168.0.40": [],
        ]
    )

    let runtime = ShadowClientRemoteDesktopRuntime(metadataClient: client)
    runtime.refreshHosts(
        candidates: ["192.168.0.40"],
        preferredHost: "192.168.0.40"
    )

    await waitForHostCatalogReady(runtime)
    await waitForAppCatalogReady(runtime)

    #expect(runtime.hostState == .loaded)
    #expect(runtime.appState == .loaded)
    #expect(runtime.apps.count == 1)
    #expect(runtime.apps.first?.id == 881_448_767)
    #expect(runtime.apps.first?.title == "Current Session (881448767)")
}

@Test("Remote desktop runtime allows pairing for external host without local candidate")
@MainActor
func remoteDesktopRuntimeAllowsExternalPairWithoutLocalCandidate() async {
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "external-host.example.invalid": .init(
                host: "external-host.example.invalid",
                displayName: "Example-PC",
                pairStatus: .notPaired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
        ],
        appListByHost: [:]
    )
    let controlClient = RecordingGameStreamControlClient(successfulHosts: ["external-host.example.invalid"])
    let pairingRouteStore = ShadowClientPairingRouteStore(
        defaultsSuiteName: "shadow-client.pairing.external-only.\(UUID().uuidString)"
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: controlClient,
        pairingRouteStore: pairingRouteStore
    )

    runtime.refreshHosts(
        candidates: ["external-host.example.invalid"],
        preferredHost: "external-host.example.invalid"
    )
    await waitForHostCatalogReady(runtime)

    runtime.pairSelectedHost()
    await waitForPairingState(runtime)

    if case .paired = runtime.pairingState {
        #expect(true)
    } else {
        Issue.record("Expected pairing success for external-only host, got \(runtime.pairingState)")
    }

    #expect(await controlClient.pairRequests() == ["external-host.example.invalid"])
}

@Test("Remote desktop runtime tries selected external host before local fallback when unique ID matches")
@MainActor
func remoteDesktopRuntimeTriesSelectedExternalHostBeforeLocalFallback() async {
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "external-host.example.invalid": .init(
                host: "external-host.example.invalid",
                displayName: "Example-PC",
                pairStatus: .notPaired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
            "192.168.0.20": .init(
                host: "192.168.0.20",
                displayName: "Example-PC",
                pairStatus: .notPaired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
        ],
        appListByHost: [:]
    )
    let controlClient = RecordingGameStreamControlClient(successfulHosts: ["192.168.0.20"])
    let pairingRouteStore = ShadowClientPairingRouteStore(
        defaultsSuiteName: "shadow-client.pairing.local-preferred.\(UUID().uuidString)"
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: controlClient,
        pairingRouteStore: pairingRouteStore
    )

    runtime.refreshHosts(
        candidates: ["external-host.example.invalid", "192.168.0.20"],
        preferredHost: "external-host.example.invalid"
    )
    await waitForHostCatalogReady(runtime)

    runtime.pairSelectedHost()
    await waitForPairingState(runtime)

    #expect(runtime.pairingState == .paired("Paired"))
    #expect(await controlClient.pairRequests() == ["external-host.example.invalid", "192.168.0.20"])
}

@Test("Remote desktop runtime merges local and external descriptors for the same unique ID")
@MainActor
func remoteDesktopRuntimeMergesDescriptorsSharingUniqueID() async {
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "external-host.example.invalid": .init(
                host: "external-host.example.invalid",
                displayName: "Example-PC",
                pairStatus: .notPaired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
            "192.168.0.20": .init(
                host: "192.168.0.20",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
        ],
        appListByHost: [:]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient()
    )

    runtime.refreshHosts(
        candidates: ["external-host.example.invalid", "192.168.0.20"],
        preferredHost: "external-host.example.invalid"
    )
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.uniqueID == "HOST-123")
    #expect(runtime.hosts.first?.pairStatus == .paired)
}

@Test("Remote desktop runtime prefers reachable local route when merging host routes")
@MainActor
func remoteDesktopRuntimePrefersReachableLocalRouteWhenMerging() async {
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "external-host.example.invalid": .init(
                host: "external-host.example.invalid",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
            "192.168.0.20": .init(
                host: "192.168.0.20",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
        ],
        appListByHost: [:]
    )
    let pairingRouteStore = ShadowClientPairingRouteStore(
        defaultsSuiteName: "shadow-client.pairing.merge-preferred.\(UUID().uuidString)"
    )
    await pairingRouteStore.setPreferredHost(
        "external-host.example.invalid",
        for: "uniqueid:host-123"
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient(),
        pairingRouteStore: pairingRouteStore
    )

    runtime.refreshHosts(
        candidates: ["external-host.example.invalid", "192.168.0.20"]
    )
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.host == "192.168.0.20")
}

@Test("Remote desktop runtime rewrites launch session URLs to the active runtime host")
func remoteDesktopRuntimeRewritesLaunchSessionURLToRuntimeHost() {
    let rewritten = ShadowClientRemoteDesktopRuntime.rewrittenSessionURL(
        "rtsp://192.168.0.52:48010",
        runtimeHost: "wifi.skyline23.com"
    )

    #expect(rewritten == "rtsp://wifi.skyline23.com:48010")
}

private struct FailingIdentityProvider: ShadowClientPairingIdentityProviding {
    func loadIdentityMaterial() throws -> ShadowClientPairingIdentityMaterial {
        throw ShadowClientGameStreamControlError.invalidKeyMaterial
    }
}

private actor ScriptedRequestTransport: ShadowClientGameStreamRequestTransporting {
    struct Call: Equatable, Sendable {
        let scheme: String
        let command: String
    }

    struct CallWithPort: Equatable, Sendable {
        let scheme: String
        let command: String
        let port: Int
    }

    struct ScriptStep: Sendable {
        let scheme: String
        let command: String
        let expectedPort: Int?
        let result: Result<String, ShadowClientGameStreamError>

        init(
            scheme: String,
            command: String,
            expectedPort: Int? = nil,
            result: Result<String, ShadowClientGameStreamError>
        ) {
            self.scheme = scheme
            self.command = command
            self.expectedPort = expectedPort
            self.result = result
        }
    }

    private var script: [ScriptStep]
    private var recordedCalls: [Call] = []
    private var recordedCallsWithPort: [CallWithPort] = []

    init(script: [ScriptStep]) {
        self.script = script
    }

    func requestXML(
        host: String,
        port: Int,
        scheme: String,
        command: String,
        parameters: [String: String],
        uniqueID: String,
        pinnedServerCertificateDER: Data?,
        clientCertificateCredential: URLCredential?,
        clientCertificates: [SecCertificate]?,
        clientCertificateIdentity: SecIdentity?
    ) async throws -> String {
        recordedCalls.append(.init(scheme: scheme, command: command))
        recordedCallsWithPort.append(.init(scheme: scheme, command: command, port: port))
        guard !script.isEmpty else {
            throw ShadowClientGameStreamError.requestFailed("Unexpected request \(scheme)://\(host):\(port)/\(command)")
        }

        let step = script.removeFirst()
        guard step.scheme == scheme, step.command == command else {
            throw ShadowClientGameStreamError.requestFailed(
                "Unexpected request \(scheme)://\(host):\(port)/\(command), expected \(step.scheme)/\(step.command)"
            )
        }
        if let expectedPort = step.expectedPort, expectedPort != port {
            throw ShadowClientGameStreamError.requestFailed(
                "Unexpected request \(scheme)://\(host):\(port)/\(command), expected port \(expectedPort)"
            )
        }

        return try step.result.get()
    }

    func calls() -> [Call] {
        recordedCalls
    }

    func callsWithPort() -> [CallWithPort] {
        recordedCallsWithPort
    }
}

private actor FakeGameStreamMetadataClient: ShadowClientGameStreamMetadataClient {
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
        if let info = serverInfoByHost[host] {
            return info
        }

        throw ShadowClientGameStreamError.requestFailed("host not found")
    }

    func fetchAppList(host: String, httpsPort: Int?) async throws -> [ShadowClientRemoteAppDescriptor] {
        appListByHost[host] ?? []
    }
}

private actor RecordingGameStreamControlClient: ShadowClientGameStreamControlClient {
    private let successfulHosts: Set<String>
    private var recordedPairHosts: [String] = []

    init(successfulHosts: Set<String> = []) {
        self.successfulHosts = successfulHosts
    }

    func pair(
        host: String,
        pin: String,
        appVersion: String?,
        httpsPort: Int?
    ) async throws -> ShadowClientGameStreamPairingResult {
        recordedPairHosts.append(host)

        if successfulHosts.isEmpty || successfulHosts.contains(host) {
            return .init(host: host)
        }

        throw ShadowClientGameStreamError.requestFailed("A server with the specified hostname could not be found.")
    }

    func launch(
        host: String,
        httpsPort: Int,
        appID: Int,
        currentGameID: Int,
        forceLaunch: Bool,
        settings: ShadowClientGameStreamLaunchSettings
    ) async throws -> ShadowClientGameStreamLaunchResult {
        .init(sessionURL: nil, verb: "launch")
    }

    func pairRequests() -> [String] {
        recordedPairHosts
    }
}

@MainActor
private func waitForHostCatalogReady(
    _ runtime: ShadowClientRemoteDesktopRuntime,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if runtime.hostState == .loaded || runtime.hostState == .failed("No hosts resolved.") {
            return
        }

        try? await Task.sleep(for: .milliseconds(20))
    }
}

@MainActor
private func waitForAppCatalogReady(
    _ runtime: ShadowClientRemoteDesktopRuntime,
    maxAttempts: Int = 50
) async {
    for _ in 0..<maxAttempts {
        if runtime.appState == .loaded || runtime.appState.label.starts(with: "Failed") {
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
        switch runtime.pairingState {
        case .idle, .pairing:
            break
        case .paired, .failed:
            return
        }

        try? await Task.sleep(for: .milliseconds(20))
    }
}
