import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Sunshine handshake negotiation enables session-id-v1 when ping payloads and connect data exist")
func sunshineHandshakeNegotiationEnablesSessionIdentifierV1() {
    let negotiation = ShadowClientSunshineHandshakeNegotiation(
        audioPingPayload: Data("AUDIOPAYLOAD12345".utf8),
        videoPingPayload: Data("VIDEOPAYLOAD1234".utf8),
        controlConnectData: 12_345,
        encryptionRequestedFlags: 0x01,
        prefersSessionIdentifierV1: true,
        supportsEncryptedControlChannelV2: false
    )

    #expect(negotiation.supportsSessionIdentifierV1)
    #expect(negotiation.moonlightFeatureFlags == 0x03)
    #expect(!negotiation.controlChannelEncryptionEnabled)
    #expect(negotiation.encryptionEnabledFlags == 0x00)
}

@Test("Sunshine handshake negotiation falls back to legacy ping when payload negotiation is incomplete")
func sunshineHandshakeNegotiationDisablesSessionIdentifierV1WhenPayloadMissing() {
    let negotiation = ShadowClientSunshineHandshakeNegotiation(
        audioPingPayload: nil,
        videoPingPayload: Data("VIDEOPAYLOAD1234".utf8),
        controlConnectData: nil,
        encryptionRequestedFlags: 0x01,
        prefersSessionIdentifierV1: true,
        supportsEncryptedControlChannelV2: false
    )

    #expect(!negotiation.supportsSessionIdentifierV1)
    #expect(negotiation.moonlightFeatureFlags == 0x01)
    #expect(!negotiation.controlChannelEncryptionEnabled)
    #expect(negotiation.encryptionEnabledFlags == 0x00)
}

@Test("Sunshine handshake negotiation enables control-v2 only when client supports encrypted control channel")
func sunshineHandshakeNegotiationGatesEncryptedControlV2OnClientCapability() {
    let negotiation = ShadowClientSunshineHandshakeNegotiation(
        audioPingPayload: Data("AUDIOPAYLOAD12345".utf8),
        videoPingPayload: Data("VIDEOPAYLOAD1234".utf8),
        controlConnectData: 99,
        encryptionRequestedFlags: 0x01,
        prefersSessionIdentifierV1: true,
        supportsEncryptedControlChannelV2: true
    )

    #expect(negotiation.supportsSessionIdentifierV1)
    #expect(negotiation.controlChannelEncryptionEnabled)
    #expect(negotiation.encryptionEnabledFlags == 0x01)
}
