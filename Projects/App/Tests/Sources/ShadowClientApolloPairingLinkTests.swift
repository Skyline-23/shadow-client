import Testing
@testable import ShadowClientFeatureHome

@Test("Pairing state exposes the current Lumen pairing code while pairing")
func pairingStateExposesCurrentLumenPairingCode() {
    let state = ShadowClientRemotePairingState.pairing(host: "external-route.example.invalid", code: "AB12CD")

    #expect(state.activeCode == "AB12CD")
    #expect(state.isInProgress)
    #expect(
        state.label ==
            "Pairing with external-route.example.invalid. Approve this device in Lumen using the displayed code."
    )
}
