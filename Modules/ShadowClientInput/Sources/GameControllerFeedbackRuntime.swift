import Combine
import Foundation

public actor GameControllerFeedbackRuntime {
    public typealias EvaluationStream = AsyncStream<Evaluation>

    public struct Evaluation: Equatable, Sendable {
        public let state: MappedControllerState
        public let feedback: DualSenseFeedbackResult

        public init(state: MappedControllerState, feedback: DualSenseFeedbackResult) {
            self.state = state
            self.feedback = feedback
        }
    }

    nonisolated(unsafe) private let subject = PassthroughSubject<Evaluation, Never>()
    private let runtime: ControllerInputRuntime
    private let adapter: GameControllerInputAdapter
    private let contract: DualSenseFeedbackContract
    private var continuations: [UUID: EvaluationStream.Continuation]
    private var latest: Evaluation?

    public init(
        runtime: ControllerInputRuntime = .init(),
        adapter: GameControllerInputAdapter = .init(),
        contract: DualSenseFeedbackContract = .init()
    ) {
        self.runtime = runtime
        self.adapter = adapter
        self.contract = contract
        self.continuations = [:]
        self.latest = nil
    }

    public nonisolated var evaluationPublisher: AnyPublisher<Evaluation, Never> {
        subject.eraseToAnyPublisher()
    }

    public func evaluationStream(
        bufferingPolicy: EvaluationStream.Continuation.BufferingPolicy = .bufferingNewest(64)
    ) -> EvaluationStream {
        let subscriberID = UUID()

        return EvaluationStream(bufferingPolicy: bufferingPolicy) { continuation in
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
    public func ingest(
        gameControllerState: any GameControllerStateProviding,
        device: any DualSenseFeedbackDevice
    ) async -> Evaluation {
        let snapshot = adapter.makeSnapshot(from: gameControllerState)
        let mappedState = await runtime.ingest(snapshot)
        let feedback = contract.evaluate(device: device)
        let evaluation = Evaluation(state: mappedState, feedback: feedback)
        latest = evaluation
        subject.send(evaluation)

        for continuation in continuations.values {
            continuation.yield(evaluation)
        }

        return evaluation
    }

    public func latestEvaluation() -> Evaluation? {
        latest
    }

    public func activeSubscriberCount() -> Int {
        continuations.count
    }

    private func removeSubscriber(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
