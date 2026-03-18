import Testing
@testable import ShadowClientFeatureHome

@Test("Pairing state exposes the current local PIN while pairing")
func pairingStateExposesCurrentLocalPIN() {
    let state = ShadowClientRemotePairingState.pairing(host: "external-route.example.invalid", pin: "1234")

    #expect(state.activePIN == "1234")
    #expect(state.isInProgress)
    #expect(state.label == "Pairing with external-route.example.invalid. Enter displayed PIN in Apollo.")
}
