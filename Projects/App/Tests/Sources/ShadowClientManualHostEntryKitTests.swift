import Testing
@testable import ShadowClientFeatureHome

@Test("Manual host entry kit normalizes host names and preserves explicit ports")
func manualHostEntryKitNormalization() {
    #expect(ShadowClientManualHostEntryKit.normalizedDraft("  ExampleHost  ") == "examplehost")
    #expect(ShadowClientManualHostEntryKit.normalizedDraft("https://ExampleHost:48010") == "examplehost:48010")
    #expect(ShadowClientManualHostEntryKit.normalizedDraft("   ") == "")
    #expect(
        ShadowClientManualHostEntryKit.normalizedDraft(
            hostDraft: "https://ExampleHost:47984",
            portDraft: "48010"
        ) == "examplehost:48010"
    )
    #expect(
        ShadowClientManualHostEntryKit.normalizedDraft(
            hostDraft: "ExampleHost",
            portDraft: "  "
        ) == "examplehost"
    )
}

@Test("Manual host entry kit only enables submission for non-empty normalized drafts")
func manualHostEntryKitSubmitGate() {
    #expect(ShadowClientManualHostEntryKit.canSubmit("desktop.local"))
    #expect(!ShadowClientManualHostEntryKit.canSubmit("   "))
    #expect(ShadowClientManualHostEntryKit.canSubmit(hostDraft: "desktop.local", portDraft: "48010"))
    #expect(!ShadowClientManualHostEntryKit.canSubmit(hostDraft: "desktop.local", portDraft: "abc"))
    #expect(!ShadowClientManualHostEntryKit.canSubmit(hostDraft: "desktop.local", portDraft: "70000"))
}
