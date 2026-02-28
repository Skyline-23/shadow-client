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

private actor ShadowClientControlRoundTripStreamHub {
    private var continuations: [UUID: AsyncStream<Int?>.Continuation] = [:]

    func register(
        id: UUID,
        continuation: AsyncStream<Int?>.Continuation,
        initialValue: Int?
    ) {
        continuations[id] = continuation
        continuation.yield(initialValue)
    }

    func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    func publish(_ value: Int?) {
        continuations.values.forEach { $0.yield(value) }
    }

    func finishAll() {
        let pendingContinuations = Array(continuations.values)
        continuations.removeAll(keepingCapacity: false)
        pendingContinuations.forEach { $0.finish() }
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

    public enum DynamicRangeMode: String, Equatable, Sendable {
        case unknown
        case sdr
        case hdr
    }

    @Published public private(set) var renderState: RenderState = .idle
    @Published public private(set) var controlRoundTripMs: Int?
    @Published public private(set) var activeVideoCodec: ShadowClientVideoCodec?
    @Published public private(set) var estimatedVideoFPS: Double?
    @Published public private(set) var estimatedVideoBitrateKbps: Int?
    @Published public private(set) var audioOutputState: ShadowClientRealtimeAudioOutputState = .idle
    @Published public private(set) var activeDynamicRangeMode: DynamicRangeMode = .unknown
    @Published public private(set) var preferredRenderFPS = ShadowClientStreamingLaunchBounds.defaultFPS
    private var lastControlRoundTripPublishUptime: TimeInterval = 0
    private let controlRoundTripStreamHub = ShadowClientControlRoundTripStreamHub()

    public let frameStore: ShadowClientRealtimeSessionFrameStore

    public init(frameStore: ShadowClientRealtimeSessionFrameStore = .init()) {
        self.frameStore = frameStore
    }

    deinit {
        let streamHub = controlRoundTripStreamHub
        Task {
            await streamHub.finishAll()
        }
    }

    public func reset() {
        frameStore.update(pixelBuffer: nil)
        renderState = .idle
        controlRoundTripMs = nil
        publishControlRoundTripSample(nil)
        activeVideoCodec = nil
        estimatedVideoFPS = nil
        estimatedVideoBitrateKbps = nil
        audioOutputState = .idle
        activeDynamicRangeMode = .unknown
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
        publishControlRoundTripSample(normalized)
    }

    public func controlRoundTripAsyncStream() -> AsyncStream<Int?> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let identifier = UUID()
            let initialValue = controlRoundTripMs
            let streamHub = controlRoundTripStreamHub
            Task {
                await streamHub.register(
                    id: identifier,
                    continuation: continuation,
                    initialValue: initialValue
                )
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else {
                    return
                }
                let streamHub = self.controlRoundTripStreamHub
                Task {
                    await streamHub.unregister(id: identifier)
                }
            }
        }
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

    public func updateActiveDynamicRangeMode(_ mode: DynamicRangeMode) {
        if activeDynamicRangeMode == mode {
            return
        }
        activeDynamicRangeMode = mode
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

    private func publishControlRoundTripSample(_ milliseconds: Int?) {
        let streamHub = controlRoundTripStreamHub
        Task {
            await streamHub.publish(milliseconds)
        }
    }
}

extension ShadowClientRealtimeSessionSurfaceContext: @unchecked Sendable {}
