# Repository Guidelines

## Project Structure & Module Organization
Tuist manifests live at repo root: `Project.swift`, `Tuist.swift`, and `Tuist/Package.swift`.
- `Projects/App/iOS`, `Projects/App/macOS`, `Projects/App/tvOS`: platform app entrypoints and composition.
- `Projects/App/Features/Home`: shared Home feature UI/runtime wiring.
- `Projects/App/Tests`: app-level Swift Testing suites.
- `Modules/ShadowClientCore`, `Modules/ShadowClientStreaming`, `Modules/ShadowClientInput`, `Modules/ShadowClientUI`, `Modules/ShadowClientFeatureHome`: modular runtime layers with `Sources/` and `Tests/`.
- `moonlight-qt-master/`: upstream reference only (gitignored), never a runtime dependency.
`HomeFeatureBuilder` snapshots must include session configuration derived from the streaming settings mapper.

## Build, Test, and Development Commands
Run from repository root:
- `tuist install`: resolve Tuist package dependencies.
- `tuist generate --no-open`: generate `shadow-client.xcworkspace`.
- `xcodebuild build -workspace shadow-client.xcworkspace -scheme ShadowClientiOSApp -destination 'generic/platform=iOS Simulator'`: build iOS app.
- `xcodebuild test -workspace shadow-client.xcworkspace -scheme ShadowClientTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'`: run app test bundle.
- `cd Modules && swift test`: fast module-level verification during TDD loops.

## Coding Style & Naming Conventions
Use Swift 6 style: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for functions/properties, and explicit access control for exported APIs. Keep platform-specific glue in `Projects/App/*` and reusable logic in `Modules/*`.

## Concurrency, DI, and Streaming Rules
Use native Swift concurrency first: prefer `actor` for shared mutable streaming state, and use `async/await` for telemetry ingest and decision flow. Keep Combine for UI-facing event surfaces (`AnyPublisher`).

Use Pure DI: inject dependencies via initializers (for example feature dependencies and telemetry bridge), and avoid hidden service locators. Compatibility boundaries must stay thin (`MoonlightSessionTelemetryCallbackAdapter` -> `MoonlightSessionTelemetryBridge` -> normalized snapshot).
For streaming recovery, keep hysteresis in `LowLatencyTelemetryPipeline`: require sustained stable samples before releasing quality reduction.
Propagate recovery diagnostics and session launch plan (HDR/audio/reconfigure flags) from decision layer to UI HUD for observability.

## Testing Guidelines
TDD is mandatory: start with a failing test, implement minimally, then refactor.
Use Swift Testing (`import Testing`, `@Test`, `#expect`) for authored tests, and do not add new `XCTestCase`-based tests.
Keep coverage for low-latency gates, telemetry normalization, HDR/audio/settings behavior, native controller mapping profiles, and controller feedback contracts.
Use `StreamingSessionSettingsMapper` + `AdaptiveSessionLaunchRuntime` for telemetry-driven HDR/audio launch and renegotiation plans.

## Commit & PR Guidelines
History already follows Conventional Commits (`feat(streaming): ...`, `docs(agents): ...`, `chore(...)`); keep using that format. Make small, single-purpose commits on `main` and keep the tree buildable.

PRs must include scope, commands run, iOS/macOS/tvOS coverage, and measurable latency/input impact.

## Agent Execution Rules
Use subagents in parallel for non-trivial work with disjoint ownership, then merge after tests pass. Update `AGENTS.md` whenever architecture priorities or execution rules change.
