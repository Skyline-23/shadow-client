import Foundation

enum ShadowClientSunshinePingPacketCodec {
    static func makePingPackets(
        sequence: UInt32,
        negotiatedPayload: Data?,
        fallbackASCII: String = ShadowClientRealtimeSessionDefaults.defaultPingASCII
    ) -> [Data] {
        if let negotiatedPayload {
            let sequenceBytes = withUnsafeBytes(of: sequence.bigEndian) { Data($0) }
            var payloadThenSequence = negotiatedPayload
            payloadThenSequence.append(sequenceBytes)

            var sequenceThenPayload = sequenceBytes
            sequenceThenPayload.append(negotiatedPayload)

            if payloadThenSequence == sequenceThenPayload {
                return [payloadThenSequence]
            }
            return [payloadThenSequence, sequenceThenPayload]
        }

        return [Data(fallbackASCII.utf8)]
    }
}
