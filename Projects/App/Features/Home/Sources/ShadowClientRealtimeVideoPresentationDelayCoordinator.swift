import CoreVideo
import Foundation

actor ShadowClientRealtimeVideoPresentationDelayCoordinator {
    private struct PendingFrame: Sendable {
        let pixelBuffer: ShadowClientSendableFramePixelBuffer
        let dueUptime: TimeInterval
    }

    private let onReadyToPresent: @Sendable (CVPixelBuffer) async -> Void
    private var pendingFrames: [PendingFrame] = []
    private var runnerTask: Task<Void, Never>?
    private var runnerGeneration: UInt64 = 0

    init(
        onReadyToPresent: @escaping @Sendable (CVPixelBuffer) async -> Void
    ) {
        self.onReadyToPresent = onReadyToPresent
    }

    func enqueue(
        pixelBuffer: CVPixelBuffer,
        delaySeconds: TimeInterval
    ) {
        let dueUptime = ProcessInfo.processInfo.systemUptime + max(0, delaySeconds)
        let previousEarliestDueUptime = pendingFrames.first?.dueUptime
        pendingFrames.append(
            PendingFrame(
                pixelBuffer: ShadowClientSendableFramePixelBuffer(value: pixelBuffer),
                dueUptime: dueUptime
            )
        )
        pendingFrames.sort { $0.dueUptime < $1.dueUptime }

        let currentEarliestDueUptime = pendingFrames.first?.dueUptime
        let shouldRestartRunner =
            runnerTask == nil ||
            currentEarliestDueUptime != previousEarliestDueUptime
        if shouldRestartRunner {
            runnerTask?.cancel()
            runnerGeneration &+= 1
            let generation = runnerGeneration
            runnerTask = Task { [weak self] in
                guard let self else {
                    return
                }
                await self.run(generation: generation)
            }
        }
    }

    func reset() {
        pendingFrames.removeAll(keepingCapacity: false)
        runnerTask?.cancel()
        runnerTask = nil
        runnerGeneration &+= 1
    }

    private func run(generation: UInt64) async {
        while !Task.isCancelled {
            guard let pendingFrame = pendingFrames.first else {
                if runnerGeneration == generation {
                    runnerTask = nil
                }
                return
            }

            let remainingDelaySeconds = pendingFrame.dueUptime - ProcessInfo.processInfo.systemUptime
            if remainingDelaySeconds > 0 {
                let sleepNanoseconds = UInt64(
                    max(0, (remainingDelaySeconds * 1_000_000_000).rounded(.up))
                )
                do {
                    try await Task.sleep(nanoseconds: sleepNanoseconds)
                } catch {
                    if runnerGeneration == generation {
                        runnerTask = nil
                    }
                    return
                }
                continue
            }

            pendingFrames.removeFirst()
            await onReadyToPresent(pendingFrame.pixelBuffer.value)
        }

        if runnerGeneration == generation {
            runnerTask = nil
        }
    }
}
