import Foundation
import os
import ShadowClientFeatureSession

actor ShadowClientRealtimeInputChannelGateway {
    private let logger = Logger(subsystem: "com.skyline23.shadow-client", category: "InputChannel")
    private let inputChannelUnavailableLogMinimumIntervalSeconds: TimeInterval = 2.0

    private var controlChannelRuntime: ShadowClientHostControlChannelRuntime?
    private var loggedInputSendKinds = Set<String>()
    private var loggedInputDropKinds = Set<String>()
    private var transientInputSendFailureCount = 0
    private var firstTransientInputSendFailureUptime: TimeInterval = 0
    private var lastInputChannelUnavailableLogUptime: TimeInterval = 0

    func install(_ runtime: ShadowClientHostControlChannelRuntime?) {
        controlChannelRuntime = runtime
        if runtime == nil {
            resetFailureState()
        }
    }

    func clear() {
        controlChannelRuntime = nil
        loggedInputSendKinds.removeAll(keepingCapacity: false)
        loggedInputDropKinds.removeAll(keepingCapacity: false)
        resetFailureState()
    }

    func sendInput(
        _ event: ShadowClientRemoteInputEvent,
        ensureRuntime: @escaping @Sendable () async -> ShadowClientHostControlChannelRuntime?,
        invalidateRuntime: @escaping @Sendable (ShadowClientHostControlChannelRuntime) async -> Void
    ) async throws {
        guard let packet = ShadowClientHostInputPacketCodec.encode(event) else {
            let kind = inputEventKind(event)
            if loggedInputDropKinds.insert(kind).inserted {
                logger.notice("Lumen input dropped during encode for event \(kind, privacy: .public)")
            }
            return
        }

        let kind = inputEventKind(event)
        if loggedInputSendKinds.insert(kind).inserted {
            logger.notice(
                "Lumen input send enabled for event \(kind, privacy: .public) channel=\(packet.channelID, privacy: .public) bytes=\(packet.payload.count, privacy: .public)"
            )
        }

        guard let runtime = await resolvedRuntime(ensureRuntime: ensureRuntime) else {
            let now = ProcessInfo.processInfo.systemUptime
            if now - lastInputChannelUnavailableLogUptime >= inputChannelUnavailableLogMinimumIntervalSeconds {
                logger.notice("Lumen input send skipped: control channel unavailable")
                lastInputChannelUnavailableLogUptime = now
            }
            return
        }

        do {
            try await runtime.sendInputPacket(
                packet.payload,
                channelID: packet.channelID
            )
            resetFailureState()
        } catch {
            if ShadowClientRealtimeRTSPSessionRuntime.isTransientInputSendError(error) {
                let now = ProcessInfo.processInfo.systemUptime
                if firstTransientInputSendFailureUptime == 0 ||
                    now - firstTransientInputSendFailureUptime >
                    ShadowClientRealtimeSessionDefaults.transientInputSendFailureBurstWindowSeconds
                {
                    firstTransientInputSendFailureUptime = now
                    transientInputSendFailureCount = 0
                }
                transientInputSendFailureCount += 1
                if ShadowClientRealtimeRTSPSessionRuntime.shouldResetControlChannelAfterTransientInputSendFailures(
                    failureCount: transientInputSendFailureCount,
                    now: now,
                    firstFailureUptime: firstTransientInputSendFailureUptime
                ) {
                    logger.notice(
                        "Lumen input channel reset after transient send failure burst (count=\(self.transientInputSendFailureCount, privacy: .public), window=\(ShadowClientRealtimeSessionDefaults.transientInputSendFailureBurstWindowSeconds, privacy: .public)s)"
                    )
                    await invalidateRuntime(runtime)
                    controlChannelRuntime = nil
                    resetFailureState()
                }
                return
            }
            if ShadowClientRealtimeRTSPSessionRuntime.shouldResetInputControlChannelAfterSendError(error) {
                logger.notice(
                    "Lumen input channel reset after send failure: \(error.localizedDescription, privacy: .public)"
                )
                await invalidateRuntime(runtime)
                controlChannelRuntime = nil
                resetFailureState()
                return
            }
            throw error
        }
    }

    func sendKeepAlive(
        ensureRuntime: @escaping @Sendable () async -> ShadowClientHostControlChannelRuntime?,
        invalidateRuntime: @escaping @Sendable (ShadowClientHostControlChannelRuntime) async -> Void
    ) async throws {
        guard let runtime = await resolvedRuntime(ensureRuntime: ensureRuntime) else {
            throw ShadowClientRealtimeSessionRuntimeError.connectionClosed
        }

        do {
            try await runtime.sendInputKeepAlive()
            resetFailureState()
        } catch {
            if ShadowClientRealtimeRTSPSessionRuntime.isTransientInputSendError(error) {
                return
            }
            if ShadowClientRealtimeRTSPSessionRuntime.shouldResetInputControlChannelAfterSendError(error) {
                await invalidateRuntime(runtime)
                controlChannelRuntime = nil
                resetFailureState()
                throw ShadowClientRealtimeSessionRuntimeError.connectionClosed
            }
            throw error
        }
    }

    private func resolvedRuntime(
        ensureRuntime: @escaping @Sendable () async -> ShadowClientHostControlChannelRuntime?
    ) async -> ShadowClientHostControlChannelRuntime? {
        if let controlChannelRuntime {
            return controlChannelRuntime
        }
        let runtime = await ensureRuntime()
        controlChannelRuntime = runtime
        return runtime
    }

    private func resetFailureState() {
        transientInputSendFailureCount = 0
        firstTransientInputSendFailureUptime = 0
        lastInputChannelUnavailableLogUptime = 0
    }

    private func inputEventKind(_ event: ShadowClientRemoteInputEvent) -> String {
        switch event {
        case .keyDown:
            return "keyDown"
        case .keyUp:
            return "keyUp"
        case .text:
            return "text"
        case .pointerMoved:
            return "pointerMoved"
        case .pointerPosition:
            return "pointerPosition"
        case .pointerButton:
            return "pointerButton"
        case .scroll:
            return "scroll"
        case .gamepadState:
            return "gamepadState"
        case .gamepadArrival:
            return "gamepadArrival"
        }
    }
}
