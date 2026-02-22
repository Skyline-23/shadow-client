import Testing
@testable import ShadowClientFeatureHome
import AVFoundation

private final class MockCustomAudioDecoder: ShadowClientRealtimeCustomAudioDecoder {
    let codec: ShadowClientAudioCodec
    let sampleRate: Int
    let channels: Int
    let outputFormat: AVAudioFormat

    init(
        codec: ShadowClientAudioCodec,
        sampleRate: Int,
        channels: Int
    ) {
        self.codec = codec
        self.sampleRate = sampleRate
        self.channels = channels
        self.outputFormat = AVAudioFormat(
            standardFormatWithSampleRate: Double(sampleRate),
            channels: AVAudioChannelCount(max(1, channels))
        )!
    }

    func decode(payload _: Data) throws -> AVAudioPCMBuffer? {
        nil
    }
}

@Test("Payload type adaptation accepts dynamic payload type changes before lock")
func payloadTypeAdaptationAcceptsDynamicChangesBeforeLock() {
    let adapted = ShadowClientRealtimeAudioSessionRuntime.payloadTypePreference(
        observed: 98,
        current: 97,
        hasLockedPayloadType: false
    )

    #expect(adapted == 98)
}

@Test("Payload type adaptation rejects payload type changes after lock")
func payloadTypeAdaptationRejectsChangesAfterLock() {
    let adapted = ShadowClientRealtimeAudioSessionRuntime.payloadTypePreference(
        observed: 98,
        current: 97,
        hasLockedPayloadType: true
    )

    #expect(adapted == nil)
}

@Test("Payload type adaptation ignores matching payload types")
func payloadTypeAdaptationIgnoresMatching() {
    let adapted = ShadowClientRealtimeAudioSessionRuntime.payloadTypePreference(
        observed: 97,
        current: 97,
        hasLockedPayloadType: false
    )

    #expect(adapted == nil)
}

@Test("Payload type adaptation rejects RTCP/control-like payload types")
func payloadTypeAdaptationRejectsControlValues() {
    let adapted = ShadowClientRealtimeAudioSessionRuntime.payloadTypePreference(
        observed: 72,
        current: 97,
        hasLockedPayloadType: false
    )

    #expect(adapted == nil)
}

@Test("Payload type adaptation rejects PT127 RED wrapper payload type")
func payloadTypeAdaptationRejectsPT127REDWrapper() {
    let adapted = ShadowClientRealtimeAudioSessionRuntime.payloadTypePreference(
        observed: ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType,
        current: 97,
        hasLockedPayloadType: false
    )

    #expect(adapted == nil)
}

@Test("RTP RED payload extraction returns primary payload for single block packet")
func redPayloadExtractionReturnsPrimaryPayloadForSingleBlockPacket() {
    let redPayload = Data([97, 0x11, 0x22, 0x33])
    let extracted = ShadowClientRealtimeAudioSessionRuntime.extractRTPREDPrimaryPayload(
        from: redPayload
    )

    #expect(extracted?.payloadType == 97)
    #expect(extracted?.payload == Data([0x11, 0x22, 0x33]))
}

@Test("RTP RED payload extraction skips redundant blocks and returns primary payload")
func redPayloadExtractionSkipsRedundantBlocks() {
    let redPayload = Data([
        0xE1, // F=1, PT=97 (redundant)
        0x00, // timestamp offset high bits
        0x04, // timestamp offset low bits + block length high bits
        0x02, // block length low bits (2 bytes)
        0x61, // F=0, PT=97 (primary)
        0xAA, 0xBB, // redundant block payload
        0xCC, 0xDD, 0xEE, // primary payload
    ])
    let extracted = ShadowClientRealtimeAudioSessionRuntime.extractRTPREDPrimaryPayload(
        from: redPayload
    )

    #expect(extracted?.payloadType == 97)
    #expect(extracted?.payload == Data([0xCC, 0xDD, 0xEE]))
}

@Test("RTP payload normalizer classifies Moonlight audio FEC payloads")
func rtpPayloadNormalizerClassifiesMoonlightAudioFECPayloads() {
    let normalized = ShadowClientRealtimeAudioRTPPayloadNormalizer.normalize(
        payloadType: 127,
        payload: Data([
            0x00, // fecShardIndex
            0x61, // payloadType=97
            0x00, 0x20, // baseSequenceNumber
            0x00, 0x00, 0x03, 0xE8, // baseTimestamp
            0x00, 0x00, 0x00, 0x01, // ssrc
            0x11, 0x22, 0x33, 0x44, // parity payload
        ]),
        preferredPayloadType: 97,
        wrapperPayloadType: 127
    )

    #expect(normalized.payloadType == 127)
    #expect(normalized.normalizationKey == "rtp-audio-fec:127")
}

@Test("RTP payload normalizer unwraps RED wrapper payload to primary payload")
func rtpPayloadNormalizerUnwrapsREDWrapperPayload() {
    let normalized = ShadowClientRealtimeAudioRTPPayloadNormalizer.normalize(
        payloadType: 127,
        payload: Data([
            0x81, // F=1, PT=97 (redundant block)
            0x00, // timestamp offset high
            0x02, // timestamp offset low + block length high (10 bits)
            0x02, // block length low (2 bytes)
            0x61, // F=0, PT=97 primary
            0xAA, 0xBB, // redundant block
            0xCC, 0xDD, 0xEE, // primary payload
        ]),
        preferredPayloadType: 97,
        wrapperPayloadType: 127
    )

    #expect(normalized.payloadType == 97)
    #expect(normalized.payload == Data([0xCC, 0xDD, 0xEE]))
    #expect(normalized.normalizationKey == "rtp-audio-red:127->97")
}

@Test("RTP payload normalizer does not treat ambiguous PT127 payload as direct Opus")
func rtpPayloadNormalizerDoesNotTreatAmbiguousPT127AsDirectOpus() {
    let normalized = ShadowClientRealtimeAudioRTPPayloadNormalizer.normalize(
        payloadType: 127,
        payload: Data([0xF8, 0xAA, 0xBB]),
        preferredPayloadType: 97,
        wrapperPayloadType: 127
    )

    #expect(normalized.payloadType == 127)
    #expect(normalized.payload == Data([0xF8, 0xAA, 0xBB]))
    #expect(normalized.normalizationKey == nil)
}

@Test("RTP payload normalizer unwraps RED primary payload for PT127 wrapper")
func rtpPayloadNormalizerUnwrapsREDPrimaryPayload() {
    let normalized = ShadowClientRealtimeAudioRTPPayloadNormalizer.normalize(
        payloadType: 127,
        payload: Data([97, 0xF8, 0xAA, 0xBB]),
        preferredPayloadType: 97,
        wrapperPayloadType: 127
    )

    #expect(normalized.payloadType == 97)
    #expect(normalized.payload == Data([0xF8, 0xAA, 0xBB]))
    #expect(normalized.normalizationKey == "rtp-audio-red:127->97")
}

@Test("Moonlight audio FEC payload classifier validates header fields")
func moonlightAudioFECClassifierValidatesHeaderFields() {
    let valid = ShadowClientRealtimeAudioRTPPayloadNormalizer.isLikelyMoonlightAudioFECPayload(
        Data([0x01, 0x61, 0x00, 0x10, 0x00, 0x00, 0x01, 0x00, 0, 0, 0, 1, 0xAA]),
        expectedPrimaryPayloadType: 97
    )
    let invalidShardIndex = ShadowClientRealtimeAudioRTPPayloadNormalizer
        .isLikelyMoonlightAudioFECPayload(
            Data([0x7F, 0x61, 0x00, 0x10, 0x00, 0x00, 0x01, 0x00, 0, 0, 0, 1, 0xAA]),
            expectedPrimaryPayloadType: 97
        )
    let invalidPrimaryPayloadType = ShadowClientRealtimeAudioRTPPayloadNormalizer
        .isLikelyMoonlightAudioFECPayload(
            Data([0x01, 0x62, 0x00, 0x10, 0x00, 0x00, 0x01, 0x00, 0, 0, 0, 1, 0xAA]),
            expectedPrimaryPayloadType: 97
        )

    #expect(valid)
    #expect(!invalidShardIndex)
    #expect(!invalidPrimaryPayloadType)
}

@Test("Audio jitter skip policy does not skip before out-of-order wait elapses")
func audioJitterSkipPolicyDoesNotSkipBeforeOutOfOrderWaitElapses() {
    let shouldSkip = ShadowClientRealtimeAudioSessionRuntime.shouldSkipMissingAudioSequence(
        bufferedPacketCount: 6,
        targetDepth: 6,
        waitElapsed: 0.005,
        requiredOutOfOrderWait: 0.010,
        isSevereOverflow: false
    )

    #expect(!shouldSkip)
}

@Test("Audio jitter skip policy skips after out-of-order wait elapses")
func audioJitterSkipPolicySkipsAfterOutOfOrderWaitElapses() {
    let shouldSkip = ShadowClientRealtimeAudioSessionRuntime.shouldSkipMissingAudioSequence(
        bufferedPacketCount: 6,
        targetDepth: 6,
        waitElapsed: 0.012,
        requiredOutOfOrderWait: 0.010,
        isSevereOverflow: false
    )

    #expect(shouldSkip)
}

@Test("Audio jitter skip policy skips immediately under severe overflow")
func audioJitterSkipPolicySkipsImmediatelyUnderSevereOverflow() {
    let shouldSkip = ShadowClientRealtimeAudioSessionRuntime.shouldSkipMissingAudioSequence(
        bufferedPacketCount: 2,
        targetDepth: 6,
        waitElapsed: nil,
        requiredOutOfOrderWait: 0.010,
        isSevereOverflow: true
    )

    #expect(shouldSkip)
}

@Test("Audio jitter skip policy does not skip below target depth")
func audioJitterSkipPolicyDoesNotSkipBelowTargetDepth() {
    let shouldSkip = ShadowClientRealtimeAudioSessionRuntime.shouldSkipMissingAudioSequence(
        bufferedPacketCount: 3,
        targetDepth: 6,
        waitElapsed: 0.020,
        requiredOutOfOrderWait: 0.010,
        isSevereOverflow: false
    )

    #expect(!shouldSkip)
}

@Test("Audio decode window keeps oldest packets under output queue pressure")
func audioDecodeWindowKeepsOldestPacketsUnderOutputQueuePressure() {
    let window = ShadowClientRealtimeAudioSessionRuntime.audioReadyPacketDecodeWindow(
        readyPacketCount: 8,
        availableOutputSlots: 2,
        decodeSheddingLowWatermarkSlots: 2
    )

    #expect(window.decodeStartIndex == 0)
    #expect(window.decodeEndIndex == 2)
    #expect(window.droppedPacketCount == 6)
}

@Test("Audio decode window decodes all packets when output queue has headroom")
func audioDecodeWindowDecodesAllPacketsWithHeadroom() {
    let window = ShadowClientRealtimeAudioSessionRuntime.audioReadyPacketDecodeWindow(
        readyPacketCount: 6,
        availableOutputSlots: 4,
        decodeSheddingLowWatermarkSlots: 2
    )

    #expect(window.decodeStartIndex == 0)
    #expect(window.decodeEndIndex == 6)
    #expect(window.droppedPacketCount == 0)
}

@Test("Custom audio decoder registry prioritizes preferred providers")
func customAudioDecoderRegistryPrioritizesPreferredProviders() throws {
    ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders()
    defer { ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders() }

    ShadowClientRealtimeCustomAudioDecoderRegistry.register(
        provider: { _ in
            MockCustomAudioDecoder(
                codec: .opus,
                sampleRate: 48_000,
                channels: 6
            )
        },
        preferred: false
    )
    ShadowClientRealtimeCustomAudioDecoderRegistry.register(
        provider: { _ in
            MockCustomAudioDecoder(
                codec: .opus,
                sampleRate: 44_100,
                channels: 8
            )
        },
        preferred: true
    )

    let track = ShadowClientRTSPAudioTrackDescriptor(
        codec: .opus,
        rtpPayloadType: 97,
        sampleRate: 48_000,
        channelCount: 6,
        controlURL: nil,
        formatParameters: [:]
    )
    let decoder = try ShadowClientRealtimeCustomAudioDecoderRegistry.makeDecoder(
        for: track
    )

    #expect(decoder != nil)
    #expect(decoder?.sampleRate == 44_100)
    #expect(decoder?.channels == 8)
}

@Test("Audio negotiation downgrades surround request to stereo without multichannel decoder")
func audioNegotiationDowngradesSurroundWhenDecoderUnavailable() {
    ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders()
    defer { ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders() }

    let preferredChannels = ShadowClientRealtimeAudioSessionRuntime.preferredOpusChannelCountForNegotiation(
        surroundRequested: true,
        preferredSurroundChannelCount: 6
    )

    #expect(preferredChannels == 2)
}

@Test("Opus decoding requires external decoder provider")
func opusDecodingRequiresExternalDecoderProvider() {
    ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders()
    defer { ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders() }

    let stereoTrack = ShadowClientRTSPAudioTrackDescriptor(
        codec: .opus,
        rtpPayloadType: 97,
        sampleRate: 48_000,
        channelCount: 2,
        controlURL: nil,
        formatParameters: [:]
    )

    #expect(!ShadowClientRealtimeAudioSessionRuntime.canDecode(track: stereoTrack))
}

@Test("Opus decoding succeeds when external decoder provider is available")
func opusDecodingSucceedsWithExternalDecoderProvider() {
    ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders()
    defer { ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders() }

    ShadowClientRealtimeCustomAudioDecoderRegistry.register(
        provider: { track in
            guard track.codec == .opus else {
                return nil
            }
            return MockCustomAudioDecoder(
                codec: .opus,
                sampleRate: track.sampleRate,
                channels: track.channelCount
            )
        }
    )

    let stereoTrack = ShadowClientRTSPAudioTrackDescriptor(
        codec: .opus,
        rtpPayloadType: 97,
        sampleRate: 48_000,
        channelCount: 2,
        controlURL: nil,
        formatParameters: [:]
    )

    #expect(ShadowClientRealtimeAudioSessionRuntime.canDecode(track: stereoTrack))
}

@Test("Audio negotiation keeps surround request when multichannel decoder is available")
func audioNegotiationKeepsSurroundWhenDecoderAvailable() {
    ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders()
    defer { ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders() }

    ShadowClientRealtimeCustomAudioDecoderRegistry.register(
        provider: { track in
            guard track.codec == .opus, track.channelCount > 2 else {
                return nil
            }
            return MockCustomAudioDecoder(
                codec: .opus,
                sampleRate: track.sampleRate,
                channels: track.channelCount
            )
        }
    )

    let preferredChannels = ShadowClientRealtimeAudioSessionRuntime.preferredOpusChannelCountForNegotiation(
        surroundRequested: true,
        preferredSurroundChannelCount: 6,
        maximumOutputChannels: 8
    )

    #expect(preferredChannels == 6)
}

@Test("Audio negotiation downgrades surround request when playback output is stereo-only")
func audioNegotiationDowngradesSurroundWhenOutputIsStereoOnly() {
    ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders()
    defer { ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders() }

    ShadowClientRealtimeCustomAudioDecoderRegistry.register(
        provider: { track in
            guard track.codec == .opus, track.channelCount > 2 else {
                return nil
            }
            return MockCustomAudioDecoder(
                codec: .opus,
                sampleRate: track.sampleRate,
                channels: track.channelCount
            )
        }
    )

    let preferredChannels = ShadowClientRealtimeAudioSessionRuntime.preferredOpusChannelCountForNegotiation(
        surroundRequested: true,
        preferredSurroundChannelCount: 6,
        maximumOutputChannels: 2
    )

    #expect(preferredChannels == 2)
}
