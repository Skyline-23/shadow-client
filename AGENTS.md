# Repository Guidelines

## Project Structure & Module Organization
Tuist manifests live at repo root: `Project.swift`, `Tuist.swift`, and `Tuist/Package.swift`.
- `Projects/App/iOS`, `Projects/App/macOS`, `Projects/App/tvOS`: platform entrypoints.
- `Projects/App/Features/Home`: app shell, Home surface, settings toggles, and `ControllerFeedbackStatusPanel`.
- `Projects/App/Tests`: test suites.
- `Modules/ShadowClientCore`, `Modules/ShadowClientStreaming`, `Modules/ShadowClientInput`, `Modules/ShadowClientUI`, `Modules/ShadowClientFeatureHome`: layered modules with `Sources/` and `Tests/`.
- `external/moonlight-qt-master/`: upstream reference only (gitignored), never a runtime dependency.
`HomeFeatureBuilder` snapshots must include mapped session configuration.

## Build, Test, and Development Commands
- `tuist install`: resolve dependencies.
- `tuist generate --no-open`: generate `shadow-client.xcworkspace`.
- `xcodebuild build -workspace shadow-client.xcworkspace -scheme ShadowClientmacOS -destination 'platform=macOS'`: primary local build validation.
- `xcodebuild build -workspace shadow-client.xcworkspace -scheme ShadowClientTests -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`: primary fast compile check for app test target.
- `xcodebuild build -workspace shadow-client.xcworkspace -scheme ShadowClientiOSApp -destination 'generic/platform=iOS Simulator'`: build iOS app.
- `xcodebuild test -workspace shadow-client.xcworkspace -scheme ShadowClientTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'`: run tests.
- `xcodebuild clean test -workspace shadow-client.xcworkspace -scheme ShadowClientTests -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2'`: use when module cache/state is stale.
- `cd Modules && swift test`: module tests.

## Coding Style & Naming Conventions
Use Swift 6 style: 4-space indentation, `UpperCamelCase` types, `lowerCamelCase` members, and access control for exported APIs. Keep platform glue in `Projects/App/*` and reusable logic in `Modules/*`.

## Concurrency, DI, and Streaming Rules
Use native Swift concurrency first: prefer `actor` for shared mutable streaming state, and use `async/await` for telemetry ingest and decision flow. Keep Combine for UI-facing event surfaces (`AnyPublisher`).
For `ObservableObject` runtimes (`HostDiscoveryRuntime`, `RemoteDesktopRuntime`), keep `@Published`/SwiftUI binding surface but migrate internal orchestration to `AsyncStream` + `actor` command/event pipelines.

Use Pure DI: inject dependencies via initializers and avoid hidden service locators. Keep compatibility boundaries thin (`MoonlightSessionTelemetryCallbackAdapter` -> `MoonlightSessionTelemetryBridge` -> normalized snapshot).
For streaming recovery, keep hysteresis in `LowLatencyTelemetryPipeline`: require sustained stable samples before releasing quality reduction, and ignore out-of-order telemetry timestamps.
Propagate recovery diagnostics and session launch plan (HDR/audio/reconfigure flags) from decision layer to the settings HUD.

## Testing Guidelines
TDD is mandatory: start with a failing test, implement minimally, then refactor.
Use Swift Testing (`import Testing`, `@Test`, `#expect`) for authored tests, and do not add new `XCTestCase`-based tests.
Default local validation order is macOS-first (`ShadowClientmacOS` build + `ShadowClientTests` compile build + `Modules` swift tests). iOS simulator test runs are secondary and executed when macOS-first validation is green or when iOS-specific behavior is touched.
For this repo’s current Swift Testing setup, `xcodebuild test`/Xcode MCP test actions may report `Executed 0 tests` or `No result` for app-level tests; treat `ShadowClientTests` as a compile gate and use `cd Modules && swift test` for executable Swift Testing coverage.
Keep coverage for low-latency gates, telemetry normalization, HDR/audio/settings behavior, native controller mapping profiles, and controller feedback contracts.
Keep coverage for controller feedback presentation state and USB-first DualSense requirements.
Use `StreamingSessionSettingsMapper` + `AdaptiveSessionLaunchRuntime` + `GameControllerInputAdapter`/`GameControllerFeedbackRuntime` for telemetry-driven launch and USB-first feedback input plans.

## Commit & PR Guidelines
Use Conventional Commits (`feat(streaming): ...`, `docs(agents): ...`, `chore(...)`). Make small, single-purpose commits on `main` and keep the tree buildable.

PRs must include scope, commands run, iOS/macOS/tvOS coverage, and measurable latency/input impact.

## Agent Execution Rules
Use subagents in parallel for non-trivial work with disjoint ownership, then merge after tests pass. Update `AGENTS.md` whenever architecture priorities or execution rules change.

### Subagent Lifecycle Discipline
- Keep subagents ownership-scoped (one concern per agent) and run in parallel only for disjoint files/tasks.
- At the end of every work batch, close completed/idle subagents and report a short status summary (`in-use`, `completed/closed`, `remaining`).
- Do not leave stale agents running between unrelated batches.

### XcodeBuildMCP Interactive Validation (Required)
- Always verify simulator defaults first: `session-show-defaults` then `session-set-defaults` (workspace, scheme, simulatorId, bundleId).
- For tap/click validation, use XcodeBuildMCP UI automation in this order:
  1. `snapshot_ui` to get exact element coordinates.
  2. `ui-automation tap` (`Connect` -> `Launch`) using simulator coordinates or element label/id.
  3. `ui-automation screenshot` after each important state change.
- For transport/decoder debugging, wrap interaction with structured logs:
  1. `logging start-simulator-log-capture --simulator-id ... --bundle-id ...`
  2. Perform taps and wait for transition.
  3. `logging stop-simulator-log-capture --log-session-id ...` and attach relevant RTSP/decoder lines to the report.
- If `tap` tools are not exposed through function wrappers, use the `xcodebuildmcp` CLI workflow (`ui-automation tap`, `snapshot-ui`, `logging ...`) instead of skipping interaction validation.
- Use `xcodebuildmcp --style minimal ...` for CLI calls to avoid known next-step rendering failures in normal style.
- When duplicate labels exist (for example two `Refresh` buttons), do not tap by label. Use `snapshot-ui` coordinates and tap by `-x/-y`.

### macOS Runtime Validation (Required)
- Default validation target is macOS. Use `xcodebuildmcp --style minimal macos build-and-run` for launch and `xcodebuildmcp --style minimal macos stop` for cleanup.
- `xcodebuildmcp` UI tap tools are simulator-only (`--simulator-id` required). For macOS click automation, use AX/CGEvent scripts from CLI and attach before/after screenshots plus RTSP/control log snippets.
- If the desktop is on lock screen, do not continue blind retries. Unlock first, then rerun click/log capture sequence.

### Realtime Streaming Integration Notes
- Treat Sunshine `DESCRIBE` codec metadata as advisory; actual selected codec is finalized by RTSP `ANNOUNCE` (`x-nv-vqos[0].bitStreamFormat`) and launch plan policy.
- For H264/H265 Moonlight NV RTP packets, use depacketizer tail strategy `.passthroughForAnnexBCodecs` (do not enforce `lastPacketPayloadLength` truncation).
- Reserve `lastPacketPayloadLength` truncation for AV1/non-AnnexB streams only (`.trimUsingLastPacketLength`).
- `ShadowClientAppShellView` must observe `sessionSurfaceContext` directly; relying only on `remoteDesktopRuntime` can leave session HUD stuck in `waitingForFirstFrame` even when frames render.
- GPU-first hot path is mandatory:
  - Prefer hardware VideoToolbox decode + Metal render path; avoid CPU-bound fallback paths in steady-state runtime.
  - Avoid CPU spin/poll patterns in ingest/decode loops; use bounded queues and async backpressure.
  - Avoid per-packet/per-frame unnecessary copies in transport/depacketize/decode boundaries where protocol safety permits.
- Queue pressure policy must be adaptive, not static:
  - Derive receive/decode queue sizing and trim thresholds from session bitrate/fps (and keep sane caps).
  - Do not escalate queue-pressure recovery while decoded frames are still being produced (recovery escalation requires output-stall evidence).
  - Decode-queue pressure must drive throughput relief (`queue saturation` signal), while `decoder instability` signal is reserved for real decoder failure/stall paths.

### Streaming Refactor Priority (Current)
- Execute refactors in this exact order unless explicitly overridden by user:
  1. AV1 receive/decode path stabilization (`refactor(video)`):
     - hard-separate RTP receive, depacketize, and decode stages into independent actors/queues,
     - use bounded ring buffers and watermark-based drop policy between stages,
     - ensure decode stall does not block ingest.
     - status: `partial` (queue separation landed in `8ea1e0b`, but runtime remains a large single actor/file and still needs stronger stage isolation).
  2. AV1 failure fast fallback (`fix(streaming)`):
     - if AV1 decode/recovery failures exceed threshold within short window, trigger immediate HEVC fallback/relaunch path.
     - status: `partial` (fallback path and tests landed, but field logs still show prolonged recovery-loop behavior before fallback in some scenarios).
  3. Depacketizer continuity/recovery tuning (`fix(streaming)`):
     - relax over-strict continuity checks,
     - tune recovery cooldown/hysteresis to prevent recovery-loop oscillation.
     - status: `partial` (threshold/cooldown tuning is implemented, but oscillation is not fully eliminated under stress).

### Active Functional Roadmap (Must Be Implemented In Order)
- `feat(audio): external Opus integration + capability-driven negotiation`
  - use external `opus` module for Opus decode path across stereo and multichannel tracks,
  - use external `opus` decoder as the default/required Opus path (system Opus decoder disabled for runtime streaming due corruption risk on target workloads),
  - keep decoder capability/combination-based negotiation:
    - use surround only if local decoder/output can actually support it,
    - otherwise select stereo parameters during SDP/track negotiation (not runtime failure).
  - status: `in_progress` (external decoder path is now the primary Opus runtime path; stereo provider + queue/guard tuning are being hardened with field logs).
- `refactor(runtime): AsyncStream/actor-first runtime internals`
  - preserve SwiftUI-facing `@Published` API contracts,
  - reduce ad-hoc `Task` fan-out by routing runtime intents/events through typed `AsyncStream` pipelines,
  - centralize mutable runtime coordination state in actors (or actor-backed reducers).
  - status: `done` (runtime command/event flow migrated to typed `AsyncStream` + actor-backed coordination while preserving `@Published` surfaces).
- `refactor(input): single producer queue + coalescing sender`
  - replace per-event send `Task` fan-out with a dedicated input send queue actor,
  - coalesce high-rate events (`pointerMoved`, `scroll`),
  - suppress cancellation-class network noise (`ECANCELED`/`ENOTCONN`) and apply controlled channel rebootstrap cooldown.
  - status: `partial` (single queue + coalescing + benign error suppression are done; explicit rebootstrap cooldown/backoff policy is still pending).
- `refactor(video): hard isolate receive/depacketize/decode stages`
  - split current runtime file responsibilities into pipeline components with clear ownership,
  - MainActor transitions only for HUD/surface state; never in ingest/decode hot path.
  - status: `partial` (receive/depacketize/decode queues/tasks exist, but component split and stricter hot-path isolation are incomplete).
- `fix(streaming): av1 recovery policy tuning + fast hevc switch`
  - retune AV1 recovery thresholds/windows/cooldowns,
  - enforce fast and consistent HEVC switch trigger when AV1 recovery is exhausted.
  - status: `partial` (policy/tuning landed with fallback triggers, but consistency and immediacy under interaction/fullscreen stress still need improvement).
- `perf(streaming): GPU-first queue/backpressure tuning`
  - apply bitrate/fps-adaptive receive/decode queue profiles instead of fixed queue constants,
  - tune VideoToolbox AV1/H26x in-flight decode budget adaptively from session resolution/fps (aggressive enough to prevent decode starvation under fullscreen/interaction bursts),
  - apply backlog-aware in-flight expansion (bounded) so decode submission catches up under transient bursts without permanently overdriving VT,
  - gate queue-pressure recovery escalation on decoded-frame output stall (prevent recovery-request loops while rendering is healthy),
  - preserve frame boundaries when trimming receive queue under pressure (avoid partial-AU restart corruption),
  - keep decode throughput recovery and render cadence synchronized to session FPS to avoid decode↔render oscillation,
  - apply the same pressure-shed policy family to audio output queue saturation (decode-side shedding + bounded queue policy) to avoid audio loop thrash.
  - status: `in_progress` (adaptive queue profile + stall-gated recovery + backlog-aware VT in-flight + audio saturation cooldown are landed; receive-queue sizing now caps bitrate outliers using resolution/fps model and decoder output bridge no longer timer-throttles frame delivery, but fullscreen/interaction stress stability is still being tuned).
- `fix(macos): fullscreen transition state machine`
  - state-machine fullscreen toggles (no retrigger during transition),
  - prevent capture/app-focus transitions from tearing down decoder/transport loops.
  - status: `not_done` (current implementation uses boolean/debounce guards, not a full explicit transition state machine).

### Current Priority Status Snapshot (Updated: 2026-02-21)
- 1순위 AV1 수신/디코드 분리: partial (structure exists, isolation strength insufficient).
- 2순위 AV1 실패 시 HEVC 전환: partial (trigger exists, immediacy/consistency insufficient).
- 3순위 연속성/복구 정책 조정: partial (policy exists, tuning required).

### Functional-Unit Commit Discipline
- Commit each completed feature/fix in isolation with Conventional Commits before starting the next unit.
