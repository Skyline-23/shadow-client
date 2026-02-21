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

@Test("Payload type adaptation accepts dynamic payload type changes")
func payloadTypeAdaptationAcceptsDynamicChanges() {
    let adapted = ShadowClientRealtimeAudioSessionRuntime.payloadTypePreference(
        observed: 98,
        current: 97
    )

    #expect(adapted == 98)
}

@Test("Payload type adaptation ignores matching payload types")
func payloadTypeAdaptationIgnoresMatching() {
    let adapted = ShadowClientRealtimeAudioSessionRuntime.payloadTypePreference(
        observed: 97,
        current: 97
    )

    #expect(adapted == nil)
}

@Test("Payload type adaptation rejects RTCP/control-like payload types")
func payloadTypeAdaptationRejectsControlValues() {
    let adapted = ShadowClientRealtimeAudioSessionRuntime.payloadTypePreference(
        observed: 72,
        current: 97
    )

    #expect(adapted == nil)
}

@Test("Payload type adaptation ignores negotiated control payload type")
func payloadTypeAdaptationIgnoresNegotiatedControlPayloadType() {
    let adapted = ShadowClientRealtimeAudioSessionRuntime.payloadTypePreference(
        observed: ShadowClientRealtimeSessionDefaults.ignoredRTPControlPayloadType,
        current: 97
    )

    #expect(adapted == nil)
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
        preferredSurroundChannelCount: 6
    )

    #expect(preferredChannels == 6)
}
