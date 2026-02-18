import Foundation

public struct ShadowClientH264DepacketizedOutput: Equatable, Sendable {
    public let annexBAccessUnit: Data
    public let parameterSets: [Data]

    public init(annexBAccessUnit: Data, parameterSets: [Data]) {
        self.annexBAccessUnit = annexBAccessUnit
        self.parameterSets = parameterSets
    }
}

public struct ShadowClientH264RTPDepacketizer: Sendable {
    private var currentNALUnits: [Data] = []
    private var fragmentedNALBuffer: Data?
    private var latestSPS: Data?
    private var latestPPS: Data?
    private var hasEmittedParameterSets = false

    public init() {}

    public mutating func reset() {
        currentNALUnits = []
        fragmentedNALBuffer = nil
        latestSPS = nil
        latestPPS = nil
        hasEmittedParameterSets = false
    }

    public mutating func ingest(payload: Data, marker: Bool) -> ShadowClientH264DepacketizedOutput? {
        guard !payload.isEmpty else {
            return marker ? flushIfNeeded() : nil
        }

        let nalType = payload[0] & 0x1F
        switch nalType {
        case 1...23:
            appendNALUnit(payload)
        case 24:
            ingestSTAPA(payload)
        case 28:
            ingestFUA(payload)
        default:
            break
        }

        if marker {
            return flushIfNeeded()
        }
        return nil
    }

    private mutating func ingestSTAPA(_ payload: Data) {
        guard payload.count > 1 else {
            return
        }

        var index = 1
        while (index + 2) <= payload.count {
            let length = Int(payload[index]) << 8 | Int(payload[index + 1])
            index += 2

            guard length > 0, (index + length) <= payload.count else {
                return
            }

            appendNALUnit(payload[index..<(index + length)])
            index += length
        }
    }

    private mutating func ingestFUA(_ payload: Data) {
        guard payload.count >= 2 else {
            return
        }

        let fuIndicator = payload[0]
        let fuHeader = payload[1]
        let start = (fuHeader & 0x80) != 0
        let end = (fuHeader & 0x40) != 0
        let reconstructedType = fuHeader & 0x1F
        let reconstructedHeader = (fuIndicator & 0xE0) | reconstructedType
        let fragmentPayload = payload.dropFirst(2)

        if start {
            var nal = Data()
            nal.append(reconstructedHeader)
            nal.append(contentsOf: fragmentPayload)
            fragmentedNALBuffer = nal
            if end {
                if let nal = fragmentedNALBuffer {
                    appendNALUnit(nal)
                }
                fragmentedNALBuffer = nil
            }
            return
        }

        guard var buffer = fragmentedNALBuffer else {
            return
        }

        buffer.append(contentsOf: fragmentPayload)
        fragmentedNALBuffer = buffer

        if end {
            appendNALUnit(buffer)
            fragmentedNALBuffer = nil
        }
    }

    private mutating func appendNALUnit<S>(_ payload: S) where S: DataProtocol {
        let nal = Data(payload)
        guard !nal.isEmpty else {
            return
        }

        let type = nal[0] & 0x1F
        if type == 7 {
            latestSPS = nal
        } else if type == 8 {
            latestPPS = nal
        }

        currentNALUnits.append(nal)
    }

    private mutating func flushIfNeeded() -> ShadowClientH264DepacketizedOutput? {
        guard !currentNALUnits.isEmpty else {
            return nil
        }

        var annexB = Data()
        var containsIDR = false
        for nal in currentNALUnits {
            annexB.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
            annexB.append(nal)
            if (nal[0] & 0x1F) == 5 {
                containsIDR = true
            }
        }

        let shouldEmitParameterSets = !hasEmittedParameterSets || containsIDR
        let parameterSets: [Data]
        if shouldEmitParameterSets,
           let sps = latestSPS,
           let pps = latestPPS
        {
            hasEmittedParameterSets = true
            parameterSets = [sps, pps]
        } else {
            parameterSets = []
        }

        currentNALUnits = []
        return ShadowClientH264DepacketizedOutput(
            annexBAccessUnit: annexB,
            parameterSets: parameterSets
        )
    }
}
