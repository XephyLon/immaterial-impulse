#!/bin/bash
# Headless weston + qs, the runtime-harness pattern, trimmed to one probe.
# The output is taller than the card probe's because it renders five widgets
# in three states, so weston gets an output big enough to hold the window.
set -u
SOCKET="wl-imi-widget-elevation"
TMP=$(mktemp -d)
export XDG_RUNTIME_DIR="$TMP/runtime"; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"
weston --backend=headless-backend.so --socket="$SOCKET" --width=1100 --height=1700 &>"$TMP/weston.log" &
WPID=$!
sleep 2
DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent" WAYLAND_DISPLAY="$SOCKET" WIDGET_ELEVATION_SHOT="${WIDGET_ELEVATION_SHOT:-}" timeout 90 qs -p "$(dirname "$0")/../WidgetElevationProbe.qml" 2>&1 | grep -E "WidgetElevation|ERROR|WARN scene"
kill $WPID 2>/dev/null
rm -rf "$TMP"
