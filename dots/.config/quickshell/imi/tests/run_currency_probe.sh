#!/bin/bash
# Headless weston + qs, the runtime-harness pattern, trimmed to one probe.
set -u
SOCKET="wl-imi-currency-tree"
TMP=$(mktemp -d)
export XDG_RUNTIME_DIR="$TMP/runtime"; mkdir -p "$XDG_RUNTIME_DIR"; chmod 700 "$XDG_RUNTIME_DIR"
export XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME"
weston --backend=headless-backend.so --socket="$SOCKET" --width=1280 --height=800 &>"$TMP/weston.log" &
WPID=$!
sleep 2
DBUS_SESSION_BUS_ADDRESS="unix:path=/nonexistent" WAYLAND_DISPLAY="$SOCKET" CURRENCY_PROBE_SHOTS="${CURRENCY_PROBE_SHOTS:-}" timeout 60 qs -p "$(dirname "$0")/../CurrencyTreeMotionProbe.qml" 2>&1 | grep "CurrencyTreeMotion"
kill $WPID 2>/dev/null
rm -rf "$TMP"
