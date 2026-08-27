#!/usr/bin/env bash
# droidcam_session.sh — Persistent lifecycle manager for DroidCam sessions.
#
# The droidcam-cli / scrcpy process is launched DETACHED (setsid + nohup) so it
# keeps running when the Quickshell process dies, reloads, or restarts. A small
# JSON state file records the PID + connection info so the shell can re-adopt
# the existing process on boot instead of spawning a duplicate.
#
# Sessions:
#   video      — droidcam-cli -nocontrols [ip|adb] <port>           (webcam)
#   audio      — env PULSE_SINK=DroidCam-Mic droidcam-cli -a ...    (mic via droidcam)
#   scrcpy-mic — scrcpy --no-video --no-window --audio-source=mic   (preferred mic)
#
# Usage:
#   droidcam_session.sh launch <session> <bin> <args...>   Start detached + save state, print PID
#   droidcam_session.sh status <session>                   Validate process → JSON on stdout
#   droidcam_session.sh stop <session>                     Kill saved PID (only if cmdline matches)
#   droidcam_session.sh killall                            Stop every tracked session
#
# State is written atomically (tmp + mv). Idempotent.

set -u
IFS=$'\n\t'

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/imi/phone"
mkdir -p "$STATE_DIR"

logfile_for()   { printf '%s/%s.log'   "$STATE_DIR" "$1"; }
statefile_for() { printf '%s/%s.json'  "$STATE_DIR" "$1"; }

# ─── Helpers ─────────────────────────────────────────────────────────────

# atomically_write <file> <content>
atomically_write() {
    local file="$1" content="$2" tmp
    tmp="$file.tmp.$$"
    printf '%s' "$content" > "$tmp" && mv -f "$tmp" "$file"
}

# cmdline_of <pid> → normalized single-line cmdline (NUL → space)
cmdline_of() { tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//'; }

# is_alive <pid> → 0 if process exists
is_alive() { [ -n "$1" ] && [ -d "/proc/$1" ] 2>/dev/null; }

# read_json_field <file> <key> → value (naive parser for our single-line JSON;
# supports both string and numeric values)
read_json_field() {
    sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\)\"\{0,1\}.*/\1/p" "$1" 2>/dev/null | head -n1
}

# session_signature <session> → substring the process cmdline must contain
session_signature() {
    case "$1" in
        video)      echo "droidcam-cli" ;;
        audio)      echo "droidcam-cli -a" ;;
        scrcpy-mic) echo "--audio-source=mic" ;;
        *)          echo "" ;;
    esac
}

# find_running <session> [port] → pid (empty if none). Matches live processes
# of the session kind whose cmdline contains the port (when given).
find_running() {
    local session="$1" port="${2:-}" sig pid cl comm argv0 want
    sig="$(session_signature "$session")"
    [ -n "$sig" ] || return 1
    case "$session" in
        scrcpy-mic) want="scrcpy" ;;
        *)          want="droidcam-cli" ;;
    esac
    # `pgrep -x` on the binary's own name, never a full-cmdline match on
    # the signature: that matches every process carrying these args,
    # including the shell that was invoked to launch one, so a session would
    # "adopt" its own launcher (this repo's lint refuses the bare form for
    # exactly that reason). The signature is then checked on the cmdline.
    for pid in $(pgrep -x "$want" 2>/dev/null); do
        [ -r "/proc/$pid/cmdline" ] || continue
        cl="$(cmdline_of "$pid")"
        case "$cl" in
            *"$sig"*)
                if [ -z "$port" ]; then printf '%s' "$pid"; return 0; fi
                case "$cl" in
                    *"$port"*) printf '%s' "$pid"; return 0 ;;
                esac
                ;;
        esac
    done
    return 1
}

# extract_port <args...> → last standalone numeric token
extract_port() {
    local a last=""
    for a in "$@"; do
        case "$a" in
            ''|*[!0-9]*) ;;
            *) last="$a" ;;
        esac
    done
    printf '%s' "$last"
}

# extract_ip <mode> <args...> → the token before the port (wifi) or "adb" (usb)
extract_ip() {
    local mode="$1"; shift
    local a prev=""
    for a in "$@"; do
        case "$a" in
            ''|*[!0-9]*) ;;
            *) [ "$mode" = "usb" ] && printf 'adb' && return 0
               printf '%s' "$prev"; return 0 ;;
        esac
        prev="$a"
    done
    printf ''
}

# ─── Commands ────────────────────────────────────────────────────────────

# cmd_launch <session> <bin> <args...>
cmd_launch() {
    local session="$1" bin="$2"; shift 2
    [ $# -ge 1 ] || { echo "droidcam_session: launch needs args" >&2; exit 1; }

    local statefile logfile
    statefile="$(statefile_for "$session")"
    logfile="$(logfile_for "$session")"

    local port mode ip
    port="$(extract_port "$@")"
    mode="wifi"
    for a in "$@"; do
        [ "$a" = "adb" ] && mode="usb" && break
    done
    ip="$(extract_ip "$mode" "$@")"

    # If a live process with the same signature + port already exists, adopt
    # it instead of double-launching.
    local existing
    existing="$(find_running "$session" "$port" 2>/dev/null || true)"
    if [ -n "$existing" ]; then
        local cl
        cl="$(cmdline_of "$existing")"
        atomically_write "$statefile" \
            "{\"pid\":\"$existing\",\"started\":$(date +%s),\"port\":\"$port\",\"mode\":\"$mode\",\"ip\":\"$ip\",\"cmdline\":\"$cl\"}"
        echo "$existing"
        exit 0
    fi

    # An idle wireless ADB transport drops the first command thrown at it.
    # scrcpy then dies on startup with "Could not list ADB devices" or a
    # failed "adb push", while `adb devices` looks perfectly healthy a second
    # later. Waking the transport first noticeably improves launch odds.
    # Bounded, because an unreachable phone must not hang the launch.
    case "$session" in
        scrcpy-mic)
            timeout 3 adb devices  > /dev/null 2>&1 || true
            timeout 3 adb shell true > /dev/null 2>&1 || true
            ;;
    esac

    # The detached process reports its own PID: `exec` replaces this inner
    # shell, so what lands in the pidfile IS the binary. $! cannot be used
    # (setsid's parent exits at once), and re-deriving the PID by scanning
    # the process table made a perfectly healthy session look like a failed
    # launch every time the scan came up empty.
    local pidfile="$STATE_DIR/$session.pid"
    rm -f "$pidfile"
    setsid nohup bash -c 'echo $$ > "$1"; shift; exec "$@"' _ "$pidfile" "$bin" "$@" \
        > "$logfile" 2>&1 < /dev/null &

    local pid=""
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        sleep 0.1
        if [ -s "$pidfile" ]; then pid="$(cat "$pidfile" 2>/dev/null || true)"; break; fi
    done
    is_alive "$pid" || pid=""
    # Last resort for a session adopted from an earlier launch.
    if [ -z "$pid" ]; then
        pid="$(find_running "$session" "$port" 2>/dev/null || true)"
    fi
    if [ -z "$pid" ]; then
        echo "droidcam_session: failed to start session '$session'" >&2
        exit 1
    fi

    local cl
    cl="$(cmdline_of "$pid")"
    atomically_write "$statefile" \
        "{\"pid\":\"$pid\",\"started\":$(date +%s),\"port\":\"$port\",\"mode\":\"$mode\",\"ip\":\"$ip\",\"cmdline\":\"$cl\"}"
    echo "$pid"
}

# cmd_status <session> → JSON:
#   {session,pid,alive,started,port,mode,ip,device,video_running,audio_running}
cmd_status() {
    local session="$1"
    local statefile logfile
    statefile="$(statefile_for "$session")"
    logfile="$(logfile_for "$session")"

    local pid="" alive="false" port="" mode="unknown" ip="" started=""
    if [ -f "$statefile" ]; then
        pid="$(read_json_field "$statefile" pid)"
        port="$(read_json_field "$statefile" port)"
        mode="$(read_json_field "$statefile" mode)"
        ip="$(read_json_field "$statefile" ip)"
        started="$(read_json_field "$statefile" started)"
        [ -z "$mode" ] && mode="unknown"
        if is_alive "$pid"; then
            alive="true"
        else
            pid=""
        fi
    fi

    # Stale/absent state — try to re-discover a live process for this session.
    if [ "$alive" = "false" ]; then
        pid="$(find_running "$session" "$port" 2>/dev/null || true)"
        if [ -n "$pid" ]; then
            alive="true"
            local cl
            cl="$(cmdline_of "$pid")"
            if [ -z "$port" ]; then
                port="$(extract_port $cl)"
            fi
            case "$cl" in
                *" adb "*) mode="usb" ;;
                *) mode="wifi" ;;
            esac
            if [ "$mode" = "wifi" ] && [ -z "$ip" ]; then
                ip="$(extract_ip "$mode" $cl)"
            fi
            [ -z "$started" ] && started="$(stat -c %Y "/proc/$pid" 2>/dev/null || echo 0)"
        fi
    fi

    local video_running="false" audio_running="false"
    case "$session" in
        video)      [ "$alive" = "true" ] && video_running="true" ;;
        audio|scrcpy-mic) [ "$alive" = "true" ] && audio_running="true" ;;
    esac

    # Device: droidcam sessions print "Video: /dev/videoN" on stdout (logged).
    local device=""
    if [ -f "$logfile" ]; then
        device="$(grep -oE 'Video: /dev/video[0-9]+' "$logfile" | head -n1 | awk '{print $2}' || true)"
    fi

    printf '{"session":"%s","pid":"%s","alive":%s,"started":"%s","port":"%s","mode":"%s","ip":"%s","device":"%s","video_running":%s,"audio_running":%s}\n' \
        "$session" "$pid" "$alive" "$started" "$port" "$mode" "$ip" "$device" "$video_running" "$audio_running"
}

# cmd_stop <session> — kill the saved PID only if the cmdline still matches.
cmd_stop() {
    local session="$1"
    local statefile
    statefile="$(statefile_for "$session")"
    if [ ! -f "$statefile" ]; then
        # No state — still try to stop any matching live process.
        local stray
        stray="$(find_running "$session" "" 2>/dev/null || true)"
        if [ -n "$stray" ]; then
            kill -TERM "$stray" 2>/dev/null || true
            for _ in 1 2 3 4 5 6 7 8; do
                is_alive "$stray" || break
                sleep 0.25
            done
            is_alive "$stray" && kill -KILL "$stray" 2>/dev/null || true
        fi
        echo "droidcam_session: no state for '$session'" >&2
        exit 0
    fi

    local pid
    pid="$(read_json_field "$statefile" pid)"
    if [ -z "$pid" ] || ! is_alive "$pid"; then
        rm -f "$statefile"
        echo "droidcam_session: '$session' not running" >&2
        exit 0
    fi

    # Safety: only kill if the cmdline still looks like our kind of process.
    local cl
    cl="$(cmdline_of "$pid")"
    case "$cl" in
        *"droidcam-cli"*|*"scrcpy"*)
            kill -TERM "$pid" 2>/dev/null
            for _ in 1 2 3 4 5 6 7 8; do
                is_alive "$pid" || break
                sleep 0.25
            done
            if is_alive "$pid"; then
                kill -KILL "$pid" 2>/dev/null || true
            fi
            ;;
        *)
            echo "droidcam_session: pid $pid no longer matches droidcam/scrcpy — not killing" >&2
            ;;
    esac
    rm -f "$statefile"
}

# cmd_killall — stop every tracked session.
cmd_killall() {
    for session in video audio scrcpy-mic; do
        cmd_stop "$session" >/dev/null 2>&1 || true
    done
}

# ─── Dispatch ────────────────────────────────────────────────────────────

case "${1:-}" in
    launch)  shift; cmd_launch "$@" ;;
    status)  shift; cmd_status "$@" ;;
    stop)    shift; cmd_stop "$@" ;;
    killall) shift; cmd_killall "$@" ;;
    *)
        echo "Usage: droidcam_session.sh {launch|status|stop|killall} <session> [args...]" >&2
        exit 1
        ;;
esac
