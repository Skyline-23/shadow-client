import Foundation

enum ShadowClientAV1CodecConfigurationBuilder {
    private struct SequenceHeaderInfo {
        let seqProfile: UInt8
        let seqLevelIdx0: UInt8
        let seqTier0: Bool
        let highBitdepth: Bool
        let twelveBit: Bool
        let monochrome: Bool
        let chromaSubsamplingX: Bool
        let chromaSubsamplingY: Bool
        let chromaSamplePosition: UInt8
    }

    private struct SequenceHeaderOBU {
        let payload: Data
        let encodedWithSizeField: Data
    }

    private struct ParsedOBU {
        let type: UInt8
        let hasSizeField: Bool
        let nextIndex: Int
        let sequenceHeader: SequenceHeaderOBU?
    }

    static func build(fromAccessUnit accessUnit: Data) -> Data? {
        guard let sequenceHeaderOBU = firstSequenceHeaderOBU(in: accessUnit),
              let info = parseSequenceHeaderInfo(from: sequenceHeaderOBU.payload)
        else {
            return nil
        }

        return makeCodecConfiguration(
            from: info,
            sequenceHeaderOBU: sequenceHeaderOBU.encodedWithSizeField
        )
    }

    static func fallbackCodecConfigurationRecord(
        hdrEnabled: Bool,
        yuv444Enabled: Bool
    ) -> Data {
        let info = SequenceHeaderInfo(
            seqProfile: yuv444Enabled ? 1 : 0,
            seqLevelIdx0: 0,
            seqTier0: false,
            highBitdepth: hdrEnabled,
            twelveBit: false,
            monochrome: false,
            chromaSubsamplingX: !yuv444Enabled,
            chromaSubsamplingY: !yuv444Enabled,
            chromaSamplePosition: 0
        )

        return makeCodecConfiguration(from: info, sequenceHeaderOBU: nil)
    }

    private static func makeCodecConfiguration(
        from info: SequenceHeaderInfo,
        sequenceHeaderOBU: Data?
    ) -> Data {
        var codecConfiguration = Data()
        codecConfiguration.append(0x81) // marker=1, version=1
        codecConfiguration.append((info.seqProfile << 5) | (info.seqLevelIdx0 & 0x1F))

        var byte2: UInt8 = 0
        if info.seqTier0 {
            byte2 |= 0x80
        }
        if info.highBitdepth {
            byte2 |= 0x40
        }
        if info.twelveBit {
            byte2 |= 0x20
        }
        if info.monochrome {
            byte2 |= 0x10
        }
        if info.chromaSubsamplingX {
            byte2 |= 0x08
        }
        if info.chromaSubsamplingY {
            byte2 |= 0x04
        }
        byte2 |= info.chromaSamplePosition & 0x03
        codecConfiguration.append(byte2)

        // initial_presentation_delay_present = 0
        codecConfiguration.append(0x00)

        if let sequenceHeaderOBU {
            codecConfiguration.append(sequenceHeaderOBU)
        }

        return codecConfiguration
    }

    private static func firstSequenceHeaderOBU(in accessUnit: Data) -> SequenceHeaderOBU? {
        let bytes = [UInt8](accessUnit)
        guard !bytes.isEmpty else {
            return nil
        }

        if let sequenceHeader = extractSequenceHeaderFromOBUStream(
            bytes,
            startAt: 0,
            stopOnUnsizedNonSequence: true
        ) {
            return sequenceHeader
        }

        if let sequenceHeader = extractSequenceHeaderFromLengthDelimitedUnits(bytes) {
            return sequenceHeader
        }

        if let sequenceHeader = scanForSizedSequenceHeaderOBU(bytes) {
            return sequenceHeader
        }

        return nil
    }

    private static func extractSequenceHeaderFromOBUStream(
        _ bytes: [UInt8],
        startAt start: Int,
        stopOnUnsizedNonSequence: Bool
    ) -> SequenceHeaderOBU? {
        var index = start

        while index < bytes.count {
            guard let parsedOBU = parseOBU(
                in: bytes,
                at: index,
                allowUnsizedPayload: true
            ) else {
                return nil
            }

            if let sequenceHeader = parsedOBU.sequenceHeader {
                return sequenceHeader
            }

            if !parsedOBU.hasSizeField && stopOnUnsizedNonSequence {
                return nil
            }

            index = parsedOBU.nextIndex
        }

        return nil
    }

    private static func extractSequenceHeaderFromLengthDelimitedUnits(
        _ bytes: [UInt8]
    ) -> SequenceHeaderOBU? {
        var index = 0

        while index < bytes.count {
            guard let leb = decodeLEB128(from: bytes, at: index), leb.value > 0 else {
                return nil
            }
            index += leb.length

            guard index + leb.value <= bytes.count else {
                return nil
            }

            let unitBytes = Array(bytes[index..<(index + leb.value)])
            if let sequenceHeader = extractSequenceHeaderFromOBUStream(
                unitBytes,
                startAt: 0,
                stopOnUnsizedNonSequence: false
            ) {
                return sequenceHeader
            }

            index += leb.value
        }

        return nil
    }

    private static func scanForSizedSequenceHeaderOBU(
        _ bytes: [UInt8]
    ) -> SequenceHeaderOBU? {
        guard !bytes.isEmpty else {
            return nil
        }

        for start in bytes.indices {
            guard let parsedOBU = parseOBU(
                in: bytes,
                at: start,
                allowUnsizedPayload: false
            ) else {
                continue
            }

            if let sequenceHeader = parsedOBU.sequenceHeader {
                return sequenceHeader
            }
        }

        return nil
    }

    private static func parseOBU(
        in bytes: [UInt8],
        at start: Int,
        allowUnsizedPayload: Bool
    ) -> ParsedOBU? {
        guard start < bytes.count else {
            return nil
        }

        let header = bytes[start]

        // forbidden bit must be 0
        guard (header & 0x80) == 0 else {
            return nil
        }

        let obuType = (header >> 3) & 0x0F
        let hasExtension = (header & 0x04) != 0
        let hasSizeField = (header & 0x02) != 0

        var payloadStart = start + 1
        var extensionByte: UInt8?

        if hasExtension {
            guard payloadStart < bytes.count else {
                return nil
            }
            extensionByte = bytes[payloadStart]
            payloadStart += 1
        }

        let payloadSize: Int
        let sizeFieldBytes: [UInt8]
        if hasSizeField {
            guard let leb = decodeLEB128(from: bytes, at: payloadStart) else {
                return nil
            }
            payloadSize = leb.value
            sizeFieldBytes = leb.bytes
            payloadStart += leb.length
        } else {
            guard allowUnsizedPayload else {
                return nil
            }
            payloadSize = bytes.count - payloadStart
            sizeFieldBytes = encodeLEB128(payloadSize)
        }

        guard payloadSize >= 0, payloadStart + payloadSize <= bytes.count else {
            return nil
        }

        let payloadEnd = payloadStart + payloadSize
        let payload = Data(bytes[payloadStart..<payloadEnd])

        var encoded = Data()
        encoded.append(header | 0x02) // force obu_has_size_field=1 in av1C
        if let extensionByte {
            encoded.append(extensionByte)
        }
        encoded.append(contentsOf: sizeFieldBytes)
        encoded.append(payload)

        let sequenceHeader: SequenceHeaderOBU? = obuType == 1
            ? SequenceHeaderOBU(payload: payload, encodedWithSizeField: encoded)
            : nil

        return ParsedOBU(
            type: obuType,
            hasSizeField: hasSizeField,
            nextIndex: payloadEnd,
            sequenceHeader: sequenceHeader
        )
    }

    private static func parseSequenceHeaderInfo(from payload: Data) -> SequenceHeaderInfo? {
        var reader = AV1BitReader(payload)

        guard let seqProfileBits = reader.readBits(3),
              reader.readBits(1) != nil, // still_picture
              let reducedStillPictureHeader = reader.readBool()
        else {
            return nil
        }

        let seqProfile = UInt8(seqProfileBits)
        var seqLevelIdx0: UInt8 = 0
        var seqTier0 = false

        var decoderModelInfoPresent = false
        var initialDisplayDelayPresent = false
        var bufferDelayLengthMinus1 = 0

        if reducedStillPictureHeader {
            guard let levelBits = reader.readBits(5) else {
                return nil
            }
            seqLevelIdx0 = UInt8(levelBits)
        } else {
            let timingInfoPresent = reader.readBool() ?? false
            if timingInfoPresent {
                guard reader.skipBits(32), // num_units_in_display_tick
                      reader.skipBits(32), // time_scale
                      let equalPictureInterval = reader.readBool()
                else {
                    return nil
                }
                if equalPictureInterval {
                    guard reader.readUVLC() != nil else {
                        return nil
                    }
                }

                decoderModelInfoPresent = reader.readBool() ?? false
                if decoderModelInfoPresent {
                    guard let bufferDelayBits = reader.readBits(5),
                          reader.skipBits(32), // num_units_in_decoding_tick
                          reader.readBits(5) != nil, // buffer_removal_time_length_minus_1
                          reader.readBits(5) != nil // frame_presentation_time_length_minus_1
                    else {
                        return nil
                    }
                    bufferDelayLengthMinus1 = Int(bufferDelayBits)
                }
            }

            initialDisplayDelayPresent = reader.readBool() ?? false
            guard let operatingPointsCountMinus1Bits = reader.readBits(5) else {
                return nil
            }

            let operatingPointsCountMinus1 = Int(operatingPointsCountMinus1Bits)
            for operatingPointIndex in 0...operatingPointsCountMinus1 {
                guard reader.skipBits(12), // operating_point_idc
                      let levelBits = reader.readBits(5)
                else {
                    return nil
                }

                var tier = false
                if levelBits > 7 {
                    guard let tierBit = reader.readBool() else {
                        return nil
                    }
                    tier = tierBit
                }

                if operatingPointIndex == 0 {
                    seqLevelIdx0 = UInt8(levelBits)
                    seqTier0 = tier
                }

                if decoderModelInfoPresent {
                    guard let decoderModelPresentForOperatingPoint = reader.readBool() else {
                        return nil
                    }
                    if decoderModelPresentForOperatingPoint {
                        let bufferFieldLength = bufferDelayLengthMinus1 + 1
                        guard reader.skipBits(bufferFieldLength), // decoder_buffer_delay
                              reader.skipBits(bufferFieldLength), // encoder_buffer_delay
                              reader.skipBits(1) // low_delay_mode_flag
                        else {
                            return nil
                        }
                    }
                }

                if initialDisplayDelayPresent {
                    guard let initialDisplayDelayPresentForOperatingPoint = reader.readBool() else {
                        return nil
                    }
                    if initialDisplayDelayPresentForOperatingPoint {
                        guard reader.skipBits(4) else { // initial_display_delay_minus_1
                            return nil
                        }
                    }
                }
            }
        }

        guard let frameWidthBitsMinus1 = reader.readBits(4),
              let frameHeightBitsMinus1 = reader.readBits(4),
              reader.skipBits(Int(frameWidthBitsMinus1 + 1)),
              reader.skipBits(Int(frameHeightBitsMinus1 + 1))
        else {
            return nil
        }

        if !reducedStillPictureHeader {
            guard let frameIDNumbersPresent = reader.readBool() else {
                return nil
            }
            if frameIDNumbersPresent {
                guard reader.skipBits(4), // delta_frame_id_length_minus_2
                      reader.skipBits(3) // additional_frame_id_length_minus_1
                else {
                    return nil
                }
            }

            // use_128x128_superblock, enable_filter_intra, enable_intra_edge_filter
            guard reader.skipBits(3) else {
                return nil
            }
            // enable_interintra_compound, enable_masked_compound, enable_warped_motion, enable_dual_filter
            guard reader.skipBits(4),
                  let enableOrderHint = reader.readBool()
            else {
                return nil
            }
            if enableOrderHint {
                // enable_jnt_comp, enable_ref_frame_mvs
                guard reader.skipBits(2) else {
                    return nil
                }
            }

            guard let seqChooseScreenContentTools = reader.readBool() else {
                return nil
            }
            var seqForceScreenContentTools: Int = 2
            if !seqChooseScreenContentTools {
                guard let forceScreenContentTools = reader.readBool() else {
                    return nil
                }
                seqForceScreenContentTools = forceScreenContentTools ? 1 : 0
            }
            if seqForceScreenContentTools > 0 {
                guard let seqChooseIntegerMV = reader.readBool() else {
                    return nil
                }
                if !seqChooseIntegerMV {
                    guard reader.skipBits(1) else { // seq_force_integer_mv
                        return nil
                    }
                }
            }

            if enableOrderHint {
                guard reader.skipBits(3) else { // order_hint_bits_minus_1
                    return nil
                }
            }
        }

        // enable_superres, enable_cdef, enable_restoration
        guard reader.skipBits(3) else {
            return nil
        }

        var highBitdepth = false
        var twelveBit = false
        var monochrome = false
        var chromaSubsamplingX = false
        var chromaSubsamplingY = false
        var chromaSamplePosition: UInt8 = 0

        if seqProfile == 2 {
            highBitdepth = true
            guard let twelveBitFlag = reader.readBool() else {
                return nil
            }
            twelveBit = twelveBitFlag
        } else {
            guard let highBitdepthFlag = reader.readBool() else {
                return nil
            }
            highBitdepth = highBitdepthFlag
        }

        let bitDepth = highBitdepth ? (twelveBit ? 12 : 10) : 8

        if seqProfile == 1 {
            monochrome = false
        } else {
            guard let monochromeFlag = reader.readBool() else {
                return nil
            }
            monochrome = monochromeFlag
        }

        let colorDescriptionPresent = reader.readBool() ?? false
        var colorPrimaries = 2
        var transferCharacteristics = 2
        var matrixCoefficients = 2
        if colorDescriptionPresent {
            guard let cp = reader.readBits(8),
                  let tc = reader.readBits(8),
                  let mc = reader.readBits(8)
            else {
                return nil
            }
            colorPrimaries = Int(cp)
            transferCharacteristics = Int(tc)
            matrixCoefficients = Int(mc)
        }

        if monochrome {
            guard reader.skipBits(1) else { // color_range
                return nil
            }
            chromaSubsamplingX = true
            chromaSubsamplingY = true
            chromaSamplePosition = 0
            _ = reader.readBool() // separate_uv_delta_q
            return SequenceHeaderInfo(
                seqProfile: seqProfile,
                seqLevelIdx0: seqLevelIdx0,
                seqTier0: seqTier0,
                highBitdepth: highBitdepth,
                twelveBit: twelveBit,
                monochrome: monochrome,
                chromaSubsamplingX: chromaSubsamplingX,
                chromaSubsamplingY: chromaSubsamplingY,
                chromaSamplePosition: chromaSamplePosition
            )
        }

        if colorPrimaries == 1 && transferCharacteristics == 13 && matrixCoefficients == 0 {
            chromaSubsamplingX = false
            chromaSubsamplingY = false
        } else {
            guard reader.skipBits(1) else { // color_range
                return nil
            }

            if seqProfile == 0 {
                chromaSubsamplingX = true
                chromaSubsamplingY = true
            } else if seqProfile == 1 {
                chromaSubsamplingX = false
                chromaSubsamplingY = false
            } else if bitDepth == 12 {
                guard let subsamplingX = reader.readBool() else {
                    return nil
                }
                chromaSubsamplingX = subsamplingX
                if chromaSubsamplingX {
                    guard let subsamplingY = reader.readBool() else {
                        return nil
                    }
                    chromaSubsamplingY = subsamplingY
                } else {
                    chromaSubsamplingY = false
                }
            } else {
                chromaSubsamplingX = true
                chromaSubsamplingY = false
            }

            if chromaSubsamplingX && chromaSubsamplingY {
                guard let samplePosition = reader.readBits(2) else {
                    return nil
                }
                chromaSamplePosition = UInt8(samplePosition)
            }
        }

        _ = reader.readBool() // separate_uv_delta_q

        return SequenceHeaderInfo(
            seqProfile: seqProfile,
            seqLevelIdx0: seqLevelIdx0,
            seqTier0: seqTier0,
            highBitdepth: highBitdepth,
            twelveBit: twelveBit,
            monochrome: monochrome,
            chromaSubsamplingX: chromaSubsamplingX,
            chromaSubsamplingY: chromaSubsamplingY,
            chromaSamplePosition: chromaSamplePosition
        )
    }

    private static func decodeLEB128(
        from bytes: [UInt8],
        at start: Int
    ) -> (value: Int, length: Int, bytes: [UInt8])? {
        var value = 0
        var shift = 0
        var index = start
        var encodedBytes: [UInt8] = []

        while index < bytes.count, shift <= 63 {
            let byte = bytes[index]
            encodedBytes.append(byte)
            value |= Int(byte & 0x7F) << shift
            index += 1

            if (byte & 0x80) == 0 {
                return (value, index - start, encodedBytes)
            }
            shift += 7
        }

        return nil
    }

    private static func encodeLEB128(_ value: Int) -> [UInt8] {
        var remaining = max(0, value)
        var bytes: [UInt8] = []

        while true {
            var byte = UInt8(remaining & 0x7F)
            remaining >>= 7
            if remaining != 0 {
                byte |= 0x80
            }
            bytes.append(byte)
            if remaining == 0 {
                return bytes
            }
        }
    }
}

private struct AV1BitReader {
    private let bytes: [UInt8]
    private var bitIndex: Int = 0

    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    mutating func readBool() -> Bool? {
        guard let bit = readBit() else {
            return nil
        }
        return bit == 1
    }

    mutating func readBits(_ count: Int) -> UInt32? {
        guard count >= 0 else {
            return nil
        }
        var value: UInt32 = 0
        for _ in 0..<count {
            guard let bit = readBit() else {
                return nil
            }
            value = (value << 1) | UInt32(bit)
        }
        return value
    }

    mutating func skipBits(_ count: Int) -> Bool {
        guard count >= 0 else {
            return false
        }
        for _ in 0..<count {
            guard readBit() != nil else {
                return false
            }
        }
        return true
    }

    mutating func readUVLC() -> UInt32? {
        var leadingZeroCount = 0
        while true {
            guard let bit = readBit() else {
                return nil
            }
            if bit == 1 {
                break
            }
            leadingZeroCount += 1
            if leadingZeroCount > 31 {
                return nil
            }
        }

        if leadingZeroCount == 0 {
            return 0
        }

        guard let suffix = readBits(leadingZeroCount) else {
            return nil
        }

        return ((1 << leadingZeroCount) - 1) + suffix
    }

    private mutating func readBit() -> UInt8? {
        let byteIndex = bitIndex / 8
        guard byteIndex < bytes.count else {
            return nil
        }
        let bitOffsetInByte = 7 - (bitIndex % 8)
        bitIndex += 1
        return (bytes[byteIndex] >> bitOffsetInByte) & 0x01
    }
}
