# Embedded Stream Runtime

Place the stream runtime executable at:

`Projects/App/Features/Home/Runtime/moonlight`

Requirements:

- executable bit enabled (`chmod +x moonlight`)
- binary must support command shape:
  - `moonlight list <host>`

Optional override:

- set `SHADOW_CLIENT_MOONLIGHT_BIN` to an absolute executable path.

The app no longer requires a globally installed `moonlight-qt` binary for host probe.
