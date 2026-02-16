# Repository Guidelines

## Project Structure & Module Organization
Tuist manifests live at repo root: `Project.swift`, `Tuist.swift`, and `Tuist/Package.swift`.
- `Projects/App/iOS`, `Projects/App/macOS`, `Projects/App/tvOS`: platform entrypoints.
- `Projects/App/Features/Home`: app shell, Home surface, settings toggles, and `ControllerFeedbackStatusPanel`.
- `Projects/App/Tests`: test suites.
- `Modules/ShadowClientCore`, `Modules/ShadowClientStreaming`, `Modules/ShadowClientInput`, `Modules/ShadowClientUI`, `Modules/ShadowClientFeatureHome`: layered modules with `Sources/` and `Tests/`.
- `moonlight-qt-master/`: upstream reference only (gitignored), never a runtime dependency.
`HomeFeatureBuilder` snapshots must include mapped session configuration.

## Build, Test, and Development Commands
- `tuist install`: resolve dependencies.
- `tuist generate --no-open`: generate `shadow-client.xcworkspace`.
- `xcodebuild build -workspace shadow-client.xcworkspace -scheme ShadowClientiOSApp -destination 'generic/platform=iOS Simulator'`: build iOS app.
- `xcodebuild test -workspace shadow-client.xcworkspace -scheme ShadowClientTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'`: run tests.
- `xcodebuild clean test -workspace shadow-client.xcworkspace -scheme ShadowClientTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'`: use when module cache/state is stale.
- `cd Modules && swift test`: module tests.

## Coding Style & Naming Conventions
Use Swift 6 style: 4-space indentation, `UpperCamelCase` types, `lowerCamelCase` members, and access control for exported APIs. Keep platform glue in `Projects/App/*` and reusable logic in `Modules/*`.

## Concurrency, DI, and Streaming Rules
Use native Swift concurrency first: prefer `actor` for shared mutable streaming state, and use `async/await` for telemetry ingest and decision flow. Keep Combine for UI-facing event surfaces (`AnyPublisher`).

Use Pure DI: inject dependencies via initializers and avoid hidden service locators. Keep compatibility boundaries thin (`MoonlightSessionTelemetryCallbackAdapter` -> `MoonlightSessionTelemetryBridge` -> normalized snapshot).
For streaming recovery, keep hysteresis in `LowLatencyTelemetryPipeline`: require sustained stable samples before releasing quality reduction, and ignore out-of-order telemetry timestamps.
Propagate recovery diagnostics and session launch plan (HDR/audio/reconfigure flags) from decision layer to the settings HUD.

## Testing Guidelines
TDD is mandatory: start with a failing test, implement minimally, then refactor.
Use Swift Testing (`import Testing`, `@Test`, `#expect`) for authored tests, and do not add new `XCTestCase`-based tests.
Keep coverage for low-latency gates, telemetry normalization, HDR/audio/settings behavior, native controller mapping profiles, and controller feedback contracts.
Keep coverage for controller feedback presentation state and USB-first DualSense requirements.
Use `StreamingSessionSettingsMapper` + `AdaptiveSessionLaunchRuntime` + `GameControllerInputAdapter`/`GameControllerFeedbackRuntime` for telemetry-driven launch and USB-first feedback input plans.

## Commit & PR Guidelines
Use Conventional Commits (`feat(streaming): ...`, `docs(agents): ...`, `chore(...)`). Make small, single-purpose commits on `main` and keep the tree buildable.

PRs must include scope, commands run, iOS/macOS/tvOS coverage, and measurable latency/input impact.

## Agent Execution Rules
Use subagents in parallel for non-trivial work with disjoint ownership, then merge after tests pass. Update `AGENTS.md` whenever architecture priorities or execution rules change.
