import Foundation
import Network
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

public struct ShadowClientHostProbeResult: Equatable, Sendable {
    public let reachablePorts: [Int]

    public init(reachablePorts: [Int]) {
        self.reachablePorts = Array(Set(reachablePorts)).sorted()
    }

    public var hasReachableService: Bool {
        !reachablePorts.isEmpty
    }
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

public actor NativeHostProbeConnectionClient: ShadowClientConnectionClient {
    public typealias HostProbe = @Sendable (String) async throws -> ShadowClientHostProbeResult

    private let hostProbe: HostProbe
    private let requiredPorts: [Int]
    private var connectedHost: String?

    public init(
        requiredPorts: [Int] = NativeTCPHostProbe.defaultServicePorts,
        hostProbe: HostProbe? = nil
    ) {
        let normalizedPorts = Array(Set(requiredPorts)).sorted()
        self.requiredPorts = normalizedPorts
        if let hostProbe {
            self.hostProbe = hostProbe
        } else {
            self.hostProbe = { host in
                try await NativeTCPHostProbe.probe(host: host, ports: normalizedPorts)
            }
        }
        connectedHost = nil
    }

    public func connect(to host: String) async throws {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            throw ShadowClientConnectionFailure.invalidHost
        }

        let probeResult = try await hostProbe(normalizedHost)
        guard probeResult.hasReachableService else {
            throw ShadowClientConnectionFailure.connectRejected(
                unavailableServiceMessage(for: normalizedHost)
            )
        }

        connectedHost = normalizedHost
    }

    public func disconnect() async {
        connectedHost = nil
    }

    private func unavailableServiceMessage(for host: String) -> String {
        let ports = requiredPorts.map(String.init).joined(separator: ", ")
        return "No stream services reachable on \(host). Checked TCP ports: \(ports)."
    }
}

public enum NativeTCPHostProbe {
    public static let defaultServicePorts: [Int] = ShadowClientGameStreamNetworkDefaults.defaultServicePorts

    public static func probe(
        host: String,
        ports: [Int] = defaultServicePorts,
        timeout: Duration = ShadowClientHostProbeDefaults.tcpPortTimeout
    ) async throws -> ShadowClientHostProbeResult {
        let normalizedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedHost.isEmpty else {
            throw ShadowClientConnectionFailure.invalidHost
        }

        let normalizedPorts = Array(Set(ports.compactMap { port -> Int? in
            guard (ShadowClientGameStreamNetworkDefaults.minimumPort...ShadowClientGameStreamNetworkDefaults.maximumPort).contains(port) else {
                return nil
            }
            return port
        })).sorted()

        let reachablePorts = await withTaskGroup(of: Int?.self, returning: [Int].self) { group in
            for port in normalizedPorts {
                group.addTask {
                    let isReachable = await probeTCPPort(
                        host: normalizedHost,
                        port: port,
                        timeout: timeout
                    )
                    return isReachable ? port : nil
                }
            }

            var matches: [Int] = []
            for await result in group {
                if let port = result {
                    matches.append(port)
                }
            }
            return matches.sorted()
        }

        return ShadowClientHostProbeResult(reachablePorts: reachablePorts)
    }

    private static func probeTCPPort(
        host: String,
        port: Int,
        timeout: Duration
    ) async -> Bool {
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            return false
        }

        let connection = NWConnection(
            host: NWEndpoint.Host(host),
            port: endpointPort,
            using: .tcp
        )
        let queue = DispatchQueue(
            label: "com.skyline23.shadowclient.connection-probe.\(port)"
        )

        return await withTaskGroup(of: Bool.self, returning: Bool.self) { group in
            group.addTask {
                await awaitConnectionReady(connection, queue: queue)
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    connection.cancel()
                    return false
                } catch {
                    return false
                }
            }

            let firstResult = await group.next() ?? false
            group.cancelAll()
            return firstResult
        }
    }

    private static func awaitConnectionReady(
        _ connection: NWConnection,
        queue: DispatchQueue
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            actor ResumeGate {
                private var continuation: CheckedContinuation<Bool, Never>?

                init(continuation: CheckedContinuation<Bool, Never>) {
                    self.continuation = continuation
                }

                func finish(with result: Bool) -> Bool {
                    guard let continuation else {
                        return false
                    }
                    self.continuation = nil
                    continuation.resume(returning: result)
                    return true
                }
            }

            let gate = ResumeGate(continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task {
                        if await gate.finish(with: true) {
                            connection.stateUpdateHandler = nil
                            connection.cancel()
                        }
                    }
                case .failed, .cancelled:
                    Task {
                        if await gate.finish(with: false) {
                            connection.stateUpdateHandler = nil
                        }
                    }
                default:
                    break
                }
            }

            connection.start(queue: queue)
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
                let renderedFrames =
                    ShadowClientTelemetrySimulationDefaults.baseRenderedFrames +
                    (sampleIndex * ShadowClientTelemetrySimulationDefaults.renderedFrameIncrement)
                let unstableWindow = sampleIndex % ShadowClientTelemetrySimulationDefaults.instabilityCycleLength
                let isUnstable = unstableWindow < ShadowClientTelemetrySimulationDefaults.unstableSampleCount
                let droppedFrames = isUnstable
                    ? ShadowClientTelemetrySimulationDefaults.unstableDroppedFrames
                    : ShadowClientTelemetrySimulationDefaults.stableDroppedFrames
                let networkDroppedFrames = isUnstable
                    ? ShadowClientTelemetrySimulationDefaults.unstableNetworkDroppedFrames
                    : ShadowClientTelemetrySimulationDefaults.stableNetworkDroppedFrames
                let pacerDroppedFrames = droppedFrames - networkDroppedFrames
                let jitterMs = isUnstable
                    ? ShadowClientTelemetrySimulationDefaults.unstableJitterMs
                    : ShadowClientTelemetrySimulationDefaults.stableJitterBaseMs +
                        Double(
                            sampleIndex % ShadowClientTelemetrySimulationDefaults.stableJitterVarianceCycle
                        )
                let packetLossPercent = isUnstable
                    ? ShadowClientTelemetrySimulationDefaults.unstablePacketLossPercent
                    : ShadowClientTelemetrySimulationDefaults.stablePacketLossPercent
                let avSyncOffsetMs = isUnstable
                    ? ShadowClientTelemetrySimulationDefaults.unstableAVSyncOffsetMs
                    : ShadowClientTelemetrySimulationDefaults.stableAVSyncOffsetMs

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

                try? await Task.sleep(for: ShadowClientTelemetrySimulationDefaults.sampleInterval)
            }
        }
    }

    public func disconnect() async {
        telemetryTask?.cancel()
        telemetryTask = nil
    }
}
