import Testing
@testable import ShadowClientFeatureHome

@Test("Pairing state exposes the current Apollo pairing code while pairing")
func pairingStateExposesCurrentApolloPairingCode() {
    let state = ShadowClientRemotePairingState.pairing(host: "external-route.example.invalid", code: "AB12CD")

    #expect(state.activeCode == "AB12CD")
    #expect(state.isInProgress)
    #expect(
        state.label ==
            "Pairing with external-route.example.invalid. Approve this device in Apollo using the displayed code."
    )
}
