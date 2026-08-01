#!/usr/bin/env python3
"""Scan icon-theme directories and emit selectable themes as JSON.

Usage: scan-icon-themes.py [ROOT ...]
Defaults to the standard icon roots when no ROOT is given.
Output: JSON array of {id, name, path, sampleIcons:[abs path,...]} sorted by name.
"""
import configparser
import json
import os
import sys

# App-ish icon names we try to preview, in preference order. Whatever resolves
# first (up to SAMPLE_COUNT) is used; a theme that ships none simply gets fewer.
SAMPLE_NAMES = [
    "firefox", "org.mozilla.firefox", "google-chrome", "code",
    "folder", "user-home", "text-editor", "org.gnome.TextEditor",
    "system-settings", "preferences-system", "utilities-terminal", "terminal",
]
SAMPLE_COUNT = 4
ICON_EXTS = (".svg", ".png")
EXCLUDE_IDS = {"hicolor", "default", "locolor"}


def default_roots():
    home = os.path.expanduser("~")
    data_home = os.environ.get("XDG_DATA_HOME", f"{home}/.local/share")
    return [f"{data_home}/icons", f"{home}/.icons", "/usr/share/icons"]


def parse_index(path):
    cp = configparser.ConfigParser(interpolation=None, strict=False)
    cp.optionxform = str
    try:
        cp.read(path, encoding="utf-8")
    except (configparser.Error, UnicodeDecodeError):
        return None
    if not cp.has_section("Icon Theme"):
        return None
    name = cp.get("Icon Theme", "Name", fallback="").strip()
    dirs = cp.get("Icon Theme", "Directories", fallback="").strip()
    dir_list = [d.strip() for d in dirs.replace(",", " ").split() if d.strip()]
    return {"name": name, "dirs": dir_list, "cp": cp}


def is_selectable(meta, theme_id):
    if theme_id in EXCLUDE_IDS:
        return False
    if theme_id.lower().endswith("cursors") or theme_id.lower().endswith("cursor"):
        return False
    non_cursor = [d for d in meta["dirs"] if "cursor" not in d.lower()]
    return bool(non_cursor)


def find_samples(theme_dir, meta):
    # Prefer larger, scalable, apps/places dirs first for nicer previews.
    def score(d):
        s = 0
        if "scalable" in d:
            s += 1000
        for token in d.replace("/", "x").split("x"):
            if token.isdigit():
                s = max(s, int(token))
        if "apps" in d or "places" in d:
            s += 5
        return s

    ordered = sorted(meta["dirs"], key=score, reverse=True)
    samples = []
    for name in SAMPLE_NAMES:
        for d in ordered:
            hit = None
            for ext in ICON_EXTS:
                candidate = os.path.join(theme_dir, d, name + ext)
                if os.path.isfile(candidate):
                    hit = candidate
                    break
            if hit:
                samples.append(hit)
                break
        if len(samples) >= SAMPLE_COUNT:
            break
    return samples


def scan(roots):
    seen = set()
    themes = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        for entry in sorted(os.listdir(root)):
            theme_dir = os.path.join(root, entry)
            index = os.path.join(theme_dir, "index.theme")
            if entry in seen or not os.path.isfile(index):
                continue
            meta = parse_index(index)
            if not meta or not is_selectable(meta, entry):
                continue
            samples = find_samples(theme_dir, meta)
            if not samples:
                # No previewable icons resolved: skip (nothing to show, likely
                # a symbolic-only or incomplete theme).
                continue
            seen.add(entry)
            themes.append({
                "id": entry,
                "name": meta["name"] or entry,
                "path": theme_dir,
                "sampleIcons": samples,
            })
    themes.sort(key=lambda t: t["name"].lower())
    return themes


def main():
    roots = sys.argv[1:] or default_roots()
    json.dump(scan(roots), sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
