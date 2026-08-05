#!/usr/bin/env bash
# Apply a cursor theme + size: hyprctl setcursor (Wayland-native clients) plus
# GTK settings.ini, ~/.icons/default/index.theme Inherits (the XCursor default
# pointer, which XWayland/X11 clients resolve without env vars) and gsettings.
# The theme id is the directory name of an installed cursor theme. It is
# validated and passed as an argv element to every command (never spliced into
# a shell string), mirroring apply-icon-theme.sh.
set -euo pipefail

id="${1:-}"
size="${2:-}"

# Whitelist the id to filesystem-safe characters (theme directory names). This
# blocks path traversal (no '/'), and command/expansion metacharacters.
if ! [[ "$id" =~ ^[A-Za-z0-9\ ._+-]+$ ]]; then
    echo "apply-cursor-theme: invalid theme id: '$id'" >&2
    exit 2
fi

if ! [[ "$size" =~ ^[0-9]+$ ]] || (( size < 8 || size > 256 )); then
    echo "apply-cursor-theme: invalid cursor size: '$size'" >&2
    exit 2
fi

# Confirm the theme actually ships cursors under a known icon root before
# applying, so a value that passed the charset check but is not a real cursor
# theme is still refused. Either format counts: an XCursor `cursors/` payload
# or a hyprcursor manifest.
data_home="${XDG_DATA_HOME:-$HOME/.local/share}"
found=0
for root in "$data_home/icons" "$HOME/.icons" /usr/share/icons; do
    if [ -d "$root/$id/cursors" ] || [ -f "$root/$id/manifest.hl" ] \
        || [ -f "$root/$id/manifest.toml" ]; then
        found=1
        break
    fi
done
if [ "$found" -ne 1 ]; then
    echo "apply-cursor-theme: cursor theme not found: '$id'" >&2
    exit 3
fi

# The compositor is the primary consumer; if it rejects the theme, fail before
# recording anything so the caller does not persist a theme that never applied.
hyprctl setcursor "$id" "$size"

# GTK 3/4 settings.ini keys and the XCursor default-theme stub are plain ini;
# edit them with configparser so unrelated keys/sections are preserved. id and
# size arrive as argv (sys.argv), never interpolated into the script text.
python3 - "$id" "$size" <<'PY'
import sys, os, configparser
theme, size = sys.argv[1], sys.argv[2]
home = os.path.expanduser("~")

def set_keys(path, section, pairs):
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str  # keep key case (gtk-cursor-theme-name, Inherits)
    if os.path.exists(path):
        cp.read(path, encoding="utf-8")
    if not cp.has_section(section):
        cp.add_section(section)
    for key, value in pairs:
        cp.set(section, key, value)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        cp.write(f, space_around_delimiters=False)

for gtk in ("gtk-3.0", "gtk-4.0"):
    set_keys(f"{home}/.config/{gtk}/settings.ini", "Settings",
             [("gtk-cursor-theme-name", theme), ("gtk-cursor-theme-size", size)])
set_keys(f"{home}/.icons/default/index.theme", "Icon Theme",
         [("Inherits", theme)])
PY

# Live signal for running GTK apps (same idiom as apply-icon-theme.sh).
# Best-effort: absent schema (e.g. CI) must not fail the apply - hyprctl and
# the ini writes already stuck.
gsettings set org.gnome.desktop.interface cursor-theme "$id" 2>/dev/null || true
gsettings set org.gnome.desktop.interface cursor-size "$size" 2>/dev/null || true

echo "$id $size"
