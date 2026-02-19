import Foundation

enum ShadowClientSunshinePingPacketCodec {
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
            // Send both Sunshine v2 and legacy ping variants for host compatibility.
            // Sunshine accepts payload-matching pings, while some stacks still rely
            // on receiving the fixed ASCII probe during startup.
            return [payloadThenSequence, legacyPacket]
        }

        return [legacyPacket]
    }
}
