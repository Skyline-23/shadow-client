import Testing
@testable import ShadowClientFeatureHome

@Test("Pairing state exposes the current local PIN while pairing")
func pairingStateExposesCurrentLocalPIN() {
    let state = ShadowClientRemotePairingState.pairing(host: "wifi.skyline23.com", pin: "1234")

    #expect(state.activePIN == "1234")
    #expect(state.isInProgress)
    #expect(state.label == "Pairing with wifi.skyline23.com. Enter displayed PIN in Apollo.")
}
