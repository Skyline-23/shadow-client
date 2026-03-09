import Foundation

enum ShadowClientSunshineENetProtocolProfile {
    static let maximumPeerID: UInt16 = 0x0FFF
    static let controlChannelCount: UInt32 = 0x30

    static let protocolHeaderFlagSentTime: UInt16 = 1 << 15
    static let protocolHeaderFlagCompressed: UInt16 = 1 << 14
    static let protocolHeaderSessionShift: UInt16 = 12
    static let protocolHeaderSessionMask: UInt16 = 3 << protocolHeaderSessionShift
    static let sessionValueMask: UInt8 = 0x03

    static let protocolCommandMask: UInt8 = 0x0F
    static let protocolCommandFlagAcknowledge: UInt8 = 1 << 7
    static let protocolCommandAcknowledge: UInt8 = 1
    static let protocolCommandConnect: UInt8 = 2
    static let protocolCommandVerifyConnect: UInt8 = 3
    static let protocolCommandDisconnect: UInt8 = 4
    static let protocolCommandPing: UInt8 = 5
    static let protocolCommandSendReliable: UInt8 = 6
    static let protocolCommandSendUnreliable: UInt8 = 7
    static let protocolCommandSendFragment: UInt8 = 8
    static let protocolCommandSendUnsequenced: UInt8 = 9
    static let protocolCommandBandwidthLimit: UInt8 = 10
    static let protocolCommandThrottleConfigure: UInt8 = 11
    static let protocolCommandSendUnreliableFragment: UInt8 = 12

    // ENet commandSizes[] from protocol.c
    static let fixedCommandSizes: [UInt8: Int] = [
        protocolCommandAcknowledge: 8,
        protocolCommandConnect: 48,
        protocolCommandVerifyConnect: 44,
        protocolCommandDisconnect: 8,
        protocolCommandPing: 4,
        protocolCommandSendReliable: 6,
        protocolCommandSendUnreliable: 8,
        protocolCommandSendFragment: 24,
        protocolCommandSendUnsequenced: 8,
        protocolCommandBandwidthLimit: 12,
        protocolCommandThrottleConfigure: 16,
        protocolCommandSendUnreliableFragment: 24,
    ]

    static let firstOutgoingReliableSequence: UInt16 = 1
    static let localIncomingPeerID: UInt16 = 0
    static let wildcardSessionID: UInt8 = 0xFF

    static let defaultMTU: UInt32 = 1_392
    static let maximumWindowSize: UInt32 = 65_536
    static let packetThrottleIntervalMs: UInt32 = 5_000
    static let packetThrottleAcceleration: UInt32 = 2
    static let packetThrottleDeceleration: UInt32 = 2
}

enum ShadowClientSunshineHandshakeProfile {
    static let encryptionDisabled: UInt32 = 0
    static let moonlightFeatureFlagFECStatus: UInt32 = 0x01
    static let moonlightFeatureFlagSessionIDV1: UInt32 = 0x02

    static let sunshineEncryptionControlV2: UInt32 = 0x01
    static let sunshineEncryptionAudio: UInt32 = 0x04
    static let featureFlagsAttributePrefix = "x-ss-general.featureflags:"
    static let encryptionSupportedAttributePrefix = "x-ss-general.encryptionsupported:"
    static let encryptionRequestedAttributePrefix = "x-ss-general.encryptionrequested:"
}

enum ShadowClientSunshineControlMessageProfile {
    static let genericChannelID: UInt8 = 0x00
    static let urgentChannelID: UInt8 = 0x01
    static let keyboardChannelID: UInt8 = 0x02
    static let mouseChannelID: UInt8 = 0x03
    static let gamepadChannelBaseID: UInt8 = 0x10

    static let startATypeLegacy: UInt16 = 0x0305
    static let startATypeEncryptedV2: UInt16 = 0x0302
    static let startBType: UInt16 = 0x0307
    static let invalidateReferenceFramesType: UInt16 = 0x0301
    static let periodicPingType: UInt16 = 0x0200
    static let inputDataType: UInt16 = 0x0206
    static let rumbleType: UInt16 = 0x010b
    static let terminationType: UInt16 = 0x0109
    static let rumbleTriggersType: UInt16 = 0x5500
    static let setMotionEventType: UInt16 = 0x5501
    static let setRGBLEDType: UInt16 = 0x5502
    static let adaptiveTriggersType: UInt16 = 0x5503
    static let hdrModeType: UInt16 = 0x010e

    static let startAPayload = Data([0x00, 0x00])
    static let startBPayload = Data([0x00])
    static let periodicPingInterval: Duration = .milliseconds(100)
    static let periodicPingPayload = Data([0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

    static func invalidateReferenceFramesPayload(
        firstFrame: UInt32,
        lastFrame: UInt32
    ) -> Data {
        var payload = Data()
        payload.reserveCapacity(24)
        appendUInt32LE(firstFrame, to: &payload)
        appendUInt32LE(0, to: &payload)
        appendUInt32LE(lastFrame, to: &payload)
        appendUInt32LE(0, to: &payload)
        appendUInt32LE(0, to: &payload)
        appendUInt32LE(0, to: &payload)
        return payload
    }

    private static func appendUInt32LE(_ value: UInt32, to payload: inout Data) {
        payload.append(UInt8(truncatingIfNeeded: value))
        payload.append(UInt8(truncatingIfNeeded: value >> 8))
        payload.append(UInt8(truncatingIfNeeded: value >> 16))
        payload.append(UInt8(truncatingIfNeeded: value >> 24))
    }
}

enum ShadowClientRTSPAnnounceProfile {
    static let fallbackHostAddress = "127.0.0.1"

    static let bitStreamFormatH264 = "0"
    static let bitStreamFormatH265 = "1"
    static let bitStreamFormatAV1 = "2"

    static let hevcSupportDisabled = "0"
    static let hevcSupportEnabled = "1"

    static let reliableUDPModeStandard = "1"
    static let reliableUDPModeEncrypted = "13"
    static let useControlChannelEnabled = "1"

    // Match Moonlight Gen5 baseline flags so Sunshine parsing stays on the
    // expected feature path instead of host defaults.
    static let nvFeatureFlagsBase: UInt32 = 0x87
    static let nvFeatureFlagEncryptionControlV2: UInt32 = 0x80
    static let nvFeatureFlagEncryptedAudio: UInt32 = 0x20

    static let chromaSamplingType420 = "0"
    static let chromaSamplingType444 = "1"
    static let packetSize = "1392"
    static let rateControlMode = "4"
    static let timeoutLengthMs = "7000"
    static let invalidReferenceThreshold = "0"
    static let fecEnabled = "1"
    static let qualityScoreUpdateTimeMs = "5000"
    static let videoQoSTrafficType = "5"
    static let audioQoSTrafficType = "4"
    static let fecMinimumRequiredPackets = "2"
    static let bllFecEnabled = "0"
    static let drcEnabled = "0"
    static let recoveryModeEnabled = "0"
    static let encoderSlicesPerFrame = "1"
    static let dynamicRangeModeSDR = "0"
    static let dynamicRangeModeHDR = "1"
    static let maxReferenceFrames = "0"
    static let stereoAudioNumChannels = "2"
    static let stereoAudioChannelMask = "3"
    static let surroundAudioNumChannels = "6"
    static let surroundAudioChannelMask = "63"
    static let surroundDisabled = "0"
    static let surroundEnabled = "1"
    static let surroundAudioQualityDisabled = "0"
    static let surroundAudioQualityEnabled = "1"
    static let aqosPacketDuration = "5"
    static let encoderCSCMode = "0"

    static let sdpVersion = "0"
    static let sdpOriginUsername = "shadowclient"
    static let sdpOriginSessionID = "0"
    static let sdpOriginSessionVersion = "14"
    static let sdpOriginNetworkType = "IN"
    static let sdpOriginAddressType = "IPv4"
    static let sdpSessionName = "ShadowClient Remote Session"
    static let sdpTiming = "0 0"
    static let sdpMediaNameVideo = "video"

    static func bitStreamFormat(for codec: ShadowClientVideoCodec) -> String {
        switch codec {
        case .h264:
            return bitStreamFormatH264
        case .h265:
            return bitStreamFormatH265
        case .av1:
            return bitStreamFormatAV1
        }
    }

    static func hevcSupport(for codec: ShadowClientVideoCodec) -> String {
        switch codec {
        case .h264:
            return hevcSupportDisabled
        case .h265, .av1:
            return hevcSupportEnabled
        }
    }

    static func reliableUDPMode(encryptionEnabledFlags: UInt32) -> String {
        (encryptionEnabledFlags & ShadowClientSunshineHandshakeProfile.sunshineEncryptionControlV2) != 0
            ? reliableUDPModeEncrypted
            : reliableUDPModeStandard
    }

    static func negotiatedNVFeatureFlags(encryptionEnabledFlags: UInt32) -> UInt32 {
        var flags = nvFeatureFlagsBase
        if (encryptionEnabledFlags & ShadowClientSunshineHandshakeProfile.sunshineEncryptionControlV2) != 0 {
            flags |= nvFeatureFlagEncryptionControlV2
        }
        if (encryptionEnabledFlags & ShadowClientSunshineHandshakeProfile.sunshineEncryptionAudio) != 0 {
            flags |= nvFeatureFlagEncryptedAudio
        }
        return flags
    }

    static func refreshRateX100(for fps: Int) -> String {
        let boundedFPS = max(1, fps)
        return String(boundedFPS * 100)
    }

    static func chromaSamplingType(yuv444Enabled: Bool) -> String {
        yuv444Enabled ? chromaSamplingType444 : chromaSamplingType420
    }

    static func dynamicRangeMode(hdrEnabled: Bool) -> String {
        hdrEnabled ? dynamicRangeModeHDR : dynamicRangeModeSDR
    }

    static func audioNumChannels(surroundEnabled: Bool) -> String {
        surroundEnabled ? surroundAudioNumChannels : stereoAudioNumChannels
    }

    static func audioChannelMask(surroundEnabled: Bool) -> String {
        surroundEnabled ? surroundAudioChannelMask : stereoAudioChannelMask
    }

    static func surroundEnabledValue(surroundEnabled: Bool) -> String {
        surroundEnabled ? self.surroundEnabled : surroundDisabled
    }

    static func surroundAudioQuality(surroundEnabled: Bool) -> String {
        surroundEnabled ? surroundAudioQualityEnabled : surroundAudioQualityDisabled
    }
}

private extension Data {
    mutating func appendUInt64LE(_ value: UInt64) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { append(contentsOf: $0) }
    }
}
