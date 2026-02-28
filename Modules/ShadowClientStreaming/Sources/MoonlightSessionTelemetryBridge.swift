import Combine
import Foundation

public actor MoonlightSessionTelemetryBridge {
    public typealias SnapshotStream = AsyncStream<StreamingTelemetrySnapshot>
    public static let shared = MoonlightSessionTelemetryBridge()

    nonisolated(unsafe) private let subject = PassthroughSubject<StreamingTelemetrySnapshot, Never>()
    private var continuations: [UUID: SnapshotStream.Continuation] = [:]

    public init() {}

    public nonisolated var snapshotPublisher: AnyPublisher<StreamingTelemetrySnapshot, Never> {
        subject.eraseToAnyPublisher()
    }

    public func snapshotStream(
        bufferingPolicy: SnapshotStream.Continuation.BufferingPolicy = .bufferingNewest(64)
    ) -> SnapshotStream {
        let subscriberID = UUID()

        return SnapshotStream(bufferingPolicy: bufferingPolicy) { continuation in
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

    public func ingest(qtSample: MoonlightQTTelemetrySample) {
        ingest(snapshot: StreamingTelemetrySnapshot(qtSample: qtSample))
    }

    public func ingest(snapshot: StreamingTelemetrySnapshot) {
        subject.send(snapshot)
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    public func activeSubscriberCount() -> Int {
        continuations.count
    }

    private func removeSubscriber(_ subscriberID: UUID) {
        continuations.removeValue(forKey: subscriberID)
    }
}
