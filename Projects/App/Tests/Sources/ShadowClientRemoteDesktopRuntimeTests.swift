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
    #expect(runtime.appState == .loaded)
    #expect(runtime.apps.isEmpty)
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
