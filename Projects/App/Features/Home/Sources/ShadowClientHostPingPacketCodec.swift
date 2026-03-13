import Foundation

enum ShadowClientHostPingPacketCodec {
    static func makePingPackets(
        sequence: UInt32,
        negotiatedPayload: Data?,
        fallbackASCII: String = ShadowClientRealtimeSessionDefaults.defaultPingASCII
    ) -> [Data] {
        let legacyPacket = Data(fallbackASCII.utf8)

        if let negotiatedPayload {
            let sequenceBytes = withUnsafeBytes(of: sequence.bigEndian) { Data($0) }
            var payloadThenSequence = negotiatedPayload
            payloadThenSequence.append(sequenceBytes)
            // Moonlight/Sunshine v2 ping format:
            // [16-byte payload token][big-endian sequence].
            return [payloadThenSequence]
        }

        return [legacyPacket]
    }
}
