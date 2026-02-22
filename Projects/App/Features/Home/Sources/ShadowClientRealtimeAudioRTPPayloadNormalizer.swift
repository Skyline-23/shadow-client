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

        if let redPrimary = extractRTPREDPrimaryPayload(from: payload),
           redPrimary.payloadType != wrapperPayloadType,
           (96 ... 127).contains(redPrimary.payloadType)
        {
            return .init(
                payloadType: redPrimary.payloadType,
                payload: redPrimary.payload,
                normalizationKey: "rtp-red:\(wrapperPayloadType)->\(redPrimary.payloadType)",
                normalizationMessage: "Unwrapped RTP RED payload type \(wrapperPayloadType) to primary payload type \(redPrimary.payloadType)"
            )
        }

        if preferredPayloadType != wrapperPayloadType,
           isLikelyDirectOpusPayload(payload)
        {
            return .init(
                payloadType: preferredPayloadType,
                payload: payload,
                normalizationKey: "rtp-direct-opus:\(wrapperPayloadType)->\(preferredPayloadType)",
                normalizationMessage: "Treating RTP payload type \(wrapperPayloadType) as direct Opus for payload type \(preferredPayloadType)"
            )
        }

        return .init(
            payloadType: payloadType,
            payload: payload,
            normalizationKey: nil,
            normalizationMessage: nil
        )
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

    private static func isLikelyDirectOpusPayload(_ payload: Data) -> Bool {
        guard !payload.isEmpty, payload.count <= 1_500 else {
            return false
        }
        let toc = payload[payload.startIndex]
        switch toc & 0x03 {
        case 0, 1, 2:
            return true
        case 3:
            guard payload.count >= 2 else {
                return false
            }
            let encodedFrameCount = Int(payload[payload.startIndex + 1] & 0x3F)
            return encodedFrameCount > 0 && encodedFrameCount <= 48
        default:
            return false
        }
    }
}
