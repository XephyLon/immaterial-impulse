#!/bin/bash
# Headless weston + qs, the runtime-harness pattern. The chrome is masks, a
# gaussian blur and a shadow, so this needs the GL renderer weston's headless
# backend gives it by default - the software scene graph the QtTest harnesses
# run under draws none of it.
#
# EDIT_MODE_WALLPAPER points it at whatever picture is wanted: the suite passes
# a synthetic fixture, a human passes a real photograph and looks at the PNGs.
# No check reads the wallpaper's own pixels.
set -u
SOCKET="wl-imi-edit-mode-look"
TMP=$(mktemp -d)
export XDG_RUNTIME_DIR="$TMP/runtime"; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"
WIDTH="${EDIT_MODE_WIDTH:-1600}"
HEIGHT="${EDIT_MODE_HEIGHT:-900}"
weston --backend=headless-backend.so --socket="$SOCKET" \
    --width="$WIDTH" --height="$HEIGHT" &>"$TMP/weston.log" &
WPID=$!
sleep 2
DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent" WAYLAND_DISPLAY="$SOCKET" \
    EDIT_MODE_WALLPAPER="${EDIT_MODE_WALLPAPER:-}" \
    EDIT_MODE_SHOT_DIR="${EDIT_MODE_SHOT_DIR:-}" \
    EDIT_MODE_WIDTH="$WIDTH" EDIT_MODE_HEIGHT="$HEIGHT" \
    timeout 60 qs -p "$(dirname "$0")/../EditModeLookProbe.qml" 2>&1 | grep "EditModeLook"
kill $WPID 2>/dev/null
rm -rf "$TMP"
