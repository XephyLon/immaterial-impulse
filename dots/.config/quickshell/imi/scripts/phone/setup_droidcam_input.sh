#!/usr/bin/env bash
# setup_droidcam_input.sh — Creates a virtual null-sink for routing the DroidCam
# audio stream as a microphone source in PulseAudio/PipeWire.
#
# Why: droidcam-cli (in audio mode) writes PCM to the default sink. To use it
# as a *microphone* (source), we create a null-sink named "DroidCam-Mic" whose
# `.monitor` source becomes an available input device for system apps.
#
# Output: prints the monitor source name on stdout ("DroidCam-Mic.monitor", or
#         "alsa_output.DroidCam-Mic.monitor" on a server that prefixes it)
#         so the QML service can use it with `pactl set-source-*` commands.
# Exit codes: 0 on success (sink already existed or was created), 1 on failure.

set -u

SINK_NAME="DroidCam-Mic"
SINK_DESC="DroidCam Microphone"

if ! command -v pactl >/dev/null 2>&1; then
    echo "pactl not installed" >&2
    exit 1
fi

# find_monitor → the null-sink's monitor source name, empty when it is absent.
#
# There is ONE resolution now, and that is the whole fix. The idempotence
# check used to ask for `DroidCam-Mic.monitor` alone, while the lookup after a
# fresh load — twenty lines below it, for the same fact — tried
# `alsa_output.DroidCam-Mic.monitor` FIRST and then two fallbacks. So on a
# server using the prefixed form that does not also propagate
# `device.description`, the existing-sink branch missed a sink it had already
# loaded and loaded a second one under the same name, on every call, while
# teardown removed one per call. Driven against a fake server: three setups,
# three null sinks.
find_monitor() {
    local name resolved
    for name in "alsa_output.${SINK_NAME}.monitor" "${SINK_NAME}.monitor"; do
        resolved="$(pactl list short sources 2>/dev/null \
            | awk -v m="$name" '$2 == m { print $2; exit }')"
        if [ -n "$resolved" ]; then
            echo "$resolved"
            return 0
        fi
    done
    # Last resort: the server named it something else entirely, so ask by the
    # description the sink was loaded with.
    resolved="$(pactl list sources 2>/dev/null | awk -v desc="$SINK_DESC" '
        /Name:/ { name=$2 }
        /Description:/ && $0 ~ desc { print name; exit }
    ')"
    [ -n "$resolved" ] || return 1
    echo "$resolved"
}

# Already loaded? Then the monitor it published is the answer (idempotent).
existing="$(pactl list short sinks 2>/dev/null | awk -v sink="$SINK_NAME" '$2 == sink {print $1; exit}' || true)"
if [ -n "$existing" ]; then
    monitor_name="$(find_monitor || true)"
    if [ -n "$monitor_name" ]; then
        echo "$monitor_name"
        exit 0
    fi
    # A sink whose monitor cannot be named is not usable; fall through to the
    # load rather than reporting a source nothing can open.
fi

# Load module-null-sink with the DroidCam name and description. The index it
# prints is the handle teardown otherwise reconstructs by grepping, and it was
# being discarded into /dev/null — so the failure path below had nothing to
# undo with.
module_id="$(pactl load-module module-null-sink \
    sink_name="$SINK_NAME" \
    sink_properties="device.description='$SINK_DESC'" \
    2>/dev/null)" || {
        echo "Failed to load module-null-sink" >&2
        exit 1
    }

found="$(find_monitor || true)"

if [ -z "$found" ]; then
    # Undo what this run did before giving up. Exiting 1 with the module still
    # resident left a null sink behind on every failed attempt, and the caller
    # never learned there was one to unload.
    case "$module_id" in
        ''|*[!0-9]*) ;;
        *) pactl unload-module "$module_id" >/dev/null 2>&1 || true ;;
    esac
    echo "Could not find monitor source after loading null-sink" >&2
    exit 1
fi

echo "$found"
exit 0
