import Foundation

enum ShadowClientHostPingPacketCodec {
    static func makePingPackets(
        sequence: UInt32,
        negotiatedPayload: Data?
    ) -> [Data] {
        if let negotiatedPayload {
            let sequenceBytes = withUnsafeBytes(of: sequence.bigEndian) { Data($0) }
            var payloadThenSequence = negotiatedPayload
            payloadThenSequence.append(sequenceBytes)
            // Moonlight/Apollo-host v2 ping format:
            // [16-byte payload token][big-endian sequence].
            return [payloadThenSequence]
        }

        return []
    }
}
