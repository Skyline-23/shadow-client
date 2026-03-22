import Testing
@testable import ShadowClientFeatureHome
import AVFoundation
import Foundation

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

private final class RecordingDefaultCustomAudioDecoder: ShadowClientRealtimeCustomAudioDecoder {
    let codec: ShadowClientAudioCodec = .opus
    let sampleRate: Int = 48_000
    let channels: Int = 2
    let outputFormat: AVAudioFormat = AVAudioFormat(
        standardFormatWithSampleRate: 48_000,
        channels: 2
    )!
    private(set) var decodeCallCount = 0
    private(set) var decodedPayloads: [Data] = []

    func decode(payload: Data) throws -> AVAudioPCMBuffer? {
        decodeCallCount += 1
        decodedPayloads.append(payload)
        return nil
    }
}

private final class RecordingPLCCustomAudioDecoder: ShadowClientRealtimeCustomAudioDecoder {
    let codec: ShadowClientAudioCodec = .opus
    let sampleRate: Int = 48_000
    let channels: Int = 2
    let outputFormat: AVAudioFormat = AVAudioFormat(
        standardFormatWithSampleRate: 48_000,
        channels: 2
    )!
    private(set) var requestedPLCSamples: [Int] = []

    func decode(payload _: Data) throws -> AVAudioPCMBuffer? {
        nil
    }

    func decodePacketLossConcealment(samplesPerChannel: Int) throws -> AVAudioPCMBuffer? {
        requestedPLCSamples.append(samplesPerChannel)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(samplesPerChannel)
        ) else {
            return nil
        }
        buffer.frameLength = AVAudioFrameCount(samplesPerChannel)
        return buffer
    }
}

private actor TestAudioOutputState {
    struct Snapshot: Equatable, Sendable {
        let enqueueAttemptCount: Int
    }

    private var enqueueResults: [Bool]
    private var enqueueAttemptCount = 0
    private let shouldDeferPressureSheddingValue: Bool
    private let pendingDurationMsValue: Double

    init(
        enqueueResults: [Bool],
        shouldDeferPressureShedding: Bool = false,
        pendingDurationMs: Double = 0
    ) {
        self.enqueueResults = enqueueResults
        self.shouldDeferPressureSheddingValue = shouldDeferPressureShedding
        self.pendingDurationMsValue = pendingDurationMs
    }

    func nextEnqueueResult() -> Bool {
        enqueueAttemptCount += 1
        if !enqueueResults.isEmpty {
            return enqueueResults.removeFirst()
        }
        return false
    }

    func shouldDeferPressureShedding() -> Bool {
        shouldDeferPressureSheddingValue
    }

    func pendingDurationMs() -> Double {
        pendingDurationMsValue
    }

    func snapshot() -> Snapshot {
        Snapshot(enqueueAttemptCount: enqueueAttemptCount)
    }
}

private final class TestRealtimeAudioOutput: ShadowClientRealtimeAudioOutput, Sendable {
    private let state: TestAudioOutputState
    private let recoveryResult: Bool

    init(
        enqueueResults: [Bool],
        shouldDeferPressureShedding: Bool = false,
        pendingDurationMs: Double = 0,
        recoveryResult: Bool = false
    ) {
        self.state = TestAudioOutputState(
            enqueueResults: enqueueResults,
            shouldDeferPressureShedding: shouldDeferPressureShedding,
            pendingDurationMs: pendingDurationMs
        )
        self.recoveryResult = recoveryResult
    }

    func enqueue(pcmBuffer _: AVAudioPCMBuffer) async -> Bool {
        await state.nextEnqueueResult()
    }

    func hasEnqueueCapacity() async -> Bool {
        true
    }

    func pendingDurationMs() async -> Double {
        await state.pendingDurationMs()
    }

    func availableEnqueueSlots() async -> Int {
        1
    }

    func shouldDeferPressureShedding() async -> Bool {
        await state.shouldDeferPressureShedding()
    }

    func stop() {}

    func recoverPlaybackUnderPressure() -> Bool {
        recoveryResult
    }

    var usesSystemManagedBuffering: Bool {
        false
    }

    var debugFormatDescription: String {
        "test"
    }

    func updateVideoRenderingState(isRendering _: Bool) {}

    func snapshot() async -> TestAudioOutputState.Snapshot {
        await state.snapshot()
    }
}

private func makeTestAudioPCMBuffer(
    frameCount: AVAudioFrameCount = 240,
    sampleRate: Double = 48_000,
    channels: AVAudioChannelCount = 2
) -> AVAudioPCMBuffer {
    let format = AVAudioFormat(
        standardFormatWithSampleRate: sampleRate,
        channels: channels
    )!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
    buffer.frameLength = frameCount
    return buffer
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
    #expect(normalized.isMoonlightAudioFECPayload)
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldProcessPayloadMismatch(
            for: normalized
        )
    )
}

@Test("RTP payload normalizer keeps PT127 RED wrapper payload opaque")
func rtpPayloadNormalizerKeepsREDWrapperPayloadOpaque() {
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

    #expect(normalized.payloadType == 127)
    #expect(normalized.payload == Data([
        0x81,
        0x00,
        0x02,
        0x02,
        0x61,
        0xAA,
        0xBB,
        0xCC,
        0xDD,
        0xEE,
    ]))
    #expect(normalized.normalizationKey == nil)
    #expect(!normalized.isMoonlightAudioFECPayload)
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldProcessPayloadMismatch(
            for: normalized
        )
    )
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
    #expect(!normalized.isMoonlightAudioFECPayload)
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldProcessPayloadMismatch(
            for: normalized
        )
    )
}

@Test("RTP payload normalizer keeps RED primary payload wrapper for PT127")
func rtpPayloadNormalizerKeepsREDPrimaryPayloadWrapper() {
    let normalized = ShadowClientRealtimeAudioRTPPayloadNormalizer.normalize(
        payloadType: 127,
        payload: Data([97, 0xF8, 0xAA, 0xBB]),
        preferredPayloadType: 97,
        wrapperPayloadType: 127
    )

    #expect(normalized.payloadType == 127)
    #expect(normalized.payload == Data([97, 0xF8, 0xAA, 0xBB]))
    #expect(normalized.normalizationKey == nil)
    #expect(!normalized.isMoonlightAudioFECPayload)
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldProcessPayloadMismatch(
            for: normalized
        )
    )
}

@Test("Moonlight audio FEC payload classifier validates header fields")
func moonlightAudioFECClassifierValidatesHeaderFields() {
    let valid = ShadowClientRealtimeAudioRTPPayloadNormalizer.isLikelyMoonlightAudioFECPayload(
        Data([0x01, 0x61, 0x00, 0x10, 0x00, 0x00, 0x01, 0x00, 0, 0, 0, 1, 0xAA]),
        expectedPrimaryPayloadType: 97
    )
    let invalidShardIndexOutsideMoonlightRange = ShadowClientRealtimeAudioRTPPayloadNormalizer
        .isLikelyMoonlightAudioFECPayload(
            Data([0x02, 0x61, 0x00, 0x10, 0x00, 0x00, 0x01, 0x00, 0, 0, 0, 1, 0xAA]),
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
    #expect(!invalidShardIndexOutsideMoonlightRange)
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

@Test("Audio decode window defers newest packets under output queue pressure")
func audioDecodeWindowDefersNewestPacketsUnderOutputQueuePressure() {
    let window = ShadowClientRealtimeAudioSessionRuntime.audioReadyPacketDecodeWindow(
        readyPacketCount: 8,
        availableOutputSlots: 2,
        decodeSheddingLowWatermarkSlots: 2
    )

    #expect(window.decodeStartIndex == 0)
    #expect(window.decodeEndIndex == 2)
    #expect(window.deferredPacketCount == 6)
}

@Test("Audio decode window limits decode batch to available output slots and defers overflow")
func audioDecodeWindowLimitsDecodeBatchToAvailableSlotsAndDefersOverflow() {
    let window = ShadowClientRealtimeAudioSessionRuntime.audioReadyPacketDecodeWindow(
        readyPacketCount: 6,
        availableOutputSlots: 4,
        decodeSheddingLowWatermarkSlots: 2
    )

    #expect(window.decodeStartIndex == 0)
    #expect(window.decodeEndIndex == 4)
    #expect(window.deferredPacketCount == 2)
}

@Test("Audio decode window drains all ready packets when output slots are sufficient")
func audioDecodeWindowDrainsAllReadyPacketsWhenOutputSlotsAreSufficient() {
    let window = ShadowClientRealtimeAudioSessionRuntime.audioReadyPacketDecodeWindow(
        readyPacketCount: 3,
        availableOutputSlots: 4,
        decodeSheddingLowWatermarkSlots: 2
    )

    #expect(window.decodeStartIndex == 0)
    #expect(window.decodeEndIndex == 3)
    #expect(window.deferredPacketCount == 0)
}

@Test("Audio ready packet drain limit disables draining while decode cooldown is active")
func audioReadyPacketDrainLimitDisablesDuringCooldown() {
    let limit = ShadowClientRealtimeAudioSessionRuntime.audioReadyPacketDrainLimit(
        isDecodeCooldownActive: true,
        availableOutputSlots: 4
    )

    #expect(limit == 0)
}

@Test("Audio ready packet drain limit disables draining when output queue has no slots")
func audioReadyPacketDrainLimitDisablesWhenNoSlots() {
    let limit = ShadowClientRealtimeAudioSessionRuntime.audioReadyPacketDrainLimit(
        isDecodeCooldownActive: false,
        availableOutputSlots: 0
    )

    #expect(limit == 0)
}

@Test("Audio runtime holds decode when ready drain is empty because output queue is full")
func audioEmptyReadyDrainHoldDecisionWhenOutputQueueIsFull() {
    #expect(
        ShadowClientRealtimeAudioSessionRuntime.shouldHoldDecodeWhenReadyPacketsEmpty(
            isDecodeCooldownActive: false,
            availableOutputSlots: 0
        )
    )
    #expect(
        ShadowClientRealtimeAudioSessionRuntime.shouldHoldDecodeWhenReadyPacketsEmpty(
            isDecodeCooldownActive: false,
            availableOutputSlots: -1
        )
    )
}

@Test("Audio runtime does not treat cooldown hold as output-full hold path")
func audioEmptyReadyDrainHoldDecisionExcludesCooldownPath() {
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldHoldDecodeWhenReadyPacketsEmpty(
            isDecodeCooldownActive: true,
            availableOutputSlots: 0
        )
    )
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldHoldDecodeWhenReadyPacketsEmpty(
            isDecodeCooldownActive: false,
            availableOutputSlots: 2
        )
    )
}

@Test("Audio missing-packet recovery gate allows expansion with headroom and no backlog")
func audioMissingPacketRecoveryGateAllowsExpansionWithHeadroomAndNoBacklog() {
    #expect(
        ShadowClientRealtimeAudioSessionRuntime.shouldAttemptMissingPacketRecoveryOrConcealment(
            missingPacketCount: 2,
            isFECIncompatible: false,
            remainingOutputSlots: 5,
            decodeSheddingLowWatermarkSlots: 2,
            deferredPacketCount: 0
        )
    )
}

@Test("Audio missing-packet recovery gate skips when decode backlog exists")
func audioMissingPacketRecoveryGateSkipsWhenDecodeBacklogExists() {
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldAttemptMissingPacketRecoveryOrConcealment(
            missingPacketCount: 2,
            isFECIncompatible: false,
            remainingOutputSlots: 6,
            decodeSheddingLowWatermarkSlots: 2,
            deferredPacketCount: 1
        )
    )
}

@Test("Audio missing-packet recovery gate requires headroom above low-watermark")
func audioMissingPacketRecoveryGateRequiresHeadroomAboveLowWatermark() {
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldAttemptMissingPacketRecoveryOrConcealment(
            missingPacketCount: 1,
            isFECIncompatible: false,
            remainingOutputSlots: 2,
            decodeSheddingLowWatermarkSlots: 2,
            deferredPacketCount: 0
        )
    )
    #expect(
        ShadowClientRealtimeAudioSessionRuntime.shouldAttemptMissingPacketRecoveryOrConcealment(
            missingPacketCount: 1,
            isFECIncompatible: false,
            remainingOutputSlots: 3,
            decodeSheddingLowWatermarkSlots: 2,
            deferredPacketCount: 0
        )
    )
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldAttemptMissingPacketRecoveryOrConcealment(
            missingPacketCount: 1,
            isFECIncompatible: false,
            remainingOutputSlots: 1,
            decodeSheddingLowWatermarkSlots: 2,
            deferredPacketCount: 0
        )
    )
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldAttemptMissingPacketRecoveryOrConcealment(
            missingPacketCount: 1,
            isFECIncompatible: false,
            remainingOutputSlots: 0,
            decodeSheddingLowWatermarkSlots: 2,
            deferredPacketCount: 0
        )
    )
}

@Test("Audio missing-packet recovery gate can consume all slots when reserve is disabled")
func audioMissingPacketRecoveryGateAllowsSingleSlotWhenReserveIsDisabled() {
    #expect(
        ShadowClientRealtimeAudioSessionRuntime.shouldAttemptMissingPacketRecoveryOrConcealment(
            missingPacketCount: 1,
            isFECIncompatible: false,
            remainingOutputSlots: 1,
            decodeSheddingLowWatermarkSlots: 1,
            deferredPacketCount: 0,
            minimumReservedOutputSlots: 0
        )
    )
}

@Test("Audio missing-packet recovery gate is disabled when Moonlight FEC is incompatible")
func audioMissingPacketRecoveryGateSkipsWhenFECIncompatible() {
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldAttemptMissingPacketRecoveryOrConcealment(
            missingPacketCount: 2,
            isFECIncompatible: true,
            remainingOutputSlots: 4,
            decodeSheddingLowWatermarkSlots: 2,
            deferredPacketCount: 0
        )
    )
}

@Test("Audio missing-packet recovery gate skips when nothing is missing")
func audioMissingPacketRecoveryGateSkipsWhenNoPacketsAreMissing() {
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldAttemptMissingPacketRecoveryOrConcealment(
            missingPacketCount: 0,
            isFECIncompatible: false,
            remainingOutputSlots: 8,
            decodeSheddingLowWatermarkSlots: 2,
            deferredPacketCount: 0
        )
    )
}

@Test("Audio missing packet count subtracts observed Moonlight FEC shard observations")
func audioMissingPacketCountSubtractsObservedMoonlightFECObservations() {
    let adjusted = ShadowClientRealtimeAudioSessionRuntime
        .adjustMissingRTPPacketCountForObservedMoonlightFEC(
            rawMissingPacketCount: 4,
            observedMoonlightFECShardsSinceLastDecodedPacket: 3
        )

    #expect(adjusted == 1)
}

@Test("Audio missing packet count clamps to zero when observed Moonlight FEC shards exceed raw gap")
func audioMissingPacketCountClampsToZeroWhenObservedMoonlightFECExceedsRawGap() {
    let adjusted = ShadowClientRealtimeAudioSessionRuntime
        .adjustMissingRTPPacketCountForObservedMoonlightFEC(
            rawMissingPacketCount: 2,
            observedMoonlightFECShardsSinceLastDecodedPacket: 8
        )

    #expect(adjusted == 0)
}

@Test("Audio missing packet count clamps negative raw values to zero")
func audioMissingPacketCountClampsNegativeRawValuesToZero() {
    let adjusted = ShadowClientRealtimeAudioSessionRuntime
        .adjustMissingRTPPacketCountForObservedMoonlightFEC(
            rawMissingPacketCount: -1,
            observedMoonlightFECShardsSinceLastDecodedPacket: 5
        )

    #expect(adjusted == 0)
}

@Test("Audio missing packet count is unchanged when no Moonlight FEC shards were observed")
func audioMissingPacketCountIsUnchangedWithoutMoonlightFECShards() {
    let adjusted = ShadowClientRealtimeAudioSessionRuntime
        .adjustMissingRTPPacketCountForObservedMoonlightFEC(
            rawMissingPacketCount: 3,
            observedMoonlightFECShardsSinceLastDecodedPacket: 0
        )

    #expect(adjusted == 3)
}

@Test("Audio packet sample estimation ignores sub-5ms timestamp deltas")
func audioPacketSampleEstimationIgnoresSubFiveMillisecondTimestampDeltas() {
    let estimated = ShadowClientRealtimeAudioSessionRuntime.estimatedAudioSamplesPerPacket(
        sampleRate: 48_000,
        previousSequenceNumber: 100,
        currentSequenceNumber: 101,
        previousTimestamp: 1_000,
        currentTimestamp: 1_120,
        minimumPacketSamples: 240,
        maximumPacketSamples: 5_760
    )

    #expect(estimated == nil)
}

@Test("Audio packet sample estimation rounds to nearest 5ms step")
func audioPacketSampleEstimationRoundsToNearestFiveMillisecondStep() {
    let estimated = ShadowClientRealtimeAudioSessionRuntime.estimatedAudioSamplesPerPacket(
        sampleRate: 48_000,
        previousSequenceNumber: 100,
        currentSequenceNumber: 101,
        previousTimestamp: 1_000,
        currentTimestamp: 1_370,
        minimumPacketSamples: 240,
        maximumPacketSamples: 5_760
    )

    #expect(estimated == 480)
}

@Test("Audio ready packet drain limit is bounded by available slots and batch size")
func audioReadyPacketDrainLimitUsesAvailableSlotsAndBatchCap() {
    let bySlots = ShadowClientRealtimeAudioSessionRuntime.audioReadyPacketDrainLimit(
        isDecodeCooldownActive: false,
        availableOutputSlots: 3,
        maximumDrainBatch: 8
    )
    let byBatch = ShadowClientRealtimeAudioSessionRuntime.audioReadyPacketDrainLimit(
        isDecodeCooldownActive: false,
        availableOutputSlots: 12,
        maximumDrainBatch: 8
    )

    #expect(bySlots == 3)
    #expect(byBatch == 8)
}

@Test("Audio ready packet drain limit collapses to one packet when output backlog nears realtime cap")
func audioReadyPacketDrainLimitCollapsesNearRealtimeCap() {
    let limit = ShadowClientRealtimeAudioSessionRuntime.audioReadyPacketDrainLimit(
        isDecodeCooldownActive: false,
        availableOutputSlots: 12,
        maximumDrainBatch: 8,
        shouldDeferPressureShedding: false,
        outputPendingDurationMs: 26,
        realtimePendingDurationCapMs: 30,
        pendingPressureHysteresisMs: 5
    )

    #expect(limit == 1)
}

@Test("Audio ready packet drain limit keeps batch size when output backlog stays below near-cap threshold")
func audioReadyPacketDrainLimitKeepsBatchSizeBelowNearRealtimeCap() {
    let limit = ShadowClientRealtimeAudioSessionRuntime.audioReadyPacketDrainLimit(
        isDecodeCooldownActive: false,
        availableOutputSlots: 12,
        maximumDrainBatch: 8,
        shouldDeferPressureShedding: false,
        outputPendingDurationMs: 24,
        realtimePendingDurationCapMs: 30,
        pendingPressureHysteresisMs: 5
    )

    #expect(limit == 8)
}

@Test("Audio ready packets are requeued when pending output duration exceeds realtime cap")
func audioReadyPacketsAreRequeuedForPendingOutputPressure() {
    let shouldRequeue = ShadowClientRealtimeAudioSessionRuntime
        .shouldRequeueReadyPacketsForPendingOutputPressure(
            readyPacketPendingDurationMs: 121,
            outputPendingDurationMs: 121,
            realtimePendingDurationCapMs: 120,
            pendingPressureHysteresisMs: 0
        )
    let shouldNotRequeue = ShadowClientRealtimeAudioSessionRuntime
        .shouldRequeueReadyPacketsForPendingOutputPressure(
            readyPacketPendingDurationMs: 121,
            outputPendingDurationMs: 120,
            realtimePendingDurationCapMs: 120,
            pendingPressureHysteresisMs: 0
        )

    #expect(shouldRequeue)
    #expect(!shouldNotRequeue)
}

@Test("Audio ready packets are requeued when output slots are unavailable")
func audioReadyPacketsAreRequeuedWhenOutputSlotsUnavailable() {
    let shouldRequeue = ShadowClientRealtimeAudioSessionRuntime
        .shouldRequeueReadyPacketsForUnavailableOutputSlots(
            availableOutputSlots: 0
        )
    let shouldNotRequeue = ShadowClientRealtimeAudioSessionRuntime
        .shouldRequeueReadyPacketsForUnavailableOutputSlots(
            availableOutputSlots: 1
        )

    #expect(shouldRequeue)
    #expect(!shouldNotRequeue)
}

@Test("Audio decode cooldown gate activates only after pressure burst threshold inside window")
func audioDecodeCooldownGateRequiresBurstThresholdInsideWindow() {
    #expect(
        ShadowClientRealtimeAudioSessionRuntime.shouldActivateAudioDecodeCooldown(
            now: 10.0,
            firstOutputQueuePressureDropUptime: 9.4,
            outputQueuePressureDropCount: 8,
            dropWindowSeconds: 1.0,
            burstThreshold: 8
        )
    )
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldActivateAudioDecodeCooldown(
            now: 10.0,
            firstOutputQueuePressureDropUptime: 9.4,
            outputQueuePressureDropCount: 7,
            dropWindowSeconds: 1.0,
            burstThreshold: 8
        )
    )
}

@Test("Audio decode cooldown gate suppresses stale pressure bursts")
func audioDecodeCooldownGateSuppressesStaleBursts() {
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldActivateAudioDecodeCooldown(
            now: 10.0,
            firstOutputQueuePressureDropUptime: 8.5,
            outputQueuePressureDropCount: 12,
            dropWindowSeconds: 1.0,
            burstThreshold: 8
        )
    )
}

@Test("Audio pending pressure and cooldown gates remain deterministic without startup grace overrides")
func audioPendingPressureAndCooldownGatesRemainDeterministic() {
    #expect(
        ShadowClientRealtimeAudioSessionRuntime.shouldRequeueReadyPacketsForPendingOutputPressure(
            readyPacketPendingDurationMs: 240,
            outputPendingDurationMs: 240,
            realtimePendingDurationCapMs: 30,
            pendingPressureHysteresisMs: 0
        )
    )
    #expect(
        ShadowClientRealtimeAudioSessionRuntime.shouldRequeueReadyPacketsForUnavailableOutputSlots(
            availableOutputSlots: 0
        )
    )
    #expect(
        ShadowClientRealtimeAudioSessionRuntime.shouldActivateAudioDecodeCooldown(
            now: 10.0,
            firstOutputQueuePressureDropUptime: 9.4,
            outputQueuePressureDropCount: 12,
            dropWindowSeconds: 1.0,
            burstThreshold: 8
        )
    )
}

@Test("Audio pending pressure gate honors output startup grace")
func audioPendingPressureGateHonorsOutputStartupGrace() {
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldDropAudioPacketForPendingPressure(
            usesSystemManagedBuffering: false,
            shouldDeferPressureShedding: true,
            readyPacketPendingDurationMs: 240,
            outputPendingDurationMs: 240,
            realtimePendingDurationCapMs: 30,
            pendingPressureHysteresisMs: 0
        )
    )
    #expect(
        ShadowClientRealtimeAudioSessionRuntime.shouldDropAudioPacketForPendingPressure(
            usesSystemManagedBuffering: false,
            shouldDeferPressureShedding: false,
            readyPacketPendingDurationMs: 240,
            outputPendingDurationMs: 240,
            realtimePendingDurationCapMs: 30,
            pendingPressureHysteresisMs: 0
        )
    )
}

@Test("Audio pending pressure gate does not shed when output backlog stays below realtime cap")
func audioPendingPressureGateRequiresOutputBacklogToAlsoBeHigh() {
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldDropAudioPacketForPendingPressure(
            usesSystemManagedBuffering: false,
            shouldDeferPressureShedding: false,
            readyPacketPendingDurationMs: 240,
            outputPendingDurationMs: 10,
            realtimePendingDurationCapMs: 30,
            pendingPressureHysteresisMs: 0
        )
    )
}

@Test("Audio pending pressure gate tolerates one-packet transient above cap before shedding")
func audioPendingPressureGateAppliesOnePacketHysteresis() {
    #expect(
        !ShadowClientRealtimeAudioSessionRuntime.shouldDropAudioPacketForPendingPressure(
            usesSystemManagedBuffering: false,
            shouldDeferPressureShedding: false,
            readyPacketPendingDurationMs: 34,
            outputPendingDurationMs: 34,
            realtimePendingDurationCapMs: 30,
            pendingPressureHysteresisMs: 5
        )
    )
    #expect(
        ShadowClientRealtimeAudioSessionRuntime.shouldDropAudioPacketForPendingPressure(
            usesSystemManagedBuffering: false,
            shouldDeferPressureShedding: false,
            readyPacketPendingDurationMs: 36,
            outputPendingDurationMs: 36,
            realtimePendingDurationCapMs: 30,
            pendingPressureHysteresisMs: 5
        )
    )
}

@Test("Audio enqueue retries once after output recovery")
func audioEnqueueRetriesOnceAfterOutputRecovery() async {
    let output = TestRealtimeAudioOutput(
        enqueueResults: [false, true],
        recoveryResult: true
    )

    let result = await ShadowClientRealtimeAudioSessionRuntime.enqueueDecodedBufferWithRecovery(
        makeTestAudioPCMBuffer(),
        using: output
    )
    let snapshot = await output.snapshot()

    #expect(result == .recoveredAndEnqueued)
    #expect(snapshot.enqueueAttemptCount == 2)
}

@Test("Audio enqueue fails when output recovery cannot restore playback")
func audioEnqueueFailsWhenOutputRecoveryCannotRestorePlayback() async {
    let output = TestRealtimeAudioOutput(
        enqueueResults: [false],
        recoveryResult: false
    )

    let result = await ShadowClientRealtimeAudioSessionRuntime.enqueueDecodedBufferWithRecovery(
        makeTestAudioPCMBuffer(),
        using: output
    )
    let snapshot = await output.snapshot()

    #expect(result == .failed)
    #expect(snapshot.enqueueAttemptCount == 1)
}

@Test("Audio drop window packet count scales with packet duration")
func audioDropWindowPacketCountScalesWithPacketDuration() {
    let fiveMsPackets = ShadowClientRealtimeAudioSessionRuntime.dropPacketCountForWindow(
        windowSeconds: 0.25,
        packetDurationMs: 5
    )
    let tenMsPackets = ShadowClientRealtimeAudioSessionRuntime.dropPacketCountForWindow(
        windowSeconds: 0.25,
        packetDurationMs: 10
    )

    #expect(fiveMsPackets == 50)
    #expect(tenMsPackets == 25)
}

@Test("Audio drop window packet count has sane lower bounds")
func audioDropWindowPacketCountHasSaneLowerBounds() {
    let zeroWindow = ShadowClientRealtimeAudioSessionRuntime.dropPacketCountForWindow(
        windowSeconds: 0,
        packetDurationMs: 5
    )
    let onePacketWindow = ShadowClientRealtimeAudioSessionRuntime.dropPacketCountForWindow(
        windowSeconds: 0.001,
        packetDurationMs: 5
    )

    #expect(zeroWindow == 0)
    #expect(onePacketWindow == 1)
}

@Test("Audio queue profile keeps output buffer window low-latency for stereo")
func audioQueueProfileKeepsLowLatencyWindowForStereo() {
    let maximumQueuedBuffers = ShadowClientRealtimeAudioSessionRuntime
        .recommendedMaximumQueuedAudioBuffers(
            sampleRate: 48_000,
            channels: 2
        )
    let pressureTrimToRecentPackets = ShadowClientRealtimeAudioSessionRuntime
        .recommendedAudioPressureTrimToRecentPackets(
            sampleRate: 48_000,
            channels: 2
        )

    #expect(maximumQueuedBuffers == 10)
    #expect(pressureTrimToRecentPackets <= 12)
    #expect(pressureTrimToRecentPackets >= 1)
}

@Test("Audio realtime pending cap stays moonlight-aligned for 5ms Opus")
func audioRealtimePendingCapStaysMoonlightAlignedForFiveMsOpus() {
    let capMs = ShadowClientRealtimeAudioSessionRuntime.recommendedAudioRealtimePendingDurationCapMs(
        sampleRate: 48_000,
        channels: 2,
        packetDurationMs: 5
    )

    #expect(capMs == 30)
}

@Test("Audio realtime pending cap remains fixed across queue depth")
func audioRealtimePendingCapRemainsFixedAcrossQueueDepth() {
    let softBoundCap = ShadowClientRealtimeAudioSessionRuntime.audioRealtimePendingDurationCapMs(
        packetDurationMs: 5,
        maximumQueuedBuffers: 1
    )
    let hardBoundCap = ShadowClientRealtimeAudioSessionRuntime.audioRealtimePendingDurationCapMs(
        packetDurationMs: 5,
        maximumQueuedBuffers: 20
    )

    #expect(softBoundCap == 30)
    #expect(hardBoundCap == 30)
}

@Test("Audio queue profile scales channel slack without unbounded queue growth")
func audioQueueProfileScalesChannelSlackWithoutUnboundedGrowth() {
    let stereoQueuedBuffers = ShadowClientRealtimeAudioSessionRuntime
        .recommendedMaximumQueuedAudioBuffers(
            sampleRate: 48_000,
            channels: 2
        )
    let surroundQueuedBuffers = ShadowClientRealtimeAudioSessionRuntime
        .recommendedMaximumQueuedAudioBuffers(
            sampleRate: 48_000,
            channels: 6
        )

    #expect(surroundQueuedBuffers == stereoQueuedBuffers)
    #expect(surroundQueuedBuffers == 10)
}

@Test("Audio queue profile expands queued buffer budget for shorter packet durations")
func audioQueueProfileExpandsQueuedBufferBudgetForShortPacketDurations() {
    let fiveMsQueuedBuffers = ShadowClientRealtimeAudioSessionRuntime
        .recommendedMaximumQueuedAudioBuffers(
            sampleRate: 48_000,
            channels: 2,
            packetDurationMs: 5
        )
    let tenMsQueuedBuffers = ShadowClientRealtimeAudioSessionRuntime
        .recommendedMaximumQueuedAudioBuffers(
            sampleRate: 48_000,
            channels: 2,
            packetDurationMs: 10
        )

    #expect(fiveMsQueuedBuffers == tenMsQueuedBuffers)
    #expect(fiveMsQueuedBuffers == 10)
}

@Test("Audio recovered-packet burst budget follows available output slots")
func audioRecoveredPacketBurstBudgetFollowsAvailableOutputSlots() {
    let zeroSlotBudget = ShadowClientRealtimeAudioSessionRuntime.maximumRecoveredAudioPacketsPerBurst(
        availableOutputSlots: 0
    )
    let oneSlotBudget = ShadowClientRealtimeAudioSessionRuntime.maximumRecoveredAudioPacketsPerBurst(
        availableOutputSlots: 1
    )
    let twoSlotBudget = ShadowClientRealtimeAudioSessionRuntime.maximumRecoveredAudioPacketsPerBurst(
        availableOutputSlots: 2
    )
    let tenSlotBudget = ShadowClientRealtimeAudioSessionRuntime.maximumRecoveredAudioPacketsPerBurst(
        availableOutputSlots: 10
    )

    #expect(zeroSlotBudget == 0)
    #expect(oneSlotBudget == 1)
    #expect(twoSlotBudget == 2)
    #expect(tenSlotBudget == 2)
}

@Test("Audio concealment burst budget follows available output slots")
func audioConcealmentBurstBudgetFollowsAvailableOutputSlots() {
    let zeroSlotBudget = ShadowClientRealtimeAudioSessionRuntime.maximumConcealmentPacketsPerBurst(
        availableOutputSlots: 0
    )
    let oneSlotBudget = ShadowClientRealtimeAudioSessionRuntime.maximumConcealmentPacketsPerBurst(
        availableOutputSlots: 1
    )
    let fourSlotBudget = ShadowClientRealtimeAudioSessionRuntime.maximumConcealmentPacketsPerBurst(
        availableOutputSlots: 4
    )
    let tenSlotBudget = ShadowClientRealtimeAudioSessionRuntime.maximumConcealmentPacketsPerBurst(
        availableOutputSlots: 10
    )

    #expect(zeroSlotBudget == 0)
    #expect(oneSlotBudget == 1)
    #expect(fourSlotBudget == 4)
    #expect(tenSlotBudget == 4)
}

@Test("Audio PLC frame samples follow Moonlight packet-duration rule")
func audioPLCSampleCountFollowsMoonlightPacketDurationRule() {
    let fiveMs = ShadowClientRealtimeAudioSessionRuntime.moonlightPLCSamplesPerChannel(
        sampleRate: 48_000,
        packetDurationMs: 5,
        minimumPacketSamples: 240,
        maximumPacketSamples: 5_760
    )
    let tenMs = ShadowClientRealtimeAudioSessionRuntime.moonlightPLCSamplesPerChannel(
        sampleRate: 48_000,
        packetDurationMs: 10,
        minimumPacketSamples: 240,
        maximumPacketSamples: 5_760
    )

    #expect(fiveMs == 240)
    #expect(tenMs == 480)
}

@Test("Audio startup resync drop window follows Moonlight packet-duration rule")
func audioStartupResyncDropWindowFollowsMoonlightPacketDurationRule() {
    #expect(
        ShadowClientRealtimeAudioSessionRuntime.initialAudioResyncDropPacketCount(
            packetDurationMs: 5
        ) == 100
    )
    #expect(
        ShadowClientRealtimeAudioSessionRuntime.initialAudioResyncDropPacketCount(
            packetDurationMs: 10
        ) == 50
    )
}

@Test("Custom audio decoder default decodeFEC path delegates to decode(payload:)")
func customAudioDecoderDefaultDecodeFECDelegatesToDecodePayload() throws {
    let decoder = RecordingDefaultCustomAudioDecoder()
    let payload = Data([0x11, 0x22, 0x33])

    _ = try decoder.decode(payload: payload, decodeFEC: false)
    _ = try decoder.decode(payload: payload, decodeFEC: true)

    #expect(decoder.decodeCallCount == 2)
    #expect(decoder.decodedPayloads == [payload, payload])
}

@Test("Custom audio decoder default packet-loss concealment API returns nil for silence fallback path")
func customAudioDecoderDefaultPacketLossConcealmentReturnsNil() throws {
    let decoder = RecordingDefaultCustomAudioDecoder()
    let plc = try decoder.decodePacketLossConcealment(samplesPerChannel: 960)

    #expect(plc == nil)
}

@Test("Custom audio decoder PLC override receives exact samples-per-channel request")
func customAudioDecoderPacketLossConcealmentOverrideReceivesRequestedSampleCount() throws {
    let decoder = RecordingPLCCustomAudioDecoder()
    let plc = try decoder.decodePacketLossConcealment(samplesPerChannel: 960)

    #expect(decoder.requestedPLCSamples == [960])
    #expect(plc?.frameLength == 960)
}

@Test("Custom audio decoder registry prioritizes preferred providers")
func customAudioDecoderRegistryPrioritizesPreferredProviders() async throws {
    await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders()
    defer { Task { await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders() } }

    await ShadowClientRealtimeCustomAudioDecoderRegistry.register(
        provider: { _ in
            MockCustomAudioDecoder(
                codec: .opus,
                sampleRate: 48_000,
                channels: 6
            )
        },
        preferred: false
    )
    await ShadowClientRealtimeCustomAudioDecoderRegistry.register(
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
    let decoder = try await ShadowClientRealtimeCustomAudioDecoderRegistry.makeDecoder(
        for: track
    )

    #expect(decoder != nil)
    #expect(decoder?.sampleRate == 44_100)
    #expect(decoder?.channels == 8)
}

@Test("Audio negotiation downgrades surround request to stereo without multichannel decoder")
func audioNegotiationDowngradesSurroundWhenDecoderUnavailable() async {
    await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders()
    defer { Task { await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders() } }

    let preferredChannels = await ShadowClientRealtimeAudioSessionRuntime.preferredOpusChannelCountForNegotiation(
        surroundRequested: true,
        preferredSurroundChannelCount: 6
    )

    #expect(preferredChannels == 2)
}

@Test("Opus decoding requires external decoder provider")
func opusDecodingRequiresExternalDecoderProvider() async {
    await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders()
    defer { Task { await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders() } }

    let stereoTrack = ShadowClientRTSPAudioTrackDescriptor(
        codec: .opus,
        rtpPayloadType: 97,
        sampleRate: 48_000,
        channelCount: 2,
        controlURL: nil,
        formatParameters: [:]
    )

    #expect(!(await ShadowClientRealtimeAudioSessionRuntime.canDecode(track: stereoTrack)))
}

@Test("Opus decoding succeeds when external decoder provider is available")
func opusDecodingSucceedsWithExternalDecoderProvider() async {
    await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders()
    defer { Task { await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders() } }

    await ShadowClientRealtimeCustomAudioDecoderRegistry.register(
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

    #expect(await ShadowClientRealtimeAudioSessionRuntime.canDecode(track: stereoTrack))
}

@Test("Audio negotiation keeps surround request when multichannel decoder is available")
func audioNegotiationKeepsSurroundWhenDecoderAvailable() async {
    await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders()
    defer { Task { await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders() } }

    await ShadowClientRealtimeCustomAudioDecoderRegistry.register(
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

    let preferredChannels = await ShadowClientRealtimeAudioSessionRuntime.preferredOpusChannelCountForNegotiation(
        surroundRequested: true,
        preferredSurroundChannelCount: 6,
        maximumOutputChannels: 8
    )

    #expect(preferredChannels == 6)
}

@Test("Audio negotiation downgrades surround request when playback output is stereo-only")
func audioNegotiationDowngradesSurroundWhenOutputIsStereoOnly() async {
    await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders()
    defer { Task { await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders() } }

    await ShadowClientRealtimeCustomAudioDecoderRegistry.register(
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

    let preferredChannels = await ShadowClientRealtimeAudioSessionRuntime.preferredOpusChannelCountForNegotiation(
        surroundRequested: true,
        preferredSurroundChannelCount: 6,
        maximumOutputChannels: 2
    )

    #expect(preferredChannels == 2)
}

@Test("Audio negotiation respects requested surround ceiling")
func audioNegotiationRespectsRequestedSurroundCeiling() async {
    await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders()
    defer { Task { await ShadowClientRealtimeCustomAudioDecoderRegistry.clearProviders() } }

    await ShadowClientRealtimeCustomAudioDecoderRegistry.register(
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

    let preferredChannels = await ShadowClientRealtimeAudioSessionRuntime.preferredOpusChannelCountForNegotiation(
        surroundRequested: true,
        preferredSurroundChannelCount: 6,
        maximumOutputChannels: 8
    )

    #expect(preferredChannels == 6)
}
