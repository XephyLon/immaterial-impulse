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
  setsid -f env XDG_CONFIG_HOME="$SB/config" XDG_CACHE_HOME="$SB/cache" XDG_STATE_HOME="$SB/state" XDG_DATA_HOME="$SB/data" \
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
  # Every shell of THIS sandbox, found by its own environment: the recorded
  # pid, and anything else started against the same config dir. A shell that
  # outlived a stop kept rendering, and later CPU readings landed on it.
  shells() {
    local p
    for p in $(pgrep -f quickshell); do
      { tr '\0' '\n' < "/proc/$p/environ"; } 2>/dev/null | grep -qx "XDG_CONFIG_HOME=$SB/config" && echo "$p"
    done
  }
  kill "$SANDBOX_QS_PID" $(shells) 2>/dev/null
  for _ in $(seq 1 10); do [ -z "$(shells)" ] && break; sleep 0.5; done
  left=$(shells); [ -n "$left" ] && kill -9 $left 2>/dev/null
  kill "$SANDBOX_HYPR_PID" 2>/dev/null; sleep 1; kill -9 "$SANDBOX_HYPR_PID" 2>/dev/null
  [ -f "$SB/run.path" ] && rm -rf "$(cat "$SB/run.path")"
  echo "sandbox stopped"
  ;;
*) echo "usage: $0 start <shell-root> <sandbox-dir> [overrides.json] | shot <sandbox-dir> <out.png> | stop <sandbox-dir>"; exit 2 ;;
esac
