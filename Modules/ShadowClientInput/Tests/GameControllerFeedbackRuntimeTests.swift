import Testing
@testable import ShadowClientInput

@Test("GameController feedback runtime emits mapped state with passing USB feedback contract")
func gameControllerFeedbackRuntimeEmitsPassingEvaluation() async {
    let runtime = GameControllerFeedbackRuntime()
    let state = GameControllerStateStub(
        faceSouthPressed: true,
        menuPressed: true,
        leftStickX: -0.6,
        leftTriggerValue: 0.8
    )
    let device = DualSenseFeedbackDeviceStub(
        transport: .usb,
        capabilities: .init(
            supportsRumble: true,
            supportsAdaptiveTriggers: true,
            supportsLED: true
        )
    )

    let evaluation = await runtime.ingest(gameControllerState: state, device: device)

    #expect(evaluation.state.pressedButtons.contains(.actionSouth))
    #expect(evaluation.state.pressedButtons.contains(.menu))
    #expect(evaluation.state.axisValues[.moveX] == -0.6)
    #expect(evaluation.state.axisValues[.leftTrigger] == 0.8)
    #expect(evaluation.feedback.passes)
}

@Test("GameController feedback runtime fails feedback contract when transport is bluetooth")
func gameControllerFeedbackRuntimeFailsForBluetoothTransport() async {
    let runtime = GameControllerFeedbackRuntime()
    let state = GameControllerStateStub(faceSouthPressed: true)
    let device = DualSenseFeedbackDeviceStub(
        transport: .bluetooth,
        capabilities: .init(
            supportsRumble: true,
            supportsAdaptiveTriggers: true,
            supportsLED: true
        )
    )

    let evaluation = await runtime.ingest(gameControllerState: state, device: device)

    #expect(!evaluation.feedback.passes)
    #expect(evaluation.feedback.missingCapabilities.contains("usbTransport"))
}

@Test("GameController feedback runtime stores latest evaluation for pull-based consumers")
func gameControllerFeedbackRuntimeStoresLatestEvaluation() async {
    let runtime = GameControllerFeedbackRuntime()
    let firstDevice = DualSenseFeedbackDeviceStub(
        transport: .usb,
        capabilities: .init(
            supportsRumble: true,
            supportsAdaptiveTriggers: true,
            supportsLED: true
        )
    )
    let secondDevice = DualSenseFeedbackDeviceStub(
        transport: .usb,
        capabilities: .init(
            supportsRumble: true,
            supportsAdaptiveTriggers: false,
            supportsLED: true
        )
    )

    _ = await runtime.ingest(
        gameControllerState: GameControllerStateStub(faceSouthPressed: true),
        device: firstDevice
    )
    let secondEvaluation = await runtime.ingest(
        gameControllerState: GameControllerStateStub(faceNorthPressed: true),
        device: secondDevice
    )
    let latest = await runtime.latestEvaluation()

    #expect(latest == secondEvaluation)
    #expect(latest?.state.pressedButtons.contains(.actionNorth) == true)
    #expect(latest?.feedback.missingCapabilities.contains("adaptiveTriggers") == true)
}

@Test("GameController feedback runtime streams evaluations and removes subscribers after cancellation")
func gameControllerFeedbackRuntimeStreamsAndRemovesSubscribers() async {
    let runtime = GameControllerFeedbackRuntime()
    let stream = await runtime.evaluationStream()
    let device = DualSenseFeedbackDeviceStub(
        transport: .usb,
        capabilities: .init(
            supportsRumble: true,
            supportsAdaptiveTriggers: true,
            supportsLED: true
        )
    )

    #expect(await runtime.activeSubscriberCount() == 1)

    async let first = stream.first(where: { $0.state.pressedButtons.contains(.actionSouth) })
    _ = await runtime.ingest(
        gameControllerState: GameControllerStateStub(faceSouthPressed: true),
        device: device
    )
    let received = await first

    #expect(received != nil)

    let consumer = Task {
        for await _ in stream {
            if Task.isCancelled { break }
        }
    }
    consumer.cancel()
    _ = await consumer.result

    for _ in 0..<20 {
        if await runtime.activeSubscriberCount() == 0 {
            break
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }

    #expect(await runtime.activeSubscriberCount() == 0)
}
