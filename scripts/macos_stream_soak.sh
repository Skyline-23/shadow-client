#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AX_SCRIPT="$ROOT_DIR/scripts/macos_ax.swift"

XCODEBUILDMCP_BIN="${XCODEBUILDMCP_BIN:-xcodebuildmcp}"
WORKSPACE_PATH="${SC_WORKSPACE_PATH:-$ROOT_DIR/shadow-client.xcworkspace}"
SCHEME_NAME="${SC_SCHEME_NAME:-ShadowClientmacOS}"
TARGET_HOST="${SC_TARGET_HOST:-Example-PC.local}"
OUTPUT_DIR="${SC_OUTPUT_DIR:-$ROOT_DIR/Derived/macos-soak}"
SOAK_SECONDS="${SC_SOAK_SECONDS:-90}"
WIGGLE_INTERVAL_MS="${SC_WIGGLE_INTERVAL_MS:-24}"
WIGGLE_AMPLITUDE="${SC_WIGGLE_AMPLITUDE:-28}"
APP_BOOT_TIMEOUT="${SC_APP_BOOT_TIMEOUT:-25}"
AX_TIMEOUT="${SC_AX_TIMEOUT:-12}"
WINDOW_READY_TIMEOUT="${SC_WINDOW_READY_TIMEOUT:-15}"
REQUIRE_STREAM="${SC_REQUIRE_STREAM:-1}"
REQUIRE_LAUNCH="${SC_REQUIRE_LAUNCH:-1}"
LOG_PREDICATE="${SC_LOG_PREDICATE:-subsystem == \"com.skyline23.shadow-client\"}"

mkdir -p "$OUTPUT_DIR"

RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$OUTPUT_DIR/macos-soak-$RUN_ID.log"
BUILD_JSON="$OUTPUT_DIR/macos-build-$RUN_ID.json"
APP_INFO_JSON="$OUTPUT_DIR/macos-app-info-$RUN_ID.json"
REPORT_JSON="$OUTPUT_DIR/macos-report-$RUN_ID.json"
REPORT_TXT="$OUTPUT_DIR/macos-report-$RUN_ID.txt"
PRE_SCREENSHOT="$OUTPUT_DIR/macos-pre-$RUN_ID.png"
POST_SCREENSHOT="$OUTPUT_DIR/macos-post-$RUN_ID.png"

log_pid=""
app_name=""
bundle_id=""
connection_status=""

log_step() {
    printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*"
}

mcp_json() {
    "$XCODEBUILDMCP_BIN" --style minimal "$@" --output json
}

flatten_mcp_text() {
    jq -r '.content[]?.text // empty'
}

ax_call() {
    swift "$AX_SCRIPT" "$@"
}

ax_wait_id_or_text() {
    local id="$1"
    local contains="$2"
    local role="${3:-}"
    if ax_call wait-id --bundle-id "$bundle_id" --id "$id" --timeout "$AX_TIMEOUT" >/dev/null 2>&1; then
        ax_call wait-id --bundle-id "$bundle_id" --id "$id" --timeout "$AX_TIMEOUT"
        return
    fi
    if [[ -n "$role" ]]; then
        ax_call find-text --bundle-id "$bundle_id" --contains "$contains" --role "$role" --timeout "$AX_TIMEOUT" >/dev/null
    else
        ax_call find-text --bundle-id "$bundle_id" --contains "$contains" --timeout "$AX_TIMEOUT" >/dev/null
    fi
}

ax_tap_id_or_text() {
    local id="$1"
    local contains="$2"
    local role="${3:-AXButton}"
    if ax_call tap-id --bundle-id "$bundle_id" --id "$id" --timeout "$AX_TIMEOUT" >/dev/null 2>&1; then
        ax_call tap-id --bundle-id "$bundle_id" --id "$id" --timeout "$AX_TIMEOUT"
        return
    fi
    ax_call tap-text --bundle-id "$bundle_id" --contains "$contains" --role "$role" --timeout "$AX_TIMEOUT"
}

cleanup() {
    if [[ -n "$log_pid" ]] && kill -0 "$log_pid" 2>/dev/null; then
        kill "$log_pid" >/dev/null 2>&1 || true
        wait "$log_pid" 2>/dev/null || true
    fi
}

trap cleanup EXIT

count_pattern() {
    local pattern="$1"
    if [[ ! -f "$LOG_FILE" ]]; then
        printf '0'
        return
    fi
    local count
    count="$(rg -N -c --regexp "$pattern" "$LOG_FILE" 2>/dev/null || true)"
    if [[ -z "$count" ]]; then
        printf '0'
    else
        printf '%s' "$count"
    fi
}

array_to_json() {
    if [[ "$#" -eq 0 ]]; then
        printf '[]'
        return
    fi
    printf '%s\n' "$@" | jq -R . | jq -s .
}

if [[ ! -f "$AX_SCRIPT" ]]; then
    echo "error: AX helper script not found at $AX_SCRIPT" >&2
    exit 1
fi

log_step "Resolving target host: $TARGET_HOST"
host_lookup="$(dscacheutil -q host -a name "$TARGET_HOST" 2>/dev/null || true)"
if [[ -n "$host_lookup" ]]; then
    printf '%s\n' "$host_lookup" | sed -n '1,20p'
else
    log_step "warning: host lookup returned no result for $TARGET_HOST"
fi

log_step "Building and running macOS app ($SCHEME_NAME)"
mcp_json macos build-and-run --workspace-path "$WORKSPACE_PATH" --scheme "$SCHEME_NAME" >"$BUILD_JSON"

log_step "Resolving app path and bundle id"
app_path="$(mcp_json macos get-app-path --workspace-path "$WORKSPACE_PATH" --scheme "$SCHEME_NAME" \
    | flatten_mcp_text \
    | sed -n 's/^✅ App path retrieved successfully: //p' \
    | tail -n 1)"

if [[ -z "$app_path" ]]; then
    echo "error: failed to resolve macOS app path" >&2
    exit 1
fi

mcp_json macos get-macos-bundle-id --app-path "$app_path" >"$APP_INFO_JSON"
bundle_id="$(flatten_mcp_text <"$APP_INFO_JSON" | sed -n 's/^✅ Bundle ID: //p' | tr -d '\r' | tail -n 1)"
app_name="$(basename "$app_path" .app)"

if [[ -z "$bundle_id" ]]; then
    echo "error: failed to resolve macOS bundle id" >&2
    exit 1
fi

log_step "App: $app_name ($bundle_id)"

log_step "Activating app and waiting for visible window"
open -a "$app_path" >/dev/null 2>&1 || true
osascript -e "tell application id \"$bundle_id\" to activate" >/dev/null 2>&1 || true

window_ready_deadline=$((SECONDS + WINDOW_READY_TIMEOUT))
window_count=0
while (( SECONDS < window_ready_deadline )); do
    window_count="$(ax_call window-count --bundle-id "$bundle_id" --timeout 2 2>/dev/null || echo 0)"
    if [[ "$window_count" =~ ^[0-9]+$ ]] && (( window_count > 0 )); then
        break
    fi
    sleep 1
done

if ! [[ "$window_count" =~ ^[0-9]+$ ]] || (( window_count == 0 )); then
    echo "error: app window is not visible (window-count=$window_count). Ensure macOS desktop is unlocked and app has window focus." >&2
    exit 3
fi

log_step "Starting structured log capture"
log stream --style compact --predicate "$LOG_PREDICATE" >"$LOG_FILE" 2>&1 &
log_pid="$!"
sleep 1

log_step "Waiting for app root accessibility node"
if ax_call wait-id --bundle-id "$bundle_id" --id shadow.root.tabview --timeout "$APP_BOOT_TIMEOUT" >/dev/null 2>&1; then
    ax_call wait-id --bundle-id "$bundle_id" --id shadow.root.tabview --timeout "$APP_BOOT_TIMEOUT"
elif ax_call find-text --bundle-id "$bundle_id" --contains "Remote Desktop Hosts" --timeout "$APP_BOOT_TIMEOUT" >/dev/null 2>&1; then
    log_step "Root tabview id not exposed; continuing with text-based AX lookup"
else
    log_step "warning: app root accessibility node not detected within timeout"
fi

log_step "Capturing pre-run screenshot"
/usr/sbin/screencapture -x "$PRE_SCREENSHOT" || true

log_step "Refreshing hosts and connecting"
ax_tap_id_or_text shadow.tab.home "Home"
ax_wait_id_or_text shadow.home.hosts.card "Remote Desktop Hosts"
ax_tap_id_or_text shadow.home.hosts.refresh "Refresh"
sleep 1

if ! ax_call tap-prefix --bundle-id "$bundle_id" --prefix shadow.home.host. --suffix .use --timeout "$AX_TIMEOUT"; then
    log_step "warning: host 'Use' tap failed (continuing with direct connect)"
fi

if ! ax_call tap-prefix --bundle-id "$bundle_id" --prefix shadow.home.host. --suffix .connect --timeout "$AX_TIMEOUT"; then
    ax_call tap-text --bundle-id "$bundle_id" --contains "Connect" --role AXButton --timeout "$AX_TIMEOUT"
fi
sleep 3

connection_raw="$(
    ax_call get-id --bundle-id "$bundle_id" --id shadow.home.connection-status --timeout "$AX_TIMEOUT" 2>/dev/null \
    | sed -n 's/^value=//p' \
    | tail -n 1 || true
)"
if [[ -n "$connection_raw" ]]; then
    connection_status="$connection_raw"
else
    connection_status="$(
        ax_call find-text --bundle-id "$bundle_id" --contains "Status:" --field value --timeout "$AX_TIMEOUT" 2>/dev/null \
        | sed -n 's/^value=//p' \
        | head -n 1 || true
    )"
fi
log_step "Connection status: ${connection_status:-<empty>}"

if [[ "$REQUIRE_LAUNCH" == "1" ]]; then
    log_step "Refreshing app list and launching first app"
    if ! ax_call tap-id --bundle-id "$bundle_id" --id shadow.home.applist.refresh --timeout "$AX_TIMEOUT"; then
        ax_call tap-text --bundle-id "$bundle_id" --contains "Refresh Host App Library" --timeout "$AX_TIMEOUT"
    fi
    sleep 2
    if ! ax_call tap-prefix --bundle-id "$bundle_id" --prefix shadow.home.applist.launch. --timeout "$AX_TIMEOUT"; then
        ax_call tap-text --bundle-id "$bundle_id" --contains "Launch" --role AXButton --timeout "$AX_TIMEOUT"
    fi
fi

if [[ "$REQUIRE_STREAM" == "1" ]]; then
    log_step "Waiting for remote session surface"
    if ! ax_call wait-id --bundle-id "$bundle_id" --id shadow.remote.session.surface --timeout 20 >/dev/null 2>&1; then
        if ! ax_call find-text --bundle-id "$bundle_id" --contains "Remote Session Surface" --timeout 20 >/dev/null 2>&1; then
            ax_call find-text --bundle-id "$bundle_id" --contains "Remote Session" --timeout 20 >/dev/null
        fi
    fi
    log_step "Running pointer wiggle stress for ${SOAK_SECONDS}s"
    if ! ax_call wiggle-id \
        --bundle-id "$bundle_id" \
        --id shadow.remote.session.surface \
        --seconds "$SOAK_SECONDS" \
        --interval-ms "$WIGGLE_INTERVAL_MS" \
        --amplitude "$WIGGLE_AMPLITUDE" \
        --timeout 20; then
        if ! ax_call wiggle-text \
            --bundle-id "$bundle_id" \
            --contains "Remote Session Surface" \
            --seconds "$SOAK_SECONDS" \
            --interval-ms "$WIGGLE_INTERVAL_MS" \
            --amplitude "$WIGGLE_AMPLITUDE" \
            --timeout 20; then
            ax_call wiggle-text \
                --bundle-id "$bundle_id" \
                --contains "Remote Session" \
                --seconds "$SOAK_SECONDS" \
                --interval-ms "$WIGGLE_INTERVAL_MS" \
                --amplitude "$WIGGLE_AMPLITUDE" \
                --timeout 20
        fi
    fi
else
    log_step "REQUIRE_STREAM=0, running wiggle on host card"
    if ! ax_call wiggle-id \
        --bundle-id "$bundle_id" \
        --id shadow.home.hosts.card \
        --seconds "$SOAK_SECONDS" \
        --interval-ms "$WIGGLE_INTERVAL_MS" \
        --amplitude "$WIGGLE_AMPLITUDE" \
        --timeout 12; then
        ax_call wiggle-text \
            --bundle-id "$bundle_id" \
            --contains "Remote Desktop Hosts" \
            --seconds "$SOAK_SECONDS" \
            --interval-ms "$WIGGLE_INTERVAL_MS" \
            --amplitude "$WIGGLE_AMPLITUDE" \
            --timeout 12
    fi
fi

log_step "Capturing post-run screenshot"
/usr/sbin/screencapture -x "$POST_SCREENSHOT" || true

log_step "Stopping app"
mcp_json macos stop --app-name "$app_name" >/dev/null || true
sleep 1

cleanup
trap - EXIT

launch_decision_count="$(count_pattern 'Launch decision verb=')"
rtsp_play_ok_count="$(count_pattern 'RTSP PLAY ok|RTSP PLAY <- status 200')"
first_video_datagram_count="$(count_pattern 'First UDP video datagram received')"
first_frame_metadata_count="$(count_pattern 'Decoded first frame metadata')"
pointer_moved_emit_count="$(count_pattern 'Input capture emitting pointerMoved')"
pointer_moved_send_count="$(count_pattern 'Sunshine input send enabled for event pointerMoved')"
audio_queue_pressure_count="$(count_pattern 'Audio output queue pressure detected')"
audio_payload_mismatch_count="$(count_pattern 'Audio RTP payload mismatch summary')"
video_decode_fail_count="$(count_pattern 'av1 decode failed|h265 decode failed|h264 decode failed')"
fatal_runtime_count="$(count_pattern 'Runtime recovery exhausted|Video decoder reported fatal failure|Session runtime failed|rendering failed')"

fail_reasons=()
warn_reasons=()

if [[ "$REQUIRE_STREAM" == "1" && "$first_video_datagram_count" -eq 0 ]]; then
    fail_reasons+=("No first UDP video datagram log was observed")
fi
if [[ "$REQUIRE_STREAM" == "1" && "$first_frame_metadata_count" -eq 0 ]]; then
    fail_reasons+=("No decoded first frame metadata log was observed")
fi
if [[ "$pointer_moved_emit_count" -eq 0 && "$pointer_moved_send_count" -eq 0 ]]; then
    fail_reasons+=("No pointerMoved input emission/send log was observed during wiggle")
fi
if [[ "$fatal_runtime_count" -gt 0 ]]; then
    fail_reasons+=("Fatal runtime recovery/error pattern detected ($fatal_runtime_count)")
fi
if [[ -n "$connection_status" && "$connection_status" != *"Connected"* ]]; then
    fail_reasons+=("Connection status is not connected: ${connection_status:-<empty>}")
fi

if [[ "$video_decode_fail_count" -gt 0 ]]; then
    warn_reasons+=("Video decode failure logs detected ($video_decode_fail_count)")
fi
if [[ "$audio_queue_pressure_count" -gt 0 ]]; then
    warn_reasons+=("Audio queue pressure logs detected ($audio_queue_pressure_count)")
fi
if [[ "$audio_payload_mismatch_count" -gt 0 ]]; then
    warn_reasons+=("Audio RTP payload mismatch logs detected ($audio_payload_mismatch_count)")
fi
if [[ "$rtsp_play_ok_count" -eq 0 ]]; then
    warn_reasons+=("No RTSP PLAY ok log observed")
fi
if [[ "$launch_decision_count" -eq 0 ]]; then
    warn_reasons+=("No launch decision log observed")
fi
if [[ -z "$connection_status" ]]; then
    warn_reasons+=("Connection status node was not readable from macOS accessibility tree")
fi

result="PASS"
exit_code=0
if [[ "${#fail_reasons[@]}" -gt 0 ]]; then
    result="FAIL"
    exit_code=2
elif [[ "${#warn_reasons[@]}" -gt 0 ]]; then
    result="WARN"
fi

fail_json="$(array_to_json "${fail_reasons[@]}")"
warn_json="$(array_to_json "${warn_reasons[@]}")"

jq -n \
    --arg run_id "$RUN_ID" \
    --arg result "$result" \
    --arg scheme "$SCHEME_NAME" \
    --arg workspace "$WORKSPACE_PATH" \
    --arg bundle_id "$bundle_id" \
    --arg app_name "$app_name" \
    --arg target_host "$TARGET_HOST" \
    --arg connection_status "$connection_status" \
    --arg log_file "$LOG_FILE" \
    --arg pre_screenshot "$PRE_SCREENSHOT" \
    --arg post_screenshot "$POST_SCREENSHOT" \
    --argjson launch_decision_count "$launch_decision_count" \
    --argjson rtsp_play_ok_count "$rtsp_play_ok_count" \
    --argjson first_video_datagram_count "$first_video_datagram_count" \
    --argjson first_frame_metadata_count "$first_frame_metadata_count" \
    --argjson pointer_moved_emit_count "$pointer_moved_emit_count" \
    --argjson pointer_moved_send_count "$pointer_moved_send_count" \
    --argjson audio_queue_pressure_count "$audio_queue_pressure_count" \
    --argjson audio_payload_mismatch_count "$audio_payload_mismatch_count" \
    --argjson video_decode_fail_count "$video_decode_fail_count" \
    --argjson fatal_runtime_count "$fatal_runtime_count" \
    --argjson fail_reasons "$fail_json" \
    --argjson warn_reasons "$warn_json" \
    '{
        runID: $run_id,
        result: $result,
        scheme: $scheme,
        workspace: $workspace,
        bundleID: $bundle_id,
        appName: $app_name,
        targetHost: $target_host,
        connectionStatus: $connection_status,
        artifacts: {
            logFile: $log_file,
            preScreenshot: $pre_screenshot,
            postScreenshot: $post_screenshot
        },
        metrics: {
            launchDecisionCount: $launch_decision_count,
            rtspPlayOKCount: $rtsp_play_ok_count,
            firstVideoDatagramCount: $first_video_datagram_count,
            firstFrameMetadataCount: $first_frame_metadata_count,
            pointerMovedEmitCount: $pointer_moved_emit_count,
            pointerMovedSendCount: $pointer_moved_send_count,
            audioQueuePressureCount: $audio_queue_pressure_count,
            audioPayloadMismatchCount: $audio_payload_mismatch_count,
            videoDecodeFailCount: $video_decode_fail_count,
            fatalRuntimeCount: $fatal_runtime_count
        },
        failReasons: $fail_reasons,
        warnReasons: $warn_reasons
    }' >"$REPORT_JSON"

{
    echo "result=$result"
    echo "run_id=$RUN_ID"
    echo "target_host=$TARGET_HOST"
    echo "bundle_id=$bundle_id"
    echo "connection_status=${connection_status:-<empty>}"
    echo "launch_decision_count=$launch_decision_count"
    echo "rtsp_play_ok_count=$rtsp_play_ok_count"
    echo "first_video_datagram_count=$first_video_datagram_count"
    echo "first_frame_metadata_count=$first_frame_metadata_count"
    echo "pointer_moved_emit_count=$pointer_moved_emit_count"
    echo "pointer_moved_send_count=$pointer_moved_send_count"
    echo "audio_queue_pressure_count=$audio_queue_pressure_count"
    echo "audio_payload_mismatch_count=$audio_payload_mismatch_count"
    echo "video_decode_fail_count=$video_decode_fail_count"
    echo "fatal_runtime_count=$fatal_runtime_count"
    echo "report_json=$REPORT_JSON"
    echo "log_file=$LOG_FILE"
    echo "pre_screenshot=$PRE_SCREENSHOT"
    echo "post_screenshot=$POST_SCREENSHOT"
    if [[ "${#fail_reasons[@]}" -gt 0 ]]; then
        echo "fail_reasons:"
        printf '  - %s\n' "${fail_reasons[@]}"
    fi
    if [[ "${#warn_reasons[@]}" -gt 0 ]]; then
        echo "warn_reasons:"
        printf '  - %s\n' "${warn_reasons[@]}"
    fi
} >"$REPORT_TXT"

cat "$REPORT_TXT"
exit "$exit_code"
