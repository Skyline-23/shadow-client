import CoreVideo
import Foundation

public final class ShadowClientRealtimeSessionFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?

    public init() {}

    public func update(pixelBuffer: CVPixelBuffer?) {
        lock.lock()
        latestPixelBuffer = pixelBuffer
        lock.unlock()
    }

    public func snapshot() -> CVPixelBuffer? {
        lock.lock()
        let buffer = latestPixelBuffer
        lock.unlock()
        return buffer
    }
}

public final class ShadowClientRealtimeSessionSurfaceContext: ObservableObject {
    public enum RenderState: Equatable, Sendable {
        case idle
        case connecting
        case waitingForFirstFrame
        case rendering
        case disconnected(String)
        case failed(String)
    }

    @Published public private(set) var renderState: RenderState = .idle
    @Published public private(set) var controlRoundTripMs: Int?
    @Published public private(set) var activeVideoCodec: ShadowClientVideoCodec?
    @Published public private(set) var estimatedVideoFPS: Double?
    @Published public private(set) var estimatedVideoBitrateKbps: Int?

    public let frameStore: ShadowClientRealtimeSessionFrameStore

    public init(frameStore: ShadowClientRealtimeSessionFrameStore = .init()) {
        self.frameStore = frameStore
    }

    public func reset() {
        frameStore.update(pixelBuffer: nil)
        renderState = .idle
        controlRoundTripMs = nil
        activeVideoCodec = nil
        estimatedVideoFPS = nil
        estimatedVideoBitrateKbps = nil
    }

    public func transition(to state: RenderState) {
        renderState = state
    }

    public func updateControlRoundTripMs(_ milliseconds: Int?) {
        controlRoundTripMs = milliseconds.map { max(0, $0) }
    }

    public func updateActiveVideoCodec(_ codec: ShadowClientVideoCodec?) {
        activeVideoCodec = codec
    }

    public func updateRuntimeVideoStats(
        fps: Double?,
        bitrateKbps: Int?
    ) {
        if let fps, fps.isFinite, fps >= 0 {
            estimatedVideoFPS = fps
        } else {
            estimatedVideoFPS = nil
        }

        if let bitrateKbps {
            estimatedVideoBitrateKbps = max(0, bitrateKbps)
        } else {
            estimatedVideoBitrateKbps = nil
        }
    }
}

extension ShadowClientRealtimeSessionSurfaceContext: @unchecked Sendable {}
