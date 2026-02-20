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
        case failed(String)
    }

    @Published public private(set) var renderState: RenderState = .idle
    @Published public private(set) var controlRoundTripMs: Int?

    public let frameStore: ShadowClientRealtimeSessionFrameStore

    public init(frameStore: ShadowClientRealtimeSessionFrameStore = .init()) {
        self.frameStore = frameStore
    }

    public func reset() {
        frameStore.update(pixelBuffer: nil)
        renderState = .idle
        controlRoundTripMs = nil
    }

    public func transition(to state: RenderState) {
        renderState = state
    }

    public func updateControlRoundTripMs(_ milliseconds: Int?) {
        controlRoundTripMs = milliseconds.map { max(0, $0) }
    }
}

extension ShadowClientRealtimeSessionSurfaceContext: @unchecked Sendable {}
