#!/usr/bin/env bash
# Apply the cursor theme/size chosen in Settings > Cursor at Hyprland start.
# Reads the shell config directly rather than hardcoding a literal, so this
# line no longer clobbers the user's choice on every start. Falls back to the
# former hardcoded values (Bibata-Modern-Classic 24) when no config exists yet
# or the keys are absent.
set -u

theme="Bibata-Modern-Classic"
size=24

cfg="$HOME/.config/immaterial-impulse/config.json"
# Pre-migration installs still hold their config under the legacy name; the
# shell migrates it on first start, which may not have happened yet at this
# point in Hyprland's startup.
[ -f "$cfg" ] || cfg="$HOME/.config/illogical-impulse/config.json"

if [ -f "$cfg" ]; then
    saved="$(python3 - "$cfg" <<'PY'
import json, sys
try:
    cursor = json.load(open(sys.argv[1])).get("hyprland", {}).get("cursor", {})
    theme = str(cursor.get("theme", "") or "")
    size = int(cursor.get("size", 0) or 0)
except (OSError, ValueError, TypeError):
    theme, size = "", 0
print(theme)
print(size)
PY
)" || saved=""
    saved_theme="$(printf '%s\n' "$saved" | sed -n 1p)"
    saved_size="$(printf '%s\n' "$saved" | sed -n 2p)"
    [ -n "$saved_theme" ] && theme="$saved_theme"
    case "$saved_size" in
        ''|*[!0-9]*|0) ;;
        *) size="$saved_size" ;;
    esac
fi

exec hyprctl setcursor "$theme" "$size"
