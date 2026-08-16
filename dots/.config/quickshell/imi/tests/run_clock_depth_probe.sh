#!/bin/bash
# Headless weston + qs, the runtime-harness pattern. The fixtures are synthetic
# on purpose: a flat wallpaper and a half-white mask, so nothing here runs a
# model and the compositing contract is what gets scored.
set -u
SOCKET="wl-imi-clock-depth"
TMP=$(mktemp -d)
export XDG_RUNTIME_DIR="$TMP/runtime"; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"
weston --backend=headless-backend.so --socket="$SOCKET" --width=1280 --height=800 &>"$TMP/weston.log" &
WPID=$!
sleep 2
DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent" WAYLAND_DISPLAY="$SOCKET" \
    CLOCK_DEPTH_WALLPAPER="${CLOCK_DEPTH_WALLPAPER:-}" \
    CLOCK_DEPTH_MASK="${CLOCK_DEPTH_MASK:-}" \
    CLOCK_DEPTH_REST_SHOT="${CLOCK_DEPTH_REST_SHOT:-}" \
    CLOCK_DEPTH_PAN_SHOT="${CLOCK_DEPTH_PAN_SHOT:-}" \
    CLOCK_DEPTH_FLAT_SHOT="${CLOCK_DEPTH_FLAT_SHOT:-}" \
    CLOCK_DEPTH_BROKEN_SHOT="${CLOCK_DEPTH_BROKEN_SHOT:-}" \
    timeout 60 qs -p "$(dirname "$0")/../ClockDepthProbe.qml" 2>&1 | grep "ClockDepth"
kill $WPID 2>/dev/null
rm -rf "$TMP"
