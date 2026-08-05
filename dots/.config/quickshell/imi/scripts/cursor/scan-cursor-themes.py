#!/usr/bin/env python3
"""Scan cursor-theme directories and emit selectable themes as JSON.

Usage: scan-cursor-themes.py [ROOT ...]
Defaults to the standard icon roots when no ROOT is given.

A directory is a cursor theme when it ships either format:
  - XCursor:    a `cursors/` subdirectory
  - hyprcursor: a `manifest.hl`/`manifest.toml` (its `hyprcursors/` payload
    directory only exists once extracted, so the manifest is the marker)
`hyprctl setcursor` accepts both (hyprcursor preferred, XCursor fallback), so
the two formats are listed together rather than as separate sections.
Output: JSON array of {id, name, path, xcursor, hyprcursor} sorted by name.
"""
import configparser
import json
import os
import re
import sys

EXCLUDE_IDS = {"default", "hicolor", "locolor"}
HYPRCURSOR_MANIFESTS = ("manifest.hl", "manifest.toml")


def default_roots():
    home = os.path.expanduser("~")
    data_home = os.environ.get("XDG_DATA_HOME", f"{home}/.local/share")
    return [f"{data_home}/icons", f"{home}/.icons", "/usr/share/icons"]


def index_theme_name(theme_dir):
    path = os.path.join(theme_dir, "index.theme")
    if not os.path.isfile(path):
        return ""
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    try:
        cp.read(path, encoding="utf-8")
    except (configparser.Error, UnicodeDecodeError):
        return ""
    return cp.get("Icon Theme", "Name", fallback="").strip()


def hyprcursor_manifest_name(theme_dir):
    for manifest in HYPRCURSOR_MANIFESTS:
        path = os.path.join(theme_dir, manifest)
        if not os.path.isfile(path):
            continue
        try:
            text = open(path, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError):
            continue
        match = re.search(r'^\s*name\s*=\s*"?([^"\n]+)"?\s*$', text, re.MULTILINE)
        if match:
            return match.group(1).strip()
    return ""


def has_hyprcursor(theme_dir):
    return any(os.path.isfile(os.path.join(theme_dir, m))
               for m in HYPRCURSOR_MANIFESTS)


def scan(roots):
    seen = set()
    themes = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for entry in sorted(os.listdir(root)):
            theme_dir = os.path.join(root, entry)
            if entry in seen or entry in EXCLUDE_IDS or not os.path.isdir(theme_dir):
                continue
            xcursor = os.path.isdir(os.path.join(theme_dir, "cursors"))
            hyprcursor = has_hyprcursor(theme_dir)
            if not xcursor and not hyprcursor:
                continue
            name = (index_theme_name(theme_dir)
                    or hyprcursor_manifest_name(theme_dir)
                    or entry)
            seen.add(entry)
            themes.append({
                "id": entry,
                "name": name,
                "path": theme_dir,
                "xcursor": xcursor,
                "hyprcursor": hyprcursor,
            })
    themes.sort(key=lambda t: t["name"].lower())
    return themes


def main():
    roots = sys.argv[1:] or default_roots()
    json.dump(scan(roots), sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
