#!/usr/bin/env bash
# Render a full-resolution still of a Wallpaper Engine project.
#
# Why this exists: the SDDM greeter cannot run Wallpaper Engine, so it needs a
# static image of whatever the desktop is showing. The only image a WE project
# ships is the Steam Workshop preview, which is a thumbnail - typically square
# and around 1000px. Cropped to a wide display that is a narrow band upscaled
# several times over (immaterial-impulse#113: a 910x910 preview on 5120x1440).
#
# linux-wallpaperengine can render a project and dump a frame, at whatever size
# it is given, so the greeter can have the wallpaper at the display's own
# resolution instead. This has to run in the user's session, with a GPU and a
# compositor: the theme's apply script runs as root through sudo and has
# neither, which is why the work happens here and only the resulting file is
# handed over.
#
# Usage: we_still.sh <project-id> <output.jpg> [WIDTHxHEIGHT]
set -euo pipefail

PROJECT_ID="${1:-}"
OUT="${2:-}"
GEOMETRY="${3:-}"
[[ -n "$PROJECT_ID" && -n "$OUT" ]] || { echo "usage: we_still.sh <project-id> <out.jpg> [WxH]" >&2; exit 2; }
[[ "$PROJECT_ID" =~ ^[0-9]+$ ]] || { echo "we_still.sh: project id must be numeric" >&2; exit 2; }

# Default to the focused monitor: the greeter fills one screen, and rendering
# at that size is what makes the result native rather than upscaled. The name
# is wanted as well as the size - see the render mode below.
MONITOR_NAME=""
if [[ -z "$GEOMETRY" ]]; then
    monitor_json="$(hyprctl monitors -j 2>/dev/null \
        | jq -c 'map(select(.focused)) | .[0] // empty' 2>/dev/null || true)"
    if [[ -n "$monitor_json" ]]; then
        MONITOR_NAME="$(jq -r '.name // ""' <<<"$monitor_json" 2>/dev/null || true)"
        GEOMETRY="$(jq -r '"\(.width)x\(.height)"' <<<"$monitor_json" 2>/dev/null || true)"
    fi
fi
[[ "$GEOMETRY" =~ ^[0-9]+x[0-9]+$ ]] || GEOMETRY="1920x1080"
WIDTH="${GEOMETRY%x*}"; HEIGHT="${GEOMETRY#*x}"

TIMEOUT="${WE_STILL_TIMEOUT:-45}"
DELAY_FRAMES="${WE_STILL_DELAY_FRAMES:-20}"

mkdir -p "$(dirname "$OUT")"

# A project's render does not change, so render it once and keep it. Without
# this the renderer runs on every single wallpaper switch - including switching
# back to something seen a minute ago - which is several seconds of GPU for a
# file that is already on disk and identical.
#
# The size is checked rather than just the existence: a still cached at the old
# resolution is exactly the upscaled-thumbnail problem this script exists to
# fix, so a monitor change has to invalidate it. WE_STILL_FORCE=1 re-renders
# regardless, for a project whose content was updated in the Workshop.
still_geometry() {
    ffprobe -v error -select_streams v -show_entries stream=width,height \
        -of csv=p=0:s=x "$1" 2>/dev/null || true
}
if [[ -z "${WE_STILL_FORCE:-}" && -s "$OUT" ]] \
    && [[ "$(still_geometry "$OUT")" == "${WIDTH}x${HEIGHT}" ]]; then
    echo "$OUT"
    exit 0
fi

# Checked after the cache, not before: a usable still on disk needs no renderer,
# and failing here would throw away a good file on a machine that has since
# dropped the Wallpaper Engine extra.
command -v linux-wallpaperengine >/dev/null || { echo "we_still.sh: linux-wallpaperengine not installed" >&2; exit 3; }

raw="$(mktemp --suffix=-we-still.jpg)"
cleanup() { rm -f "$raw"; }
trap cleanup EXIT

# Render mode. --window opens an ordinary floating window: on a compositor it
# takes focus and covers the screen for the seconds the render takes, which is
# a visible interruption for a file the user never asked to see being made.
#
# --screen-root binds a wlr-layer-shell surface instead, and --layer background
# puts it on the lowest layer - underneath the shell's own wallpaper, which is
# opaque and covers it completely. Same frame, no window, no focus change,
# nothing on screen. It also takes the output's real size, so the geometry is
# the monitor's by construction rather than by being told.
#
# --no-fullscreen-pause is required with it: a background pauses by default
# while a fullscreen window is active, and a paused renderer never reaches the
# screenshot frame, so a render started over a fullscreen app would sit there
# until the timeout and produce nothing.
#
# The window path stays for anything without a named output - a non-Hyprland
# compositor, or an explicit geometry argument asking for a specific size.
if [[ -n "$MONITOR_NAME" ]]; then
    render_args=(--screen-root "$MONITOR_NAME" --layer background
        --no-fullscreen-pause --bg "$PROJECT_ID")
else
    render_args=(--window "0x0x${WIDTH}x${HEIGHT}" "$PROJECT_ID")
fi

# --silent because a burst of the wallpaper's audio while nothing is visible on
# screen would be worse than the window ever was.
#
# setsid + process-group kill because --screenshot does NOT exit once it has
# written the file: it keeps rendering, so the caller has to notice the file
# and stop it. Killing the group rather than the pid matters - the renderer
# spawns children and a bare `kill` leaves them holding the GPU.
setsid linux-wallpaperengine \
    --silent \
    --screenshot "$raw" \
    --screenshot-delay "$DELAY_FRAMES" \
    "${render_args[@]}" >/dev/null 2>&1 &
pgid=$!

for _ in $(seq 1 "$TIMEOUT"); do
    [[ -s "$raw" ]] && break
    sleep 1
done
# A moment for the writer to finish flushing before the group is torn down;
# without it the file can exist but be truncated.
[[ -s "$raw" ]] && sleep 1
kill -TERM -"$pgid" 2>/dev/null || true
sleep 1
kill -KILL -"$pgid" 2>/dev/null || true
wait "$pgid" 2>/dev/null || true

[[ -s "$raw" ]] || { echo "we_still.sh: no frame produced for $PROJECT_ID" >&2; exit 1; }

# The renderer writes JPEG at maximum quality - about 8 MiB at 5120x1440. This
# is copied onto /usr/share by the greeter's installer, so recompress: -q:v 2
# is visually equivalent on a render and roughly a tenth the size. Falls back
# to the raw file if ffmpeg is unavailable rather than failing outright.
# The temporary keeps a .jpg suffix: ffmpeg picks the encoder from the output
# extension, and a bare ".tmp" makes it fail - silently, since stderr is
# discarded, leaving the uncompressed frame in place looking like a success.
tmp_out="${OUT%.jpg}.tmp.jpg"
if command -v ffmpeg >/dev/null && ffmpeg -y -i "$raw" -q:v 2 "$tmp_out" >/dev/null 2>&1 && [[ -s "$tmp_out" ]]; then
    mv -f "$tmp_out" "$OUT"
else
    rm -f "$tmp_out"
    cp -f "$raw" "$OUT"
fi

echo "$OUT"
