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
# This script calls itself (start stops a sandbox it reuses or failed to
# bring up): by bash and its own path, not "$0", which need not be an
# executable path (a copy without +x, a noexec mount). A script read from a
# pipe or `bash <(...)` has no path to re-read; run it from a file.
self() { bash "${BASH_SOURCE[0]}" "$@"; }
cmd="${1:-}"; shift || true
case "$cmd" in
start)
  # One spelling of the sandbox dir everywhere: it is the session's marker,
  # and a stop given another spelling (relative, a trailing slash) found
  # nothing and reported "nothing left" over a running session.
  ROOT="$1"; SB=$(realpath -m -- "$2"); OVERRIDES="${3:-}"
  [ -n "${WAYLAND_DISPLAY:-}" ] || { echo "no WAYLAND_DISPLAY: the nested compositor needs a parent"; exit 1; }
  PARENT_SOCKET="$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY"
  # Reusing a sandbox dir: stop what is running there first. Wiping the dir
  # under a live session left it running with nothing on disk to find it by.
  # A directory is a sandbox only if start made it: it carries the
  # .imi-sandbox sentinel. Nothing else counts - a sandbox's file names are
  # ordinary ones (a Python venv is commonly env/), and guessing from them
  # would wipe a project. A non-empty directory without the sentinel is
  # never wiped, and neither is a sandbox that could not be stopped (a stop
  # that refuses leaves its session running, and wiping the dir would
  # orphan it).
  if [ -e "$SB" ]; then
    if [ -f "$SB/.imi-sandbox" ]; then
      self stop "$SB" || { echo "start: could not stop the sandbox in $SB; not reusing it" >&2; exit 1; }
    elif [ -n "$(ls -A "$SB" 2>/dev/null)" ]; then
      echo "start: $SB exists and is not a sandbox (no .imi-sandbox); not wiping it" >&2
      echo "  if it is a sandbox made before the sentinel existed, run \`$0 stop $SB\` first, then remove it" >&2
      exit 1
    fi
  fi
  # SANDBOX_START_WAIT (whole seconds) exists for test_sandbox_shell.py,
  # which drives a start that never comes up. It bounds the compositor's
  # wait; the shell's is longer, so a compositor that comes up at its
  # deadline still gets its shell (30 s and 40 s by default). Validated
  # before it reaches arithmetic, and announced.
  WAIT_S=30; SHELL_S=40
  if [ -n "${SANDBOX_START_WAIT:-}" ]; then
    [[ "$SANDBOX_START_WAIT" =~ ^[1-9][0-9]{0,3}$ ]] || { echo "start: SANDBOX_START_WAIT must be a whole number of seconds (a test hook)" >&2; exit 2; }
    WAIT_S=$SANDBOX_START_WAIT; SHELL_S=$(( WAIT_S + 2 ))
    echo "start: SANDBOX_START_WAIT=$WAIT_S is set - waiting ${WAIT_S}s for the compositor (test mode)" >&2
  fi
  rm -rf "$SB"; mkdir -p "$SB/config/immaterial-impulse" "$SB/config/quickshell" "$SB/cache" "$SB/state" "$SB/data"
  echo "made by tests/sandbox/sandbox_shell.sh start; stop it before deleting this directory" > "$SB/.imi-sandbox"
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
      SB="$1"; ROOT="$2"; WAIT_S="$3"
      echo "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" > "$SB/env.partial"
      Hyprland -c "$SB/hypr.lua" > "$SB/hypr.log" 2>&1 &
      HPID=$!
      SIG=""
      for _ in $(seq 1 $(( WAIT_S * 10 ))); do sleep 0.1; SIG=$(ls "$XDG_RUNTIME_DIR/hypr" 2>/dev/null | head -1); [ -n "$SIG" ] && [ -S "$XDG_RUNTIME_DIR/hypr/$SIG/.socket.sock" ] && break; SIG=""; done
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
    ' _ "$SB" "$ROOT" "$WAIT_S" < /dev/null > "$SB/session.log" 2>&1
  for _ in $(seq 1 $(( SHELL_S * 10 ))); do sleep 0.1; [ -f "$SB/env" ] && grep -q SANDBOX_QS_PID "$SB/env" && break; done
  # A start that did not get as far as the shell has still started a
  # session (the compositor at least); end it rather than leave it running.
  if ! grep -qs SANDBOX_QS_PID "$SB/env"; then
    echo "FAILED"; cat "$SB/env.partial" 2>/dev/null; tail -5 "$SB/hypr.log" 2>/dev/null
    self stop "$SB" || echo "start: the failed session could not be stopped; run stop from outside any sandbox" >&2
    exit 1
  fi
  echo "sandbox up: source $SB/env"
  ;;
shot)
  SB="$1"; OUT="$2"; source "$SB/env"; grim "$OUT" && echo "$OUT"
  ;;
stop)
  SB=$(realpath -m -- "$1")
  # Everything started inside THIS sandbox, found by its environment: every
  # process of the session inherits IMI_SANDBOX_SESSION=<sandbox>, which the
  # env file does not export, so a terminal that sourced that file is never
  # taken for part of the sandbox (matching XDG_CONFIG_HOME killed it, and
  # this script). That covers the shell and the helpers it starts - a tray
  # watchdog, monitors, a keyring, the session's D-Bus - which outlived every
  # stop that killed only the recorded pids: 274 of them after a day of
  # reviews, a watchdog whose bus had gone spinning at 14% each. Nothing
  # needs the env file: a start that failed before writing it still left a
  # compositor running, and the pids in an env file that outlived its
  # session can be anyone's. The shell goes first (the marked process whose
  # argv[0] is quickshell - not a whole-command-line match, which finds this
  # script by its own path) and gets a moment to exit; the rest follows,
  # then SIGKILL.
  if tr '\0' '\n' < /proc/$$/environ 2>/dev/null | grep -q '^IMI_SANDBOX_SESSION='; then
    echo "stop: run this from outside the sandbox - from inside, it would end its own caller" >&2
    exit 1
  fi
  # One grep over every environ (NUL-separated, exact entry); only our own
  # processes are readable, and one that exits mid-scan is simply absent.
  session() {
    local f p argv0
    for f in $(grep -lzxF -- "IMI_SANDBOX_SESSION=$SB" /proc/[0-9]*/environ 2>/dev/null); do
      p=${f#/proc/}; p=${p%/environ}
      [ "$p" = "$$" ] && continue
      if [ "${1:-}" = shell ]; then
        argv0=$({ tr '\0' '\n' < "/proc/$p/cmdline"; } 2>/dev/null | head -1)
        [ "${argv0##*/}" = quickshell ] || continue
      fi
      echo "$p"
    done
  }
  # SANDBOX_STOP_KILL exists for test_sandbox_shell.py alone: a kill that
  # does nothing (`true`, the only value accepted) is how it reaches the
  # "still running" report. It announces itself, so a stray export is not
  # mistaken for a stuck session.
  case "${SANDBOX_STOP_KILL:-}" in
    "") signal() { kill "$@"; } ;;
    true) echo "stop: SANDBOX_STOP_KILL=true is set - nothing will be signalled (test mode)" >&2
          signal() { :; } ;;
    *) echo "stop: SANDBOX_STOP_KILL may only be 'true' (a test hook); refusing" >&2; exit 2 ;;
  esac
  found=$(session | wc -w)
  signal $(session shell) 2>/dev/null
  for _ in $(seq 1 50); do [ -z "$(session shell)" ] && break; sleep 0.1; done
  signal $(session) 2>/dev/null
  for _ in $(seq 1 30); do [ -z "$(session)" ] && break; sleep 0.1; done
  hard=$(session); [ -n "$hard" ] && signal -9 $hard 2>/dev/null
  sleep 0.2
  left=$(session | wc -w)
  # The run dir: only one start made - /tmp/imi-sb-XXXXXX, an existing
  # directory owned by us. run.path feeds an unmount pass and an rm -rf, so an
  # empty or foreign value (a failed mktemp, a hand edit) is left alone. A
  # portal or gvfs killed hard can leave its FUSE mount there, and rm cannot
  # remove a mountpoint; unmount lazily first.
  RUN=$(head -1 "$SB/run.path" 2>/dev/null)
  if [[ "$RUN" =~ ^/tmp/imi-sb-[A-Za-z0-9]{6}$ ]] && [ -d "$RUN" ] && [ ! -L "$RUN" ] && [ -O "$RUN" ]; then
    awk -v r="$RUN/" 'index($2, r) == 1 { print $2 }' /proc/self/mounts | while read -r m; do
      fusermount3 -u -z "$m" 2>/dev/null || fusermount -u -z "$m" 2>/dev/null
    done
    rm -rf "$RUN" 2>/dev/null
  fi
  hardn=$(echo $hard | wc -w)
  if [ "$left" -eq 0 ]; then
    echo "sandbox stopped: $found processes ended, nothing left${hard:+ ($hardn needed SIGKILL)}"
  else
    echo "sandbox stopped: $found processes found, $left STILL RUNNING - check /proc for IMI_SANDBOX_SESSION=$SB" >&2
    echo "sandbox stopped (incomplete)"
    exit 1
  fi
  ;;
*) echo "usage: $0 start <shell-root> <sandbox-dir> [overrides.json] | shot <sandbox-dir> <out.png> | stop <sandbox-dir>"; exit 2 ;;
esac
