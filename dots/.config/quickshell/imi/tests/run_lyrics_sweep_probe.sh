#!/bin/bash
# Headless weston + qs, trimmed to one probe: the line-level lyric sweep,
# photographed at three pinned clock positions.
set -u
SOCKET="wl-imi-lyrics-sweep"
TMP=$(mktemp -d)
export XDG_RUNTIME_DIR="$TMP/runtime"; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"
weston --backend=headless-backend.so --socket="$SOCKET" --width=800 --height=600 &>"$TMP/weston.log" &
WPID=$!
sleep 2
DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent" WAYLAND_DISPLAY="$SOCKET" LYRICS_SWEEP_SHOTS="${LYRICS_SWEEP_SHOTS:-/tmp}" timeout 30 qs -p "$(dirname "$0")/../LyricsSweepProbe.qml" 2>&1 | grep -E "LyricsSweepProbe|Error|error"
kill $WPID 2>/dev/null
rm -rf "$TMP"
