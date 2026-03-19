import Foundation
import Testing
import ShadowClientFeatureSession
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

@Test("GameStream parser maps host applist XML without status_message")
func gameStreamParserMapsHostAppListWithoutStatusMessage() throws {
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

@Test("GameStream parser rejects Apollo applist permission sentinel")
func gameStreamParserRejectsApolloAppListPermissionSentinel() {
    let xml = """
    <root status_code="200" status_message="OK">
      <App>
        <IsHdrSupported>0</IsHdrSupported>
        <AppTitle>Permission Denied</AppTitle>
        <UUID></UUID>
        <IDX>0</IDX>
        <ID>114514</ID>
      </App>
    </root>
    """

    do {
        _ = try ShadowClientGameStreamXMLParsers.parseAppList(xml: xml)
        Issue.record("Expected Apollo permission sentinel to be rejected")
    } catch let error as ShadowClientGameStreamError {
        #expect(error == .responseRejected(code: 403, message: "Permission denied"))
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
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

@Test("Metadata client preserves explicit custom HTTPS ports for pinned hosts")
func metadataClientUsesExplicitCustomHTTPSPortsForPinnedHosts() async throws {
    let defaultsSuite = "shadow-client.metadata.serverinfo.custom-https-port.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pinnedStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: defaultsSuite)
    await pinnedStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "apollo-host.example.invalid")

    let transport = ScriptedRequestTransport(
        script: [
            .init(
                scheme: "https",
                command: "serverinfo",
                expectedPort: 48984,
                result: .success(
                    """
                    <root status_code="200">
                        <hostname>Apollo-Mac</hostname>
                        <PairStatus>1</PairStatus>
                        <currentgame>0</currentgame>
                        <state>SUNSHINE_SERVER_FREE</state>
                        <HttpsPort>48984</HttpsPort>
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

    let info = try await client.fetchServerInfo(host: "apollo-host.example.invalid:48984")
    #expect(info.displayName == "Apollo-Mac")
    #expect(info.httpsPort == 48984)
    #expect(
        await transport.callsWithPort() == [
            .init(scheme: "https", command: "serverinfo", port: 48984),
        ]
    )
}

@Test("Metadata client keeps pinned HTTPS authorization failures on HTTPS without HTTP fallback")
func metadataClientKeepsPinnedUnauthorizedServerInfoFailuresOnHTTPS() async throws {
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
    await pinnedStore.bindHost("stream-host.example.invalid", toMachineID: "host-123")
    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: defaultsSuite),
        pinnedCertificateStore: pinnedStore,
        transport: transport
    )

    do {
        _ = try await client.fetchServerInfo(host: "stream-host.example.invalid")
        Issue.record("Expected pinned HTTPS authorization failure")
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
            .init(scheme: "https", command: "serverinfo"),
        ]
    )
}

@Test("Metadata client keeps pinned HTTPS certificate mismatches on HTTPS without HTTP fallback")
func metadataClientKeepsPinnedHTTPSCertificateMismatchesOnHTTPS() async throws {
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

    do {
        _ = try await client.fetchServerInfo(host: "stream-host.example.invalid")
        Issue.record("Expected pinned HTTPS certificate mismatch failure")
    } catch let error as ShadowClientGameStreamError {
        #expect(
            error == .responseRejected(
                code: 401,
                message: "Server certificate mismatch"
            )
        )
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(
        await transport.calls() == [
            .init(scheme: "https", command: "serverinfo"),
        ]
    )
    #expect(await pinnedStore.isRejectedHost("stream-host.example.invalid"))
    #expect(await pinnedStore.machineID(forHost: "stream-host.example.invalid") == nil)
}

@Test("Metadata client skips plain HTTP fallback for local .local hosts after pinned HTTPS certificate mismatch")
func metadataClientKeepsLocalPinnedCertificateMismatchOnHTTPS() async throws {
    let defaultsSuite = "shadow-client.metadata.serverinfo.local-mismatch.\(UUID().uuidString)"
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
        ]
    )

    let pinnedStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: defaultsSuite)
    await pinnedStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "local-stream-host.local")
    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: defaultsSuite),
        pinnedCertificateStore: pinnedStore,
        transport: transport
    )

    do {
        _ = try await client.fetchServerInfo(host: "local-stream-host.local")
        Issue.record("Expected pinned local HTTPS certificate mismatch failure")
    } catch let error as ShadowClientGameStreamError {
        #expect(
            error == .responseRejected(
                code: 401,
                message: "Server certificate mismatch"
            )
        )
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(
        await transport.calls() == [
            .init(scheme: "https", command: "serverinfo"),
        ]
    )
}

@Test("Metadata client can reuse a pinned certificate from a related route alias")
func metadataClientUsesProvidedPinnedCertificateForAliasHost() async throws {
    let transport = ScriptedRequestTransport(
        script: [
            .init(
                scheme: "https",
                command: "serverinfo",
                result: .success(
                    #"<root status_code="200" status_message="OK"><hostname>Example-PC</hostname><PairStatus>1</PairStatus><currentgame>0</currentgame><state>SUNSHINE_SERVER_FREE</state><HttpsPort>47984</HttpsPort><uniqueid>HOST-123</uniqueid></root>"#
                )
            ),
        ]
    )

    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: "shadow-client.metadata.alias-cert.\(UUID().uuidString)"),
        pinnedCertificateStore: ShadowClientPinnedHostCertificateStore(defaultsSuiteName: "shadow-client.metadata.alias-cert.\(UUID().uuidString)"),
        transport: transport
    )

    let info = try await client.fetchServerInfo(
        host: "external-route.example.invalid",
        pinnedServerCertificateDER: Data([0x01, 0x02, 0x03])
    )

    #expect(info.host == "external-route.example.invalid")
    #expect(info.pairStatus == .paired)
    #expect(
        await transport.calls() == [
            .init(scheme: "https", command: "serverinfo"),
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

@Test("Remote desktop runtime surfaces Apollo app list permission denial")
@MainActor
func remoteDesktopRuntimeSurfacesApolloAppListPermissionDenial() async {
    let client = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "192.168.0.40": .init(
                host: "192.168.0.40",
                displayName: "Apollo-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-40"
            ),
        ],
        appListByHost: [:],
        appListFailureByHost: [
            "192.168.0.40": .responseRejected(code: 403, message: "Permission denied"),
        ]
    )

    let runtime = ShadowClientRemoteDesktopRuntime(metadataClient: client)
    runtime.refreshHosts(
        candidates: ["192.168.0.40"],
        preferredHost: "192.168.0.40"
    )

    await waitForHostCatalogReady(runtime)
    await waitForAppCatalogReady(runtime)

    if case let .failed(message) = runtime.appState {
        #expect(message == "Apollo denied List Apps permission for this paired client.")
    } else {
        Issue.record("Expected failed app state for Apollo permission denial, got \(runtime.appState)")
    }
}

@Test("Remote desktop runtime does not persist unpaired scanned hosts")
@MainActor
func remoteDesktopRuntimeDoesNotPersistUnpairedScannedHosts() async {
    let defaultsSuite = "shadow-client.runtime.unpaired-cache.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "192.168.0.40": .init(
                host: "192.168.0.40",
                displayName: "Scan-PC",
                pairStatus: .notPaired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-40"
            ),
        ],
        appListByHost: [:]
    )

    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )
    runtime.refreshHosts(
        candidates: ["192.168.0.40"],
        preferredHost: "192.168.0.40"
    )
    await waitForHostCatalogReady(runtime)
    #expect(runtime.hosts.count == 1)

    let restoredRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )

    #expect(restoredRuntime.hosts.isEmpty)
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

@Test("Remote desktop runtime preserves paired status when a host has a pinned certificate")
@MainActor
func remoteDesktopRuntimePreservesPairedStatusForPinnedHosts() async {
    let defaultsSuite = "shadow-client.runtime.pinned-paired.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pinnedStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: defaultsSuite)
    await pinnedStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "192.168.0.20")

    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
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

    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient(),
        pinnedCertificateStore: pinnedStore,
        defaults: defaults
    )

    runtime.refreshHosts(
        candidates: ["192.168.0.20"],
        preferredHost: "192.168.0.20"
    )
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.first?.pairStatus == .paired)
}

@Test("Remote desktop runtime deletes cached hosts and clears pairing artifacts")
@MainActor
func remoteDesktopRuntimeDeletesHostAndClearsPairingArtifacts() async {
    let defaultsSuite = "shadow-client.runtime.delete-host.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pinnedStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: defaultsSuite)
    await pinnedStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "192.168.0.20")

    let pairingRouteStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    await pairingRouteStore.setPreferredHost("192.168.0.20", for: "uniqueid:host-123")

    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
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
        controlClient: RecordingGameStreamControlClient(),
        pinnedCertificateStore: pinnedStore,
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )

    runtime.refreshHosts(
        candidates: ["192.168.0.20"],
        preferredHost: "192.168.0.20"
    )
    await waitForHostCatalogReady(runtime)

    runtime.deleteHost("192.168.0.20")

    #expect(runtime.hosts.isEmpty)
    #expect(runtime.selectedHost == nil)
    #expect(await pinnedStore.certificateDER(forHost: "192.168.0.20") == nil)
    #expect(await pairingRouteStore.preferredHost(for: "uniqueid:host-123") == nil)
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

@Test("Remote desktop runtime matches preferred hosts that include the HTTPS port")
@MainActor
func remoteDesktopRuntimeMatchesPreferredHostWithExplicitPort() async {
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
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient()
    )

    runtime.refreshHosts(
        candidates: ["external-host.example.invalid", "192.168.0.20"],
        preferredHost: "external-host.example.invalid:47984"
    )
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.host == "external-host.example.invalid")
}

@Test("Remote desktop runtime refreshes persisted manual routes alongside local discovery candidates")
@MainActor
func remoteDesktopRuntimeRefreshesPersistedManualRoutes() async {
    let defaultsSuite = "shadow-client.runtime.persisted-manual-route.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let seededMetadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "external-route.example.invalid": .init(
                host: "external-route.example.invalid",
                localHost: "local-stream-host.local",
                remoteHost: "external-route.example.invalid",
                manualHost: nil,
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
    let seededRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: seededMetadataClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )
    seededRuntime.refreshHosts(
        candidates: ["external-route.example.invalid"],
        preferredHost: "external-route.example.invalid"
    )
    await waitForHostCatalogReady(seededRuntime)

    let refreshedMetadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "external-route.example.invalid": .init(
                host: "external-route.example.invalid",
                localHost: "local-stream-host.local",
                remoteHost: "external-route.example.invalid",
                manualHost: nil,
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
    let refreshedRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: refreshedMetadataClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )

    refreshedRuntime.refreshHosts(
        candidates: ["local-stream-host.local"],
        preferredHost: "external-route.example.invalid:47984"
    )
    await waitForHostCatalogReady(refreshedRuntime)

    #expect(refreshedRuntime.hosts.count == 1)
    #expect(refreshedRuntime.hosts.first?.host == "external-route.example.invalid")
    #expect(refreshedRuntime.hosts.first?.routes.local?.host == "local-stream-host.local")
    #expect(refreshedRuntime.hosts.first?.pairStatus == .paired)
}

@Test("Remote desktop runtime preserves cached route groups when refreshed hosts time out")
@MainActor
func remoteDesktopRuntimePreservesCachedRoutesAcrossRefreshFailures() async {
    let defaultsSuite = "shadow-client.runtime.refresh-failure-routes.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let seededMetadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "external-route.example.invalid": .init(
                host: "external-route.example.invalid",
                localHost: "local-stream-host.local",
                remoteHost: "external-route.example.invalid",
                manualHost: nil,
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
            "second-stream-host.local": .init(
                host: "second-stream-host.local",
                displayName: "Skyline-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-456"
            ),
        ],
        appListByHost: [:]
    )
    let seededRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: seededMetadataClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )
    seededRuntime.refreshHosts(
        candidates: ["external-route.example.invalid", "second-stream-host.local"],
        preferredHost: "external-route.example.invalid:47984"
    )
    await waitForHostCatalogReady(seededRuntime)

    let failingMetadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [:],
        appListByHost: [:]
    )
    let failingRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: failingMetadataClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )
    failingRuntime.refreshHosts(
        candidates: [
            "external-route.example.invalid",
            "local-stream-host.local",
            "second-stream-host.local",
        ],
        preferredHost: "external-route.example.invalid:47984"
    )
    await waitForHostCatalogReady(failingRuntime)

    #expect(failingRuntime.hosts.count == 2)
    #expect(failingRuntime.hosts.first?.host == "external-route.example.invalid")
    #expect(failingRuntime.hosts.first?.routes.local?.host == "local-stream-host.local")
    #expect(failingRuntime.hosts.first?.lastError != nil)
    #expect(failingRuntime.hosts.contains(where: { $0.host == "second-stream-host.local" }))
}

@Test("Remote desktop runtime treats default HTTP route ports as the same manual host candidate")
@MainActor
func remoteDesktopRuntimeMatchesDefaultHTTPPortCandidateToCachedRoute() async {
    let defaultsSuite = "shadow-client.runtime.default-http-port-route.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let seededMetadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "external-route.example.invalid": .init(
                host: "external-route.example.invalid",
                localHost: "local-stream-host.local",
                remoteHost: "external-route.example.invalid",
                manualHost: nil,
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
    let seededRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: seededMetadataClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )
    seededRuntime.refreshHosts(
        candidates: ["external-route.example.invalid"],
        preferredHost: "external-route.example.invalid"
    )
    await waitForHostCatalogReady(seededRuntime)

    let failingMetadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [:],
        appListByHost: [:]
    )
    let failingRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: failingMetadataClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )
    failingRuntime.refreshHosts(
        candidates: ["external-route.example.invalid:47989", "local-stream-host.local"],
        preferredHost: "external-route.example.invalid:47989"
    )
    await waitForHostCatalogReady(failingRuntime)

    #expect(failingRuntime.hosts.count == 1)
    #expect(failingRuntime.hosts.first?.host == "external-route.example.invalid")
    #expect(failingRuntime.hosts.first?.routes.local?.host == "local-stream-host.local")
}

@Test("Remote desktop runtime copies pinned certificates onto remembered manual routes before refresh")
@MainActor
func remoteDesktopRuntimeCopiesPinnedCertificateForRememberedManualRoute() async {
    let certificateStore = ShadowClientPinnedHostCertificateStore(
        defaultsSuiteName: "shadow-client.runtime.manual-route-cert-alias.\(UUID().uuidString)"
    )
    let pairingRouteStore = ShadowClientPairingRouteStore(
        defaultsSuiteName: "shadow-client.runtime.manual-route-pair-route.\(UUID().uuidString)"
    )
    let localCertificate = Data([0xCA, 0xFE, 0xBA, 0xBE])
    await certificateStore.setCertificateDER(localCertificate, forHost: "local-stream-host.local")

    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "local-stream-host.local": .init(
                host: "local-stream-host.local",
                localHost: "local-stream-host.local",
                remoteHost: "external-route.example.invalid",
                manualHost: nil,
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
        controlClient: RecordingGameStreamControlClient(),
        pinnedCertificateStore: certificateStore,
        pairingRouteStore: pairingRouteStore
    )

    runtime.refreshHosts(candidates: ["local-stream-host.local"])
    await waitForHostCatalogReady(runtime)

    await runtime.rememberPreferredHostRoute("manual-route.example.invalid")

    #expect(
        await pairingRouteStore.preferredHost(for: "uniqueid:host-123")
            == "manual-route.example.invalid"
    )
    #expect(runtime.hosts.first?.routes.manual?.host == "manual-route.example.invalid")
    #expect(
        await certificateStore.certificateDER(forHost: "manual-route.example.invalid")
            == localCertificate
    )
}

@Test("Remote desktop runtime keeps remembered manual routes attached to the same published host across refreshes")
@MainActor
func remoteDesktopRuntimeKeepsRememberedManualRoutesOnPublishedHost() async {
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "local-stream-host.local": .init(
                host: "local-stream-host.local",
                localHost: "local-stream-host.local",
                remoteHost: nil,
                manualHost: nil,
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

    runtime.refreshHosts(candidates: ["local-stream-host.local"])
    await waitForHostCatalogReady(runtime)
    await runtime.rememberPreferredHostRoute("manual-route.example.invalid")

    runtime.refreshHosts(
        candidates: ["manual-route.example.invalid", "local-stream-host.local"],
        preferredHost: "manual-route.example.invalid"
    )
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.routes.local?.host == "local-stream-host.local")
    #expect(runtime.hosts.first?.routes.manual?.host == "manual-route.example.invalid")
}

@Test("Remote desktop runtime propagates pinned certificates across discovered routes for one physical host")
@MainActor
func remoteDesktopRuntimePropagatesPinnedCertificatesAcrossDiscoveredRoutes() async {
    let certificateStore = ShadowClientPinnedHostCertificateStore(
        defaultsSuiteName: "shadow-client.runtime.route-cert-propagation.\(UUID().uuidString)"
    )
    let localCertificate = Data([0xDE, 0xAD, 0xBE, 0xEF])
    await certificateStore.setCertificateDER(localCertificate, forHost: "local-stream-host.local")

    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "local-stream-host.local": .init(
                host: "local-stream-host.local",
                localHost: "local-stream-host.local",
                remoteHost: "external-route.example.invalid",
                manualHost: "manual-route.example.invalid",
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
        controlClient: RecordingGameStreamControlClient(),
        pinnedCertificateStore: certificateStore
    )

    runtime.refreshHosts(candidates: ["local-stream-host.local"])
    await waitForHostCatalogReady(runtime)

    #expect(
        await certificateStore.certificateDER(forHost: "external-route.example.invalid")
            == localCertificate
    )
    #expect(
        await certificateStore.certificateDER(forHost: "manual-route.example.invalid")
            == localCertificate
    )
}

@Test("Remote desktop runtime does not reuse an unrelated pinned certificate for a preferred custom Apollo route")
@MainActor
func remoteDesktopRuntimeDoesNotReusePinnedCertificateForUnrelatedPreferredApolloRoute() async {
    let certificateStore = ShadowClientPinnedHostCertificateStore(
        defaultsSuiteName: "shadow-client.runtime.unrelated-preferred-apollo-cert.\(UUID().uuidString)"
    )
    let pcCertificate = Data([0xDE, 0xAD, 0xBE, 0xEF])
    await certificateStore.setCertificateDER(pcCertificate, forHost: "192.168.0.52")

    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "192.168.0.52": .init(
                host: "192.168.0.52",
                displayName: "Skyline23-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "PC-HOST"
            ),
            "buseongs-macbook-pro-14.local:48984": .init(
                host: "buseongs-macbook-pro-14.local",
                displayName: "Buseong's MacBook Pro 14",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 48984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "APOLLO-HOST"
            ),
        ],
        appListByHost: [:]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient(),
        pinnedCertificateStore: certificateStore
    )

    runtime.refreshHosts(candidates: ["192.168.0.52"], preferredHost: "192.168.0.52")
    await waitForHostCatalogReady(runtime)

    runtime.refreshHosts(
        candidates: ["192.168.0.52", "buseongs-macbook-pro-14.local:48984"],
        preferredHost: "buseongs-macbook-pro-14.local:48984"
    )
    await waitForHostCatalogReady(runtime)

    let apolloRequest = await metadataClient.recordedServerInfoRequests().last(where: {
        $0.host == "buseongs-macbook-pro-14.local:48984"
    })

    #expect(apolloRequest?.pinnedServerCertificateDER == nil)
}

@Test("Remote desktop runtime still publishes hosts that fail with a certificate mismatch during discovery")
@MainActor
func remoteDesktopRuntimePublishesCertificateMismatchHosts() async {
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "192.168.0.52": .init(
                host: "192.168.0.52",
                displayName: "Skyline23-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "PC-HOST"
            ),
        ],
        appListByHost: [:],
        serverInfoFailureByHost: [
            "buseongs-macbook-pro-14.local:48984": .responseRejected(
                code: 401,
                message: "Server certificate mismatch"
            ),
        ]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient()
    )

    runtime.refreshHosts(
        candidates: ["192.168.0.52", "buseongs-macbook-pro-14.local:48984"],
        preferredHost: "buseongs-macbook-pro-14.local:48984"
    )
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.count == 2)
    let apolloHost = runtime.hosts.first(where: { $0.host == "buseongs-macbook-pro-14.local" })
    #expect(apolloHost?.httpsPort == 48984)
    #expect(apolloHost?.lastError == "Host rejected request (401): Server certificate mismatch")
}

@Test("Remote desktop runtime skips probing routes rejected for certificate mismatch on subsequent refreshes")
@MainActor
func remoteDesktopRuntimeSkipsRejectedCertificateRoutesOnRefresh() async {
    let defaultsSuite = "shadow-client.runtime.rejected-route-skip.\(UUID().uuidString)"
    let certificateStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: defaultsSuite)
    await certificateStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "wifi-route.example.invalid")
    await certificateStore.bindHost("wifi-route.example.invalid", toMachineID: "host-123")
    await certificateStore.markRejectedHost("wifi-route.example.invalid")

    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "local-stream-host.local": .init(
                host: "local-stream-host.local",
                localHost: "local-stream-host.local",
                remoteHost: nil,
                manualHost: nil,
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
        controlClient: RecordingGameStreamControlClient(),
        pinnedCertificateStore: certificateStore
    )

    runtime.refreshHosts(
        candidates: ["wifi-route.example.invalid", "local-stream-host.local"],
        preferredHost: "wifi-route.example.invalid"
    )
    await waitForHostCatalogReady(runtime)

    #expect(await metadataClient.recordedServerInfoHosts() == ["local-stream-host.local"])
}

@Test("Rejected route stays rejected after alias synchronization to a machine")
@MainActor
func rejectedRouteRemainsRejectedAfterAliasSynchronization() async {
    let defaultsSuite = "shadow-client.runtime.rejected-route-persists.\(UUID().uuidString)"
    let certificateStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: defaultsSuite)
    await certificateStore.setCertificateDER(Data([0xAA, 0xBB, 0xCC]), forHost: "wifi-route.example.invalid")
    await certificateStore.bindHost("wifi-route.example.invalid", toMachineID: "host-123")
    await certificateStore.markRejectedHost("wifi-route.example.invalid")

    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "192.168.0.52": .init(
                host: "192.168.0.52",
                localHost: "192.168.0.52",
                remoteHost: nil,
                manualHost: nil,
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
        controlClient: RecordingGameStreamControlClient(),
        pinnedCertificateStore: certificateStore,
        hostAliasResolver: { hosts in
            var aliases: [String: Set<String>] = [:]
            for host in hosts {
                let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty else {
                    continue
                }
                if normalized == "wifi-route.example.invalid" || normalized == "192.168.0.52" {
                    aliases[normalized] = ["wifi-route.example.invalid", "192.168.0.52"]
                } else {
                    aliases[normalized] = [normalized]
                }
            }
            return aliases
        }
    )

    runtime.refreshHosts(candidates: ["wifi-route.example.invalid", "192.168.0.52"])
    await waitForHostCatalogReady(runtime)

    #expect(await certificateStore.isRejectedHost("wifi-route.example.invalid"))

    runtime.refreshHosts(candidates: ["wifi-route.example.invalid", "192.168.0.52"])
    await waitForHostCatalogReady(runtime)

    #expect(await metadataClient.recordedServerInfoHosts() == ["192.168.0.52", "192.168.0.52"])
}

@Test("Remote desktop runtime merges hostname and LAN IP aliases into one published host")
@MainActor
func remoteDesktopRuntimeMergesResolvedRouteAliasesWithoutUniqueID() async {
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [:],
        appListByHost: [:]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient(),
        hostAliasResolver: { hosts in
            var aliases: [String: Set<String>] = [:]
            for host in hosts {
                let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty else {
                    continue
                }
                if normalized == "wifi-route.example.invalid" || normalized == "192.168.0.52" {
                    aliases[normalized] = ["wifi-route.example.invalid", "192.168.0.52"]
                } else {
                    aliases[normalized] = [normalized]
                }
            }
            return aliases
        }
    )

    runtime.refreshHosts(candidates: ["wifi-route.example.invalid", "192.168.0.52"])
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.count == 1)
    #expect(
        Set(runtime.hosts[0].routes.allEndpoints.map(\.host))
            == ["wifi-route.example.invalid", "192.168.0.52"]
    )
}

@Test("Remote desktop runtime prefers .local DNS alias over raw LAN IP for merged hosts")
@MainActor
func remoteDesktopRuntimePrefersDotLocalAliasOverRawLANIP() async {
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [:],
        appListByHost: [:]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient(),
        hostAliasResolver: { hosts in
            var aliases: [String: Set<String>] = [:]
            for host in hosts {
                let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !normalized.isEmpty else {
                    continue
                }
                if normalized == "local-stream-host.local" || normalized == "192.168.0.52" {
                    aliases[normalized] = ["local-stream-host.local", "192.168.0.52"]
                } else {
                    aliases[normalized] = [normalized]
                }
            }
            return aliases
        }
    )

    runtime.refreshHosts(candidates: ["192.168.0.52", "local-stream-host.local"])
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.host == "local-stream-host.local")
}

@Test("Remote desktop runtime drops duplicate cached host identities on startup")
@MainActor
func remoteDesktopRuntimeDeduplicatesPersistedHostIDs() async {
    let defaultsSuite = "shadow-client.runtime.persisted-duplicate-ids.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let duplicateCatalog = """
    {
      "hosts": [
        {
          "activeHost": "external-route.example.invalid",
          "httpsPort": 47984,
          "displayName": "Example-PC",
          "pairStatusRawValue": "paired",
          "currentGameID": 0,
          "serverState": "SUNSHINE_SERVER_FREE",
          "appVersion": "1.0",
          "gfeVersion": null,
          "uniqueID": "HOST-123",
          "lastError": null,
          "localHost": "local-stream-host.local",
          "remoteHost": "external-route.example.invalid",
          "manualHost": null
        },
        {
          "activeHost": "external-route.example.invalid",
          "httpsPort": 47984,
          "displayName": "Example-PC",
          "pairStatusRawValue": "paired",
          "currentGameID": 0,
          "serverState": "SUNSHINE_SERVER_FREE",
          "appVersion": "1.0",
          "gfeVersion": null,
          "uniqueID": "HOST-123",
          "lastError": "Could not query host serverinfo",
          "localHost": null,
          "remoteHost": null,
          "manualHost": null
        }
      ]
    }
    """
    defaults.set(
        duplicateCatalog.data(using: .utf8),
        forKey: ShadowClientAppSettings.StorageKeys.cachedRemoteHosts
    )

    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: FakeGameStreamMetadataClient(serverInfoByHost: [:], appListByHost: [:]),
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )

    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.host == "external-route.example.invalid")
}

@Test("Remote desktop runtime preserves preferred external routes when refresh probes fail")
@MainActor
func remoteDesktopRuntimePreservesPreferredExternalRoutesAcrossFailures() async {
    let defaultsSuite = "shadow-client.runtime.preferred-route-failure-merge.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pairingRouteStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    await pairingRouteStore.setPreferredHost(
        "external-route.example.invalid:47989",
        for: "uniqueid:host-123"
    )

    let seededHost = ShadowClientRemoteHostDescriptor(
        host: "local-stream-host.local",
        displayName: "Example-PC",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        httpsPort: 47984,
        appVersion: "1.0",
        gfeVersion: nil,
        uniqueID: "HOST-123",
        lastError: nil,
        localHost: "local-stream-host.local",
        remoteHost: nil,
        manualHost: nil
    )
    let seededCatalog = """
    {
      "hosts": [
        {
          "activeHost": "\(seededHost.host)",
          "httpsPort": \(seededHost.httpsPort),
          "displayName": "\(seededHost.displayName)",
          "pairStatusRawValue": "\(seededHost.pairStatus.rawValue)",
          "currentGameID": \(seededHost.currentGameID),
          "serverState": "\(seededHost.serverState)",
          "appVersion": "1.0",
          "gfeVersion": null,
          "uniqueID": "HOST-123",
          "lastError": null,
          "localHost": "local-stream-host.local",
          "remoteHost": null,
          "manualHost": null
        }
      ]
    }
    """
    defaults.set(
        seededCatalog.data(using: .utf8),
        forKey: ShadowClientAppSettings.StorageKeys.cachedRemoteHosts
    )

    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: FakeGameStreamMetadataClient(serverInfoByHost: [:], appListByHost: [:]),
        controlClient: RecordingGameStreamControlClient(),
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )

    runtime.refreshHosts(
        candidates: ["external-route.example.invalid:47989", "local-stream-host.local"],
        preferredHost: "external-route.example.invalid:47989"
    )
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.host == "external-route.example.invalid")
    #expect(runtime.hosts.first?.routes.local?.host == "local-stream-host.local")
    #expect(runtime.hosts.first?.routes.manual?.host == "external-route.example.invalid")
}

@Test("Remote desktop runtime rewrites local launch session URLs to the runtime host")
func remoteDesktopRuntimeRewritesLocalLaunchSessionURLToRuntimeHost() {
    let rewritten = ShadowClientRemoteDesktopRuntime.rewrittenSessionURL(
        "rtsp://192.168.0.52:48010",
        runtimeHost: "external-route.example.invalid"
    )

    #expect(rewritten == "rtsp://external-route.example.invalid:48010")
}

@Test("Remote desktop runtime preserves host-provided launch session URLs for local runtime hosts")
func remoteDesktopRuntimePreservesHostProvidedLaunchSessionURLForLocalRuntimeHost() {
    let rewritten = ShadowClientRemoteDesktopRuntime.rewrittenSessionURL(
        "rtsp://192.168.0.52:48010",
        runtimeHost: "192.168.0.52"
    )

    #expect(rewritten == "rtsp://192.168.0.52:48010")
}

@Test("Remote desktop runtime rewrites link-local launch session URLs to the runtime host")
func remoteDesktopRuntimeRewritesLinkLocalLaunchSessionURLToRuntimeHost() {
    let rewritten = ShadowClientRemoteDesktopRuntime.rewrittenSessionURL(
        "rtsp://[fe80::4453:7fff:fedf:44ba%25en12]:49010/session",
        runtimeHost: "buseongs-macbook-pro-14.local",
        knownHosts: ["buseongs-macbook-pro-14.local"],
        localRouteHosts: ["buseongs-macbook-pro-14.local"]
    )

    #expect(rewritten == "rtsp://buseongs-macbook-pro-14.local:49010/session")
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
    struct ServerInfoRequest: Equatable {
        let host: String
        let pinnedServerCertificateDER: Data?
    }

    private let serverInfoByHost: [String: ShadowClientGameStreamServerInfo]
    private let appListByHost: [String: [ShadowClientRemoteAppDescriptor]]
    private let serverInfoFailureByHost: [String: ShadowClientGameStreamError]
    private let appListFailureByHost: [String: ShadowClientGameStreamError]
    private var serverInfoHosts: [String] = []
    private var serverInfoRequests: [ServerInfoRequest] = []

    init(
        serverInfoByHost: [String: ShadowClientGameStreamServerInfo],
        appListByHost: [String: [ShadowClientRemoteAppDescriptor]],
        serverInfoFailureByHost: [String: ShadowClientGameStreamError] = [:],
        appListFailureByHost: [String: ShadowClientGameStreamError] = [:]
    ) {
        self.serverInfoByHost = serverInfoByHost
        self.appListByHost = appListByHost
        self.serverInfoFailureByHost = serverInfoFailureByHost
        self.appListFailureByHost = appListFailureByHost
    }

    func fetchServerInfo(host: String) async throws -> ShadowClientGameStreamServerInfo {
        try await fetchServerInfo(host: host, pinnedServerCertificateDER: nil)
    }

    func fetchServerInfo(
        host: String,
        pinnedServerCertificateDER: Data?
    ) async throws -> ShadowClientGameStreamServerInfo {
        serverInfoHosts.append(host)
        serverInfoRequests.append(
            .init(host: host, pinnedServerCertificateDER: pinnedServerCertificateDER)
        )
        if let error = serverInfoFailureByHost[host] {
            throw error
        }
        if let info = serverInfoByHost[host] {
            return info
        }

        throw ShadowClientGameStreamError.requestFailed("host not found")
    }

    func fetchAppList(host: String, httpsPort: Int?) async throws -> [ShadowClientRemoteAppDescriptor] {
        if let error = appListFailureByHost[host] {
            throw error
        }
        return appListByHost[host] ?? []
    }

    func recordedServerInfoHosts() -> [String] {
        serverInfoHosts
    }

    func recordedServerInfoRequests() -> [ServerInfoRequest] {
        serverInfoRequests
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
