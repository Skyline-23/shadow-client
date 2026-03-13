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

Latest reproduced sessions:

- Before fixing Apollo host colorspace signaling:
  - Actual session codec is HEVC, not AV1.
  - First decoded frame metadata:
    - `pixel-format=0x34323076`
    - `primaries=SMPTE_C`
    - `transfer=ITU_R_709_2`
    - `matrix=ITU_R_601_4`
  - Active render path:
    - `YUV Metal pipeline loaded bundled Metal library`
    - `Surface render path=metal-yuv pixel-format=0x34323076`
  - YUV Metal diagnostics from the same frame:
    - `source-standard=rec601`
    - `range=limited`
    - `bit-depth=8`
    - `chroma-location=Left`
    - `csc-row0=[1.164384,0.000000,1.596027]`
    - `csc-row1=[1.164384,-0.391721,-0.812926]`
    - `csc-row2=[1.164384,2.017232,0.000000]`
    - `offsets=[0.062745,0.501961,0.501961]`
    - `chroma-offset=[0.500000,0.000000]`
  - Sample comparison from the same frame:
    - CPU-predicted CSC sample:
      - `tl=Y232/Cb130/Cr122->RGB[242,255,255]`
      - `tr=Y230/Cb131/Cr119->RGB[235,255,255]`
      - `c=Y82/Cb216/Cr86->RGB[10,77,254]`
      - `bl=Y235/Cb128/Cr128->RGB[255,255,255]`
      - `br=Y235/Cb128/Cr128->RGB[255,255,255]`
    - Final drawable sample:
      - `tl=239,255,254,255`
      - `tr=232,255,254,255`
      - `c=8,77,255,255`
      - `bl=255,255,255,255`
      - `br=254,254,254,255`
- After fixing Apollo host `encoderCscMode` request to `Rec.709 limited`:
  - Apollo host source review:
    - `external/sunshine/src/video.h` defines `encoderCscMode`
    - `external/sunshine/src/rtsp.cpp` stores the announced value
    - `external/sunshine/src/video_colorspace.cpp` maps the value into the common colorspace enum
    - `external/sunshine/src/video.cpp` and `external/sunshine/src/nvenc/nvenc_base.cpp` apply it for both HEVC and AV1
  - Actual reproduced AV1 session after the request fix:
    - `pixel-format=0x34323066`
    - `primaries=ITU_R_709_2`
    - `transfer=ITU_R_709_2`
    - `matrix=ITU_R_709_2`
  - Active render path:
    - `YUV Metal pipeline loaded bundled Metal library`
    - `Surface render path=metal-yuv pixel-format=0x34323066`
  - YUV Metal diagnostics from the same frame:
    - `source-standard=rec709`
    - `range=full`
    - `bit-depth=8`
    - `chroma-location=nil`
    - `csc-row0=[1.000000,0.000000,1.574800]`
    - `csc-row1=[1.000000,-0.187300,-0.468100]`
    - `csc-row2=[1.000000,1.855600,0.000000]`
    - `offsets=[0.000000,0.501961,0.501961]`
    - `chroma-offset=[0.500000,0.000000]`
  - Sample comparison from the same frame:
    - CPU-predicted CSC sample:
      - `tl=Y252/Cb129/Cr121->RGB[241,255,254]`
      - `tr=Y249/Cb130/Cr118->RGB[233,253,253]`
      - `c=Y75/Cb225/Cr85->RGB[7,77,255]`
      - `bl=Y254/Cb128/Cr128->RGB[254,254,254]`
      - `br=Y254/Cb128/Cr128->RGB[254,254,254]`
    - Final drawable sample:
      - `tl=238,253,252,255`
      - `tr=232,254,253,255`
      - `c=7,77,255,255`
      - `bl=254,254,254,255`
      - `br=255,255,255,255`

Excluded by logs:

- Not a final drawable-only problem.
  - In both HEVC and AV1 reproductions, the CPU-predicted CSC result and the drawable sample are nearly identical.
- Not a Core Image fallback problem.
  - The reproduced path is `metal-yuv`, not `core-image`.
- Not an AV1-specific problem.
  - The same over-bright behavior reproduces in HEVC and AV1 sessions.
- Not a simple codec-selection mismatch.
  - HEVC reproductions announce and decode as `h265`; AV1 reproductions announce and decode as `av1`.
- Not the old Apollo-host `encoderCscMode=0` request alone.
  - Fixing the request changed AV1 metadata to `709/709/709`, but the over-bright presentation remained.
- Not an HDR / EDR presentation path inside the client.
  - The affected sessions are `hdr=false`.
- Not a missing chroma siting adjustment.
  - `chroma-offset=[0.500000,0.000000]` is applied and logged.
- Not a mismatch in the current app-side CSC constants or range expansion.
  - Logged coefficients match the selected Rec.601 limited and Rec.709 full-range paths, and predicted RGB matches the drawable.

Current understanding:

- The client-side Metal YUV path is currently behaving consistently with the decoded buffers it receives.
- The remaining likely causes are now upstream or host/display-facing:
  - decoder-provided YUV content is already brighter than expected before client-side presentation
  - Apollo host's Windows capture / colorspace conversion path is emitting brighter SDR content than expected
  - host Windows HDR / Advanced Color is affecting Apollo capture through the scRGB path
  - SDR output colorspace labeling / display interpretation still differs from Moonlight in a way that only shows up on-device

Next steps:

- Reproduce the same scene with host Windows HDR / Advanced Color disabled and compare brightness immediately.
- If the issue changes with host HDR off, log Apollo's Windows capture format and verify whether the host is going through the scRGB capture/conversion path.
- Compare the same scene against Moonlight on the same hardware, if available, using the same stream settings.
- If the issue persists even with host HDR off, re-check the client SDR output colorspace choice against Moonlight for the same stream metadata.

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
