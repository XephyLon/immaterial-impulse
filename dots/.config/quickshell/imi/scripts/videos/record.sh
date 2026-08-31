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

# Writes the whole record.* block: the flag and the region it applies to.
#
# One writer, deliberately. The shell also owns this file, and it rewrites it
# wholesale from its own in-memory copy - so a region written from QML right
# after launching this script lands on top of the `enable = true` written here
# milliseconds earlier, and the recording indicator never comes on. The region
# is known here anyway; it has no business making the round trip.
set_recording_state() {
    local state=$1 region=${2-} tmp
    mkdir -p "$(dirname "$STATE_FILE")"
    [[ -f "$STATE_FILE" ]] || echo '{}' > "$STATE_FILE"
    tmp=$(mktemp)
    jq --arg region "$region" \
        ".record.enable = $state | .record.region = \$region | .record.startedAt = (if $state then (now | floor) else 0 end)" \
        "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

# Toggle: a recording we started is running -> stop it gracefully and exit.
# The pidfile scopes the toggle to OUR recording, never the replay daemon
# (both are gpu-screen-recorder processes - killing by process name would hit both).
#
# INT first, because that is gsr's "finish and save". Then an ESCALATION,
# because INT is not always enough: gsr installs its own INT handler only once
# it is capturing, and a recording that never got that far - the portal picker
# never resolved, the compositor refused the stream - sits in poll() with INT
# still ignored (a `&` job in non-interactive bash starts with INT and QUIT
# ignored, and gsr had not yet undone it) and TERM caught but never acted on.
# That is the recording the maintainer could not stop from the privacy card or
# the overlay: every stop path funnels here, this sent one signal, and the
# process was born deaf to it. There is no file to lose in that state, so the
# ladder ends in KILL rather than leaving an unstoppable process behind an
# indicator that says "recording".
if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    gsr_pid="$(cat "$PIDFILE")"
    kill -INT "$gsr_pid"
    for _ in $(seq 1 30); do   # 3s: gsr flushes a real capture well inside this
        kill -0 "$gsr_pid" 2>/dev/null || exit 0
        sleep 0.1
    done
    kill -TERM "$gsr_pid" 2>/dev/null
    for _ in $(seq 1 20); do   # 2s
        kill -0 "$gsr_pid" 2>/dev/null || exit 0
        sleep 0.1
    done
    kill -KILL "$gsr_pid" 2>/dev/null
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
# gamma - and decodes flat, grey and desaturated. Two correct ways out:
#
# - PORTAL capture (-w portal), FULLSCREEN ONLY: the stream comes through the
#   compositor, and Hyprland tonemaps screencopy for capture clients - the
#   same reason a grim screenshot of an HDR desktop looks right. Native SDR at
#   capture time, no conversion ever - verified live: portal output probes
#   bt709/yuv420p with correct colours, where the KMS path gives raw PQ. The
#   session restores from a token, so the picker appears exactly once.
#
#   THE TOKEN DEPENDS ON A SHIPPED CONFIG. xdph only issues restore tokens
#   when the picker's "Allow a restore token" checkbox is ticked, and that
#   checkbox defaults OFF - which made restore a silent no-op, the picker
#   prompt on every recording, and got misdiagnosed as xdph lacking the
#   feature entirely. dots/.config/hypr/xdph.conf ships
#   `screencopy:allow_token_by_default = true` to pre-check it. Verified end
#   to end with it set: 22-byte token issued on the approved first run, the
#   second recording produced frames within one second with no interaction.
#   If the picker reappears on every fullscreen recording, check that
#   xdph.conf is in place and the portal was restarted since it landed.
#
# - Regions NEVER go through the portal. The first version routed them to the
#   portal picker's Region tab - and the recorder overlay's "Record Region"
#   already runs the shell's own region selector first, so the user picked a
#   region and was then prompted to pick again. One selection UX everywhere:
#   regions always come from the shell's selector (or slurp), capture via KMS
#   as real HDR, and the saved-hook converter delivers SDR a few seconds
#   later on the GPU. The codec is forced to an HDR variant in that case even
#   if the user chose H.264: the converter re-encodes to H.264 anyway, and
#   honouring the choice at capture would bake the wash-out in before the
#   converter ever saw the file.
#
# - The _hdr codec variants: real HDR10, correct in anything that tonemaps.
#   Used when the user keeps the SDR toggle off.
USE_PORTAL=0
if monitor_is_hdr "$TARGET_MONITOR"; then
    if [[ "$(cfg '.screenRecord.tonemapSdr')" == "true" ]]; then
        if [[ $FULLSCREEN -eq 1 ]]; then
            USE_PORTAL=1
            # The stream is SDR, so the user's codec choice applies unchanged.
        else
            CODEC="hevc_hdr"
        fi
    else
        case "$CODEC" in
            ""|auto|hevc) CODEC="hevc_hdr" ;;
            av1)          CODEC="av1_hdr" ;;
            h264)
                # H.264 has no HDR variant here. Silently swapping the codec someone
                # explicitly chose is worse than saying why the file will look wrong.
                notify-send "Recording SDR H.264 on an HDR display" \
                    "H.264 cannot carry HDR, so this recording will look washed out. Pick HEVC or AV1, enable 'Convert HDR recordings to SDR', or turn HDR off while recording." \
                    -a 'Recorder' & disown
                ;;
        esac
    fi
fi
PORTAL_TOKEN="$HOME/.local/state/quickshell/gsr-portal-token"

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

if [[ $USE_PORTAL -eq 1 ]]; then
    # Fullscreen only (see the routing above) - the token means the picker
    # appears once, ever, and never mid-flow.
    ARGS+=(-w portal)
    mkdir -p "$(dirname "$PORTAL_TOKEN")"
    ARGS+=(-restore-portal-session yes -portal-session-token-filepath "$PORTAL_TOKEN")
elif [[ $FULLSCREEN -eq 1 ]]; then
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

# Job control ON for the launch, so gsr is not born with INT and QUIT ignored:
# a `&` job in a non-interactive shell inherits SIG_IGN for both, and the stop
# path above leads with INT. gsr normally installs its own handler and undoes
# that once capturing, but "normally" is the case that already worked; this is
# for the one that did not. Turned back off after, so the script's own
# job-control noise does not change anything else about how it runs.
set -m
"${ARGS[@]}" &
GSR_PID=$!
set +m
echo "$GSR_PID" > "$PIDFILE"
set_recording_state true "$REGION"
notify-send "Recording started" "$(basename "$OUT")" -a 'Recorder' & disown

# A recording that never starts must not sit behind an indicator that says
# it did. The portal path can wedge before the first frame - measured: a
# hard-hung xdg-desktop-portal-hyprland left gsr at CreateSession for minutes,
# single-threaded, no output file, while the bar showed "recording" - and the
# user's only signal was that Stop did nothing. So watch for the OUTPUT FILE
# to appear: gsr opens it the moment capture begins, and a screen capture
# begins well inside this window. Past it, tear gsr down through the same
# ladder the stop uses and say why, then fall through to the cleanup below.
# The picker (a first-ever portal recording, or a token the portal refused)
# needs the user's click, so the window is generous rather than tight.
START_WINDOW_S="${IMI_RECORD_START_WINDOW_S:-25}"   # env override is for the test
for _ in $(seq 1 $((START_WINDOW_S * 10))); do
    kill -0 "$GSR_PID" 2>/dev/null || break            # exited on its own: fall through
    [[ -e "$OUT" ]] && break                            # capturing
    sleep 0.1
done
if kill -0 "$GSR_PID" 2>/dev/null && [[ ! -e "$OUT" ]]; then
    notify-send "Recording did not start" \
        "No frames after ${START_WINDOW_S}s - the screen-capture portal is not answering. Try again; if it keeps happening, restart xdg-desktop-portal-hyprland." \
        -a 'Recorder' -u critical & disown
    kill -INT "$GSR_PID" 2>/dev/null; sleep 1
    kill -0 "$GSR_PID" 2>/dev/null && { kill -TERM "$GSR_PID" 2>/dev/null; sleep 1; }
    kill -0 "$GSR_PID" 2>/dev/null && kill -KILL "$GSR_PID" 2>/dev/null
fi

# Block until gsr exits (stop toggle, crash, or logout) so the pidfile and the
# shell's recording indicator are always cleaned up. The saved-file
# notification comes from the -sc hook with the real path.
wait "$GSR_PID"
rm -f "$PIDFILE"
set_recording_state false ""
