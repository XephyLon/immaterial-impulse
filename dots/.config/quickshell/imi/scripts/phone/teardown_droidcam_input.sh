#!/usr/bin/env bash
# teardown_droidcam_input.sh — Unloads the virtual null-sink created by
# setup_droidcam_input.sh, cleaning up audio routing after DroidCam stops.
#
# Idempotent: does nothing if the null-sink isn't loaded.
# Exit codes: 0 on success or no-op.

set -u

SINK_NAME="DroidCam-Mic"

if ! command -v pactl >/dev/null 2>&1; then
    exit 0
fi

# Find EVERY module ID of a null-sink with our name and unload all of them.
# `pactl list short modules` is the safest cross-server (PA/PW) way.
#
# The awk had an `exit` after the first match, so one call removed exactly one
# module. Nothing in the shell calls this in a loop, so a server that had
# accumulated duplicates — which setup_droidcam_input.sh used to produce, one
# per launch, on a naming its idempotence check could not see — kept all but
# one of them for the life of the session. Removing the `exit` costs nothing
# in the ordinary case, where there is exactly one.
module_ids="$(pactl list short modules 2>/dev/null | awk -v sink="$SINK_NAME" '
    $0 ~ "sink_name="sink { print $1 }
' || true)"

for module_id in $module_ids; do
    pactl unload-module "$module_id" >/dev/null 2>&1 || true
done

exit 0
