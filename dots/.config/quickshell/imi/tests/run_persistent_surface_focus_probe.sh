#!/usr/bin/env bash
# The overview opens on the monitor that has focus, every time - not the one
# it opened on first.
#
# A nested Hyprland with two wayland outputs (each a window on the parent
# session; headless outputs never take a mode under the nested backend), the
# full shell inside it against an empty config, and the overview opened by
# IPC after focus is moved to each output in turn. `search activeScreen` is
# the shell's own answer for which screen's window the open landed on; the
# probe compares it with `hyprctl monitors` `focused`. #297 reopened on
# exactly this: on one monitor the first fix looked right, on two every open
# after the first reused the first screen's window.
#
# Not part of run_tests.sh: it needs a Wayland parent and opens two windows
# on it. Run by hand from a graphical session.
set -u
if [ -z "${WAYLAND_DISPLAY:-}" ]; then echo "SKIPPED: no WAYLAND_DISPLAY - the nested compositor needs a parent"; exit 0; fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PARENT_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP" 2>/dev/null' EXIT
export XDG_CONFIG_HOME="$TMP/config" XDG_CACHE_HOME="$TMP/cache" XDG_STATE_HOME="$TMP/state" XDG_DATA_HOME="$TMP/data"
mkdir -p "$XDG_CONFIG_HOME/immaterial-impulse" "$XDG_CONFIG_HOME/quickshell" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$TMP/run"
ln -s "$ROOT" "$XDG_CONFIG_HOME/quickshell/imi"
printf '%s' '{}' > "$XDG_CONFIG_HOME/immaterial-impulse/config.json"
cat > "$TMP/hypr.lua" <<'LUA'
hl.monitor({ output = "WAYLAND-2", mode = "preferred", position = "1280x0", scale = 1 })
hl.monitor({ output = "", mode = "1280x720@60", position = "0x0", scale = 1 })
hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0, disable_autoreload = true }, animations = { enabled = false } })
LUA
export XDG_RUNTIME_DIR="$TMP/run"
export WAYLAND_DISPLAY="$PARENT_SOCKET"
dbus-run-session -- bash -s "$TMP" <<'NESTED'
set -u
TMP="$1"
Hyprland -c "$TMP/hypr.lua" > "$TMP/hypr.log" 2>&1 &
HPID=$!
SIG=""
for _ in $(seq 1 60); do sleep 0.5; SIG=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1); [ -n "$SIG" ] && [ -S "$XDG_RUNTIME_DIR/hypr/$SIG/.socket.sock" ] && break; SIG=""; done
if [ -z "$SIG" ]; then echo "FAILED: the nested compositor never came up"; tail -5 "$TMP/hypr.log"; kill $HPID 2>/dev/null; exit 1; fi
export HYPRLAND_INSTANCE_SIGNATURE="$SIG"
export WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -E '^wayland-[0-9]+$' | head -1)
hyprctl output create wayland >/dev/null; sleep 2
MONS=$(hyprctl monitors -j | python3 -c 'import json,sys; print(" ".join(m["name"] for m in json.load(sys.stdin) if m["width"]>0))')
if [ "$(echo $MONS | wc -w)" -lt 2 ]; then echo "FAILED: second output never came up ($MONS)"; kill $HPID; exit 1; fi
qs -c imi > "$TMP/qs.log" 2>&1 &
QPID=$!
sleep 12
fail=0; checks=0
for M in $MONS $MONS $MONS; do
  WS=$(hyprctl monitors -j | python3 -c "import json,sys; print([m for m in json.load(sys.stdin) if m['name']=='$M'][0]['activeWorkspace']['id'])")
  hyprctl dispatch workspace $WS >/dev/null; sleep 0.3; hyprctl dispatch focusmonitor "$M" >/dev/null; sleep 0.6
  FOCUSED=$(hyprctl monitors -j | python3 -c 'import json,sys; print(",".join(m["name"] for m in json.load(sys.stdin) if m["focused"]))')
  qs -c imi ipc call search open >/dev/null 2>&1; sleep 1.0
  LANDED=$(qs -c imi ipc call search activeScreen 2>/dev/null | tr -d '\n')
  qs -c imi ipc call search close >/dev/null 2>&1; sleep 0.8
  checks=$((checks+1))
  if [ "$LANDED" = "$FOCUSED" ]; then echo "ok   focused=$FOCUSED opened on $LANDED"; else echo "FAIL focused=$FOCUSED opened on ${LANDED:-<none>}"; fail=1; fi
done
kill $QPID 2>/dev/null; sleep 1; kill $HPID 2>/dev/null; sleep 1; kill -9 $HPID 2>/dev/null
echo "$checks checks, $( [ $fail = 0 ] && echo all on the focused monitor || echo FAILED )"
exit $fail
NESTED
