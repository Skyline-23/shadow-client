import Testing
@testable import ShadowClientFeatureHome

@Test("Manual host entry kit normalizes host names and preserves explicit ports")
func manualHostEntryKitNormalization() {
    #expect(ShadowClientManualHostEntryKit.normalizedDraft("  ExampleHost  ") == "examplehost")
    #expect(ShadowClientManualHostEntryKit.normalizedDraft("https://ExampleHost:47984") == "examplehost")
    #expect(ShadowClientManualHostEntryKit.normalizedDraft("https://ExampleHost:47989") == "examplehost")
    #expect(ShadowClientManualHostEntryKit.normalizedDraft("https://ExampleHost:48010") == "examplehost:48010")
    #expect(ShadowClientManualHostEntryKit.normalizedDraft("ExampleHost", portDraft: "47989") == "examplehost")
    #expect(ShadowClientManualHostEntryKit.normalizedDraft("ExampleHost", portDraft: "48010") == "examplehost:48010")
    #expect(ShadowClientManualHostEntryKit.normalizedDraft("   ") == "")
}

@Test("Manual host entry kit only enables submission for non-empty normalized drafts")
func manualHostEntryKitSubmitGate() {
    #expect(ShadowClientManualHostEntryKit.canSubmit("desktop.local"))
    #expect(ShadowClientManualHostEntryKit.canSubmit("desktop.local", portDraft: "47984"))
    #expect(!ShadowClientManualHostEntryKit.canSubmit("desktop.local", portDraft: "99999"))
    #expect(!ShadowClientManualHostEntryKit.canSubmit("   "))
}
