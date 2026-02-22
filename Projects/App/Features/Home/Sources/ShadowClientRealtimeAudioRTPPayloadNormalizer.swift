import Foundation

struct ShadowClientRealtimeAudioRTPPayloadNormalizer {
    struct Result: Sendable {
        let payloadType: Int
        let payload: Data
        let normalizationKey: String?
        let normalizationMessage: String?
    }

    static func normalize(
        payloadType: Int,
        payload: Data,
        preferredPayloadType: Int,
        wrapperPayloadType: Int
    ) -> Result {
        guard payloadType == wrapperPayloadType else {
            return .init(
                payloadType: payloadType,
                payload: payload,
                normalizationKey: nil,
                normalizationMessage: nil
            )
        }

        // Sunshine sends RTP PT127 as audio FEC shards, not decodable Opus payload.
        // Keep PT127 packets as-is so the runtime can skip decode on this type.
        if isLikelyMoonlightAudioFECPayload(
            payload,
            expectedPrimaryPayloadType: preferredPayloadType
        )
        {
            return .init(
                payloadType: payloadType,
                payload: payload,
                normalizationKey: "rtp-audio-fec:\(wrapperPayloadType)",
                normalizationMessage: "Classified RTP payload type \(wrapperPayloadType) as Moonlight audio FEC shard"
            )
        }

        if let (primaryPayloadType, primaryPayload) = extractRTPREDPrimaryPayload(from: payload),
           primaryPayloadType != wrapperPayloadType,
           (96 ... 127).contains(primaryPayloadType)
        {
            return .init(
                payloadType: primaryPayloadType,
                payload: primaryPayload,
                normalizationKey: "rtp-audio-red:\(wrapperPayloadType)->\(primaryPayloadType)",
                normalizationMessage: "Unwrapped RTP RED wrapper \(wrapperPayloadType) to primary payload type \(primaryPayloadType)"
            )
        }

        return .init(
            payloadType: payloadType,
            payload: payload,
            normalizationKey: nil,
            normalizationMessage: nil
        )
    }

    static func isLikelyMoonlightAudioFECPayload(
        _ payload: Data,
        expectedPrimaryPayloadType: Int
    ) -> Bool {
        // AUDIO_FEC_HEADER layout used by Moonlight/Sunshine:
        // shardIndex(1), payloadType(1), baseSequence(2), baseTimestamp(4), ssrc(4)
        guard payload.count >= 12 else {
            return false
        }
        let shardIndex = Int(payload[payload.startIndex])
        let payloadType = Int(payload[payload.startIndex + 1] & 0x7F)
        guard shardIndex >= 0, shardIndex < 8 else {
            return false
        }
        guard (96 ... 127).contains(payloadType) else {
            return false
        }
        return payloadType == expectedPrimaryPayloadType
    }

    static func extractRTPREDPrimaryPayload(
        from payload: Data
    ) -> (payloadType: Int, payload: Data)? {
        guard !payload.isEmpty else {
            return nil
        }

        struct REDBlockHeader: Sendable {
            let payloadType: Int
            let blockLength: Int?
        }

        var headers: [REDBlockHeader] = []
        var index = payload.startIndex
        while index < payload.endIndex {
            let headerByte = payload[index]
            index += 1

            let hasFollowingREDHeaders = (headerByte & 0x80) != 0
            let payloadType = Int(headerByte & 0x7F)
            if hasFollowingREDHeaders {
                guard (payload.endIndex - index) >= 3 else {
                    return nil
                }
                let byte2 = payload[index + 1]
                let byte3 = payload[index + 2]
                index += 3
                let blockLength = (Int(byte2 & 0x03) << 8) | Int(byte3)
                headers.append(
                    .init(
                        payloadType: payloadType,
                        blockLength: blockLength
                    )
                )
            } else {
                headers.append(
                    .init(
                        payloadType: payloadType,
                        blockLength: nil
                    )
                )
                break
            }
        }

        guard let primaryHeader = headers.last else {
            return nil
        }

        var payloadIndex = index
        for header in headers.dropLast() {
            guard let blockLength = header.blockLength else {
                return nil
            }
            guard payloadIndex + blockLength <= payload.endIndex else {
                return nil
            }
            payloadIndex += blockLength
        }

        guard payloadIndex < payload.endIndex else {
            return nil
        }
        let primaryPayload = Data(payload[payloadIndex ..< payload.endIndex])
        guard !primaryPayload.isEmpty else {
            return nil
        }
        return (primaryHeader.payloadType, primaryPayload)
    }

}
