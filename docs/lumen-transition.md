# Lumen Transition

## Local checkout

- Lumen repository cloned separately during migration work
- Remote: `https://github.com/Skyline-23/Lumen`
- Recent rename cadence verified from the Lumen commit history before updating this client

## Initial findings

- Lumen is not a clean protocol break from its Sunshine-derived host core yet.
  - The host still contains many `sunshine_*` internal symbols and config paths.
  - Core streaming still uses the same RTSP + ENet control structure.
- Lumen adds host-side functionality we care about.
  - Clipboard permission handling is visible in the Lumen control/runtime paths.
  - Display/HDR/virtual display handling is visible in the Lumen RTSP and display paths.
  - Colorspace logic remains in the host video colorspace pipeline.
- This means we can treat Lumen as the primary host target, then layer Lumen-specific capabilities on top.

## Client impact

- Our client is still tightly coupled to legacy-host-named protocol/runtime layers.
  - `Projects/App/Features/Home/Sources/ShadowClientRealtimeRTSPSessionRuntime.swift`
  - `Projects/App/Features/Home/Sources/ShadowClientHostControlChannelRuntime.swift`
  - `Projects/App/Features/Home/Sources/ShadowClientHostProtocolProfile.swift`
  - `Projects/App/Features/Home/Sources/ShadowClientHostInputPacketCodec.swift`
- User-facing branding and control contracts now move to Lumen, and internal protocol types should follow.

## Immediate migration steps

1. Keep Lumen as the primary host target and stop optimizing behavior around legacy-host-specific quirks unless Lumen still requires them.
2. Extract a neutral host-protocol layer from the current legacy host runtime types so Lumen-specific features can be added without spreading more `legacy host` naming.
3. Audit Lumen host capabilities we actually want to consume first:
   - clipboard sync
   - permission negotiation
   - HDR / display mode handling
   - virtual display behavior
4. Validate current client compatibility against Lumen before deleting legacy-host-specific logic.

## Known Lumen source entry points

- `src/rtsp.cpp`
- `src/stream.cpp`
- `src/video_colorspace.cpp`
- `src/display_device.cpp`
- `src/config.cpp`
