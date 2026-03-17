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

@Test("Metadata client derives Apollo HTTPS serverinfo port from explicit connect port")
func metadataClientDerivesApolloHTTPSServerInfoPortFromExplicitConnectPort() async throws {
    let defaultsSuite = "shadow-client.metadata.serverinfo.pinned-apollo-connect-port.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pinnedStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: defaultsSuite)
    await pinnedStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "apollo-host.local")

    let transport = ScriptedRequestTransport(
        script: [
            .init(
                scheme: "https",
                command: "serverinfo",
                expectedPort: 48984,
                result: .success(
                    """
                    <root status_code="200">
                        <hostname>Apollo</hostname>
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

    let info = try await client.fetchServerInfo(host: "apollo-host.local:48989")

    #expect(info.host == "apollo-host.local")
    #expect(info.httpsPort == 48984)
    #expect(info.manualHost == "apollo-host.local")
    #expect(
        await transport.callsWithPort() == [
            .init(scheme: "https", command: "serverinfo", port: 48984),
        ]
    )
}

@Test("Metadata client uses discovery port hint for HTTP and derived HTTPS ports")
func metadataClientUsesDiscoveryPortHintForCustomBasePort() async throws {
    let defaultsSuite = "shadow-client.metadata.serverinfo.discovery-port-hint.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pinnedStore = ShadowClientPinnedHostCertificateStore(defaultsSuiteName: defaultsSuite)
    await pinnedStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "apollo-host.local")

    let transport = ScriptedRequestTransport(
        script: [
            .init(
                scheme: "https",
                command: "serverinfo",
                expectedPort: 48984,
                result: .success(
                    """
                    <root status_code="200">
                        <hostname>Apollo</hostname>
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

    let info = try await client.fetchServerInfo(
        host: "apollo-host.local:48989",
        portHint: .init(httpPort: 48989, httpsPort: 48984)
    )

    #expect(info.host == "apollo-host.local")
    #expect(info.httpsPort == 48984)
    #expect(
        await transport.callsWithPort() == [
            .init(scheme: "https", command: "serverinfo", port: 48984),
        ]
    )
}

@Test("Metadata client prefers resolved private LAN target over serverinfo link-local LocalIP for hostname requests")
func metadataClientPrefersResolvedPrivateLANHostOverLinkLocalServerInfoLocalIP() async throws {
    let defaultsSuite = "shadow-client.metadata.serverinfo.resolved-local-route.\(UUID().uuidString)"
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
                expectedPort: 48989,
                result: .success(
                    """
                    <root status_code="200">
                        <hostname>Apollo Mac</hostname>
                        <PairStatus>1</PairStatus>
                        <currentgame>0</currentgame>
                        <state>SUNSHINE_SERVER_FREE</state>
                        <HttpsPort>48984</HttpsPort>
                        <LocalIP>169.254.244.165</LocalIP>
                    </root>
                    """
                )
            ),
        ]
    )

    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: defaultsSuite),
        pinnedCertificateStore: .init(defaultsSuiteName: defaultsSuite),
        transport: transport,
        connectionTargetsResolver: { _ in
            [
                "169.254.244.165",
                "192.168.0.50",
                "fdaf:7bd4:8418:463e:1c47:71fb:db43:1f94",
            ]
        }
    )

    let info = try await client.fetchServerInfo(
        host: "buseongs-macbook-pro-14.local:48989",
        portHint: .init(httpPort: 48989, httpsPort: 48984)
    )

    #expect(info.host == "buseongs-macbook-pro-14.local")
    #expect(info.localHost == "192.168.0.50")
    #expect(info.manualHost == "buseongs-macbook-pro-14.local")
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

@Test("Metadata client skips plain HTTP fallback for local .local hosts after HTTPS certificate mismatch")
func metadataClientSkipsPlainHTTPFallbackForLocalHostCertificateMismatch() async throws {
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
    await pinnedStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "apollo-host.local")
    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: defaultsSuite),
        pinnedCertificateStore: pinnedStore,
        transport: transport
    )

    let info = try await client.fetchServerInfo(host: "apollo-host.local")
    #expect(info.host == "apollo-host.local")
    #expect(info.pairStatus == .notPaired)
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

@Test("Metadata client uses explicit host port for HTTPS app list when no override is supplied")
func metadataClientUsesExplicitHostPortForHTTPSAppList() async throws {
    let defaultsSuite = "shadow-client.metadata.applist.explicit-port.\(UUID().uuidString)"
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
                command: "applist",
                expectedPort: 48010,
                result: .success(#"<root status_code="200" status_message="OK"></root>"#)
            ),
        ]
    )

    let client = NativeGameStreamMetadataClient(
        identityStore: .init(provider: FailingIdentityProvider(), defaultsSuiteName: defaultsSuite),
        pinnedCertificateStore: pinnedStore,
        transport: transport
    )

    _ = try await client.fetchAppList(host: "stream-host.example.invalid:48010", httpsPort: nil)

    #expect(
        await transport.callsWithPort() == [
            .init(scheme: "https", command: "applist", port: 48010),
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
            "10.0.0.20": .init(
                host: "10.0.0.20",
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
            "10.0.0.20": [
                .init(id: 10, title: "Desktop", hdrSupported: true, isAppCollectorGame: false),
                .init(id: 11, title: "Steam", hdrSupported: false, isAppCollectorGame: true),
            ],
        ]
    )

    let runtime = ShadowClientRemoteDesktopRuntime(metadataClient: client)
    runtime.refreshHosts(
        candidates: ["192.168.0.30", "10.0.0.20"],
        preferredHost: "10.0.0.20"
    )

    await waitForHostCatalogReady(runtime)
    await waitForAppCatalogReady(runtime)

    #expect(runtime.hostState == .loaded)
    #expect(runtime.selectedHost?.host == "10.0.0.20")
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
            "10.0.0.20": .init(
                host: "10.0.0.20",
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
    let controlClient = RecordingGameStreamControlClient(successfulHosts: ["10.0.0.20"])
    let pairingRouteStore = ShadowClientPairingRouteStore(
        defaultsSuiteName: "shadow-client.pairing.local-preferred.\(UUID().uuidString)"
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: controlClient,
        pairingRouteStore: pairingRouteStore
    )

    runtime.refreshHosts(
        candidates: ["external-host.example.invalid", "10.0.0.20"],
        preferredHost: "external-host.example.invalid"
    )
    await waitForHostCatalogReady(runtime)

    runtime.pairSelectedHost()
    await waitForPairingState(runtime)

    #expect(runtime.pairingState == .paired("Paired"))
    #expect(await controlClient.pairRequests() == ["external-host.example.invalid", "10.0.0.20"])
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
            "10.0.0.20": .init(
                host: "10.0.0.20",
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
        candidates: ["external-host.example.invalid", "10.0.0.20"],
        preferredHost: "external-host.example.invalid"
    )
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.uniqueID == "HOST-123")
    #expect(runtime.hosts.first?.pairStatus == .paired)
}

@Test("Remote desktop runtime preserves cached identity when alias serverinfo refresh fails")
@MainActor
func remoteDesktopRuntimePreservesCachedIdentityForFailedAliasRefresh() async {
    let defaultsSuite = "shadow-client.runtime.alias-refresh.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let initialMetadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "desktop-discovery.example.invalid": .init(
                host: "desktop-discovery.example.invalid",
                localHost: "10.0.0.52",
                remoteHost: "198.51.100.20",
                manualHost: "desktop-manual.example.invalid",
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

    let seedingRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: initialMetadataClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )
    seedingRuntime.refreshHosts(
        candidates: ["desktop-discovery.example.invalid"],
        preferredHost: "desktop-discovery.example.invalid"
    )
    await waitForHostCatalogReady(seedingRuntime)
    #expect(seedingRuntime.hosts.count == 1)

    let failingMetadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [:],
        appListByHost: [:]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: failingMetadataClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )

    runtime.refreshHosts(
        candidates: ["desktop-manual.example.invalid", "desktop-discovery.example.invalid"],
        preferredHost: "desktop-manual.example.invalid"
    )
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.uniqueID == "HOST-123")
    #expect(runtime.hosts.first?.pairStatus == .paired)
    #expect(runtime.hosts.first?.routes.allEndpoints.map(\.host).contains("desktop-manual.example.invalid") == true)
    #expect(runtime.hosts.first?.routes.allEndpoints.map(\.host).contains("desktop-discovery.example.invalid") == true)
}

@Test("Remote desktop runtime coalesces known alias candidates before probing serverinfo")
@MainActor
func remoteDesktopRuntimeCoalescesKnownAliasCandidatesBeforeProbe() async {
    let defaultsSuite = "shadow-client.runtime.alias-coalesce.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let seedingClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "desktop-discovery.example.invalid": .init(
                host: "desktop-discovery.example.invalid",
                localHost: "10.0.0.52",
                remoteHost: "198.51.100.20",
                manualHost: "desktop-manual.example.invalid",
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
    let seedingRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: seedingClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )
    seedingRuntime.refreshHosts(candidates: ["desktop-discovery.example.invalid"])
    await waitForHostCatalogReady(seedingRuntime)

    let probingClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "desktop-manual.example.invalid": .init(
                host: "desktop-manual.example.invalid",
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
        metadataClient: probingClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )

    runtime.refreshHosts(
        candidates: ["desktop-manual.example.invalid", "desktop-discovery.example.invalid"],
        preferredHost: "desktop-manual.example.invalid"
    )
    await waitForHostCatalogReady(runtime)

    #expect(await probingClient.serverInfoRequests() == ["desktop-manual.example.invalid"])
    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.host == "desktop-manual.example.invalid")
}

@Test("Remote desktop runtime merges preferred WAN alias with cached LAN host when refresh probes fail")
@MainActor
func remoteDesktopRuntimeMergesPreferredWANAliasWithCachedLANHostWhenRefreshProbesFail() async {
    let defaultsSuite = "shadow-client.runtime.wan-alias-merge.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let seedingClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "desktop-lan.local": .init(
                host: "desktop-lan.local",
                localHost: "10.0.0.52",
                remoteHost: "198.51.100.20",
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
    let seedingRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: seedingClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )
    seedingRuntime.refreshHosts(candidates: ["desktop-lan.local"])
    await waitForHostCatalogReady(seedingRuntime)

    let failingClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [:],
        appListByHost: [:]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: failingClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )

    runtime.refreshHosts(
        candidates: ["desktop-lan.local", "public-gateway.example.invalid"],
        preferredHost: "public-gateway.example.invalid"
    )
    await waitForHostCatalogReady(runtime)

    #expect(await failingClient.serverInfoRequests() == ["public-gateway.example.invalid"])
    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.displayName == "Example-PC")
    #expect(runtime.hosts.first?.uniqueID == "HOST-123")
    #expect(runtime.hosts.first?.routes.allEndpoints.map(\.host).contains("desktop-lan.local") == true)
    #expect(runtime.hosts.first?.routes.allEndpoints.map(\.host).contains("public-gateway.example.invalid") == true)
}

@Test("Remote desktop runtime uses stored preferred WAN alias to coalesce catalog refresh without an explicit preferred host")
@MainActor
func remoteDesktopRuntimeUsesStoredPreferredWANAliasDuringRefresh() async {
    let defaultsSuite = "shadow-client.runtime.stored-wan-alias.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pairingRouteStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    let seedingClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "desktop-lan.local": .init(
                host: "desktop-lan.local",
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
    let seedingRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: seedingClient,
        controlClient: RecordingGameStreamControlClient(),
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )
    seedingRuntime.refreshHosts(candidates: ["desktop-lan.local"])
    await waitForHostCatalogReady(seedingRuntime)
    await pairingRouteStore.setPreferredHost("public-gateway.example.invalid", for: "uniqueid:host-123")

    let probingClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "public-gateway.example.invalid": .init(
                host: "public-gateway.example.invalid",
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
        metadataClient: probingClient,
        controlClient: RecordingGameStreamControlClient(),
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )

    runtime.refreshHosts(candidates: ["desktop-lan.local", "public-gateway.example.invalid"])
    await waitForHostCatalogReady(runtime)

    #expect(await probingClient.serverInfoRequests() == ["public-gateway.example.invalid"])
    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.routes.allEndpoints.map(\.host).contains("desktop-lan.local") == true)
    #expect(runtime.hosts.first?.routes.allEndpoints.map(\.host).contains("public-gateway.example.invalid") == true)
    #expect(runtime.hosts.first?.routes.active.host == "public-gateway.example.invalid")
}

@Test("Host catalog cached candidates include every known route endpoint")
func hostCatalogCachedCandidatesIncludeAllRouteEndpoints() {
    let descriptors = [
        ShadowClientRemoteHostDescriptor(
            host: "desktop-lan.local",
            displayName: "Example-PC",
            pairStatus: .paired,
            currentGameID: 0,
            serverState: "SUNSHINE_SERVER_FREE",
            httpsPort: 47984,
            appVersion: "1.0",
            gfeVersion: nil,
            uniqueID: "HOST-123",
            lastError: nil,
            localHost: "192.168.0.52",
            remoteHost: "public-gateway.example.invalid",
            manualHost: nil
        ),
    ]

    let candidates = ShadowClientHostCatalogKit.cachedCandidateHosts(from: descriptors)

    #expect(candidates.contains("desktop-lan.local"))
    #expect(candidates.contains("192.168.0.52"))
    #expect(candidates.contains("public-gateway.example.invalid"))
}

@Test("Host catalog cached candidates preserve explicit custom HTTPS ports")
func hostCatalogCachedCandidatesPreserveExplicitCustomPorts() {
    let descriptors = [
        ShadowClientRemoteHostDescriptor(
            host: "desktop-lan.local:48010",
            displayName: "Example-PC",
            pairStatus: .paired,
            currentGameID: 0,
            serverState: "SUNSHINE_SERVER_FREE",
            httpsPort: 47984,
            appVersion: "1.0",
            gfeVersion: nil,
            uniqueID: "HOST-123",
            lastError: nil,
            localHost: "192.168.0.52",
            remoteHost: "public-gateway.example.invalid",
            manualHost: "wan-gateway.example.invalid:48100"
        ),
    ]

    let candidates = ShadowClientHostCatalogKit.cachedCandidateHosts(from: descriptors)

    #expect(candidates.contains("desktop-lan.local:48010"))
    #expect(candidates.contains("wan-gateway.example.invalid:48100"))
}

@Test("Remote host descriptor keeps Apollo HTTPS route when seeded from connect candidate")
func remoteHostDescriptorMapsApolloConnectCandidateToHTTPSRoute() {
    let descriptor = ShadowClientRemoteHostDescriptor(
        host: "apollo-host.local:48989",
        displayName: "Apollo",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        httpsPort: 48984,
        appVersion: "1.0",
        gfeVersion: nil,
        uniqueID: "HOST-APOLLO",
        lastError: nil,
        localHost: "192.168.0.50:48989",
        remoteHost: nil,
        manualHost: nil
    )

    #expect(descriptor.host == "apollo-host.local")
    #expect(descriptor.httpsPort == 48984)
    #expect(descriptor.hostCandidate == "apollo-host.local:48989")
    #expect(descriptor.routes.local?.httpsPort == 48984)
}

@Test("Remote desktop runtime coalesces Apollo HTTPS endpoint aliases back to connect probe candidates")
@MainActor
func remoteDesktopRuntimeCoalescesApolloHTTPProbeCandidates() async {
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "apollo-host.local:48989": .init(
                host: "apollo-host.local",
                displayName: "Apollo Mac",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 48_984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-APOLLO"
            ),
        ],
        appListByHost: [:]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient()
    )

    runtime.refreshHosts(candidates: ["apollo-host.local:48989"])
    await waitForHostCatalogReady(runtime)

    runtime.refreshHosts(
        candidates: ["apollo-host.local:48989", "apollo-host.local:48984"]
    )
    await waitForHostCatalogReady(runtime)

    #expect(await metadataClient.serverInfoRequests() == [
        "apollo-host.local:48989",
        "apollo-host.local:48989",
    ])
    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.host == "apollo-host.local")
    #expect(runtime.hosts.first?.httpsPort == 48_984)
}

@Test("Remote desktop runtime prefers Bonjour hostname over IP for Apollo probe candidates in the same host group")
@MainActor
func remoteDesktopRuntimePrefersBonjourHostnameOverIPProbeCandidate() async {
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "192.168.0.50:48989": .init(
                host: "192.168.0.50",
                displayName: "Apollo Mac",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 48_984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-APOLLO"
            ),
            "buseongs-macbook-pro-14.local:48989": .init(
                host: "buseongs-macbook-pro-14.local",
                displayName: "Apollo Mac",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 48_984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-APOLLO"
            ),
        ],
        appListByHost: [:]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient()
    )

    runtime.refreshHosts(candidates: ["192.168.0.50:48989"])
    await waitForHostCatalogReady(runtime)

    runtime.refreshHosts(
        candidates: ["192.168.0.50:48989", "buseongs-macbook-pro-14.local:48989"]
    )
    await waitForHostCatalogReady(runtime)

    #expect(await metadataClient.serverInfoRequests() == [
        "192.168.0.50:48989",
        "buseongs-macbook-pro-14.local:48989",
    ])
    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.host == "buseongs-macbook-pro-14.local")
    #expect(runtime.hosts.first?.hostCandidate == "buseongs-macbook-pro-14.local:48989")
}

@Test("Remote desktop runtime prefers Bonjour hostname over remembered IP alias when pairing Apollo host")
@MainActor
func remoteDesktopRuntimePrefersBonjourHostnameOverRememberedIPAliasWhenPairingApolloHost() async {
    let defaultsSuite = "shadow-client.runtime.apollo-pair-hostname.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pairingRouteStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "192.168.0.50:48989": .init(
                host: "192.168.0.50",
                displayName: "Apollo Mac",
                pairStatus: .notPaired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 48_984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-APOLLO"
            ),
            "buseongs-macbook-pro-14.local:48989": .init(
                host: "buseongs-macbook-pro-14.local",
                displayName: "Apollo Mac",
                pairStatus: .notPaired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 48_984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-APOLLO"
            ),
        ],
        appListByHost: [:]
    )
    let controlClient = RecordingGameStreamControlClient(
        successfulHosts: ["buseongs-macbook-pro-14.local:48989"]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: controlClient,
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )

    runtime.refreshHosts(candidates: ["192.168.0.50:48989"])
    await waitForHostCatalogReady(runtime)

    guard let hostID = runtime.hosts.first?.id else {
        Issue.record("Expected seeded Apollo host")
        return
    }

    await runtime.rememberPreferredRoute("192.168.0.50:48989", forHostID: hostID)

    runtime.refreshHosts(
        candidates: ["192.168.0.50:48989", "buseongs-macbook-pro-14.local:48989"]
    )
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.first?.hostCandidate == "buseongs-macbook-pro-14.local:48989")

    runtime.pairSelectedHost()
    await waitForPairingState(runtime)

    #expect(runtime.pairingState == .paired("Paired"))
    #expect(await controlClient.pairRequests() == ["buseongs-macbook-pro-14.local:48989"])
}

@Test("Remote desktop runtime preserves routable local route over link-local Apollo route in merged host")
@MainActor
func remoteDesktopRuntimePreservesRoutableLocalRouteOverLinkLocalApolloRoute() async {
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "192.168.0.50:48989": .init(
                host: "192.168.0.50",
                localHost: "169.254.244.165",
                remoteHost: nil,
                manualHost: nil,
                displayName: "Apollo Mac",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 48_984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-APOLLO"
            ),
            "buseongs-macbook-pro-14.local:48989": .init(
                host: "buseongs-macbook-pro-14.local",
                localHost: "169.254.244.165",
                remoteHost: nil,
                manualHost: nil,
                displayName: "Apollo Mac",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 48_984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-APOLLO"
            ),
        ],
        appListByHost: [:]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient()
    )

    runtime.refreshHosts(
        candidates: ["192.168.0.50:48989", "buseongs-macbook-pro-14.local:48989"]
    )
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.host == "buseongs-macbook-pro-14.local")
    #expect(runtime.hosts.first?.routes.local?.host == "192.168.0.50")
    #expect(runtime.hosts.first?.routes.allEndpoints.map(\.host).contains("169.254.244.165") == false)
}

@Test("Remote desktop runtime only restores active route from cached host persistence")
@MainActor
func remoteDesktopRuntimeOnlyRestoresActiveRouteFromCachedPersistence() async {
    let defaultsSuite = "shadow-client.runtime.cached-host-active-route-only.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "desktop-lan.local": .init(
                host: "desktop-lan.local",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
            "192.168.0.52": .init(
                host: "192.168.0.52",
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

    let seedingRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )

    seedingRuntime.refreshHosts(candidates: ["desktop-lan.local", "192.168.0.52"])
    await waitForHostCatalogReady(seedingRuntime)
    #expect(seedingRuntime.hosts.first?.routes.allEndpoints.count == 2)

    let reloadedRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient(),
        defaults: defaults
    )

    #expect(reloadedRuntime.hosts.count == 1)
    #expect(reloadedRuntime.hosts.first?.routes.allEndpoints.map(\.host) == ["192.168.0.52"])
}

@Test("Remote desktop runtime remembers preferred route aliases for an existing host")
@MainActor
func remoteDesktopRuntimeRemembersPreferredRouteAliasForExistingHost() async {
    let defaultsSuite = "shadow-client.runtime.remember-route.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pairingRouteStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "desktop-lan.local": .init(
                host: "desktop-lan.local",
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
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )

    runtime.refreshHosts(candidates: ["desktop-lan.local"])
    await waitForHostCatalogReady(runtime)
    guard let hostID = runtime.hosts.first?.id else {
        Issue.record("Expected seeded host to exist")
        return
    }

    await runtime.rememberPreferredRoute("public-gateway.example.invalid", forHostID: hostID)

    #expect(runtime.hosts.first?.routes.allEndpoints.map(\.host).contains("public-gateway.example.invalid") == false)
    #expect(
        await pairingRouteStore.sessionPreferredHost(for: "uniqueid:host-123") == "public-gateway.example.invalid"
    )
    #expect(await pairingRouteStore.persistentPreferredHost(for: "uniqueid:host-123") == nil)
}

@Test("Remote desktop runtime keeps remembered route aliases in-session only")
@MainActor
func remoteDesktopRuntimeKeepsRememberedRouteAliasesInSessionOnly() async {
    let defaultsSuite = "shadow-client.runtime.remember-route-session-only.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pairingRouteStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "desktop-lan.local": .init(
                host: "desktop-lan.local",
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
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )

    runtime.refreshHosts(candidates: ["desktop-lan.local"])
    await waitForHostCatalogReady(runtime)
    guard let hostID = runtime.hosts.first?.id else {
        Issue.record("Expected seeded host to exist")
        return
    }

    await runtime.rememberPreferredRoute("public-gateway.example.invalid", forHostID: hostID)

    let reloadedStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    #expect(await reloadedStore.sessionPreferredHost(for: "uniqueid:host-123") == nil)
    #expect(await reloadedStore.persistentPreferredHost(for: "uniqueid:host-123") == nil)
}

@Test("Remote desktop runtime does not remember aliases owned by another known host")
@MainActor
func remoteDesktopRuntimeDoesNotRememberAliasOwnedByAnotherHost() async {
    let defaultsSuite = "shadow-client.runtime.remember-route-conflict.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pairingRouteStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "desktop-lan.local": .init(
                host: "desktop-lan.local",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
            "other-host.local": .init(
                host: "other-host.local",
                displayName: "Other-PC",
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
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient(),
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )

    runtime.refreshHosts(candidates: ["desktop-lan.local", "other-host.local"])
    await waitForHostCatalogReady(runtime)
    guard let hostID = runtime.hosts.first(where: { $0.uniqueID == "HOST-123" })?.id else {
        Issue.record("Expected primary host to exist")
        return
    }

    await runtime.rememberPreferredRoute("other-host.local", forHostID: hostID)

    #expect(runtime.hosts.first(where: { $0.uniqueID == "HOST-123" })?.routes.allEndpoints.map(\.host).contains("other-host.local") == false)
    #expect(await pairingRouteStore.preferredHost(for: "uniqueid:host-123") == nil)
}

@Test("Remote desktop runtime does not remember aliases already stored for another host")
@MainActor
func remoteDesktopRuntimeDoesNotRememberAliasStoredForAnotherHost() async {
    let defaultsSuite = "shadow-client.runtime.remember-route-stored-conflict.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pairingRouteStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    await pairingRouteStore.setPreferredHost("other-alias.example.invalid", for: "uniqueid:host-456")
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "desktop-lan.local": .init(
                host: "desktop-lan.local",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
            "other-host.local": .init(
                host: "other-host.local",
                displayName: "Other-PC",
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
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient(),
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )

    runtime.refreshHosts(candidates: ["desktop-lan.local", "other-host.local"])
    await waitForHostCatalogReady(runtime)
    guard let hostID = runtime.hosts.first(where: { $0.uniqueID == "HOST-123" })?.id else {
        Issue.record("Expected primary host to exist")
        return
    }

    await runtime.rememberPreferredRoute("other-alias.example.invalid", forHostID: hostID)

    #expect(runtime.hosts.first(where: { $0.uniqueID == "HOST-123" })?.routes.allEndpoints.map(\.host).contains("other-alias.example.invalid") == false)
    #expect(await pairingRouteStore.preferredHost(for: "uniqueid:host-123") == nil)
}

@Test("Remote desktop runtime rewrites stale custom port aliases to the reachable host route")
@MainActor
func remoteDesktopRuntimeRewritesStaleCustomPortAliasToReachableRoute() async {
    let defaultsSuite = "shadow-client.runtime.preferred-route-port-rewrite.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pairingRouteStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "wifi.example.invalid": .init(
                host: "wifi.example.invalid",
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
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )

    runtime.refreshHosts(candidates: ["wifi.example.invalid"])
    await waitForHostCatalogReady(runtime)

    await pairingRouteStore.setPreferredHost("wifi.example.invalid:48989", for: "uniqueid:host-123")

    runtime.refreshHosts(
        candidates: ["wifi.example.invalid", "wifi.example.invalid:48989"],
        preferredHost: "wifi.example.invalid:48989"
    )
    await waitForHostCatalogReady(runtime)

    #expect(await pairingRouteStore.preferredHost(for: "uniqueid:host-123") == "wifi.example.invalid")
    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.host == "wifi.example.invalid")
}

@Test("Remote desktop runtime does not treat session preferred aliases as host identity evidence")
@MainActor
func remoteDesktopRuntimeDoesNotPromoteSessionPreferredAliasesIntoKnownGroups() async {
    let defaultsSuite = "shadow-client.runtime.session-alias-grouping.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pairingRouteStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "pc-lan.local": .init(
                host: "pc-lan.local",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-PC"
            ),
            "macbook.local": .init(
                host: "macbook.local",
                displayName: "Example-Mac",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-MAC"
            ),
        ],
        appListByHost: [:]
    )
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient(),
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )

    runtime.refreshHosts(candidates: ["pc-lan.local", "macbook.local"])
    await waitForHostCatalogReady(runtime)
    await pairingRouteStore.setSessionPreferredHost("macbook.local", for: "uniqueid:host-pc")

    runtime.refreshHosts(candidates: ["pc-lan.local", "macbook.local"], preferredHost: "macbook.local")
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.count == 2)
    #expect(Set(runtime.hosts.compactMap(\.uniqueID)) == ["HOST-PC", "HOST-MAC"])
    #expect(runtime.hosts.first(where: { $0.uniqueID == "HOST-PC" })?.routes.allEndpoints.map(\.host).contains("macbook.local") == false)
}

@Test("Remote desktop runtime clears stale custom port aliases claimed by another host")
@MainActor
func remoteDesktopRuntimeClearsStaleCustomPortAliasesClaimedByAnotherHost() async {
    let defaultsSuite = "shadow-client.runtime.preferred-route-port-conflict.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pairingRouteStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "wifi.example.invalid": .init(
                host: "wifi.example.invalid",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
            "mac.local": .init(
                host: "mac.local",
                displayName: "Mac",
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
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: metadataClient,
        controlClient: RecordingGameStreamControlClient(),
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )

    runtime.refreshHosts(candidates: ["wifi.example.invalid", "mac.local"])
    await waitForHostCatalogReady(runtime)

    await pairingRouteStore.setPreferredHost("wifi.example.invalid:48989", for: "uniqueid:host-456")

    runtime.refreshHosts(
        candidates: ["wifi.example.invalid", "wifi.example.invalid:48989", "mac.local"]
    )
    await waitForHostCatalogReady(runtime)

    #expect(await pairingRouteStore.preferredHost(for: "uniqueid:host-456") == nil)
    #expect(runtime.hosts.first(where: { $0.uniqueID == "HOST-456" })?.routes.allEndpoints.map(\.host).contains("wifi.example.invalid") == false)
}

@Test("Remote desktop runtime ignores stale hostname aliases when choosing refresh probe candidates")
@MainActor
func remoteDesktopRuntimeIgnoresStaleHostnameAliasesForProbeSelection() async {
    let defaultsSuite = "shadow-client.runtime.stale-hostname-alias-refresh.\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: defaultsSuite) else {
        Issue.record("Expected isolated defaults suite")
        return
    }
    defer {
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    let pairingRouteStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    let seedingClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "wifi.example.invalid": .init(
                host: "wifi.example.invalid",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
            "mac.local": .init(
                host: "mac.local",
                displayName: "Mac",
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
    let seedingRuntime = ShadowClientRemoteDesktopRuntime(
        metadataClient: seedingClient,
        controlClient: RecordingGameStreamControlClient(),
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )

    seedingRuntime.refreshHosts(candidates: ["wifi.example.invalid", "mac.local"])
    await waitForHostCatalogReady(seedingRuntime)
    await pairingRouteStore.setPreferredHost("mac.local", for: "uniqueid:host-123")

    let probingClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "wifi.example.invalid": .init(
                host: "wifi.example.invalid",
                displayName: "Example-PC",
                pairStatus: .paired,
                currentGameID: 0,
                serverState: "SUNSHINE_SERVER_FREE",
                httpsPort: 47984,
                appVersion: "1.0",
                gfeVersion: nil,
                uniqueID: "HOST-123"
            ),
            "mac.local": .init(
                host: "mac.local",
                displayName: "Mac",
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
    let runtime = ShadowClientRemoteDesktopRuntime(
        metadataClient: probingClient,
        controlClient: RecordingGameStreamControlClient(),
        pairingRouteStore: pairingRouteStore,
        defaults: defaults
    )

    runtime.refreshHosts(candidates: ["wifi.example.invalid", "mac.local"])
    await waitForHostCatalogReady(runtime)

    let requests = await probingClient.serverInfoRequests()
    #expect(requests.contains("wifi.example.invalid"))
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
    await pinnedStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "10.0.0.20")

    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "10.0.0.20": .init(
                host: "10.0.0.20",
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
        candidates: ["10.0.0.20"],
        preferredHost: "10.0.0.20"
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
    await pinnedStore.setCertificateDER(Data([0x01, 0x02, 0x03]), forHost: "10.0.0.20")

    let pairingRouteStore = ShadowClientPairingRouteStore(defaultsSuiteName: defaultsSuite)
    await pairingRouteStore.setPreferredHost("10.0.0.20", for: "uniqueid:host-123")

    let metadataClient = FakeGameStreamMetadataClient(
        serverInfoByHost: [
            "10.0.0.20": .init(
                host: "10.0.0.20",
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
        candidates: ["10.0.0.20"],
        preferredHost: "10.0.0.20"
    )
    await waitForHostCatalogReady(runtime)

    runtime.deleteHost("10.0.0.20")

    #expect(runtime.hosts.isEmpty)
    #expect(runtime.selectedHost == nil)
    #expect(await pinnedStore.certificateDER(forHost: "10.0.0.20") == nil)
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
            "10.0.0.20": .init(
                host: "10.0.0.20",
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
        candidates: ["external-host.example.invalid", "10.0.0.20"]
    )
    await waitForHostCatalogReady(runtime)

    #expect(runtime.hosts.count == 1)
    #expect(runtime.hosts.first?.host == "10.0.0.20")
}

@Test("Remote desktop runtime rewrites launch session URLs to the active runtime host")
func remoteDesktopRuntimeRewritesLaunchSessionURLToRuntimeHost() {
    let rewritten = ShadowClientRemoteDesktopRuntime.rewrittenSessionURL(
        "rtsp://10.0.0.52:48010",
        runtimeHost: "public-gateway.example.invalid"
    )

    #expect(rewritten == "rtsp://public-gateway.example.invalid:48010")
}

@Test("Remote desktop runtime removes self-host candidates before probing metadata")
func remoteDesktopRuntimeRefreshProbeCandidatesExcludeCurrentMachineAliases() {
    let candidates = ShadowClientRemoteDesktopRuntime.refreshProbeCandidates(
        [
            "desktop-lan.local",
            "apollo-host.local",
            "10.0.0.50",
        ],
        localInterfaceHosts: [
            "apollo-host.local",
            "apollo-host",
            "10.0.0.50",
        ]
    )

    #expect(candidates == ["desktop-lan.local"])
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
    private let appListFailureByHost: [String: ShadowClientGameStreamError]
    private var recordedServerInfoHosts: [String] = []

    init(
        serverInfoByHost: [String: ShadowClientGameStreamServerInfo],
        appListByHost: [String: [ShadowClientRemoteAppDescriptor]],
        appListFailureByHost: [String: ShadowClientGameStreamError] = [:]
    ) {
        self.serverInfoByHost = serverInfoByHost
        self.appListByHost = appListByHost
        self.appListFailureByHost = appListFailureByHost
    }

    func fetchServerInfo(
        host: String,
        portHint _: ShadowClientGameStreamPortHint?
    ) async throws -> ShadowClientGameStreamServerInfo {
        recordedServerInfoHosts.append(host)
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

    func serverInfoRequests() -> [String] {
        recordedServerInfoHosts
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
