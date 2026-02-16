import ShadowClientCore
import ShadowClientInput
import ShadowClientStreaming

public enum HealthTone: String, Equatable, Sendable {
    case healthy
    case warning
    case critical
}

public struct StreamHealthBadgeModel: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let tone: HealthTone

    public init(title: String, detail: String, tone: HealthTone) {
        self.title = title
        self.detail = detail
        self.tone = tone
    }
}

public struct StreamHealthPresenter: Sendable {
    public init() {}

    public func makeBadge(
        streaming: StreamingStabilityReport,
        inputLatency: GateEvaluation,
        feedback: DualSenseFeedbackResult
    ) -> StreamHealthBadgeModel {
        if streaming.passes && inputLatency.passes && feedback.passes {
            return StreamHealthBadgeModel(
                title: "Shadow Client Ready",
                detail: "Streaming, input latency, and feedback are within first-pass gates.",
                tone: .healthy
            )
        }

        if !streaming.passes {
            return StreamHealthBadgeModel(
                title: "Streaming Needs Attention",
                detail: "Frame drop or AV sync is outside stability gates.",
                tone: .critical
            )
        }

        if !inputLatency.passes {
            return StreamHealthBadgeModel(
                title: "Input Latency Elevated",
                detail: "Round-trip p95 exceeds the low-latency gate.",
                tone: .warning
            )
        }

        return StreamHealthBadgeModel(
            title: "Controller Feedback Limited",
            detail: "DualSense capability contract is incomplete for first-pass support.",
            tone: .warning
        )
    }
}
