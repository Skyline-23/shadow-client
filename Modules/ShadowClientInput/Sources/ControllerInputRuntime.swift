import Combine
import Foundation

public actor ControllerInputRuntime {
    public typealias StateStream = AsyncStream<MappedControllerState>

    nonisolated(unsafe) private let subject = PassthroughSubject<MappedControllerState, Never>()
    private let mapper: NativeControllerInputMapper
    private var continuations: [UUID: StateStream.Continuation]
    private var latestState: MappedControllerState?

    public init(mapper: NativeControllerInputMapper = .init()) {
        self.mapper = mapper
        self.continuations = [:]
        self.latestState = nil
    }

    public nonisolated var statePublisher: AnyPublisher<MappedControllerState, Never> {
        subject.eraseToAnyPublisher()
    }

    public func stateStream(
        bufferingPolicy: StateStream.Continuation.BufferingPolicy = .bufferingNewest(64)
    ) -> StateStream {
        let subscriberID = UUID()

        return StateStream(bufferingPolicy: bufferingPolicy) { continuation in
            continuations[subscriberID] = continuation
            continuation.onTermination = { [weak self] _ in
                guard let self else {
                    return
                }
                Task {
                    await self.removeSubscriber(subscriberID)
                }
            }
        }
    }

    @discardableResult
    public func ingest(_ snapshot: ControllerInputSnapshot) -> MappedControllerState {
        let mappedState = mapper.map(snapshot)
        latestState = mappedState
        subject.send(mappedState)
        for continuation in continuations.values {
            continuation.yield(mappedState)
        }
        return mappedState
    }

    @discardableResult
    public func ingest(
        gameControllerState: any GameControllerStateProviding,
        adapter: GameControllerInputAdapter = .init()
    ) -> MappedControllerState {
        let snapshot = adapter.makeSnapshot(from: gameControllerState)
        return ingest(snapshot)
    }

    public func currentState() -> MappedControllerState? {
        latestState
    }

    public func activeSubscriberCount() -> Int {
        continuations.count
    }

    private func removeSubscriber(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
