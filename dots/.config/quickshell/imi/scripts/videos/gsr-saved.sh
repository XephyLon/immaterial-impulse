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
