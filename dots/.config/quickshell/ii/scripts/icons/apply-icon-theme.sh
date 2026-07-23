#!/usr/bin/env bash
# Apply a system-wide icon theme: GTK 3/4 settings.ini + kdeglobals + gsettings.
# The theme id is the directory name of an installed icon theme. It is validated
# and passed as an argv element to every command (never spliced into a shell
# string), mirroring the injection-safe pattern used across this shell.
set -euo pipefail

id="${1:-}"

# Whitelist the id to filesystem-safe characters (theme directory names). This
# blocks path traversal (no '/'), and command/expansion metacharacters.
if ! [[ "$id" =~ ^[A-Za-z0-9\ ._+-]+$ ]]; then
    echo "apply-icon-theme: invalid theme id: '$id'" >&2
    exit 2
fi

# Confirm the theme actually exists under a known icon root before applying, so
# a value that passed the charset check but is not a real theme is still refused.
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
found=0
for root in "$data_home/icons" "$HOME/.icons" /usr/share/icons; do
    if [ -d "$root/$id" ]; then found=1; break; fi
done
if [ "$found" -ne 1 ]; then
    echo "apply-icon-theme: theme not found: '$id'" >&2
    exit 3
fi

# GTK 3/4 settings.ini and kdeglobals are plain ini; edit them with configparser
# so unrelated keys/sections are preserved. matugen owns gtk.css, not these
# files, so these writes are not clobbered by a later color run. id arrives as
# argv (sys.argv[1]), never interpolated into the script text.
python3 - "$id" <<'PY'
import sys, os, configparser
theme = sys.argv[1]
home = os.path.expanduser("~")

def set_key(path, section, key, value):
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str  # keep key case (gtk-icon-theme-name, Theme)
    if os.path.exists(path):
        cp.read(path, encoding="utf-8")
    if not cp.has_section(section):
        cp.add_section(section)
    cp.set(section, key, value)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        cp.write(f, space_around_delimiters=False)

set_key(f"{home}/.config/gtk-3.0/settings.ini", "Settings", "gtk-icon-theme-name", theme)
set_key(f"{home}/.config/gtk-4.0/settings.ini", "Settings", "gtk-icon-theme-name", theme)
set_key(f"{home}/.config/kdeglobals", "Icons", "Theme", theme)
PY

# Live signal for running GTK/Qt apps (same idiom as switchwall.sh). Best-effort:
# absent schema (e.g. CI) must not fail the apply - the ini writes already stuck.
gsettings set org.gnome.desktop.interface icon-theme "$id" 2>/dev/null || true

echo "$id"
