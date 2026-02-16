import Combine
import Testing
@testable import ShadowClientInput

@Test("Controller input runtime emits mapped state to async stream subscribers")
func controllerInputRuntimeEmitsMappedStateToStream() async {
    let runtime = ControllerInputRuntime()
    let stream = await runtime.stateStream()
    let snapshot = ControllerInputSnapshot(
        pressedButtons: [.cross, .options],
        axisValues: [.leftStickX: -0.6]
    )

    async let first = stream.first(where: { $0.pressedButtons.contains(.actionSouth) })
    _ = await runtime.ingest(snapshot)
    let state = await first

    #expect(state != nil)
    #expect(state?.pressedButtons.contains(.actionSouth) == true)
    #expect(state?.pressedButtons.contains(.menu) == true)
    #expect(state?.axisValues[.moveX] == -0.6)
}

@Test("Controller input runtime publishes mapped state through Combine publisher")
func controllerInputRuntimePublishesMappedStateThroughCombine() async {
    let runtime = ControllerInputRuntime()
    let snapshot = ControllerInputSnapshot(
        pressedButtons: [.circle],
        axisValues: [.rightStickX: 0.75]
    )

    let state: MappedControllerState = await withCheckedContinuation { continuation in
        var cancellable: AnyCancellable?
        cancellable = runtime.statePublisher.sink { value in
            cancellable?.cancel()
            continuation.resume(returning: value)
        }

        Task {
            await runtime.ingest(snapshot)
        }
    }

    #expect(state.pressedButtons.contains(.actionEast))
    #expect(state.axisValues[.cameraX] == 0.75)
}

@Test("Controller input runtime stores latest mapped state for pull-based consumers")
func controllerInputRuntimeStoresLatestMappedState() async {
    let runtime = ControllerInputRuntime()
    let firstSnapshot = ControllerInputSnapshot(
        pressedButtons: [.cross],
        axisValues: [.leftStickX: 0.1]
    )
    let secondSnapshot = ControllerInputSnapshot(
        pressedButtons: [.triangle],
        axisValues: [.leftStickX: 0.4]
    )

    _ = await runtime.ingest(firstSnapshot)
    _ = await runtime.ingest(secondSnapshot)
    let currentState = await runtime.currentState()

    #expect(currentState != nil)
    #expect(currentState?.pressedButtons == [.actionNorth])
    #expect(currentState?.axisValues[.moveX] == 0.4)
}

@Test("Controller input runtime removes subscribers after stream consumer cancellation")
func controllerInputRuntimeRemovesSubscribersAfterCancellation() async {
    let runtime = ControllerInputRuntime()
    let stream = await runtime.stateStream()
    #expect(await runtime.activeSubscriberCount() == 1)

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
