import Foundation

struct ShadowClientHostHandshakeNegotiation: Sendable {
    let audioPingPayload: Data?
    let videoPingPayload: Data?
    let controlConnectData: UInt32?
    let encryptionRequestedFlags: UInt32
    let prefersSessionIdentifierV1: Bool
    let supportsEncryptedControlChannelV2: Bool
    let supportsEncryptedAudioTransport: Bool

    var supportsSessionIdentifierV1: Bool {
        prefersSessionIdentifierV1 &&
            audioPingPayload != nil &&
            videoPingPayload != nil &&
            controlConnectData != nil
    }

    var moonlightFeatureFlags: UInt32 {
        var flags = ShadowClientSunshineHandshakeProfile.moonlightFeatureFlagFECStatus
        if supportsSessionIdentifierV1 {
            flags |= ShadowClientSunshineHandshakeProfile.moonlightFeatureFlagSessionIDV1
        }
        return flags
    }

    var controlChannelEncryptionEnabled: Bool {
        guard supportsSessionIdentifierV1, supportsEncryptedControlChannelV2 else {
            return false
        }
        return (encryptionRequestedFlags & ShadowClientSunshineHandshakeProfile.sunshineEncryptionControlV2) != 0
    }

    var audioEncryptionEnabled: Bool {
        guard supportsSessionIdentifierV1, supportsEncryptedAudioTransport else {
            return false
        }
        return (encryptionRequestedFlags & ShadowClientSunshineHandshakeProfile.sunshineEncryptionAudio) != 0
    }

    var encryptionEnabledFlags: UInt32 {
        var flags: UInt32 = 0
        if controlChannelEncryptionEnabled {
            flags |= ShadowClientSunshineHandshakeProfile.sunshineEncryptionControlV2
        }
        if audioEncryptionEnabled {
            flags |= ShadowClientSunshineHandshakeProfile.sunshineEncryptionAudio
        }
        return flags
    }
}
