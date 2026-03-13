# Apollo Transition

## Local checkout

- Apollo repository cloned to `external/apollo`
- Remote: `https://github.com/ClassicOldSong/Apollo`
- Checked out revision: `a40b1798`

## Initial findings

- Apollo is not a clean protocol break from Sunshine yet.
  - The host still contains many `sunshine_*` internal symbols and config paths.
  - Core streaming still uses the same RTSP + ENet control structure.
- Apollo adds host-side functionality we care about.
  - Clipboard permission handling is visible in `external/apollo/src/stream.cpp`
  - Display/HDR/virtual display handling is visible in `external/apollo/src/display_device.cpp`
  - Colorspace logic remains in `external/apollo/src/video_colorspace.cpp`
- This means we can treat Apollo as a Sunshine-derived host during migration, then layer Apollo-specific capabilities on top.

## Client impact

- Our client is still tightly coupled to Sunshine-named protocol/runtime layers.
  - `Projects/App/Features/Home/Sources/ShadowClientRealtimeRTSPSessionRuntime.swift`
  - `Projects/App/Features/Home/Sources/ShadowClientSunshineControlChannelRuntime.swift`
  - `Projects/App/Features/Home/Sources/ShadowClientSunshineProtocolProfile.swift`
  - `Projects/App/Features/Home/Sources/ShadowClientSunshineInputPacketCodec.swift`
- User-facing branding has started moving to Apollo, but internal protocol types are still Sunshine-named.

## Immediate migration steps

1. Keep Apollo as the primary host target and stop optimizing behavior around Sunshine-specific quirks unless Apollo still requires them.
2. Extract a neutral host-protocol layer from the current Sunshine runtime types so Apollo-specific features can be added without spreading more `Sunshine*` naming.
3. Audit Apollo host capabilities we actually want to consume first:
   - clipboard sync
   - permission negotiation
   - HDR / display mode handling
   - virtual display behavior
4. Validate current client compatibility against Apollo before deleting Sunshine-specific logic.

## Known Apollo source entry points

- `external/apollo/src/rtsp.cpp`
- `external/apollo/src/stream.cpp`
- `external/apollo/src/video_colorspace.cpp`
- `external/apollo/src/display_device.cpp`
- `external/apollo/src/config.cpp`
