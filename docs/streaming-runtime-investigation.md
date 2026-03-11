# Streaming Runtime Investigation

## Current state

- No uncommitted test-file changes remain under `Projects/App/Tests`.
- Host lists now remain visible from local cached descriptors before discovery completes.
- Resume is guarded by a local session fingerprint so an active game launched from another device is force-relaunched instead of blindly resumed.
- GameStream HTTP timeout failures now include the request stage label in the error text.

## Remaining issues

### 1. AV1 over WAN is unstable under burst loss

Observed symptoms:

- Frequent `Video FEC reconstruction dropped unrecoverable block`
- Immediate AV1 sync-gate transitions and recovery requests
- Visible flicker/corruption after packet loss

Current understanding:

- The primary failure is network burst loss, not codec selection.
- The current mitigations reduce how long corrupted frames remain visible, but do not prevent AV1 degradation on lossy links.

Next steps:

- Add adaptive bitrate/FPS downshift when unrecoverable FEC bursts repeat.
- Revisit AV1 recovery thresholds after the transport side is less lossy.

### 2. SDR brightness / washed-out presentation on iPad

Observed evidence from frame dumps:

- Input frames arrive as SDR BT.709 (`420f`, primaries/transfer/matrix all 709).
- `CI` output matches the final drawable sample, so the last app-side presentation step is not introducing the brightness shift.
- The issue is still visible on device despite matching renderer/drawable samples.

Current understanding:

- The remaining mismatch is likely upstream of final presentation:
  - decoder output characteristics
  - source content / host-side conversion
  - a device-specific display transform not exposed in the current logging

Next steps:

- Compare the same scene across AV1 / HEVC / H.264 on the same device.
- Sample multiple points (highlights, midtones, shadows) from the same frame instead of only the center pixel.
- If the issue reproduces only on one codec, focus on decoder output investigation rather than surface rendering.

### 3. macOS connection failures before pairing/launch

Observed symptoms:

- `-1001` timeouts before pairing or launch
- `RTSP transport connection closed` / `No message available on STREAM`
- Benign `ViewBridge` / task port diagnostics mixed into the logs

Current understanding:

- The meaningful failure is the timeout/transport closure, not the `ViewBridge` noise.
- Timeout logs now identify the exact request stage, which should make the next failure actionable.

Next steps:

- Capture the first staged timeout message on macOS after the new logging lands.
- Separate metadata timeout failures from RTSP transport failures before changing retry policy.

## Debugging hooks kept in place

- iOS frame dump logs include:
  - pixel format
  - color attachments
  - plane min/max
  - center YUV sample
  - CI average / center RGBA
  - drawable center RGBA
- These hooks are intended to stay temporary until the SDR brightness investigation is complete.
