#!/usr/bin/env bash
# droidcam_status.sh — Emits JSON state of DroidCam installation and active devices.
# Called from PhoneCameraService / PhoneMicService on demand.
#
# Output shape:
# {
#   "installed": true|false,
#   "v4l2_device": "/dev/videoN" or "",
#   "device_has_stream": true|false,
#   "audio_source": "alsa_output.droidcam_input.monitor" or "",
#   "audio_has_sink_input": true|false,
#   "audio_running": true|false,
#   "video_running": true|false,
#   "video_pid": 12345 or 0,
#   "video_port": 4747 or 0,
#   "video_mode": "wifi"|"usb"|""
# }
#
# This script is READ-ONLY — it never starts/stops anything.

set -u
IFS=$'\n\t'

installed=false
v4l2_device=""
device_has_stream=false
audio_source=""
audio_has_sink_input=false
audio_running=false
video_running=false
video_pid=0
video_port=0
video_mode=""

if command -v droidcam-cli >/dev/null 2>&1; then
    installed=true
fi

# ─── Video: /dev/videoN associated with DroidCam (v4l2loopback) ─────────
# `v4l2-ctl --list-devices` output looks like:
#   DroidCam (usb-0000:00:14.0-...):
#       /dev/video10
#       /dev/video11
# We pick the first /dev/videoN under a DroidCam-named block, then fall back
# to any v4l2loopback device when no explicit DroidCam block exists.
if command -v v4l2-ctl >/dev/null 2>&1; then
    list_output="$(v4l2-ctl --list-devices 2>/dev/null || true)"
    if [ -n "$list_output" ]; then
        in_droidcam_block=false
        for line in $list_output; do
            if echo "$line" | grep -qi "droidcam"; then
                in_droidcam_block=true
                continue
            fi
            if $in_droidcam_block; then
                if echo "$line" | grep -qE '^\s*/dev/video[0-9]+'; then
                    v4l2_device="$(echo "$line" | awk '{print $1}')"
                    break
                else
                    # Block ended (a new device name line appeared).
                    in_droidcam_block=false
                fi
            fi
        done
    fi

    # Fallback: no DroidCam-named block, but a v4l2loopback device exists.
    # Only treated as a DroidCam target when a droidcam-cli process is
    # actually running (see below) — otherwise a leftover scrcpy-loopback
    # device would be misreported as the webcam.
    if [ -z "$v4l2_device" ] && [ -n "$list_output" ]; then
        in_loop_block=false
        for line in $list_output; do
            if echo "$line" | grep -qiE "loopback|v4l2loopback"; then
                in_loop_block=true
                continue
            fi
            if $in_loop_block; then
                if echo "$line" | grep -qE '^\s*/dev/video[0-9]+'; then
                    v4l2_device="$(echo "$line" | awk '{print $1}')"
                    break
                else
                    in_loop_block=false
                fi
            fi
        done
    fi
fi

# ─── Processes: droidcam-cli (video or audio) and scrcpy (mic) ──────────
if command -v pgrep >/dev/null 2>&1; then
    for pid in $(pgrep -x droidcam-cli 2>/dev/null); do
        cl="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//')"
        case "$cl" in
            *' -a '*|*'-a '*)   # audio mode: droidcam-cli ... -a ...
                audio_running=true
                ;;
            *)                   # video mode
                if [ "$video_pid" -eq 0 ]; then
                    video_pid="$pid"
                    video_mode="wifi"
                    case "$cl" in
                        *' adb '*) video_mode="usb" ;;
                    esac
                    # Port = the last token, when it is a number.
                    # `grep ... | tail -n1 || echo 0` never fell back: grep
                    # exits 1 with no match but `tail` exits 0, so the
                    # pipeline succeeded with an empty answer and the
                    # unquoted `%s` below emitted `"video_port":,`. That is
                    # invalid JSON, so the QML JSON.parse threw and EVERY
                    # field in the payload was lost, not just the port - and
                    # the pattern only ever admitted 3-to-5-digit ports, so
                    # a configured port of 80 was enough to trigger it.
                    # droidcam-cli's argv ends `<ip|adb> <port>`, so the last
                    # word is the answer and there is nothing to search for.
                    last_token="${cl##* }"
                    case "$last_token" in
                        ''|*[!0-9]*) video_port=0 ;;
                        *)           video_port="$last_token" ;;
                    esac
                fi
                video_running=true
                ;;
        esac
    done
    # scrcpy with --audio-source=mic is an audio session too.
    for pid in $(pgrep -x scrcpy 2>/dev/null); do
        cl="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//')"
        case "$cl" in
            *'--audio-source=mic'*) audio_running=true ;;
        esac
    done
fi

# ─── device_has_stream: only meaningful while a droidcam video process runs ─
# A v4l2loopback device with the client NOT connected usually fails or
# reports an empty/invalid format. Timeout guards against a hung ioctl.
# The device may have been resolved from a DroidCam-named block (with a live
# process) or from the generic loopback fallback — but only when video is
# running do we claim an active stream.
if [ "$video_running" = "true" ] && [ -n "$v4l2_device" ] && command -v v4l2-ctl >/dev/null 2>&1; then
    fmt_out="$(timeout 2 v4l2-ctl -d "$v4l2_device" --get-fmt-video 2>/dev/null || true)"
    if [ -n "$fmt_out" ] && echo "$fmt_out" | grep -q "Width/Height"; then
        device_has_stream=true
    fi
fi

# ─── Audio: virtual null-sink "DroidCam-Mic" + active sink-input ────────
if command -v pactl >/dev/null 2>&1; then
    sources_output="$(pactl list sources short 2>/dev/null || true)"
    if [ -n "$sources_output" ]; then
        # `pactl list sources short` is `<index>\t<name>\t...`, so the
        # source's NAME is field 2. This printed field 1 - the index - while
        # this file's own header documents a name
        # (`alsa_output.droidcam_input.monitor`) and
        # `tst_phone_scrcpy.qml` feeds `PhoneMic.parseStatus` a name. Both
        # sides agreed with each other and neither agreed with the producer.
        match="$(echo "$sources_output" | awk '$0 ~ /DroidCam-Mic/ || $0 ~ /droidcam/ {print $2; exit}')"
        if [ -n "$match" ]; then
            audio_source="$match"
        fi
    fi

    # audio_has_sink_input: something is actively feeding DroidCam-Mic.
    # Sink-input blocks carry no "State:" line (only sinks do) and name
    # their sink by index, so scanning them for a running DroidCam-Mic
    # input can never match. The null-sink itself reports RUNNING exactly
    # while an uncorked stream feeds it — that is the evidence we want.
    if pactl list short sinks 2>/dev/null \
        | awk '$2 == "DroidCam-Mic" && $NF == "RUNNING" { found=1 } END { exit found ? 0 : 1 }'; then
        audio_has_sink_input=true
    fi
fi

# Emit JSON. printf to avoid echo interpreting backslashes.
printf '{"installed":%s,"v4l2_device":%s,"device_has_stream":%s,"audio_source":%s,"audio_has_sink_input":%s,"audio_running":%s,"video_running":%s,"video_pid":%s,"video_port":%s,"video_mode":%s}\n' \
    "$( $installed && echo true || echo false )" \
    "\"$v4l2_device\"" \
    "$( $device_has_stream && echo true || echo false )" \
    "\"$audio_source\"" \
    "$( $audio_has_sink_input && echo true || echo false )" \
    "$( $audio_running && echo true || echo false )" \
    "$( $video_running && echo true || echo false )" \
    "$video_pid" \
    "$video_port" \
    "\"$video_mode\""
