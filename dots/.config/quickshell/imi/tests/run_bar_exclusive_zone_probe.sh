#!/bin/bash
# Reads the compositor's reserved area back while the bar's exclusive zone
# animates, which nothing else in this tree can.
#
# An exclusive zone is a wlr-layer-shell request. `qmltestrunner` does not load
# Quickshell's plugin at all, so it cannot build the window; weston implements
# no wlr-layer-shell, so every `*RuntimeTest.qml` harness here is blind to it.
# What is left is a nested Hyprland, on the shape run_notification_blur_probe.sh
# uses - its own D-Bus session, its own XDG dirs, its own XDG_RUNTIME_DIR, and
# its wayland parent named by ABSOLUTE path because libwayland only prefixes the
# runtime dir onto a relative one. It is not headless: Aquamarine aborts with no
# wayland parent and no seat, so this opens a nested compositor window for about
# half a minute.
#
# BarZoneProbe.qml stands one BarExclusiveZoneReserver up on its own and flips
# its `zone` between 0 and 40 every three seconds, exactly as auto-hide does.
# The probe samples `hyprctl monitors` as fast as it can spawn one (~30ms) and
# prints the reserved top edge, so the animation is visible as intermediate
# numbers rather than as a pair of endpoints - which is the whole difference the
# reserver exists to make. Measured when it landed, 40px zone under a 5px edge
# margin:
#
#   45 45 ... 45 19 4 0 0 ... 0 9 26 44 45 45 ...
#
# and the surface itself comes out as `quickshell:bar 0 0 <width> 1` - one pixel
# tall, on the bar's own namespace, masked to nothing.
#
# `hyprctl` picks its instance from HYPRLAND_INSTANCE_SIGNATURE and from nothing
# else, so every call below is made with the NESTED signature exported. Without
# that they answer for the caller's own session, which is the trap AGENT.md
# records and the reason the teardown kills by pid rather than dispatching exit.
#
# Usage: tests/run_bar_exclusive_zone_probe.sh
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

for binary in Hyprland qs dbus-run-session python3; do
    command -v "$binary" >/dev/null 2>&1 || { echo "SKIPPED: $binary not on PATH"; exit 0; }
done
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "SKIPPED: no WAYLAND_DISPLAY - the nested compositor needs a parent"
    exit 0
fi

PARENT_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP" 2>/dev/null' EXIT

export XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache"
export XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
mkdir -p "$XDG_CONFIG_HOME/immaterial-impulse" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" \
    "$XDG_DATA_HOME" "$TMP/run"
printf '%s' '{}' > "$XDG_CONFIG_HOME/immaterial-impulse/config.json"

cat > "$TMP/hypr.lua" <<'LUA'
hl.monitor({ output = "", mode = "1280x720@60", position = "auto", scale = 1 })
hl.config({
    misc = { disable_hyprland_logo = true, disable_splash_rendering = true,
             force_default_wallpaper = 0, disable_autoreload = true },
    -- Off deliberately: what is being measured is the reserved area, and a
    -- window-move animation only adds a second curve to read it through.
    animations = { enabled = false },
})
LUA

export XDG_RUNTIME_DIR="$TMP/run"
export WAYLAND_DISPLAY="$PARENT_SOCKET"

dbus-run-session -- bash -s "$TMP" "$ROOT" <<'NESTED'
set -u
TMP="$1"; ROOT="$2"

Hyprland -c "$TMP/hypr.lua" > "$TMP/hypr.log" 2>&1 &
HPID=$!
SIG=""
for _ in $(seq 1 60); do
    sleep 0.5
    SIG=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1)
    [ -n "$SIG" ] && [ -S "$XDG_RUNTIME_DIR/hypr/$SIG/.socket.sock" ] && break
    SIG=""
done
if [ -z "$SIG" ]; then
    echo "FAILED: the nested compositor never came up"
    tail -20 "$TMP/hypr.log"
    kill $HPID 2>/dev/null
    exit 1
fi
export HYPRLAND_INSTANCE_SIGNATURE="$SIG"
NEW=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | head -1)
echo "nested compositor: signature=$SIG display=$NEW"

reserved_top() {
    hyprctl monitors -j | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['reserved'][1], end=' ')"
}

echo "--- reserved top with no shell running ---"
reserved_top; echo

export WAYLAND_DISPLAY="$NEW"
cd "$ROOT"
qs -p "$ROOT/BarZoneProbe.qml" > "$TMP/probe.log" 2>&1 &
QPID=$!
sleep 6

echo "--- layer surfaces ---"
hyprctl layers -j | python3 -c "
import json, sys
for monitor, value in json.load(sys.stdin).items():
    for level, layers in value['levels'].items():
        for layer in layers:
            print(f\"  {monitor} level={level} {layer['namespace']} \"
                  f\"{layer['x']},{layer['y']} {layer['w']}x{layer['h']}\")
"

echo "--- reserved top, sampled while the zone animates ---"
for _ in $(seq 1 400); do reserved_top; done
echo

kill $QPID 2>/dev/null
sleep 1
kill $HPID 2>/dev/null
sleep 1
kill -9 $HPID 2>/dev/null

echo "--- the zone, from the shell's side ---"
grep -E "ERROR|WARN scene|BarZoneProbe" "$TMP/probe.log" | head -40
NESTED
