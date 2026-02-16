import Foundation

public actor MoonlightSessionTelemetryBridge {
    public typealias SnapshotStream = AsyncStream<StreamingTelemetrySnapshot>
    public static let shared = MoonlightSessionTelemetryBridge()

    private var continuations: [UUID: SnapshotStream.Continuation] = [:]

    public init() {}

    public func snapshotStream(
        bufferingPolicy: SnapshotStream.Continuation.BufferingPolicy = .bufferingNewest(64)
    ) -> SnapshotStream {
        let subscriberID = UUID()

        return SnapshotStream(bufferingPolicy: bufferingPolicy) { continuation in
            continuations[subscriberID] = continuation
            continuation.onTermination = { _ in
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
