import Foundation

struct ShadowClientSunshineHandshakeNegotiation: Sendable {
    private static let moonlightFeatureFlagFECStatus: UInt32 = 0x01
    private static let moonlightFeatureFlagSessionIDV1: UInt32 = 0x02
    private static let sunshineEncryptionControlV2: UInt32 = 0x01

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
        var flags = Self.moonlightFeatureFlagFECStatus
        if supportsSessionIdentifierV1 {
            flags |= Self.moonlightFeatureFlagSessionIDV1
        }
        return flags
    }

    var encryptionEnabledFlags: UInt32 {
        guard supportsSessionIdentifierV1 else {
            return 0
        }
        return encryptionRequestedFlags & Self.sunshineEncryptionControlV2
    }
}
