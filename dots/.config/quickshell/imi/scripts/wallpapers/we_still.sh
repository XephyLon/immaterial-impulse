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

command -v linux-wallpaperengine >/dev/null || { echo "we_still.sh: linux-wallpaperengine not installed" >&2; exit 3; }

# Default to the focused monitor: the greeter fills one screen, and rendering
# at that size is what makes the result native rather than upscaled.
if [[ -z "$GEOMETRY" ]]; then
    GEOMETRY="$(hyprctl monitors -j 2>/dev/null \
        | jq -r 'map(select(.focused)) | .[0] | "\(.width)x\(.height)"' 2>/dev/null || true)"
fi
[[ "$GEOMETRY" =~ ^[0-9]+x[0-9]+$ ]] || GEOMETRY="1920x1080"
WIDTH="${GEOMETRY%x*}"; HEIGHT="${GEOMETRY#*x}"

TIMEOUT="${WE_STILL_TIMEOUT:-45}"
DELAY_FRAMES="${WE_STILL_DELAY_FRAMES:-20}"

mkdir -p "$(dirname "$OUT")"
raw="$(mktemp --suffix=-we-still.jpg)"
cleanup() { rm -f "$raw"; }
trap cleanup EXIT

# --silent because this runs on every wallpaper switch and a burst of the
# wallpaper's audio each time would be intolerable.
#
# setsid + process-group kill because --screenshot does NOT exit once it has
# written the file: it keeps rendering, so the caller has to notice the file
# and stop it. Killing the group rather than the pid matters - the renderer
# spawns children and a bare `kill` leaves them holding the GPU.
setsid linux-wallpaperengine \
    --silent \
    --window "0x0x${WIDTH}x${HEIGHT}" \
    --screenshot "$raw" \
    --screenshot-delay "$DELAY_FRAMES" \
    "$PROJECT_ID" >/dev/null 2>&1 &
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
