import Testing
@testable import ShadowClientFeatureHome

@Test("Host app library presentation formats primary action and app metadata copy")
func hostAppLibraryPresentationCopy() {
    #expect(
        ShadowClientHostAppLibraryPresentationKit.primaryActionHint(
            hostTitle: "Living Room",
            canConnect: true
        ) == "Connects to Living Room and opens the preferred remote session"
    )
    #expect(
        ShadowClientHostAppLibraryPresentationKit.primaryActionHint(
            hostTitle: "Living Room",
            canConnect: false
        ) == "Disabled until Living Room is ready"
    )
    #expect(ShadowClientHostAppLibraryPresentationKit.sectionTitle() == "App Library")
    #expect(ShadowClientHostAppLibraryPresentationKit.metadata(appID: 42, hdrSupported: true) == "App ID: 42 · HDR: Y")
    #expect(ShadowClientHostAppLibraryPresentationKit.launchAccessibilityHint() == "Launches the selected remote app and enters remote session view")
}

@Test("Host app library presentation exposes locked and empty callouts")
func hostAppLibraryPresentationCallouts() {
    #expect(ShadowClientHostAppLibraryPresentationKit.lockedCallout() == .init(title: "Locked", message: "Pair this device first to load desktop or game apps.", tone: .warning))
    #expect(ShadowClientHostAppLibraryPresentationKit.emptyCallout() == .init(title: "No Apps Yet", message: "Refresh after the host session becomes ready.", tone: .info))
}
