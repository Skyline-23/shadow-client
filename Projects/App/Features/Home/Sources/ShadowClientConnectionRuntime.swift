import Foundation
import ShadowClientStreaming

public enum ShadowClientConnectionState: Equatable, Sendable {
    case disconnected
    case connecting(host: String)
    case connected(host: String)
    case disconnecting(host: String)
    case failed(host: String, message: String)

    public var host: String? {
        switch self {
        case .disconnected:
            return nil
        case let .connecting(host),
            let .connected(host),
            let .disconnecting(host),
            let .failed(host, _):
            return host
        }
    }

    public var isConnected: Bool {
        if case .connected = self {
            return true
        }

        return false
    }
}

public enum ShadowClientConnectionFailure: Error, Equatable, Sendable {
    case invalidHost
    case connectRejected(String)
}

public protocol ShadowClientConnectionClient: Sendable {
    func connect(to host: String) async throws
    func disconnect() async
}

public actor ShadowClientConnectionRuntime {
    private let client: any ShadowClientConnectionClient
    private var state: ShadowClientConnectionState = .disconnected

    public init(client: any ShadowClientConnectionClient) {
        self.client = client
    }

    public func currentState() -> ShadowClientConnectionState {
        state
    }

    public func connect(to host: String) async -> ShadowClientConnectionState {
        let normalizedHost = Self.normalize(host)
        guard !normalizedHost.isEmpty else {
            state = .failed(host: "", message: "Host is required.")
            return state
        }

        state = .connecting(host: normalizedHost)

        do {
            try await client.connect(to: normalizedHost)
            state = .connected(host: normalizedHost)
        } catch let error as ShadowClientConnectionFailure {
            state = .failed(host: normalizedHost, message: Self.errorMessage(for: error))
        } catch {
            let fallback = error.localizedDescription.isEmpty
                ? "Unknown connection error."
                : error.localizedDescription
            state = .failed(host: normalizedHost, message: fallback)
        }

        return state
    }

    public func disconnect() async -> ShadowClientConnectionState {
        state = .disconnecting(host: state.host ?? "")
        await client.disconnect()
        state = .disconnected
        return state
    }

    private static func normalize(_ host: String) -> String {
        host.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func errorMessage(for error: ShadowClientConnectionFailure) -> String {
        switch error {
        case .invalidHost:
            return "Host is required."
        case let .connectRejected(message):
            return message
        }
    }
}

public actor SimulatedShadowClientConnectionClient: ShadowClientConnectionClient {
    private let bridge: MoonlightSessionTelemetryBridge
    private var telemetryTask: Task<Void, Never>?

    public init(bridge: MoonlightSessionTelemetryBridge) {
        self.bridge = bridge
    }

    public func connect(to host: String) async throws {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            throw ShadowClientConnectionFailure.invalidHost
        }

        telemetryTask?.cancel()

        telemetryTask = Task { [bridge] in
            var sampleIndex = 0

            while !Task.isCancelled {
                let timestampMs = Int(Date().timeIntervalSince1970 * 1_000)
                let renderedFrames = 1_000 + (sampleIndex * 4)
                let unstableWindow = sampleIndex % 20
                let isUnstable = unstableWindow < 3
                let droppedFrames = isUnstable ? 20 : 3
                let networkDroppedFrames = isUnstable ? 14 : 2
                let pacerDroppedFrames = droppedFrames - networkDroppedFrames
                let jitterMs = isUnstable ? 72.0 : 8.0 + Double(sampleIndex % 5)
                let packetLossPercent = isUnstable ? 2.4 : 0.3
                let avSyncOffsetMs = isUnstable ? 55.0 : 11.0

                let snapshot = StreamingTelemetrySnapshot(
                    stats: .init(
                        renderedFrames: renderedFrames,
                        droppedFrames: droppedFrames,
                        avSyncOffsetMilliseconds: avSyncOffsetMs
                    ),
                    signal: .init(
                        jitterMs: jitterMs,
                        packetLossPercent: packetLossPercent
                    ),
                    timestampMs: timestampMs,
                    dropBreakdown: .init(
                        networkDroppedFrames: networkDroppedFrames,
                        pacerDroppedFrames: pacerDroppedFrames
                    )
                )

                await bridge.ingest(snapshot: snapshot)
                sampleIndex += 1

                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    public func disconnect() async {
        telemetryTask?.cancel()
        telemetryTask = nil
    }
}
