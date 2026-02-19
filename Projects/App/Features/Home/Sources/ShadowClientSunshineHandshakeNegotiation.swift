import Foundation

struct ShadowClientSunshineHandshakeNegotiation: Sendable {
    let audioPingPayload: Data?
    let videoPingPayload: Data?
    let controlConnectData: UInt32?
    let encryptionRequestedFlags: UInt32
    let prefersSessionIdentifierV1: Bool

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

    var encryptionEnabledFlags: UInt32 {
        guard supportsSessionIdentifierV1 else {
            return 0
        }
        return encryptionRequestedFlags & ShadowClientSunshineHandshakeProfile.sunshineEncryptionControlV2
    }
}
