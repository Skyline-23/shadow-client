import CoreVideo
import Foundation

public final class ShadowClientRealtimeSessionFrameStore: @unchecked Sendable {
    private let lock = NSLock()
    private var latestPixelBuffer: CVPixelBuffer?
    private var latestRevision: UInt64 = 0

    public init() {}

    public func update(pixelBuffer: CVPixelBuffer?) {
        lock.lock()
        latestPixelBuffer = pixelBuffer
        latestRevision &+= 1
        lock.unlock()
    }

    public func snapshot() -> CVPixelBuffer? {
        snapshotWithRevision().pixelBuffer
    }

    public func snapshotWithRevision() -> (pixelBuffer: CVPixelBuffer?, revision: UInt64) {
        lock.lock()
        let buffer = latestPixelBuffer
        let revision = latestRevision
        lock.unlock()
        return (buffer, revision)
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
    @Published public private(set) var audioOutputState: ShadowClientRealtimeAudioOutputState = .idle
    @Published public private(set) var preferredRenderFPS = ShadowClientStreamingLaunchBounds.defaultFPS
    private var lastControlRoundTripPublishUptime: TimeInterval = 0

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
        audioOutputState = .idle
        preferredRenderFPS = ShadowClientStreamingLaunchBounds.defaultFPS
        lastControlRoundTripPublishUptime = 0
    }

    public func transition(to state: RenderState) {
        renderState = state
    }

    public func updateControlRoundTripMs(_ milliseconds: Int?) {
        let normalized = milliseconds.map { max(0, $0) }
        if normalized == controlRoundTripMs {
            return
        }

        let now = ProcessInfo.processInfo.systemUptime
        if let current = controlRoundTripMs,
           let next = normalized
        {
            let withinPublishInterval =
                (now - lastControlRoundTripPublishUptime) <
                ShadowClientRealtimeSessionDefaults.controlRoundTripPublishMinimumIntervalSeconds
            let smallDelta =
                abs(next - current) <=
                ShadowClientRealtimeSessionDefaults.controlRoundTripPublishDeltaThresholdMs
            if withinPublishInterval && smallDelta {
                return
            }
        }

        controlRoundTripMs = normalized
        lastControlRoundTripPublishUptime = now
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

    public func updateAudioOutputState(
        _ state: ShadowClientRealtimeAudioOutputState
    ) {
        if audioOutputState == state {
            return
        }
        audioOutputState = state
    }

    public func updatePreferredRenderFPS(_ fps: Int) {
        let normalized = Self.normalizedRenderFPS(fps)
        if preferredRenderFPS == normalized {
            return
        }
        preferredRenderFPS = normalized
    }

    private static func normalizedRenderFPS(_ fps: Int) -> Int {
        max(fps, 1)
    }
}

extension ShadowClientRealtimeSessionSurfaceContext: @unchecked Sendable {}
