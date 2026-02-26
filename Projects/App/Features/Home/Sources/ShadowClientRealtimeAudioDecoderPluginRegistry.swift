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

public enum ShadowClientRealtimeCustomAudioDecoderRegistry {
    private static let lock = NSLock()
    private static var providers: [ShadowClientRealtimeCustomAudioDecoderProvider] = []

    public static func register(
        provider: @escaping ShadowClientRealtimeCustomAudioDecoderProvider,
        preferred: Bool = true
    ) {
        lock.lock()
        if preferred {
            providers.insert(provider, at: 0)
        } else {
            providers.append(provider)
        }
        lock.unlock()
    }

    public static func clearProviders() {
        lock.lock()
        providers.removeAll(keepingCapacity: false)
        lock.unlock()
    }

    static func makeDecoder(
        for track: ShadowClientRTSPAudioTrackDescriptor
    ) throws -> (any ShadowClientRealtimeCustomAudioDecoder)? {
        lock.lock()
        let providers = self.providers
        lock.unlock()
        for provider in providers {
            if let decoder = try provider(track) {
                return decoder
            }
        }
        return nil
    }
}
