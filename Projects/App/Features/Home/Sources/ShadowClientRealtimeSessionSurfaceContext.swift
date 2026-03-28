import CoreGraphics
import CoreVideo
import Foundation
import ShadowClientFeatureSession

struct ShadowClientSendableFramePixelBuffer: @unchecked Sendable {
    let value: CVPixelBuffer
}

public actor ShadowClientRealtimeSessionFrameStore {
    struct Snapshot: Sendable {
        let pixelBuffer: ShadowClientSendableFramePixelBuffer?
        let hdrFrameState: ShadowClientHDRFrameState?
        let revision: UInt64
    }

    private var latestSnapshot = Snapshot(pixelBuffer: nil, hdrFrameState: nil, revision: 0)
    private var continuations: [UUID: AsyncStream<Snapshot>.Continuation] = [:]

    public init() {}

    public func update(
        pixelBuffer: CVPixelBuffer?,
        hdrFrameState: ShadowClientHDRFrameState? = nil
    ) {
        latestSnapshot = Snapshot(
            pixelBuffer: pixelBuffer.map(ShadowClientSendableFramePixelBuffer.init),
            hdrFrameState: hdrFrameState,
            revision: latestSnapshot.revision &+ 1
        )
        continuations.values.forEach { $0.yield(latestSnapshot) }
    }

    func snapshotStream() -> AsyncStream<Snapshot> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let identifier = UUID()
            continuations[identifier] = continuation
            continuation.yield(latestSnapshot)
            continuation.onTermination = { [weak self] _ in
                guard let self else {
                    return
                }
                Task {
                    await self.unregisterContinuation(id: identifier)
                }
            }
        }
    }

    private func unregisterContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
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

private actor ShadowClientControllerFeedbackStreamHub {
    private var continuations: [UUID: AsyncStream<ShadowClientHostControllerFeedbackEvent>.Continuation] = [:]

    func register(
        id: UUID,
        continuation: AsyncStream<ShadowClientHostControllerFeedbackEvent>.Continuation
    ) {
        continuations[id] = continuation
    }

    func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }

    func publish(_ event: ShadowClientHostControllerFeedbackEvent) {
        continuations.values.forEach { $0.yield(event) }
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
    @Published public private(set) var audioPendingDurationMs: Double = 0
    @Published public private(set) var activeDynamicRangeMode: DynamicRangeMode = .unknown
    @Published public private(set) var activeHDRMetadata: ShadowClientHDRMetadata?
    @Published public private(set) var activeHDRFrameState: ShadowClientHDRFrameState?
    @Published public private(set) var colorConfigurationRevision: UInt64 = 0
    @Published public private(set) var preferredRenderFPS = ShadowClientStreamingLaunchBounds.defaultFPS
    @Published public private(set) var videoPresentationSize: CGSize?
    private var lastControlRoundTripPublishUptime: TimeInterval = 0
    private var presentedFrameWindowStartUptime: TimeInterval = 0
    private var presentedFrameCount = 0
    private var lastPresentedFramePublishUptime: TimeInterval = 0
    private let controlRoundTripStreamHub = ShadowClientControlRoundTripStreamHub()
    private let controllerFeedbackStreamHub = ShadowClientControllerFeedbackStreamHub()

    public let frameStore: ShadowClientRealtimeSessionFrameStore

    public init(frameStore: ShadowClientRealtimeSessionFrameStore = .init()) {
        self.frameStore = frameStore
    }

    deinit {
        let streamHub = controlRoundTripStreamHub
        let feedbackHub = controllerFeedbackStreamHub
        Task {
            await streamHub.finishAll()
            await feedbackHub.finishAll()
        }
    }

    public func reset() {
        scheduleFrameClear()
        resetPublishedState()
    }

    @MainActor
    public func resetAwaitingFrameClear() async {
        await frameStore.update(
            pixelBuffer: nil,
            hdrFrameState: nil
        )
        resetPublishedState()
    }

    private func scheduleFrameClear() {
        let frameStore = self.frameStore
        Task {
            await frameStore.update(
                pixelBuffer: nil,
                hdrFrameState: nil
            )
        }
    }

    private func resetPublishedState() {
        renderState = .idle
        controlRoundTripMs = nil
        publishControlRoundTripSample(nil)
        activeVideoCodec = nil
        estimatedVideoFPS = nil
        estimatedVideoBitrateKbps = nil
        audioOutputState = .idle
        audioPendingDurationMs = 0
        activeDynamicRangeMode = .unknown
        activeHDRMetadata = nil
        activeHDRFrameState = nil
        colorConfigurationRevision = 0
        preferredRenderFPS = ShadowClientStreamingLaunchBounds.defaultFPS
        videoPresentationSize = nil
        lastControlRoundTripPublishUptime = 0
        presentedFrameWindowStartUptime = 0
        presentedFrameCount = 0
        lastPresentedFramePublishUptime = 0
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

    func controllerFeedbackAsyncStream() -> AsyncStream<ShadowClientHostControllerFeedbackEvent> {
        AsyncStream(bufferingPolicy: .bufferingNewest(8)) { continuation in
            let identifier = UUID()
            let feedbackHub = controllerFeedbackStreamHub
            Task {
                await feedbackHub.register(
                    id: identifier,
                    continuation: continuation
                )
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else {
                    return
                }
                let feedbackHub = self.controllerFeedbackStreamHub
                Task {
                    await feedbackHub.unregister(id: identifier)
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

    public func updateRuntimeVideoBitrateKbps(_ bitrateKbps: Int?) {
        if let bitrateKbps {
            estimatedVideoBitrateKbps = max(0, bitrateKbps)
        } else {
            estimatedVideoBitrateKbps = nil
        }
    }

    public func recordPresentedVideoFrame(nowUptime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if presentedFrameWindowStartUptime == 0 {
            presentedFrameWindowStartUptime = nowUptime
        }
        presentedFrameCount += 1

        if nowUptime - lastPresentedFramePublishUptime < 0.2 {
            return
        }
        lastPresentedFramePublishUptime = nowUptime

        let windowDuration = max(nowUptime - presentedFrameWindowStartUptime, 0.001)
        estimatedVideoFPS = Double(presentedFrameCount) / windowDuration
        presentedFrameWindowStartUptime = nowUptime
        presentedFrameCount = 0
    }

    public func updateAudioOutputState(
        _ state: ShadowClientRealtimeAudioOutputState
    ) {
        if audioOutputState == state {
            return
        }
        audioOutputState = state
    }

    public func updateAudioPendingDurationMs(_ milliseconds: Double) {
        let normalized = max(0, milliseconds)
        if abs(audioPendingDurationMs - normalized) < 0.5 {
            return
        }
        audioPendingDurationMs = normalized
    }

    public func updateActiveDynamicRangeMode(_ mode: DynamicRangeMode) {
        if activeDynamicRangeMode == mode {
            return
        }
        activeDynamicRangeMode = mode
        colorConfigurationRevision &+= 1
    }

    public func updateActiveHDRMetadata(_ metadata: ShadowClientHDRMetadata?) {
        if activeHDRMetadata == metadata {
            return
        }
        activeHDRMetadata = metadata
        colorConfigurationRevision &+= 1
    }

    public func updateActiveHDRFrameState(_ frameState: ShadowClientHDRFrameState?) {
        if activeHDRFrameState == frameState {
            return
        }
        activeHDRFrameState = frameState
        colorConfigurationRevision &+= 1
    }

    public func updateVideoPresentationSize(_ size: CGSize?) {
        if videoPresentationSize == size {
            return
        }
        videoPresentationSize = size
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

    func publishControllerFeedbackEvent(
        _ event: ShadowClientHostControllerFeedbackEvent
    ) {
        let feedbackHub = controllerFeedbackStreamHub
        Task {
            await feedbackHub.publish(event)
        }
    }
}

extension ShadowClientRealtimeSessionSurfaceContext: @unchecked Sendable {}
