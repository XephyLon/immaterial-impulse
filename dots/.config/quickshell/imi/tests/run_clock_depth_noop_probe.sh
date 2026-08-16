#!/bin/bash
# Headless weston + qs, the runtime-harness pattern. One process, one wallpaper
# that nothing can change under it, and only the depth flag moving between the
# frames it grabs - which is the control a pair of live `grim` captures does not
# have.
set -u
SOCKET="wl-imi-clock-depth-noop"
TMP=$(mktemp -d)
export XDG_RUNTIME_DIR="$TMP/runtime"; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"
weston --backend=headless-backend.so --socket="$SOCKET" --width=1280 --height=800 &>"$TMP/weston.log" &
WPID=$!
sleep 2
DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent" WAYLAND_DISPLAY="$SOCKET" \
    CLOCK_DEPTH_WALLPAPER="${CLOCK_DEPTH_WALLPAPER:-}" \
    CLOCK_DEPTH_FULL_MASK="${CLOCK_DEPTH_FULL_MASK:-}" \
    CLOCK_DEPTH_PART_MASK="${CLOCK_DEPTH_PART_MASK:-}" \
    CLOCK_DEPTH_SHOT_DIR="${CLOCK_DEPTH_SHOT_DIR:-}" \
    timeout 60 qs -p "$(dirname "$0")/../ClockDepthNoOpProbe.qml" 2>&1 | grep "ClockDepthNoOp"
kill $WPID 2>/dev/null
rm -rf "$TMP"
