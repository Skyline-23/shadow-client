# Repository Guidelines

## Project Structure & Module Organization
Project name is `shadow-client` and the base bundle id is `com.skyline23.shadow-client`.

Tuist lives at the repo root (`Project.swift`, `Tuist.swift`, `Tuist/Package.swift`). Keep code in these root folders:
- `Projects/App/iOS`, `Projects/App/macOS`, `Projects/App/tvOS`: platform app targets.
- `Projects/App/Features/Home`: shared feature composition.
- `Projects/App/Tests`: app-level Swift Testing suites.
- `Modules/ShadowClientCore`, `Modules/ShadowClientStreaming`, `Modules/ShadowClientInput`, `Modules/ShadowClientUI`, `Modules/ShadowClientFeatureHome`: modular runtime and feature layers (each with `Sources/` and `Tests/`).
- `moonlight-qt-master/`: reference code only; treat as upstream context unless explicitly asked to edit.
`Modules/ShadowClientFeatureHome` owns home diagnostics runtime orchestration from Qt telemetry samples.

## Build, Test, and Development Commands
Run from repository root:
- `tuist install`: resolve Tuist package dependencies.
- `tuist generate --no-open`: generate `shadow-client.xcworkspace`.
- `xcodebuild -workspace shadow-client.xcworkspace -scheme ShadowClientiOSApp build`: build iOS app target.
- `xcodebuild test -workspace shadow-client.xcworkspace -scheme ShadowClientTests -destination 'platform=iOS Simulator,name=iPhone 16'`: run app test target.
- `cd Modules && swift test`: run modular Swift package tests quickly.

## Coding Style & Naming Conventions
Use Swift 6 conventions: 4-space indentation, `UpperCamelCase` for types, `lowerCamelCase` for functions/properties, and explicit access control on public APIs. Keep cross-platform logic in `Modules/*` and platform glue in `Projects/App/*`. Prefer protocol-driven boundaries over concrete cross-module imports.

## Testing Guidelines
Use Swift Testing only (`import Testing`, `@Test`, `#expect`); do not add XCTest. TDD is mandatory: write a failing test, implement minimal code, then refactor. For streaming/input changes, keep coverage for latency gates, drop-rate/AV-sync guards, controller feedback contracts, and telemetry pipeline state transitions.

When mapping upstream metrics, normalize through `StreamingTelemetrySnapshot(qtSample:)` before runtime decisions; keep conversion tests under `Modules/ShadowClientStreaming/Tests`.
Session callbacks should enter through `MoonlightSessionTelemetryCallbackAdapter` and publish via `MoonlightSessionTelemetryBridge`; do not reintroduce timer/sample-array simulation paths.

## Agent Execution Rules
For non-trivial work, use subagents in parallel for discovery and implementation. Assign each subagent a disjoint file/module ownership and merge only after target-level tests pass. Keep `main` in a working state with incremental commits at meaningful checkpoints.

## Priority Roadmap
Implement in this order:
1. Low-latency streaming stability and recovery behavior.
2. HDR, audio, settings, and input mapping completeness with native UX polish.
3. Controller parity, including DualSense USB round-trip support (input, rumble, adaptive triggers, LED).

## Commit & PR Guidelines
No established history yet, so use Conventional Commits (for example `feat(streaming): add jitter buffer gate test`). Keep commits small and single-purpose. PRs must include scope, commands run, platform coverage (iOS/macOS/tvOS), and measurable evidence for latency or input-path changes.
