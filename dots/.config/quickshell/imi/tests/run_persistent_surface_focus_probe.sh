#!/usr/bin/env bash
# Every persistent surface opens on the monitor that has focus, every time -
# not on the one it opened on first.
#
# A nested Hyprland with two wayland outputs (each a window on the parent
# session; headless outputs never take a mode under the nested backend), the
# full shell inside it against an empty config, and each surface opened by
# IPC after focus is moved to each output in turn. `<target> activeScreen` is
# the shell's own answer for which screen's window the open landed on; the
# probe compares it with `hyprctl monitors` `focused`. #297 reopened on
# exactly this: on one monitor the first fix looked right, on two every open
# after the first reused the first screen's window - and then a third time,
# once both sidebars followed the overview onto a surface that outlives the
# gesture.
#
# The three surfaces are driven in one run on purpose. They share one bug and
# one shape, and a probe that covered the overview alone is what let the
# sidebars keep the same defect through the release that fixed it: the shell's
# answer has to be asked of each of them.
#
# Two things about moving the focus, both learned by this probe passing 18/18
# while measuring one monitor eighteen times. `hyprctl dispatch focusmonitor
# WAYLAND-2` is a LUA call on this build - the compositor wraps the argument as
# `hl.dispatch(focusmonitor WAYLAND-2)` and answers "')' expected near
# 'WAYLAND'" - so every dispatch this probe made had always failed, silently,
# into /dev/null. The focus is moved by putting the POINTER on the monitor
# instead (`hl.dsp.cursor.move`, the form SidebarLeft.qml already uses), which
# is both a spelling that works and the gesture the user makes. And the run
# now FAILS if the focused monitor never changed: eighteen agreements about one
# screen is what a probe with nothing to say looks like, and it is
# indistinguishable from a pass.
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
# The IPC targets that answer open/close/activeScreen - one per persistent
# surface. A surface converted to the per-screen family joins this list.
SURFACES="search sidebarLeft sidebarRight"
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
fail=0; checks=0; SEEN=""
for M in $MONS $MONS $MONS; do
  CENTRE=$(hyprctl monitors -j | python3 -c "import json,sys; m=[m for m in json.load(sys.stdin) if m['name']=='$M'][0]; print(m['x']+m['width']//2, m['y']+m['height']//2)")
  for T in $SURFACES; do
    # The pointer is placed again before EVERY open, and the focused monitor
    # re-read there rather than once per round. Closing one of these panels
    # hands the keyboard back, and the compositor's focused monitor goes with
    # it: measured, one cursor move followed by three opens had the first land
    # on the monitor the pointer was on and the other two on the monitor the
    # first one's close had returned to - which reads exactly like two of the
    # three surfaces being broken.
    hyprctl dispatch "hl.dsp.cursor.move({x=${CENTRE% *},y=${CENTRE#* }})" >/dev/null; sleep 0.6
    FOCUSED=$(hyprctl monitors -j | python3 -c 'import json,sys; print(",".join(m["name"] for m in json.load(sys.stdin) if m["focused"]))')
    SEEN="$SEEN $FOCUSED"
    qs -c imi ipc call $T open >/dev/null 2>&1; sleep 1.0
    LANDED=$(qs -c imi ipc call $T activeScreen 2>/dev/null | tr -d '\n')
    qs -c imi ipc call $T close >/dev/null 2>&1; sleep 0.8
    checks=$((checks+1))
    if [ "$LANDED" = "$FOCUSED" ]; then echo "ok   $T focused=$FOCUSED opened on $LANDED"; else echo "FAIL $T focused=$FOCUSED opened on ${LANDED:-<none>}"; fail=1; fi
  done
done
kill $QPID 2>/dev/null; sleep 1; kill $HPID 2>/dev/null; sleep 1; kill -9 $HPID 2>/dev/null
# The control. Every check agreeing about ONE monitor is what this probe
# reported for its whole life, and it is what a probe that never moved the
# focus reports whether or not the shell is broken.
VISITED=$(printf '%s\n' $SEEN | sort -u | grep -c .)
if [ "$VISITED" -lt 2 ]; then
  echo "FAILED: the focus never left ${FOCUSED:-<none>} - $checks checks measured one monitor"
  fail=1
fi
echo "$checks checks over $VISITED monitors, $( [ $fail = 0 ] && echo all on the focused monitor || echo FAILED )"
exit $fail
NESTED
