#!/usr/bin/env bash
# gpu-screen-recorder -sc hook: called after a file is saved.
#   $1 = saved file path, $2 = "regular" | "replay" | "screenshot"
# Kept dead simple - it runs inside gsr's process context on every save.
path="$1"
type="$2"
case "$type" in
    replay) title="Replay saved" ;;
    regular) title="Recording saved" ;;
    screenshot) title="Screenshot saved" ;;
    *) title="Saved" ;;
esac
notify-send "$title" "${path##*/}" -a 'Recorder' -i video-x-generic & disown

# A save landing is the event the SDR delivery observes - recordings and
# replays alike, which is exactly why it hangs off this hook rather than off
# record.sh (replays never pass through record.sh). Detached: this hook runs
# inside gsr's process context, and a re-encode must not block or die with it.
# The tonemap script decides for itself whether to act (toggle + HDR probe),
# keeping this hook dumb.
case "$type" in
    regular|replay)
        setsid -f bash "$(dirname "$0")/tonemap-sdr.sh" "$path" >/dev/null 2>&1
        ;;
esac
