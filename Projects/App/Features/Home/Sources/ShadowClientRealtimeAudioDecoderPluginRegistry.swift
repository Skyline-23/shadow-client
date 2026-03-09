import AVFoundation
import Foundation

public protocol ShadowClientRealtimeCustomAudioDecoder: AnyObject {
    var codec: ShadowClientAudioCodec { get }
    var sampleRate: Int { get }
    var channels: Int { get }
    var outputFormat: AVAudioFormat { get }
    var requiresPlaybackSafetyGuard: Bool { get }
    func decode(payload: Data) throws -> AVAudioPCMBuffer?
    func decode(payload: Data, decodeFEC: Bool) throws -> AVAudioPCMBuffer?
    func decodePacketLossConcealment(samplesPerChannel: Int) throws -> AVAudioPCMBuffer?
}

public extension ShadowClientRealtimeCustomAudioDecoder {
    var requiresPlaybackSafetyGuard: Bool { true }

    func decode(payload: Data, decodeFEC _: Bool) throws -> AVAudioPCMBuffer? {
        try decode(payload: payload)
    }

    func decodePacketLossConcealment(samplesPerChannel _: Int) throws -> AVAudioPCMBuffer? {
        nil
    }
}

public typealias ShadowClientRealtimeCustomAudioDecoderProvider =
    (ShadowClientRTSPAudioTrackDescriptor) throws -> (any ShadowClientRealtimeCustomAudioDecoder)?

private actor ShadowClientRealtimeCustomAudioDecoderProviderStore {
    private var providers: [ShadowClientRealtimeCustomAudioDecoderProvider] = []

    func register(
        provider: @escaping ShadowClientRealtimeCustomAudioDecoderProvider,
        preferred: Bool
    ) {
        if preferred {
            providers.insert(provider, at: 0)
        } else {
            providers.append(provider)
        }
    }

    func clearProviders() {
        providers.removeAll(keepingCapacity: false)
    }

    func makeDecoder(
        for track: ShadowClientRTSPAudioTrackDescriptor
    ) throws -> (any ShadowClientRealtimeCustomAudioDecoder)? {
        for provider in providers {
            if let decoder = try provider(track) {
                return decoder
            }
        }
        return nil
    }
}

public enum ShadowClientRealtimeCustomAudioDecoderRegistry {
    private static let store = ShadowClientRealtimeCustomAudioDecoderProviderStore()

    public static func register(
        provider: @escaping ShadowClientRealtimeCustomAudioDecoderProvider,
        preferred: Bool = true
    ) async {
        await store.register(provider: provider, preferred: preferred)
    }

    public static func clearProviders() async {
        await store.clearProviders()
    }

    static func makeDecoder(
        for track: ShadowClientRTSPAudioTrackDescriptor
    ) async throws -> (any ShadowClientRealtimeCustomAudioDecoder)? {
        try await store.makeDecoder(for: track)
    }
}
