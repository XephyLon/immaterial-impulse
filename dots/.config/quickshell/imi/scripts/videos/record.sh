#!/usr/bin/env bash
# One-shot screen recorder on gpu-screen-recorder (GPU encode - NVENC/VAAPI).
# Replaces the old CPU-encoding implementation with the same interface:
#   record.sh [--fullscreen] [--sound] [--region "X,Y WxH"] [--path DIR]
# Toggle semantics: if a recording started by this script is running, stop it
# (SIGINT = gsr finishes and saves the file). Encoder options come from the
# shell config (screenRecord.*); the ScreenRecord service owns replay mode.
set -o pipefail

CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/immaterial-impulse/config.json"
STATE_FILE="$HOME/.local/state/quickshell/states.json"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
PIDFILE="$RUNTIME_DIR/imi-screenrecord.pid"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cfg() { jq -r "$1 // empty" "$CONFIG_FILE" 2>/dev/null; }

set_recording_state() {
    local state=$1 tmp
    mkdir -p "$(dirname "$STATE_FILE")"
    [[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"
    tmp=$(mktemp)
    jq ".record.enable = $state" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# Toggle: a recording we started is running -> stop it gracefully and exit.
# The pidfile scopes the toggle to OUR recording, never the replay daemon
# (both are gpu-screen-recorder processes - killing by process name would hit both).
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    kill -INT "$(cat "$PIDFILE")"
    exit 0
fi
rm -f "$PIDFILE"

SOUND=0
FULLSCREEN=0
REGION=""
SAVE_DIR=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sound) SOUND=1 ;;
        --fullscreen) FULLSCREEN=1 ;;
        --region) REGION="$2"; shift ;;
        --path) SAVE_DIR="$2"; shift ;;
    esac
    shift
done

[[ -n "$SAVE_DIR" ]] || SAVE_DIR="$(cfg '.screenRecord.savePath')"
[[ -n "$SAVE_DIR" ]] || SAVE_DIR="$HOME/Videos"
SAVE_DIR="${SAVE_DIR/#\~/$HOME}"
mkdir -p "$SAVE_DIR"

FPS="$(cfg '.screenRecord.fps')";                       FPS="${FPS:-60}"
QUALITY="$(cfg '.screenRecord.quality')";               QUALITY="${QUALITY:-very_high}"
CODEC="$(cfg '.screenRecord.codec')"
AUDIO_CODEC="$(cfg '.screenRecord.audioCodec')";        AUDIO_CODEC="${AUDIO_CODEC:-opus}"
CURSOR="$(cfg '.screenRecord.showCursor')"
FRAMERATE_MODE="$(cfg '.screenRecord.framerateMode')";  FRAMERATE_MODE="${FRAMERATE_MODE:-vfr}"
MIC="$(cfg '.screenRecord.recordMic')"

OUT="$SAVE_DIR/recording_$(date '+%Y-%m-%d_%H.%M.%S').mp4"

# Resolved before the codec, so HDR detection has a monitor to ask about. A
# region capture is attributed to the focused monitor: slurp can straddle
# outputs, and short of asking gsr which one it settled on, "the monitor the
# user was looking at" is the best available answer.
TARGET_MONITOR="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .name' 2>/dev/null)"

# Hyprland's colorManagementPreset is the authoritative HDR signal - its HDR
# presets are "hdr" and "hdredid". currentFormat is not: XBGR2101010 only says
# the framebuffer is 10-bit, which is equally true of wide-gamut SDR.
monitor_is_hdr() {
    local name="$1"
    [[ -n "$name" ]] || return 1
    hyprctl monitors -j 2>/dev/null \
        | jq -e --arg m "$name" \
            'any(.[]; .name == $m and ((.colorManagementPreset // "") | startswith("hdr")))' \
            >/dev/null 2>&1
}

# gpu-screen-recorder does not tonemap. Given an HDR surface and an SDR codec it
# encodes 8-bit and tags the result bt709, so a PQ signal ends up labelled as
# gamma - and decodes flat, grey and desaturated. The _hdr codec variants carry
# the real transfer function and primaries, so the file is correct in anything
# that reads them.
if monitor_is_hdr "$TARGET_MONITOR"; then
    case "$CODEC" in
        ""|auto|hevc) CODEC="hevc_hdr" ;;
        av1)          CODEC="av1_hdr" ;;
        h264)
            # H.264 has no HDR variant here. Silently swapping the codec someone
            # explicitly chose is worse than saying why the file will look wrong.
            notify-send "Recording SDR H.264 on an HDR display" \
                "H.264 cannot carry HDR, so this recording will look washed out. Pick HEVC or AV1, or turn HDR off while recording." \
                -a 'Recorder' & disown
            ;;
    esac
fi

ARGS=(gpu-screen-recorder -c mp4 -f "$FPS" -q "$QUALITY" -ac "$AUDIO_CODEC"
      -fm "$FRAMERATE_MODE" -sc "$SCRIPT_DIR/gsr-saved.sh" -o "$OUT")
[[ "$CURSOR" == "false" ]] && ARGS+=(-cursor no)
[[ -n "$CODEC" && "$CODEC" != "auto" ]] && ARGS+=(-k "$CODEC")
if [[ $SOUND -eq 1 ]]; then
    if [[ "$MIC" == "true" ]]; then
        ARGS+=(-a "default_output|default_input")
    else
        ARGS+=(-a default_output)
    fi
fi

if [[ $FULLSCREEN -eq 1 ]]; then
    ARGS+=(-w "${TARGET_MONITOR:-screen}")
else
    if [[ -z "$REGION" ]]; then
        if ! REGION="$(slurp)"; then
            notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
            exit 1
        fi
    fi
    # slurp emits "X,Y WxH"; gsr wants "WxH+X+Y"
    GEOMETRY="$(awk -F'[ ,x]' '{printf "%dx%d+%d+%d", $3, $4, $1, $2}' <<< "$REGION")"
    ARGS+=(-w region -region "$GEOMETRY")
fi

"${ARGS[@]}" &
GSR_PID=$!
echo "$GSR_PID" > "$PIDFILE"
set_recording_state true
notify-send "Recording started" "$(basename "$OUT")" -a 'Recorder' & disown

# Block until gsr exits (stop toggle, crash, or logout) so the pidfile and the
# shell's recording indicator are always cleaned up. The saved-file
# notification comes from the -sc hook with the real path.
wait "$GSR_PID"
rm -f "$PIDFILE"
set_recording_state false
