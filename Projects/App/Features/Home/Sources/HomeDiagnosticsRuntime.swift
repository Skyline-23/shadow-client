import ShadowClientStreaming
import ShadowClientUI

public struct HomeDiagnosticsTick: Equatable, Sendable {
    public let model: StreamingDiagnosticsModel
    public let sessionPlan: MoonlightSessionReconfigurationPlan
    public let timestampMs: Int

    public init(
        model: StreamingDiagnosticsModel,
        sessionPlan: MoonlightSessionReconfigurationPlan,
        timestampMs: Int
    ) {
        self.model = model
        self.sessionPlan = sessionPlan
        self.timestampMs = timestampMs
    }
}

public actor HomeDiagnosticsRuntime {
    private let launchRuntime: AdaptiveSessionLaunchRuntime
    private let presenter: StreamingDiagnosticsPresenter

    public init(
        launchRuntime: AdaptiveSessionLaunchRuntime = .init(),
        presenter: StreamingDiagnosticsPresenter = .init()
    ) {
        self.launchRuntime = launchRuntime
        self.presenter = presenter
    }

    public func ingest(snapshot: StreamingTelemetrySnapshot) async -> HomeDiagnosticsTick {
        let result = await launchRuntime.ingest(snapshot)
        let model = presenter.makeModel(
            decision: result.decision,
            signal: snapshot.signal,
            stats: snapshot.stats,
            dropBreakdown: snapshot.dropBreakdown
        )

        return HomeDiagnosticsTick(
            model: model,
            sessionPlan: result.plan,
            timestampMs: snapshot.timestampMs
        )
    }
}
