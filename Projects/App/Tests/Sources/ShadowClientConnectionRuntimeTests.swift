import ShadowClientStreaming
import Testing
@testable import ShadowClientFeatureConnection

@Test("Connection runtime connects with trimmed host and forwards connect call")
func connectionRuntimeConnectsWithTrimmedHost() async {
    let client = RecordingConnectionClient()
    let runtime = ShadowClientConnectionRuntime(client: client)

    let state = await runtime.connect(to: " 192.168.1.20 ")

    #expect(state == .connected(host: "192.168.1.20"))
    #expect(await client.connectCalls() == ["192.168.1.20"])
}

@Test("Connection runtime rejects empty host without calling connector")
func connectionRuntimeRejectsEmptyHost() async {
    let client = RecordingConnectionClient()
    let runtime = ShadowClientConnectionRuntime(client: client)

    let state = await runtime.connect(to: "   ")

    #expect(state == .failed(host: "", message: "Host is required."))
    #expect(await client.connectCalls().isEmpty)
}

@Test("Connection runtime surfaces connector failure message")
func connectionRuntimeSurfacesConnectorFailure() async {
    let client = RecordingConnectionClient()
    await client.setFailure(host: "bad-host", message: "Connection refused")
    let runtime = ShadowClientConnectionRuntime(client: client)

    let state = await runtime.connect(to: "bad-host")

    #expect(state == .failed(host: "bad-host", message: "Connection refused"))
}

@Test("Connection runtime disconnect transitions to disconnected and calls connector")
func connectionRuntimeDisconnects() async {
    let client = RecordingConnectionClient()
    let runtime = ShadowClientConnectionRuntime(client: client)

    _ = await runtime.connect(to: "192.168.0.2")
    let state = await runtime.disconnect()

    #expect(state == .disconnected)
    #expect(await client.disconnectCalls() == 1)
}

@Test("Simulated connector emits telemetry after connect")
func simulatedConnectorEmitsTelemetryAfterConnect() async {
    let bridge = MoonlightSessionTelemetryBridge()
    let connector = SimulatedShadowClientConnectionClient(bridge: bridge)
    let runtime = ShadowClientConnectionRuntime(client: connector)
    let stream = await bridge.snapshotStream()

    _ = await runtime.connect(to: "127.0.0.1")
    let sample = await firstSnapshot(from: stream, timeout: .seconds(2))

    #expect(sample != nil)
    #expect(await runtime.disconnect() == .disconnected)
}

@Test("Native host probe connector trims host and uses probe callback")
func nativeHostProbeConnectorTrimsHostAndCallsProbe() async throws {
    let capture = HostProbeCapture()
    let client = NativeHostProbeConnectionClient(requiredPorts: [47984]) { host in
        await capture.recordHost(host)
        return ShadowClientHostProbeResult(reachablePorts: [47984])
    }

    try await client.connect(to: " 192.168.1.30 ")

    #expect(await capture.hosts() == ["192.168.1.30"])
}

@Test("Native host probe connector uses explicit port from host entry")
func nativeHostProbeConnectorUsesExplicitPortFromHostEntry() async {
    let capture = HostProbeCapture()
    let client = NativeHostProbeConnectionClient(requiredPorts: [47984, 47989]) { host in
        await capture.recordHost(host)
        return ShadowClientHostProbeResult(reachablePorts: [])
    }

    var capturedFailure: ShadowClientConnectionFailure?
    do {
        try await client.connect(to: " stream-host.example.invalid:48010 ")
    } catch let error as ShadowClientConnectionFailure {
        capturedFailure = error
    } catch {
        Issue.record("Unexpected error: \(error)")
    }

    #expect(await capture.hosts() == ["stream-host.example.invalid"])
    #expect(
        capturedFailure == .connectRejected(
            "No stream services reachable on stream-host.example.invalid:48010. Checked TCP ports: 48010."
        )
    )
}

@Test("Native host probe connector surfaces probe failure")
func nativeHostProbeConnectorSurfacesProbeFailure() async {
    let client = NativeHostProbeConnectionClient(requiredPorts: [47984]) { _ in
        throw ShadowClientConnectionFailure.connectRejected("Connection refused")
    }

    var capturedFailure: ShadowClientConnectionFailure?
    var didThrowUnexpectedError = false
    do {
        try await client.connect(to: "bad-host")
    } catch let error as ShadowClientConnectionFailure {
        capturedFailure = error
    } catch {
        didThrowUnexpectedError = true
    }

    #expect(!didThrowUnexpectedError)
    #expect(capturedFailure == .connectRejected("Connection refused"))
}

@Test("Native host probe connector fails when no stream service ports are reachable")
func nativeHostProbeConnectorFailsWithoutReachablePorts() async {
    let client = NativeHostProbeConnectionClient(requiredPorts: [47984, 47989]) { _ in
        ShadowClientHostProbeResult(reachablePorts: [])
    }

    var capturedFailure: ShadowClientConnectionFailure?
    var didThrowUnexpectedError = false
    do {
        try await client.connect(to: "192.168.1.44")
    } catch let error as ShadowClientConnectionFailure {
        capturedFailure = error
    } catch {
        didThrowUnexpectedError = true
    }

    #expect(!didThrowUnexpectedError)
    #expect(capturedFailure == .connectRejected(
        "No stream services reachable on 192.168.1.44. Checked TCP ports: 47984, 47989."
    ))
}

private actor HostProbeCapture {
    private var recordedHosts: [String] = []

    func recordHost(_ host: String) {
        recordedHosts.append(host)
    }

    func hosts() -> [String] {
        recordedHosts
    }
}

private actor RecordingConnectionClient: ShadowClientConnectionClient {
    private var connectInvocations: [String] = []
    private var disconnectInvocationCount = 0
    private var failureMessages: [String: String] = [:]

    func connect(to host: String) async throws {
        connectInvocations.append(host)
        if let message = failureMessages[host] {
            throw ShadowClientConnectionFailure.connectRejected(message)
        }
    }

    func disconnect() async {
        disconnectInvocationCount += 1
    }

    func setFailure(host: String, message: String) {
        failureMessages[host] = message
    }

    func connectCalls() -> [String] {
        connectInvocations
    }

    func disconnectCalls() -> Int {
        disconnectInvocationCount
    }
}

private func firstSnapshot(
    from stream: AsyncStream<StreamingTelemetrySnapshot>,
    timeout: Duration
) async -> StreamingTelemetrySnapshot? {
    await withTaskGroup(of: StreamingTelemetrySnapshot?.self) { group in
        group.addTask {
            for await snapshot in stream {
                return snapshot
            }
            return nil
        }

        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }

        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
