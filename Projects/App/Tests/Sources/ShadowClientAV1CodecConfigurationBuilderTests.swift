import Foundation
import Testing
@testable import ShadowClientFeatureHome

@Test("AV1 codec configuration builder derives av1C from sequence header OBU")
func av1CodecConfigurationBuilderDerivesAv1CFromSequenceHeaderOBU() {
    // Sequence header OBU extracted from a valid AV1 MP4 av1C record.
    let sequenceHeaderOBU = Data([
        0x0A, 0x0B, 0x00, 0x00, 0x00, 0x04, 0x3C, 0xFE, 0xCC, 0x02, 0xF8, 0x00, 0x40,
    ])

    let av1c = ShadowClientAV1CodecConfigurationBuilder.build(fromAccessUnit: sequenceHeaderOBU)

    #expect(av1c == Data([0x81, 0x00, 0x0C, 0x00]) + sequenceHeaderOBU)
}

@Test("AV1 codec configuration builder returns nil when sequence header OBU is missing")
func av1CodecConfigurationBuilderReturnsNilWithoutSequenceHeaderOBU() {
    // OBU type 6 (frame) + size + payload.
    let frameOBUOnly = Data([0x32, 0x01, 0x00])

    let av1c = ShadowClientAV1CodecConfigurationBuilder.build(fromAccessUnit: frameOBUOnly)

    #expect(av1c == nil)
}

@Test("AV1 codec configuration builder can recover sequence header after leading bytes")
func av1CodecConfigurationBuilderRecoversAfterLeadingBytes() {
    let sequenceHeaderOBU = Data([
        0x0A, 0x0B, 0x00, 0x00, 0x00, 0x04, 0x3C, 0xFE, 0xCC, 0x02, 0xF8, 0x00, 0x40,
    ])
    let accessUnit = Data([0xFF, 0x00, 0x99, 0x80]) + sequenceHeaderOBU

    let av1c = ShadowClientAV1CodecConfigurationBuilder.build(fromAccessUnit: accessUnit)

    #expect(av1c == Data([0x81, 0x00, 0x0C, 0x00]) + sequenceHeaderOBU)
}

@Test("AV1 fallback codec configuration reflects HDR and chroma settings")
func av1FallbackCodecConfigurationReflectsHints() {
    let main8 = ShadowClientAV1CodecConfigurationBuilder.fallbackCodecConfigurationRecord(
        hdrEnabled: false,
        yuv444Enabled: false
    )
    let main10 = ShadowClientAV1CodecConfigurationBuilder.fallbackCodecConfigurationRecord(
        hdrEnabled: true,
        yuv444Enabled: false
    )
    let high10 = ShadowClientAV1CodecConfigurationBuilder.fallbackCodecConfigurationRecord(
        hdrEnabled: true,
        yuv444Enabled: true
    )

    #expect(main8 == Data([0x81, 0x00, 0x0C, 0x00]))
    #expect(main10 == Data([0x81, 0x00, 0x4C, 0x00]))
    #expect(high10 == Data([0x81, 0x20, 0x40, 0x00]))
}
