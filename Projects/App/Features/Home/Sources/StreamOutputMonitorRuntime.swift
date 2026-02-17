import Foundation
import ShadowClientStreaming

enum StreamOutputMonitorState: Equatable, Sendable {
    case disconnected
    case connecting
    case awaitingTelemetry
    case live
    case stale
    case failed
}

struct StreamOutputMonitorModel: Equatable, Sendable {
    let state: StreamOutputMonitorState
    let stateLabel: String
    let detail: String
    let sampleAgeMs: Int?
    let renderedFrames: Int?
    let droppedFrames: Int?
    let frameDropPercent: Double?
    let jitterMs: Int?
    let packetLossPercent: Double?
    let estimatedFPS: Int?

    static var disconnected: Self {
        .init(
            state: .disconnected,
            stateLabel: "Disconnected",
            detail: "Connect to a host, then launch a stream to verify telemetry/video flow.",
            sampleAgeMs: nil,
            renderedFrames: nil,
            droppedFrames: nil,
            frameDropPercent: nil,
            jitterMs: nil,
            packetLossPercent: nil,
            estimatedFPS: nil
        )
    }
}

actor StreamOutputMonitorRuntime {
    private let staleAfterMs: Int
    private var latestSnapshot: StreamingTelemetrySnapshot?
    private var latestSampleReceivedAtMs: Int?
    private var lastSourceTimestampMs: Int?
    private var estimatedFPS: Int?
    private var connectionState: ShadowClientConnectionState

    init(staleAfterMs: Int = 2_500) {
        self.staleAfterMs = max(500, staleAfterMs)
        latestSnapshot = nil
        latestSampleReceivedAtMs = nil
        lastSourceTimestampMs = nil
        estimatedFPS = nil
        connectionState = .disconnected
    }

    func updateConnectionState(_ state: ShadowClientConnectionState) -> StreamOutputMonitorModel {
        updateConnectionState(state, at: Self.nowMilliseconds())
    }

    func updateConnectionState(
        _ state: ShadowClientConnectionState,
        at nowMs: Int
    ) -> StreamOutputMonitorModel {
        connectionState = state
        return makeModel(nowMs: nowMs)
    }

    func ingest(snapshot: StreamingTelemetrySnapshot) -> StreamOutputMonitorModel {
        ingest(snapshot: snapshot, at: Self.nowMilliseconds())
    }

    func ingest(
        snapshot: StreamingTelemetrySnapshot,
        at nowMs: Int
    ) -> StreamOutputMonitorModel {
        if let previousTimestampMs = lastSourceTimestampMs {
            let sampleIntervalMs = snapshot.timestampMs - previousTimestampMs
            if sampleIntervalMs > 0 {
                estimatedFPS = max(1, Int((1_000.0 / Double(sampleIntervalMs)).rounded()))
            }
        }

        latestSnapshot = snapshot
        latestSampleReceivedAtMs = nowMs
        lastSourceTimestampMs = snapshot.timestampMs
        return makeModel(nowMs: nowMs)
    }

    func heartbeat() -> StreamOutputMonitorModel {
        heartbeat(at: Self.nowMilliseconds())
    }

    func heartbeat(at nowMs: Int) -> StreamOutputMonitorModel {
        makeModel(nowMs: nowMs)
    }

    private func makeModel(nowMs: Int) -> StreamOutputMonitorModel {
        switch connectionState {
        case .disconnected:
            return .disconnected
        case .connecting, .disconnecting:
            return .init(
                state: .connecting,
                stateLabel: "Connecting",
                detail: "Negotiating host connection and waiting for stream startup.",
                sampleAgeMs: nil,
                renderedFrames: nil,
                droppedFrames: nil,
                frameDropPercent: nil,
                jitterMs: nil,
                packetLossPercent: nil,
                estimatedFPS: nil
            )
        case let .failed(_, message):
            return .init(
                state: .failed,
                stateLabel: "Failed",
                detail: message,
                sampleAgeMs: nil,
                renderedFrames: nil,
                droppedFrames: nil,
                frameDropPercent: nil,
                jitterMs: nil,
                packetLossPercent: nil,
                estimatedFPS: nil
            )
        case .connected:
            guard let snapshot = latestSnapshot, let sampleAtMs = latestSampleReceivedAtMs else {
                return .init(
                    state: .awaitingTelemetry,
                    stateLabel: "Awaiting Telemetry",
                    detail: "Host connected. Start a stream session to receive live telemetry.",
                    sampleAgeMs: nil,
                    renderedFrames: nil,
                    droppedFrames: nil,
                    frameDropPercent: nil,
                    jitterMs: nil,
                    packetLossPercent: nil,
                    estimatedFPS: nil
                )
            }

            let ageMs = max(0, nowMs - sampleAtMs)
            let totalFrames = max(snapshot.stats.totalFrames, 1)
            let frameDropPercent = (Double(max(snapshot.stats.droppedFrames, 0)) / Double(totalFrames)) * 100.0

            let baseModel = StreamOutputMonitorModel(
                state: ageMs > staleAfterMs ? .stale : .live,
                stateLabel: ageMs > staleAfterMs ? "Stale" : "Live",
                detail: ageMs > staleAfterMs
                    ? "Telemetry paused for \(ageMs) ms. Stream output may be frozen."
                    : "Telemetry updates are flowing from the current stream.",
                sampleAgeMs: ageMs,
                renderedFrames: snapshot.stats.renderedFrames,
                droppedFrames: snapshot.stats.droppedFrames,
                frameDropPercent: frameDropPercent,
                jitterMs: Int(snapshot.signal.jitterMs.rounded()),
                packetLossPercent: snapshot.signal.packetLossPercent,
                estimatedFPS: estimatedFPS
            )

            return baseModel
        }
    }

    private static func nowMilliseconds() -> Int {
        Int(Date().timeIntervalSince1970 * 1_000)
    }
}
