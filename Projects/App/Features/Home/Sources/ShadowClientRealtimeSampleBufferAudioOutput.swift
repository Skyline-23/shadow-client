@preconcurrency import AVFoundation
import Foundation
import os
import ShadowClientFeatureSession
#if os(macOS)
import CoreAudio
#endif

#if os(iOS) || os(tvOS) || os(macOS)
// Safety invariant: sample-buffer rendering state is confined to `rendererQueue`,
// while backpressure accounting is actor-isolated in `BudgetState`.
final class ShadowClientRealtimeSampleBufferAudioOutput: @unchecked Sendable, ShadowClientRealtimeAudioOutput {
    private static let logger = Logger(
        subsystem: "com.skyline23.shadow-client",
        category: "RealtimeSampleBufferAudio"
    )
    private static let millisecondsPerSecond = 1_000.0

    private actor BudgetState {
        private let sampleRate: Double
        private let nominalFramesPerBuffer: Double
        private let maximumQueuedFrameEstimate: Double
        private var queuedFrameEstimate: Double = 0
        private var lastObservedTime: CMTime?

        init(
            sampleRate: Double,
            nominalFramesPerBuffer: Double,
            maximumQueuedFrameEstimate: Double
        ) {
            self.sampleRate = sampleRate
            self.nominalFramesPerBuffer = nominalFramesPerBuffer
            self.maximumQueuedFrameEstimate = maximumQueuedFrameEstimate
        }

        func reserve(
            incomingFrameCount: Double,
            currentTime: CMTime
        ) -> Bool {
            advance(to: currentTime)
            guard queuedFrameEstimate + incomingFrameCount <= maximumQueuedFrameEstimate else {
                return false
            }
            queuedFrameEstimate += incomingFrameCount
            return true
        }

        func rollback(incomingFrameCount: Double) {
            queuedFrameEstimate = max(0, queuedFrameEstimate - incomingFrameCount)
        }

        func didHandOffToRenderer(consumedFrameCount: Double, currentTime: CMTime) {
            advance(to: currentTime)
            queuedFrameEstimate = max(0, queuedFrameEstimate - consumedFrameCount)
        }

        func pendingDurationMs(currentTime: CMTime) -> Double {
            advance(to: currentTime)
            guard sampleRate > 0 else {
                return 0
            }
            return (queuedFrameEstimate / sampleRate) * 1_000.0
        }

        func availableEnqueueSlots(currentTime: CMTime) -> Int {
            advance(to: currentTime)
            let remainingFrames = max(0, maximumQueuedFrameEstimate - queuedFrameEstimate)
            return max(0, Int((remainingFrames / nominalFramesPerBuffer).rounded(.down)))
        }

        func hasCapacity(currentTime: CMTime) -> Bool {
            advance(to: currentTime)
            return queuedFrameEstimate < maximumQueuedFrameEstimate
        }

        func reset(currentTime: CMTime?) {
            queuedFrameEstimate = 0
            lastObservedTime = currentTime
        }

        private func advance(to currentTime: CMTime) {
            guard currentTime.isValid, currentTime.isNumeric else {
                lastObservedTime = nil
                return
            }
            guard let lastObservedTime,
                  lastObservedTime.isValid,
                  lastObservedTime.isNumeric
            else {
                self.lastObservedTime = currentTime
                return
            }
            let delta = CMTimeGetSeconds(currentTime) - CMTimeGetSeconds(lastObservedTime)
            guard delta > 0 else {
                self.lastObservedTime = currentTime
                return
            }
            queuedFrameEstimate = max(0, queuedFrameEstimate - (delta * sampleRate))
            self.lastObservedTime = currentTime
        }
    }

    private struct PendingSampleBuffer {
        let sampleBuffer: CMSampleBuffer
        let frameCount: Double
    }

    private let inputFormat: AVAudioFormat
    private let renderFormat: AVAudioFormat
    private let rendererQueue = DispatchQueue(
        label: "com.skyline23.shadow-client.audio-sample-buffer-renderer",
        qos: .userInitiated
    )
    private let renderer = AVSampleBufferAudioRenderer()
    private let synchronizer = AVSampleBufferRenderSynchronizer()
    private let formatDescription: CMAudioFormatDescription
    private let formatConverter: AVAudioConverter?
    private let budgetState: BudgetState
    private let nominalFramesPerBufferEstimate: Double
    private var pendingSampleBuffers: [PendingSampleBuffer] = []
    private var nextPresentationTime: CMTime = .zero
    private var queuedDurationAnchorTime: CMTime = .zero
    private var hasStartedTimeline = false
    private var hasRequestedTimelineStart = false
    private var isTerminated = false
    private var hasLoggedFirstQueuedSample = false
    private var hasLoggedFirstRendererEnqueue = false
    private var hasLoggedFirstRenderBufferStats = false
    private var hasLoggedFirstConverterInputStats = false
    private var hasLoggedFirstConverterOutputStats = false
    private var flushTask: Task<Void, Never>?
    private var outputConfigurationTask: Task<Void, Never>?
    private var isVideoRenderingReady = false

    private enum TimelineStartupState {
        case idle
        case requested
        case started
    }

    private enum TimelineStartupReason: String {
        case playbackClockProgress = "playback-clock-progress"
    }

    internal struct PressureSheddingDecision: Equatable, Sendable {
        let shouldDefer: Bool
        let shouldClearExpiredGrace: Bool
    }

    private var timelineStartupState: TimelineStartupState = .idle
    private var timelineStartRequestTime: CMTime?
    private var pressureSheddingGraceUntilTime: CMTime?

    init(
        format: AVAudioFormat,
        maximumQueuedBufferCount: Int,
        nominalFramesPerBuffer: AVAudioFrameCount,
        maximumPendingDurationMs: Double,
        prefersSpatialHeadphoneRendering _: Bool
    ) throws {
        inputFormat = format
        renderFormat = try Self.makeRendererFormat(from: format)
        let nominalFrames = max(1, Double(nominalFramesPerBuffer))
        let boundedMaximumPendingDurationMs = max(1, maximumPendingDurationMs)
        let maximumPendingFramesFromDuration = max(
            nominalFrames,
            (renderFormat.sampleRate * boundedMaximumPendingDurationMs / 1_000.0).rounded(.up)
        )
        let maximumPendingFramesFromCount = nominalFrames * Double(max(1, maximumQueuedBufferCount))
        let maximumQueuedFrameEstimate = min(
            maximumPendingFramesFromCount,
            max(nominalFrames, maximumPendingFramesFromDuration)
        )
        nominalFramesPerBufferEstimate = nominalFrames
        formatConverter = renderFormat == format ? nil : AVAudioConverter(from: format, to: renderFormat)
        budgetState = BudgetState(
            sampleRate: renderFormat.sampleRate,
            nominalFramesPerBuffer: nominalFrames,
            maximumQueuedFrameEstimate: maximumQueuedFrameEstimate
        )
        formatDescription = try Self.makeFormatDescription(for: renderFormat)

        renderer.allowedAudioSpatializationFormats = .monoStereoAndMultichannel
        renderer.volume = 1
        renderer.isMuted = false
        synchronizer.addRenderer(renderer)
        synchronizer.delaysRateChangeUntilHasSufficientMediaData = true
        synchronizer.rate = 0

        rendererQueue.sync {
            startFeedingLocked()
            logRendererDiagnosticsLocked(reason: "configured")
        }
        startRendererNotificationMonitoring()
        isVideoRenderingReady = true
        Self.logger.notice(
            "Sample buffer audio backend configured routes=[\(Self.currentRouteSummary(), privacy: .public)] spatial-formats=\(String(describing: self.renderer.allowedAudioSpatializationFormats), privacy: .public)"
        )
    }

    deinit {
        stop()
    }

    func enqueue(pcmBuffer: AVAudioPCMBuffer) async -> Bool {
        let frameCount = max(1, Double(pcmBuffer.frameLength))
        let currentTime = rendererQueue.sync { budgetReferenceTimeLocked() }
        guard await budgetState.reserve(
            incomingFrameCount: frameCount,
            currentTime: currentTime
        ) else {
            return false
        }

        let queued = rendererQueue.sync {
            guard !isTerminated else {
                return false
            }
            recoverFromStarvationIfNeededLocked()
            guard let sampleBuffer = makeSampleBuffer(
                from: pcmBuffer,
                formatDescription: formatDescription,
                presentationTimeStamp: nextPresentationTime
            ) else {
                Self.logger.error(
                    "Sample buffer audio enqueue failed to create CMSampleBuffer frames=\(pcmBuffer.frameLength, privacy: .public)"
                )
                return false
            }

            if !hasLoggedFirstQueuedSample {
                hasLoggedFirstQueuedSample = true
                Self.logger.notice(
                    "Sample buffer audio queued first sample pts=\(CMTimeGetSeconds(self.nextPresentationTime), privacy: .public)s frames=\(pcmBuffer.frameLength, privacy: .public) renderer-ready=\(self.renderer.isReadyForMoreMediaData, privacy: .public) sample-ready=\(CMSampleBufferDataIsReady(sampleBuffer), privacy: .public)"
                )
                logRendererDiagnosticsLocked(reason: "first-queued-sample")
            }
            pendingSampleBuffers.append(
                PendingSampleBuffer(
                    sampleBuffer: sampleBuffer,
                    frameCount: frameCount
                )
            )
            nextPresentationTime = CMTimeAdd(
                nextPresentationTime,
                CMTime(
                    value: CMTimeValue(pcmBuffer.frameLength),
                    timescale: CMTimeScale(max(1, Int32(renderFormat.sampleRate.rounded())))
                )
            )
            startFeedingLocked()
            drainPendingSampleBuffersLocked()
            startTimelineIfNeededLocked()
            return true
        }

        if !queued {
            await budgetState.rollback(incomingFrameCount: frameCount)
        }
        return queued
    }

    func hasEnqueueCapacity() async -> Bool {
        let currentTime = rendererQueue.sync { budgetReferenceTimeLocked() }
        return await budgetState.hasCapacity(currentTime: currentTime)
    }

    func pendingDurationMs() async -> Double {
        let currentTime = rendererQueue.sync { budgetReferenceTimeLocked() }
        let queuePendingDurationMs = await budgetState.pendingDurationMs(currentTime: currentTime)
        let rendererPendingDurationMs: Double = rendererQueue.sync {
            let queuedDuration = CMTimeSubtract(nextPresentationTime, currentTime)
            guard queuedDuration.isValid, queuedDuration.isNumeric else {
                return 0
            }
            return max(0, CMTimeGetSeconds(queuedDuration) * Self.millisecondsPerSecond)
        }
        return Self.pressureSheddingPendingDurationMs(
            moonlightQueuePendingDurationMs: queuePendingDurationMs,
            rendererPendingDurationMs: rendererPendingDurationMs
        )
    }

    func availableEnqueueSlots() async -> Int {
        let currentTime = rendererQueue.sync { budgetReferenceTimeLocked() }
        return await budgetState.availableEnqueueSlots(currentTime: currentTime)
    }

    func shouldDeferPressureShedding() async -> Bool {
        rendererQueue.sync {
            guard !isTerminated else {
                return false
            }
            let currentTime = currentSynchronizerTimeLocked()
            let startupThreshold = Self.startupThresholdDuration(
                outputFormat: renderFormat,
                nominalFramesPerBuffer: nominalFramesPerBufferEstimate
            )
            let decision = Self.pressureSheddingDecision(
                hasStartedTimeline: timelineStartupState == .started,
                nextPresentationTime: nextPresentationTime,
                currentTime: currentTime,
                startupThreshold: startupThreshold,
                pressureSheddingGraceUntilTime: pressureSheddingGraceUntilTime
            )
            if decision.shouldClearExpiredGrace {
                pressureSheddingGraceUntilTime = nil
            }
            return decision.shouldDefer
        }
    }

    func stop() {
        flushTask?.cancel()
        outputConfigurationTask?.cancel()
        flushTask = nil
        outputConfigurationTask = nil

        rendererQueue.sync {
            guard !isTerminated else {
                return
            }
            isTerminated = true
            renderer.stopRequestingMediaData()
            renderer.flush()
            pendingSampleBuffers.removeAll(keepingCapacity: true)
            synchronizer.rate = 0
            queuedDurationAnchorTime = nextPresentationTime
            hasRequestedTimelineStart = false
            hasStartedTimeline = false
            timelineStartupState = .idle
            timelineStartRequestTime = nil
            pressureSheddingGraceUntilTime = nil
            isVideoRenderingReady = false
        }

        let budgetState = self.budgetState
        Task {
            await budgetState.reset(currentTime: nil)
        }
    }

    func recoverPlaybackUnderPressure() -> Bool {
        rendererQueue.sync {
            guard !isTerminated else {
                return false
            }
            renderer.stopRequestingMediaData()
            renderer.flush()
            pendingSampleBuffers.removeAll(keepingCapacity: true)
            let resetTime = currentSynchronizerTimeLocked()
            resetTimelineAfterFlushLocked(resetTime: resetTime)
            startFeedingLocked()
            let budgetState = self.budgetState
            Task {
                await budgetState.reset(currentTime: resetTime)
            }
            return true
        }
    }

    var debugFormatDescription: String {
        let interleaving = renderFormat.isInterleaved ? "interleaved" : "planar"
        return "AVSampleBufferAudioRenderer/\(String(describing: renderFormat.commonFormat))/\(renderFormat.channelCount)ch/\(Int(renderFormat.sampleRate))Hz/\(interleaving)"
    }

    var usesSystemManagedBuffering: Bool {
        false
    }

    func updateVideoRenderingState(isRendering: Bool) {
        rendererQueue.async { [weak self] in
            guard let self, !self.isTerminated else {
                return
            }
            guard self.isVideoRenderingReady != isRendering else {
                return
            }
            self.isVideoRenderingReady = isRendering
            if isRendering {
                Self.logger.notice("Sample buffer audio video-render gate opened")
                self.startTimelineIfNeededLocked()
            } else {
                if self.timelineStartupState != .started {
                    self.synchronizer.rate = 0
                    self.hasRequestedTimelineStart = false
                    self.timelineStartupState = .idle
                    self.timelineStartRequestTime = nil
                }
                Self.logger.notice("Sample buffer audio video-render gate closed")
            }
        }
    }

    private func startRendererNotificationMonitoring() {
        flushTask = Task { [weak self] in
            guard let self else {
                return
            }
            for await notification in NotificationCenter.default.notifications(
                named: .AVSampleBufferAudioRendererWasFlushedAutomatically,
                object: renderer
            ) {
                guard !Task.isCancelled else {
                    return
                }
                let flushTimeValue = notification.userInfo?[AVSampleBufferAudioRendererFlushTimeKey] as? NSValue
                let flushTime = flushTimeValue?.timeValue ?? .invalid
                rendererQueue.async { [weak self] in
                    self?.handleAutomaticFlushLocked(flushTime: flushTime)
                }
            }
        }

        outputConfigurationTask = Task { [weak self] in
            guard let self else {
                return
            }
            for await _ in NotificationCenter.default.notifications(
                named: .AVSampleBufferAudioRendererOutputConfigurationDidChange,
                object: renderer
            ) {
                guard !Task.isCancelled else {
                    return
                }
                rendererQueue.async { [weak self] in
                    self?.handleOutputConfigurationChangeLocked()
                }
            }
        }
    }

    private func handleAutomaticFlushLocked(flushTime: CMTime) {
        guard !isTerminated else {
            return
        }
        renderer.stopRequestingMediaData()
        renderer.flush()
        pendingSampleBuffers.removeAll(keepingCapacity: true)
        let resetTime = flushTime.isValid && flushTime.isNumeric ? flushTime : currentSynchronizerTimeLocked()
        resetTimelineAfterFlushLocked(resetTime: resetTime)
        startFeedingLocked()
        let budgetState = self.budgetState
        Task {
            await budgetState.reset(currentTime: resetTime)
        }
        Self.logger.notice(
            "Sample buffer audio renderer auto-flushed; resetting at \(CMTimeGetSeconds(resetTime), privacy: .public)s routes=[\(Self.currentRouteSummary(), privacy: .public)]"
        )
        logRendererDiagnosticsLocked(reason: "auto-flush")
    }

    private func handleOutputConfigurationChangeLocked() {
        guard !isTerminated else {
            return
        }
        renderer.stopRequestingMediaData()
        renderer.flush()
        pendingSampleBuffers.removeAll(keepingCapacity: true)
        let currentTime = currentSynchronizerTimeLocked()
        resetTimelineAfterFlushLocked(resetTime: currentTime)
        startFeedingLocked()
        let budgetState = self.budgetState
        Task {
            await budgetState.reset(currentTime: currentTime)
        }
        Self.logger.notice(
            "Sample buffer audio output configuration changed; resetting renderer routes=[\(Self.currentRouteSummary(), privacy: .public)]"
        )
        logRendererDiagnosticsLocked(reason: "output-configuration-changed")
    }

    private func recoverFromStarvationIfNeededLocked() {
        guard hasStartedTimeline, pendingSampleBuffers.isEmpty else {
            return
        }
        let currentTime = currentSynchronizerTimeLocked()
        let startupThreshold = Self.startupThresholdDuration(
            outputFormat: renderFormat,
            nominalFramesPerBuffer: nominalFramesPerBufferEstimate
        )
        guard Self.shouldResetTimelineForStarvation(
            nextPresentationTime: nextPresentationTime,
            currentTime: currentTime,
            startupThreshold: startupThreshold
        ) else {
            return
        }
        let lateness = CMTimeSubtract(currentTime, nextPresentationTime)
        renderer.stopRequestingMediaData()
        renderer.flush()
        resetTimelineAfterFlushLocked(resetTime: currentTime)
        startFeedingLocked()
        Self.logger.notice(
            "Sample buffer audio starvation detected; resetting timeline at \(CMTimeGetSeconds(currentTime), privacy: .public)s lateness-ms=\(CMTimeGetSeconds(lateness) * Self.millisecondsPerSecond, privacy: .public)"
        )
        logRendererDiagnosticsLocked(reason: "starvation-reset")
    }

    private func startFeedingLocked() {
        renderer.requestMediaDataWhenReady(on: rendererQueue) { [weak self] in
            self?.drainPendingSampleBuffersLocked()
        }
    }

    private func resetTimelineAfterFlushLocked(resetTime: CMTime) {
        synchronizer.rate = 0
        nextPresentationTime = resetTime
        queuedDurationAnchorTime = resetTime
        hasStartedTimeline = false
        hasRequestedTimelineStart = false
        timelineStartupState = .idle
        timelineStartRequestTime = nil
        pressureSheddingGraceUntilTime = nil
    }

    private func drainPendingSampleBuffersLocked() {
        guard !isTerminated else {
            renderer.stopRequestingMediaData()
            return
        }
        while renderer.isReadyForMoreMediaData,
              !pendingSampleBuffers.isEmpty
        {
            let pendingSampleBuffer = pendingSampleBuffers.removeFirst()
            renderer.enqueue(pendingSampleBuffer.sampleBuffer)
            let currentTime = budgetReferenceTimeLocked()
            let budgetState = self.budgetState
            let consumedFrameCount = pendingSampleBuffer.frameCount
            Task {
                await budgetState.didHandOffToRenderer(
                    consumedFrameCount: consumedFrameCount,
                    currentTime: currentTime
                )
            }
            if !hasLoggedFirstRendererEnqueue {
                hasLoggedFirstRendererEnqueue = true
                Self.logger.notice(
                    "Sample buffer audio renderer accepted first sample status=\(String(describing: self.renderer.status), privacy: .public) rate=\(self.synchronizer.rate, privacy: .public) pending=\(self.pendingSampleBuffers.count, privacy: .public)"
                )
                logRendererDiagnosticsLocked(reason: "first-renderer-enqueue")
            }
            startTimelineIfNeededLocked()
        }
    }

    private func startTimelineIfNeededLocked() {
        guard isVideoRenderingReady else {
            return
        }
        let currentTime = budgetReferenceTimeLocked()
        let queuedDuration = CMTimeSubtract(nextPresentationTime, currentTime)
        let startupThreshold = Self.startupThresholdDuration(
            outputFormat: renderFormat,
            nominalFramesPerBuffer: nominalFramesPerBufferEstimate
        )
        let queuedDurationMeetsStartupThreshold =
            queuedDuration.isValid &&
            queuedDuration.isNumeric &&
            CMTimeCompare(queuedDuration, startupThreshold) >= 0
        let rendererReadyForStartup = renderer.hasSufficientMediaDataForReliablePlaybackStart
        let rendererBackpressured = !renderer.isReadyForMoreMediaData
        let shouldRequestTimelineStart =
            rendererReadyForStartup ||
            rendererBackpressured ||
            queuedDurationMeetsStartupThreshold
        guard shouldRequestTimelineStart else {
            return
        }
        guard timelineStartupState != .started else {
            if synchronizer.rate == 0 {
                synchronizer.setRate(1, time: currentTime)
            }
            return
        }
        if timelineStartupState == .idle {
            hasRequestedTimelineStart = true
            timelineStartupState = .requested
            timelineStartRequestTime = currentRendererClockTimeLocked() ?? currentTime
            synchronizer.setRate(1, time: currentTime)
            Self.logger.notice(
                "Sample buffer audio timeline start requested rate=\(self.synchronizer.rate, privacy: .public) time=\(CMTimeGetSeconds(currentTime), privacy: .public)s pending=\(self.pendingSampleBuffers.count, privacy: .public) renderer-preroll=\(self.renderer.hasSufficientMediaDataForReliablePlaybackStart, privacy: .public) renderer-backpressured=\(rendererBackpressured, privacy: .public) queued-threshold-met=\(queuedDurationMeetsStartupThreshold, privacy: .public) queued-preroll-ms=\(CMTimeGetSeconds(queuedDuration) * Self.millisecondsPerSecond, privacy: .public) startup-threshold-ms=\(CMTimeGetSeconds(startupThreshold) * Self.millisecondsPerSecond, privacy: .public)"
            )
            logRendererDiagnosticsLocked(reason: "timeline-start-requested")
        }
        guard let startupReason = timelineStartupReasonLocked(
            currentTime: currentTime
        ) else {
            return
        }
        markTimelineStartedLocked(
            currentTime: currentTime,
            queuedDuration: queuedDuration,
            startupThreshold: startupThreshold,
            reason: startupReason
        )
    }

    private func timelineStartupReasonLocked(
        currentTime: CMTime
    ) -> TimelineStartupReason? {
        if timelineStartupState == .requested,
           let timelineStartRequestTime,
           currentTime.isValid,
           currentTime.isNumeric
        {
            let progressed = CMTimeSubtract(currentTime, timelineStartRequestTime)
            let requiredProgress = Self.playbackClockStartThresholdDuration(
                outputFormat: renderFormat,
                nominalFramesPerBuffer: nominalFramesPerBufferEstimate
            )
            if progressed.isValid,
               progressed.isNumeric,
               CMTimeCompare(progressed, requiredProgress) >= 0
            {
                return .playbackClockProgress
            }
        }
        return nil
    }

    private func markTimelineStartedLocked(
        currentTime: CMTime,
        queuedDuration: CMTime,
        startupThreshold: CMTime,
        reason: TimelineStartupReason
    ) {
        guard timelineStartupState != .started else {
            return
        }
        queuedDurationAnchorTime = currentTime
        hasStartedTimeline = true
        hasRequestedTimelineStart = true
        timelineStartupState = .started
        timelineStartRequestTime = nil
        if queuedDuration.isValid,
           queuedDuration.isNumeric,
           CMTimeCompare(queuedDuration, .zero) > 0
        {
            pressureSheddingGraceUntilTime = CMTimeAdd(currentTime, queuedDuration)
        } else {
            pressureSheddingGraceUntilTime = nil
        }
        Self.logger.notice(
            "Sample buffer audio timeline started reason=\(reason.rawValue, privacy: .public) rate=\(self.synchronizer.rate, privacy: .public) time=\(CMTimeGetSeconds(currentTime), privacy: .public)s pending=\(self.pendingSampleBuffers.count, privacy: .public) renderer-preroll=\(self.renderer.hasSufficientMediaDataForReliablePlaybackStart, privacy: .public) renderer-status=\(String(describing: self.renderer.status), privacy: .public) queued-preroll-ms=\(CMTimeGetSeconds(queuedDuration) * Self.millisecondsPerSecond, privacy: .public) startup-threshold-ms=\(CMTimeGetSeconds(startupThreshold) * Self.millisecondsPerSecond, privacy: .public)"
        )
        logRendererDiagnosticsLocked(reason: "timeline-started")
    }

    private func logRendererDiagnosticsLocked(reason: StaticString) {
        let errorDescription = renderer.error?.localizedDescription ?? "nil"
        #if os(macOS)
        let outputDevice = renderer.audioOutputDeviceUniqueID ?? "nil"
        #else
        let outputDevice = "unavailable"
        #endif
        Self.logger.notice(
            "Sample buffer renderer diagnostics reason=\(reason, privacy: .public) status=\(String(describing: self.renderer.status), privacy: .public) muted=\(self.renderer.isMuted, privacy: .public) volume=\(self.renderer.volume, privacy: .public) device=\(outputDevice, privacy: .public) error=\(errorDescription, privacy: .public) rendering=[\(Self.currentRenderingSummary(), privacy: .public)] routes=[\(Self.currentRouteSummary(), privacy: .public)]"
        )
    }

    private func currentSynchronizerTimeLocked() -> CMTime {
        let currentTime = synchronizer.currentTime()
        if currentTime.isValid, currentTime.isNumeric {
            return currentTime
        }
        return nextPresentationTime
    }

    private func currentRendererClockTimeLocked() -> CMTime? {
        let currentTime = synchronizer.currentTime()
        guard currentTime.isValid, currentTime.isNumeric else {
            return nil
        }
        return currentTime
    }

    private func budgetReferenceTimeLocked() -> CMTime {
        if hasStartedTimeline {
            return currentSynchronizerTimeLocked()
        }
        if timelineStartupState == .requested,
           let rendererClockTime = currentRendererClockTimeLocked()
        {
            return rendererClockTime
        }
        return queuedDurationAnchorTime
    }

    private static func makeFormatDescription(
        for format: AVAudioFormat
    ) throws -> CMAudioFormatDescription {
        let streamDescription = format.streamDescription
        var asbd = streamDescription.pointee
        var formatDescription: CMAudioFormatDescription?
        let channelLayout = format.channelLayout
        let layoutSize = channelLayout.map { audioChannelLayoutSize(for: $0) } ?? 0
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: layoutSize,
            layout: channelLayout?.layout,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let formatDescription else {
            throw NSError(
                domain: "ShadowClientRealtimeSampleBufferAudioOutput",
                code: Int(status),
                userInfo: [NSLocalizedDescriptionKey: "Failed to create audio format description (\(status))."]
            )
        }
        return formatDescription
    }

    // Apple sample-buffer output can report a thin renderer queue even while the
    // decode-side ready queue briefly spikes. Use whichever side of the pipeline is
    // actually more backlogged so pressure shedding only triggers once audio output
    // itself is also running hot.
    static func pressureSheddingPendingDurationMs(
        moonlightQueuePendingDurationMs: Double,
        rendererPendingDurationMs: Double
    ) -> Double {
        max(
            max(0, moonlightQueuePendingDurationMs),
            max(0, rendererPendingDurationMs)
        )
    }

    static func shouldResetTimelineForStarvation(
        nextPresentationTime: CMTime,
        currentTime: CMTime,
        startupThreshold: CMTime
    ) -> Bool {
        guard nextPresentationTime.isValid, nextPresentationTime.isNumeric,
              currentTime.isValid, currentTime.isNumeric,
              startupThreshold.isValid, startupThreshold.isNumeric
        else {
            return false
        }
        let lateness = CMTimeSubtract(currentTime, nextPresentationTime)
        guard lateness.isValid, lateness.isNumeric,
              CMTimeCompare(lateness, .zero) > 0
        else {
            return false
        }
        let starvationThreshold = CMTimeMultiplyByRatio(
            startupThreshold,
            multiplier: 4,
            divisor: 1
        )
        return CMTimeCompare(lateness, starvationThreshold) >= 0
    }

    static func pressureSheddingDecision(
        hasStartedTimeline: Bool,
        nextPresentationTime: CMTime,
        currentTime: CMTime,
        startupThreshold: CMTime,
        pressureSheddingGraceUntilTime: CMTime?
    ) -> PressureSheddingDecision {
        guard hasStartedTimeline else {
            return PressureSheddingDecision(
                shouldDefer: true,
                shouldClearExpiredGrace: false
            )
        }
        guard currentTime.isValid, currentTime.isNumeric else {
            return PressureSheddingDecision(
                shouldDefer: true,
                shouldClearExpiredGrace: false
            )
        }

        let queuedDuration = CMTimeSubtract(nextPresentationTime, currentTime)
        if queuedDuration.isValid,
           queuedDuration.isNumeric,
           CMTimeCompare(queuedDuration, startupThreshold) < 0
        {
            return PressureSheddingDecision(
                shouldDefer: true,
                shouldClearExpiredGrace: false
            )
        }

        guard let pressureSheddingGraceUntilTime else {
            return PressureSheddingDecision(
                shouldDefer: false,
                shouldClearExpiredGrace: false
            )
        }
        if CMTimeCompare(currentTime, pressureSheddingGraceUntilTime) < 0 {
            return PressureSheddingDecision(
                shouldDefer: true,
                shouldClearExpiredGrace: false
            )
        }
        return PressureSheddingDecision(
            shouldDefer: false,
            shouldClearExpiredGrace: true
        )
    }

    private static func makeRendererFormat(
        from format: AVAudioFormat
    ) throws -> AVAudioFormat {
        if format.channelCount <= 2,
           let layout = AVAudioChannelLayout(
               layoutTag: format.channelCount == 1
                   ? kAudioChannelLayoutTag_Mono
                   : kAudioChannelLayoutTag_Stereo
           ) {
            return AVAudioFormat(
               commonFormat: .pcmFormatFloat32,
               sampleRate: format.sampleRate,
               interleaved: true,
               channelLayout: layout
            )
        }

        let channelLayoutData = format.channelLayout.map {
            Data(
                bytes: $0.layout,
                count: audioChannelLayoutSize(for: $0)
            )
        } ?? Self.channelLayoutData(for: Int(format.channelCount))

        guard let channelLayoutData else {
            Self.logger.error(
                "Sample buffer renderer format missing channel layout inputChannels=\(format.channelCount, privacy: .public) sampleRate=\(Int(format.sampleRate), privacy: .public)"
            )
            throw NSError(
                domain: "ShadowClientRealtimeSampleBufferAudioOutput",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Missing channel layout for renderer format."]
            )
        }

        let isFloat = format.commonFormat == .pcmFormatFloat32
        let bitDepth = isFloat ? 32 : 16
        guard let rendererFormat = AVAudioFormat(settings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVLinearPCMBitDepthKey: bitDepth,
            AVLinearPCMIsFloatKey: isFloat,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVChannelLayoutKey: channelLayoutData,
        ]) else {
            throw NSError(
                domain: "ShadowClientRealtimeSampleBufferAudioOutput",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create renderer LPCM format."]
            )
        }

        return rendererFormat
    }

    private func makeSampleBuffer(
        from pcmBuffer: AVAudioPCMBuffer,
        formatDescription: CMAudioFormatDescription,
        presentationTimeStamp: CMTime
    ) -> CMSampleBuffer? {
        guard let renderBuffer = makeRenderPCMBuffer(pcmBuffer) else {
            return nil
        }
        var sampleBuffer: CMSampleBuffer?
        let createStatus = CMAudioSampleBufferCreateWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: false,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(renderBuffer.frameLength),
            presentationTimeStamp: presentationTimeStamp,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard createStatus == noErr, let sampleBuffer else {
            return nil
        }
        let dataStatus = CMSampleBufferSetDataBufferFromAudioBufferList(
            sampleBuffer,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
            bufferList: renderBuffer.audioBufferList
        )
        guard dataStatus == noErr else {
            return nil
        }
        let readyStatus = CMSampleBufferSetDataReady(sampleBuffer)
        guard readyStatus == noErr else {
            return nil
        }
        return sampleBuffer
    }

    private func makeRenderPCMBuffer(_ pcmBuffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        if pcmBuffer.format == renderFormat {
            return pcmBuffer
        }

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: renderFormat,
            frameCapacity: pcmBuffer.frameLength
        ) else {
            return nil
        }
        convertedBuffer.frameLength = pcmBuffer.frameLength

        let frameCount = Int(pcmBuffer.frameLength)
        let channelCount = Int(min(pcmBuffer.format.channelCount, renderFormat.channelCount))
        guard frameCount > 0, channelCount > 0 else {
            return nil
        }

        if let formatConverter {
            logConverterBufferStatsIfNeeded(
                pcmBuffer,
                label: "input",
                hasLogged: &hasLoggedFirstConverterInputStats
            )
            logConverterFormatDiagnosticsIfNeeded()
            var didProvideInput = false
            var conversionError: NSError?
            let status = formatConverter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
                guard !didProvideInput else {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                didProvideInput = true
                outStatus.pointee = .haveData
                return pcmBuffer
            }
            guard conversionError == nil,
                  status == .haveData || status == .inputRanDry,
                  convertedBuffer.frameLength > 0
            else {
                Self.logger.error(
                    "Sample buffer audio converter failed status=\(String(describing: status), privacy: .public) error=\(conversionError?.localizedDescription ?? "nil", privacy: .public)"
                )
                return nil
            }
            logConverterBufferStatsIfNeeded(
                convertedBuffer,
                label: "output",
                hasLogged: &hasLoggedFirstConverterOutputStats
            )
            logFirstRenderBufferStatsIfNeeded(convertedBuffer)
            return convertedBuffer
        }

        let outputList = UnsafeMutableAudioBufferListPointer(convertedBuffer.mutableAudioBufferList)
        switch (renderFormat.commonFormat, pcmBuffer.format.commonFormat) {
        case (.pcmFormatFloat32, .pcmFormatFloat32):
            guard let outputBaseAddress = outputList.first?.mData?.assumingMemoryBound(to: Float.self) else {
                return nil
            }
            if pcmBuffer.format.isInterleaved {
                guard let inputBaseAddress = pcmBuffer.audioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Float.self) else {
                    return nil
                }
                memcpy(outputBaseAddress, inputBaseAddress, frameCount * channelCount * MemoryLayout<Float>.size)
            } else {
                guard let inputChannels = pcmBuffer.floatChannelData else {
                    return nil
                }
                for frame in 0 ..< frameCount {
                    for channel in 0 ..< channelCount {
                        outputBaseAddress[(frame * channelCount) + channel] = inputChannels[channel][frame]
                    }
                }
            }
        case (.pcmFormatInt16, .pcmFormatFloat32):
            guard let outputBaseAddress = outputList.first?.mData?.assumingMemoryBound(to: Int16.self),
                  let inputChannels = pcmBuffer.floatChannelData else {
                return nil
            }
            for frame in 0 ..< frameCount {
                for channel in 0 ..< channelCount {
                    let sample = inputChannels[channel][frame]
                    let clamped = max(-1.0, min(1.0, sample))
                    outputBaseAddress[(frame * channelCount) + channel] = Int16(clamped * Float(Int16.max))
                }
            }
        case (.pcmFormatInt16, .pcmFormatInt16):
            guard let outputBaseAddress = outputList.first?.mData?.assumingMemoryBound(to: Int16.self) else {
                return nil
            }
            if pcmBuffer.format.isInterleaved {
                guard let inputBaseAddress = pcmBuffer.audioBufferList.pointee.mBuffers.mData?.assumingMemoryBound(to: Int16.self) else {
                    return nil
                }
                memcpy(outputBaseAddress, inputBaseAddress, frameCount * channelCount * MemoryLayout<Int16>.size)
            } else {
                guard let inputChannels = pcmBuffer.int16ChannelData else {
                    return nil
                }
                for frame in 0 ..< frameCount {
                    for channel in 0 ..< channelCount {
                        outputBaseAddress[(frame * channelCount) + channel] = inputChannels[channel][frame]
                    }
                }
            }
        default:
            return nil
        }

        logFirstRenderBufferStatsIfNeeded(convertedBuffer)
        return convertedBuffer
    }

    private func logFirstRenderBufferStatsIfNeeded(_ pcmBuffer: AVAudioPCMBuffer) {
        guard !hasLoggedFirstRenderBufferStats else {
            return
        }
        hasLoggedFirstRenderBufferStats = true

        let channelCount = Int(pcmBuffer.format.channelCount)
        let frameCount = Int(min(pcmBuffer.frameLength, 8))
        switch pcmBuffer.format.commonFormat {
        case .pcmFormatFloat32:
            let audioBufferList = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
            guard let baseAddress = audioBufferList.first?.mData?.assumingMemoryBound(to: Float.self) else {
                return
            }
            let samples = (0 ..< frameCount * max(1, channelCount)).map { index in
                String(format: "%.6f", baseAddress[index])
            }.joined(separator: ",")
            Self.logger.notice(
                "Sample buffer render stats format=float32 interleaved=\(pcmBuffer.format.isInterleaved, privacy: .public) frames=\(pcmBuffer.frameLength, privacy: .public) channels=\(pcmBuffer.format.channelCount, privacy: .public) samples=[\(samples, privacy: .public)]"
            )
        case .pcmFormatInt16:
            let audioBufferList = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
            guard let baseAddress = audioBufferList.first?.mData?.assumingMemoryBound(to: Int16.self) else {
                return
            }
            let samples = (0 ..< frameCount * max(1, channelCount)).map { index in
                String(baseAddress[index])
            }.joined(separator: ",")
            Self.logger.notice(
                "Sample buffer render stats format=int16 interleaved=\(pcmBuffer.format.isInterleaved, privacy: .public) frames=\(pcmBuffer.frameLength, privacy: .public) channels=\(pcmBuffer.format.channelCount, privacy: .public) samples=[\(samples, privacy: .public)]"
            )
        default:
            Self.logger.notice(
                "Sample buffer render stats format=\(String(describing: pcmBuffer.format.commonFormat), privacy: .public) interleaved=\(pcmBuffer.format.isInterleaved, privacy: .public) frames=\(pcmBuffer.frameLength, privacy: .public) channels=\(pcmBuffer.format.channelCount, privacy: .public)"
            )
        }
    }

    private func logConverterFormatDiagnosticsIfNeeded() {
        guard !hasLoggedFirstConverterInputStats else {
            return
        }
        Self.logger.notice(
            "Sample buffer audio converter formats input=[\(Self.audioFormatSummary(self.inputFormat), privacy: .public)] output=[\(Self.audioFormatSummary(self.renderFormat), privacy: .public)]"
        )
    }

    private func logConverterBufferStatsIfNeeded(
        _ pcmBuffer: AVAudioPCMBuffer,
        label: StaticString,
        hasLogged: inout Bool
    ) {
        guard !hasLogged else {
            return
        }
        hasLogged = true
        switch pcmBuffer.format.commonFormat {
        case .pcmFormatFloat32:
            let samples = Self.captureFloatSamples(pcmBuffer)
            Self.logger.notice(
                "Sample buffer audio converter \(label, privacy: .public) format=float32 interleaved=\(pcmBuffer.format.isInterleaved, privacy: .public) frames=\(pcmBuffer.frameLength, privacy: .public) channels=\(pcmBuffer.format.channelCount, privacy: .public) samples=[\(samples, privacy: .public)]"
            )
        case .pcmFormatInt16:
            let samples = Self.captureInt16Samples(pcmBuffer)
            Self.logger.notice(
                "Sample buffer audio converter \(label, privacy: .public) format=int16 interleaved=\(pcmBuffer.format.isInterleaved, privacy: .public) frames=\(pcmBuffer.frameLength, privacy: .public) channels=\(pcmBuffer.format.channelCount, privacy: .public) samples=[\(samples, privacy: .public)]"
            )
        default:
            Self.logger.notice(
                "Sample buffer audio converter \(label, privacy: .public) format=\(String(describing: pcmBuffer.format.commonFormat), privacy: .public) interleaved=\(pcmBuffer.format.isInterleaved, privacy: .public) frames=\(pcmBuffer.frameLength, privacy: .public) channels=\(pcmBuffer.format.channelCount, privacy: .public)"
            )
        }
    }

    private static func audioFormatSummary(_ format: AVAudioFormat) -> String {
        let streamDescription = format.streamDescription.pointee
        return "common=\(String(describing: format.commonFormat)) channels=\(format.channelCount) rate=\(format.sampleRate) interleaved=\(format.isInterleaved) bytesPerFrame=\(streamDescription.mBytesPerFrame) bytesPerPacket=\(streamDescription.mBytesPerPacket) framesPerPacket=\(streamDescription.mFramesPerPacket) bitsPerChannel=\(streamDescription.mBitsPerChannel) formatFlags=\(streamDescription.mFormatFlags)"
    }

    private static func captureFloatSamples(_ pcmBuffer: AVAudioPCMBuffer) -> String {
        let frameCount = Int(min(pcmBuffer.frameLength, 8))
        let channelCount = Int(max(1, pcmBuffer.format.channelCount))
        if pcmBuffer.format.isInterleaved {
            let audioBufferList = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
            guard let baseAddress = audioBufferList.first?.mData?.assumingMemoryBound(to: Float.self) else {
                return "unavailable"
            }
            return (0 ..< frameCount * channelCount).map { index in
                String(format: "%.6f", baseAddress[index])
            }.joined(separator: ",")
        }
        guard let channelData = pcmBuffer.floatChannelData else {
            return "unavailable"
        }
        var values: [String] = []
        for frame in 0 ..< frameCount {
            for channel in 0 ..< channelCount {
                values.append(String(format: "%.6f", channelData[channel][frame]))
            }
        }
        return values.joined(separator: ",")
    }

    private static func captureInt16Samples(_ pcmBuffer: AVAudioPCMBuffer) -> String {
        let frameCount = Int(min(pcmBuffer.frameLength, 8))
        let channelCount = Int(max(1, pcmBuffer.format.channelCount))
        if pcmBuffer.format.isInterleaved {
            let audioBufferList = UnsafeMutableAudioBufferListPointer(pcmBuffer.mutableAudioBufferList)
            guard let baseAddress = audioBufferList.first?.mData?.assumingMemoryBound(to: Int16.self) else {
                return "unavailable"
            }
            return (0 ..< frameCount * channelCount).map { index in
                String(baseAddress[index])
            }.joined(separator: ",")
        }
        guard let channelData = pcmBuffer.int16ChannelData else {
            return "unavailable"
        }
        var values: [String] = []
        for frame in 0 ..< frameCount {
            for channel in 0 ..< channelCount {
                values.append(String(channelData[channel][frame]))
            }
        }
        return values.joined(separator: ",")
    }

    private static func audioChannelLayoutSize(for channelLayout: AVAudioChannelLayout) -> Int {
        let descriptionCount = max(0, Int(channelLayout.layout.pointee.mNumberChannelDescriptions) - 1)
        return MemoryLayout<AudioChannelLayout>.size +
            (descriptionCount * MemoryLayout<AudioChannelDescription>.size)
    }

    private static func channelLayoutData(for channels: Int) -> Data? {
        let layoutTag: AudioChannelLayoutTag = switch channels {
        case 1:
            kAudioChannelLayoutTag_Mono
        case 2:
            kAudioChannelLayoutTag_Stereo
        case 6:
            kAudioChannelLayoutTag_MPEG_5_1_D
        case 8:
            kAudioChannelLayoutTag_MPEG_7_1_C
        default:
            kAudioChannelLayoutTag_DiscreteInOrder | AudioChannelLayoutTag(channels)
        }

        guard let channelLayout = AVAudioChannelLayout(layoutTag: layoutTag) else {
            return nil
        }

        return Data(
            bytes: channelLayout.layout,
            count: MemoryLayout<AudioChannelLayout>.size
        )
    }

    private static func currentRouteSummary() -> String {
        ShadowClientAudioOutputCapabilityKit.currentRouteSummary()
    }

    private static func currentRenderingSummary() -> String {
        ShadowClientAudioOutputCapabilityKit.currentRenderingSummary()
    }

    private static func startupThresholdDuration(
        outputFormat: AVAudioFormat,
        nominalFramesPerBuffer: Double
    ) -> CMTime {
        let packetDurationSeconds = nominalFramesPerBuffer / max(1, outputFormat.sampleRate)
        let timingBudget = ShadowClientAudioOutputCapabilityKit.currentTimingBudget()
        let thresholdSeconds = timingBudget.startupPrerollDurationSeconds(
            packetDurationSeconds: packetDurationSeconds
        )
        let timescale = CMTimeScale(max(1, Int32(Self.millisecondsPerSecond.rounded())))
        return CMTime(
            seconds: thresholdSeconds,
            preferredTimescale: timescale
        )
    }

    private static func playbackClockStartThresholdDuration(
        outputFormat: AVAudioFormat,
        nominalFramesPerBuffer: Double
    ) -> CMTime {
        let packetDurationSeconds = nominalFramesPerBuffer / max(1, outputFormat.sampleRate)
        let timingBudget = ShadowClientAudioOutputCapabilityKit.currentTimingBudget()
        let thresholdSeconds = max(packetDurationSeconds, timingBudget.ioBufferDurationSeconds)
        let timescale = CMTimeScale(max(1, Int32(Self.millisecondsPerSecond.rounded())))
        return CMTime(
            seconds: thresholdSeconds,
            preferredTimescale: timescale
        )
    }

}
#endif
