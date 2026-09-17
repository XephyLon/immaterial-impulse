#!/usr/bin/env bash
# A sandboxed shell for review: a nested Hyprland (one 1920x1080 output as a
# window on the parent session), its own XDG dirs and D-Bus, the given
# worktree's shell inside it against the shipped defaults. Prints an env file;
# `source` it to talk to the sandbox (hyprctl, qs -c imi ipc, grim, wtype).
#
#   sandbox_shell.sh start <shell-root> <sandbox-dir> [config-overrides.json]
#   sandbox_shell.sh shot  <sandbox-dir> <out.png>
#   sandbox_shell.sh stop  <sandbox-dir>
set -u
cmd="${1:-}"; shift || true
case "$cmd" in
start)
  ROOT="$1"; SB="$2"; OVERRIDES="${3:-}"
  [ -n "${WAYLAND_DISPLAY:-}" ] || { echo "no WAYLAND_DISPLAY: the nested compositor needs a parent"; exit 1; }
  PARENT_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
  rm -rf "$SB"; mkdir -p "$SB/config/immaterial-impulse" "$SB/config/quickshell" "$SB/cache" "$SB/state" "$SB/data"
  # The runtime dir must be SHORT: a unix socket path is capped at 108 bytes,
  # and under a deep scratchpad path wl_display_add_socket_auto fails
  # ("m_szWLDisplaySocket was null"). /tmp/imi-sb-<name>, mode 0700.
  RUN=$(mktemp -d /tmp/imi-sb-XXXXXX); chmod 700 "$RUN"; ln -sfn "$RUN" "$SB/run"; echo "$RUN" > "$SB/run.path"
  ln -s "$ROOT" "$SB/config/quickshell/imi"
  # Overrides: {"config": {...}, "states": {...}} - or a bare object, which is
  # config. states seeds the shell's states.json (e.g. the selected AI model).
  mkdir -p "$SB/state/quickshell"
  python3 - "$ROOT/defaults/config.json" "$SB/config/immaterial-impulse/config.json" "$OVERRIDES" "$SB/state/quickshell/states.json" <<'PY'
import json, sys
cfg = json.load(open(sys.argv[1])); cfg["migratedUpstreamSchema"] = True
def merge(a, b):
    for k, v in b.items():
        if isinstance(v, dict) and isinstance(a.get(k), dict): merge(a[k], v)
        else: a[k] = v
ov = json.load(open(sys.argv[3])) if sys.argv[3] else {}
if "config" in ov or "states" in ov:
    merge(cfg, ov.get("config", {}))
    if ov.get("states"): json.dump(ov["states"], open(sys.argv[4], "w"), indent=2)
else:
    merge(cfg, ov)
json.dump(cfg, open(sys.argv[2], "w"), indent=2)
PY
  # Already greeted: the first-run marker stops welcome.qml from opening
  # over everything under review.
  mkdir -p "$SB/state/quickshell/user"; printf '%s' "This file is just here to confirm you've been greeted :>" > "$SB/state/quickshell/user/first_run.txt"
  cat > "$SB/hypr.lua" <<'LUA'
hl.monitor({ output = "", mode = "1920x1080@60", position = "0x0", scale = 1 })
hl.config({ misc = { disable_hyprland_logo = true, disable_splash_rendering = true, force_default_wallpaper = 0, disable_autoreload = true }, general = { gaps_out = 5, gaps_in = 4, border_size = 1 }, decoration = { rounding = 12 } })
LUA
  # The nested session on its own bus, detached; its pids and env land in the env file.
  # IMI_SANDBOX_SESSION marks every process of the session for `stop`; it is
  # deliberately NOT in the env file, so a terminal that sources that file is
  # never mistaken for part of the sandbox.
  setsid -f env IMI_SANDBOX_SESSION="$SB" XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" XDG_STATE_HOME="$SB/state" XDG_DATA_HOME="$SB/data" \
    XDG_RUNTIME_DIR="$RUN" WAYLAND_DISPLAY="$PARENT_SOCKET" \
    dbus-run-session -- bash -c '
      SB="$1"; ROOT="$2"
      echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" > "$SB/env.partial"
      Hyprland -c "$SB/hypr.lua" > "$SB/hypr.log" 2>&1 &
      HPID=$!
      SIG=""
      for _ in $(seq 1 60); do sleep 0.5; SIG=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1); [ -n "$SIG" ] && [ -S "$XDG_RUNTIME_DIR/hypr/$SIG/.socket.sock" ] && break; SIG=""; done
      [ -n "$SIG" ] || { echo "FAILED: nested compositor never came up" >> "$SB/env.partial"; exit 1; }
      export HYPRLAND_INSTANCE_SIGNATURE="$SIG"
      export WAYLAND_DISPLAY=$(ls "$XDG_RUNTIME_DIR" | grep -E "^wayland-[0-9]+$" | head -1)
      {
        echo "export XDG_CONFIG_HOME=$XDG_CONFIG_HOME XDG_CACHE_HOME=$XDG_CACHE_HOME XDG_STATE_HOME=$XDG_STATE_HOME XDG_DATA_HOME=$XDG_DATA_HOME"
        echo "export XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR WAYLAND_DISPLAY=$WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE=$SIG"
        echo "export DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"
        echo "export SANDBOX_HYPR_PID=$HPID"
      } > "$SB/env"
      # Not `cd && qs &`: that backgrounds a subshell, and its pid is what
      # `stop` then killed while the shell lived on.
      cd "$ROOT" || exit 1
      qs -c imi > "$SB/qs.log" 2>&1 &
      echo "export SANDBOX_QS_PID=$!" >> "$SB/env"
      wait $HPID
    ' _ "$SB" "$ROOT" < /dev/null > "$SB/session.log" 2>&1
  for _ in $(seq 1 80); do sleep 0.5; [ -f "$SB/env" ] && grep -q SANDBOX_QS_PID "$SB/env" && break; done
  [ -f "$SB/env" ] || { echo "FAILED"; cat "$SB/env.partial" 2>/dev/null; tail -5 "$SB/hypr.log" 2>/dev/null; exit 1; }
  echo "sandbox up: source $SB/env"
  ;;
shot)
  SB="$1"; OUT="$2"; source "$SB/env"; grim "$OUT" && echo "$OUT"
  ;;
stop)
  SB="$1"; source "$SB/env" 2>/dev/null || exit 0
  # Everything started inside THIS sandbox, found by its environment: every
  # process of the session inherits IMI_SANDBOX_SESSION=<sandbox>, which the
  # env file does not export, so a terminal that sourced that file is never
  # taken for part of the sandbox (matching XDG_CONFIG_HOME killed it, and
  # this script). That covers the shell and the helpers it starts - a tray
  # watchdog, monitors, a keyring, the session's D-Bus - which outlived every
  # stop that killed only the recorded pids: 274 of them after a day of
  # reviews, a watchdog whose bus had gone spinning at 14% each. The recorded
  # pids are not killed on their own: an env file outlives its session, and
  # by then a pid can be anyone's. The shell goes first (the process whose
  # argv[0] is quickshell - not a whole-command-line match, which finds this
  # script by its own path) and gets a moment to exit; the rest follows, then
  # SIGKILL.
  session() {
    local p argv0
    for p in $(pgrep -u "$(id -u)" .); do
      { tr '\0' '\n' < "/proc/$p/environ"; } 2>/dev/null | grep -qx "IMI_SANDBOX_SESSION=$SB" || continue
      if [ "${1:-}" = shell ]; then
        argv0=$({ tr '\0' '\n' < "/proc/$p/cmdline"; } 2>/dev/null | head -1)
        [ "${argv0##*/}" = quickshell ] || continue
      fi
      echo "$p"
    done
  }
  kill $(session shell) 2>/dev/null
  for _ in $(seq 1 10); do [ -z "$(session shell)" ] && break; sleep 0.5; done
  kill $(session) 2>/dev/null
  for _ in $(seq 1 6); do [ -z "$(session)" ] && break; sleep 0.5; done
  left=$(session); [ -n "$left" ] && kill -9 $left 2>/dev/null
  # A portal or gvfs killed hard can leave its FUSE mount in the run dir, and
  # rm cannot remove a mountpoint; unmount lazily first.
  if [ -f "$SB/run.path" ]; then
    RUN=$(cat "$SB/run.path")
    awk -v r="$RUN/" 'index($2, r) == 1 { print $2 }' /proc/self/mounts | while read -r m; do
      fusermount3 -u -z "$m" 2>/dev/null || fusermount -u -z "$m" 2>/dev/null
    done
    rm -rf "$RUN" 2>/dev/null
  fi
  echo "sandbox stopped"
  ;;
*) echo "usage: $0 start <shell-root> <sandbox-dir> [overrides.json] | shot <sandbox-dir> <out.png> | stop <sandbox-dir>"; exit 2 ;;
esac
