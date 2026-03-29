import Testing
@testable import ShadowClientFeatureHome

@Test("Host issue mapper ignores generic host app failures")
func hostIssueMapperIgnoresGenericHostAppFailures() {
    let host = ShadowClientRemoteHostDescriptor(
        host: "192.168.0.40",
        displayName: "Lumen-PC",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        httpsPort: 47984,
        appVersion: "7.0.0",
        gfeVersion: nil,
        uniqueID: "HOST-40",
        lastError: nil
    )

    let issue = ShadowClientRemoteHostIssueMapper.issue(
        for: host,
        selectedHostID: host.id,
        appState: .failed("Host rejected request (403): Forbidden"),
        launchState: .idle,
        sessionIssue: nil
    )

    #expect(issue == nil)
}

@Test("Host issue mapper prefers active session issues over app or launch failures")
func hostIssueMapperPrefersActiveSessionIssue() {
    let host = ShadowClientRemoteHostDescriptor(
        host: "192.168.0.28",
        displayName: "Loft-PC",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        httpsPort: 47984,
        appVersion: "7.0.0",
        gfeVersion: nil,
        uniqueID: "HOST-CLIPBOARD",
        lastError: nil
    )

    let issue = ShadowClientRemoteHostIssueMapper.issue(
        for: host,
        selectedHostID: host.id,
        appState: .failed("Host rejected request (403): Forbidden"),
        launchState: .failed("Host rejected request (403): Forbidden"),
        sessionIssue: .init(
            title: "Clipboard Sync Unavailable",
            message: "Lumen clipboard read is unavailable for this paired client."
        )
    )

    #expect(
        issue == .init(
            title: "Clipboard Sync Unavailable",
            message: "Lumen clipboard read is unavailable for this paired client."
        )
    )
}

@Test("Host issue mapper ignores generic failures for non-selected hosts")
func hostIssueMapperIgnoresGenericFailuresForNonSelectedHost() {
    let host = ShadowClientRemoteHostDescriptor(
        host: "192.168.0.40",
        displayName: "Lumen-PC",
        pairStatus: .paired,
        currentGameID: 0,
        serverState: "SUNSHINE_SERVER_FREE",
        httpsPort: 47984,
        appVersion: "7.0.0",
        gfeVersion: nil,
        uniqueID: "HOST-40",
        lastError: nil
    )

    let issue = ShadowClientRemoteHostIssueMapper.issue(
        for: host,
        selectedHostID: "other-host",
        appState: .failed("Host rejected request (403): Forbidden"),
        launchState: .idle,
        sessionIssue: nil
    )

    #expect(issue == nil)
}
