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
    #expect(negotiation.encryptionEnabledFlags == 0x00)
}

@Test("Host handshake negotiation disables session-id-v1 when ping negotiation is incomplete")
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

@Test("Lumen control transport negotiation rejects missing session-id-v1 support")
func lumenControlTransportNegotiationRejectsMissingSessionIdentifierV1Support() {
    let handshakeNegotiation = ShadowClientHostHandshakeNegotiation(
        audioPingPayload: nil,
        videoPingPayload: Data("VIDEOPAYLOAD1234".utf8),
        controlConnectData: 99,
        encryptionRequestedFlags: 0x01,
        prefersSessionIdentifierV1: true,
        supportsEncryptedControlChannelV2: true,
        supportsEncryptedAudioTransport: false
    )

    #expect(
        throws: ShadowClientRTSPInterleavedClientError.requestFailed(
            "Lumen transport requires negotiated session ID ping support."
        )
    ) {
        _ = try ShadowClientLumenControlTransportNegotiation.resolve(
            handshakeNegotiation: handshakeNegotiation,
            remoteInputKey: Data(repeating: 0x11, count: 16),
            remoteInputKeyID: 7
        )
    }
}

@Test("Lumen control transport negotiation rejects missing encrypted control-v2 support")
func lumenControlTransportNegotiationRejectsMissingEncryptedControlV2Support() {
    let handshakeNegotiation = ShadowClientHostHandshakeNegotiation(
        audioPingPayload: Data("AUDIOPAYLOAD12345".utf8),
        videoPingPayload: Data("VIDEOPAYLOAD1234".utf8),
        controlConnectData: 99,
        encryptionRequestedFlags: 0x00,
        prefersSessionIdentifierV1: true,
        supportsEncryptedControlChannelV2: false,
        supportsEncryptedAudioTransport: false
    )

    #expect(
        throws: ShadowClientRTSPInterleavedClientError.requestFailed(
            "Lumen transport requires encrypted control stream v2 support."
        )
    ) {
        _ = try ShadowClientLumenControlTransportNegotiation.resolve(
            handshakeNegotiation: handshakeNegotiation,
            remoteInputKey: Data(repeating: 0x22, count: 16),
            remoteInputKeyID: 9
        )
    }
}

@Test("Lumen control transport negotiation enables encrypted control-v2 and negotiated audio")
func lumenControlTransportNegotiationBuildsEncryptedControlAndAudioConfiguration() throws {
    let handshakeNegotiation = ShadowClientHostHandshakeNegotiation(
        audioPingPayload: Data("AUDIOPAYLOAD12345".utf8),
        videoPingPayload: Data("VIDEOPAYLOAD1234".utf8),
        controlConnectData: 99,
        encryptionRequestedFlags: 0x05,
        prefersSessionIdentifierV1: true,
        supportsEncryptedControlChannelV2: true,
        supportsEncryptedAudioTransport: true
    )
    let remoteInputKey = Data(repeating: 0x33, count: 16)
    let negotiation = try ShadowClientLumenControlTransportNegotiation.resolve(
        handshakeNegotiation: handshakeNegotiation,
        remoteInputKey: remoteInputKey,
        remoteInputKeyID: 11
    )

    switch negotiation.controlChannelMode {
    case .encryptedV2(let key):
        #expect(key == remoteInputKey)
    case .plaintext:
        Issue.record("Expected encrypted control-v2 mode")
    }
    #expect(negotiation.controlModeLabel == "encrypted-v2")
    #expect(negotiation.audioEncryptionLabel == "encrypted")
    #expect(negotiation.audioEncryptionConfiguration == .init(key: remoteInputKey, keyID: 11))
}
