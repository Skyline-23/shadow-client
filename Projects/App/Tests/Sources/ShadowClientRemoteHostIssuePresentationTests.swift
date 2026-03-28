import Testing
@testable import ShadowClientFeatureHome

@Test("Host issue mapper surfaces selected host app permission denial")
func hostIssueMapperSurfacesSelectedHostAppPermissionDenial() {
    let host = ShadowClientRemoteHostDescriptor(
        host: "192.168.0.40",
        displayName: "Apollo-PC",
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
        appState: .failed("Lumen denied List Apps permission for this paired client."),
        launchState: .idle,
        sessionIssue: nil
    )

    #expect(
        issue == .init(
            title: "Lumen Permissions",
            message: "Lumen denied List Apps permission for this paired client."
        )
    )
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
        appState: .failed("Lumen denied List Apps permission for this paired client."),
        launchState: .failed("Lumen denied Launch Apps permission for this paired client."),
        sessionIssue: .init(
            title: "Clipboard Permission Required",
            message: "Grant Clipboard Read permission for this paired Lumen client."
        )
    )

    #expect(
        issue == .init(
            title: "Clipboard Permission Required",
            message: "Grant Clipboard Read permission for this paired Lumen client."
        )
    )
}

@Test("Host issue mapper ignores permission failures for non-selected hosts")
func hostIssueMapperIgnoresPermissionFailuresForNonSelectedHost() {
    let host = ShadowClientRemoteHostDescriptor(
        host: "192.168.0.40",
        displayName: "Apollo-PC",
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
        appState: .failed("Lumen denied List Apps permission for this paired client."),
        launchState: .idle,
        sessionIssue: nil
    )

    #expect(issue == nil)
}
