# shadow-client

Experimental Apple-platform game streaming client for Sunshine with an explicit focus on protocol correctness, low-latency decode/render, and Moonlight-compatible recovery behavior.

## Current Status

- Sunshine/Moonlight protocol parity is still in progress.
- macOS-first validation is the default workflow.
- iOS/iPadOS background session policy is explicit: active sessions are ended when the scene enters background.
- The control-path `Ping Timeout` class of failures has been substantially reduced by aligning more of the custom ENet behavior with Moonlight.
- The main active work is now video recovery, FEC resilience, decoder stability, and steady-state performance.

## Platforms

- macOS: primary validation target
- iOS/iPadOS: supported, with explicit background disconnect policy
- tvOS: builds, but receives less day-to-day validation than macOS

## Validation Philosophy

This repository validates changes in the following order:

1. `ShadowClientmacOS` build
2. `ShadowClientTests` compile gate on iOS Simulator
3. `Modules` Swift package tests

The repo intentionally treats app-level iOS test runs as secondary because the current Swift Testing/Xcode setup can report `Executed 0 tests` or `No result` at the app target level.

## Build

```bash
tuist install
tuist generate --no-open
xcodebuild build -workspace shadow-client.xcworkspace -scheme ShadowClientmacOS -destination 'platform=macOS'
xcodebuild build -workspace shadow-client.xcworkspace -scheme ShadowClientTests -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
cd Modules && swift test
```

## Repository Layout

- `Project.swift`, `Tuist.swift`, `Tuist/Package.swift`: Tuist manifests and package wiring
- `Projects/App/iOS`, `Projects/App/macOS`, `Projects/App/tvOS`: platform entrypoints
- `Projects/App/Features/Home`: app shell, session runtime integration, protocol/client implementation, and platform glue
- `Projects/App/Tests`: app-level Swift Testing suites and compile-gate coverage
- `Modules/ShadowClientCore`, `Modules/ShadowClientStreaming`, `Modules/ShadowClientInput`, `Modules/ShadowClientUI`: reusable package modules
- `external/`: upstream reference trees only, intentionally not tracked in this public repository

## Dependencies

- `SwiftOpus` is consumed as a sibling checkout because the project treats it as a separate source-of-truth repository.
- The GitHub Actions workflow checks out `Skyline-23/SwiftOpus` into the expected sibling path before generating the workspace.

## Public Repository Notes

- `external/` is ignored and not intended to be published from this repository.
- Local agent instructions such as `AGENTS.md` are not tracked in the public repo.
- Runtime logs and issue reports should avoid including private hostnames, certificates, or pairing material.

## Debugging Focus Areas

Current high-priority debugging areas:

- Sunshine control/path parity with Moonlight
- Video recovery request semantics
- AV1 and HEVC decoder recovery under loss
- FEC reconstruction behavior
- Audio queue pressure and frame pacing under load

## Filing Issues

When reporting a bug, include:

- client platform and OS version
- host OS
- Sunshine version/commit
- selected codec
- HDR on/off
- fullscreen/borderless/windowed mode
- whether the failure happens after inactivity, fullscreen changes, or Space changes
- relevant client and host logs

Use the bundled issue template for consistency.
