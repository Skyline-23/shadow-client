import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("Host handshake negotiation enables session-id-v1 when ping payloads and connect data exist")
func hostHandshakeNegotiationEnablesSessionIdentifierV1() {
    let negotiation = ShadowClientHostHandshakeNegotiation(
        audioPingPayload: Data("AUDIOPAYLOAD12345".utf8),
        videoPingPayload: Data("VIDEOPAYLOAD1234".utf8),
        controlConnectData: 12_345,
        encryptionRequestedFlags: 0x01,
        prefersSessionIdentifierV1: true,
        supportsEncryptedControlChannelV2: false,
        supportsEncryptedAudioTransport: false
    )

    #expect(negotiation.supportsSessionIdentifierV1)
    #expect(negotiation.moonlightFeatureFlags == 0x03)
    #expect(!negotiation.controlChannelEncryptionEnabled)
    #expect(negotiation.encryptionEnabledFlags == 0x00)
}

@Test("Host handshake negotiation falls back to legacy ping when payload negotiation is incomplete")
func hostHandshakeNegotiationDisablesSessionIdentifierV1WhenPayloadMissing() {
    let negotiation = ShadowClientHostHandshakeNegotiation(
        audioPingPayload: nil,
        videoPingPayload: Data("VIDEOPAYLOAD1234".utf8),
        controlConnectData: nil,
        encryptionRequestedFlags: 0x01,
        prefersSessionIdentifierV1: true,
        supportsEncryptedControlChannelV2: false,
        supportsEncryptedAudioTransport: false
    )

    #expect(!negotiation.supportsSessionIdentifierV1)
    #expect(negotiation.moonlightFeatureFlags == 0x01)
    #expect(!negotiation.controlChannelEncryptionEnabled)
    #expect(negotiation.encryptionEnabledFlags == 0x00)
}

@Test("Host handshake negotiation enables control-v2 only when client supports encrypted control channel")
func hostHandshakeNegotiationGatesEncryptedControlV2OnClientCapability() {
    let negotiation = ShadowClientHostHandshakeNegotiation(
        audioPingPayload: Data("AUDIOPAYLOAD12345".utf8),
        videoPingPayload: Data("VIDEOPAYLOAD1234".utf8),
        controlConnectData: 99,
        encryptionRequestedFlags: 0x01,
        prefersSessionIdentifierV1: true,
        supportsEncryptedControlChannelV2: true,
        supportsEncryptedAudioTransport: false
    )

    #expect(negotiation.supportsSessionIdentifierV1)
    #expect(negotiation.controlChannelEncryptionEnabled)
    #expect(negotiation.encryptionEnabledFlags == 0x01)
}

@Test("Host handshake negotiation enables encrypted audio flag when supported and requested")
func hostHandshakeNegotiationEnablesEncryptedAudioWhenRequested() {
    let negotiation = ShadowClientHostHandshakeNegotiation(
        audioPingPayload: Data("AUDIOPAYLOAD12345".utf8),
        videoPingPayload: Data("VIDEOPAYLOAD1234".utf8),
        controlConnectData: 99,
        encryptionRequestedFlags: 0x05,
        prefersSessionIdentifierV1: true,
        supportsEncryptedControlChannelV2: true,
        supportsEncryptedAudioTransport: true
    )

    #expect(negotiation.supportsSessionIdentifierV1)
    #expect(negotiation.controlChannelEncryptionEnabled)
    #expect(negotiation.audioEncryptionEnabled)
    #expect(negotiation.encryptionEnabledFlags == 0x05)
}
