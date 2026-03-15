import Foundation

struct ShadowClientH265RTPDepacketizer: Sendable {
    private var currentNALUnits: [Data] = []
    private var fragmentedNALBuffer: Data?

    mutating func reset() {
        currentNALUnits = []
        fragmentedNALBuffer = nil
    }

    mutating func ingest(payload: Data, marker: Bool) -> Data? {
        guard payload.count >= 3 else {
            return marker ? flushIfNeeded() : nil
        }

        let nalType = (payload[0] >> 1) & 0x3F
        if nalType == 49 {
            ingestFragmentationUnit(payload)
        } else if nalType == 48 {
            // RFC7798 AP packet: split embedded NAL units by 16-bit length prefix.
            ingestAggregationPacket(payload)
        } else {
            fragmentedNALBuffer = nil
            currentNALUnits.append(payload)
        }

        if marker {
            return flushIfNeeded()
        }
        return nil
    }

    private mutating func ingestFragmentationUnit(_ payload: Data) {
        guard payload.count >= 3 else {
            return
        }

        let fuHeader = payload[2]
        let start = (fuHeader & 0x80) != 0
        let end = (fuHeader & 0x40) != 0
        let nalType = fuHeader & 0x3F
        let reconstructedFirstByte = (payload[0] & 0x81) | (nalType << 1)
        let reconstructedSecondByte = payload[1]
        let fuPayload = payload.dropFirst(3)

        if start {
            var nal = Data([reconstructedFirstByte, reconstructedSecondByte])
            nal.append(contentsOf: fuPayload)
            fragmentedNALBuffer = nal
            if end, let fragmentedNALBuffer {
                currentNALUnits.append(fragmentedNALBuffer)
                self.fragmentedNALBuffer = nil
            }
            return
        }

        guard var buffer = fragmentedNALBuffer else {
            return
        }
        buffer.append(contentsOf: fuPayload)
        fragmentedNALBuffer = buffer

        if end {
            currentNALUnits.append(buffer)
            fragmentedNALBuffer = nil
        }
    }

    private mutating func ingestAggregationPacket(_ payload: Data) {
        guard payload.count > 2 else {
            return
        }

        fragmentedNALBuffer = nil
        var cursor = 2
        while cursor + 2 <= payload.count {
            let nalLength = (Int(payload[cursor]) << 8) | Int(payload[cursor + 1])
            cursor += 2

            guard nalLength > 0 else {
                continue
            }
            guard cursor + nalLength <= payload.count else {
                return
            }

            currentNALUnits.append(
                Data(payload[cursor ..< (cursor + nalLength)])
            )
            cursor += nalLength
        }
    }

    private mutating func flushIfNeeded() -> Data? {
        guard !currentNALUnits.isEmpty else {
            return nil
        }

        var annexB = Data()
        for nal in currentNALUnits {
            annexB.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            annexB.append(nal)
        }
        currentNALUnits = []
        return annexB
    }
}
