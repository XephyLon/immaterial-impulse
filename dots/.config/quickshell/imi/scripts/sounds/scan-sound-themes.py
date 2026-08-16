#!/usr/bin/env python3
"""Report what is in the XDG sound-theme roots, as JSON. Decides nothing.

Usage: scan-sound-themes.py [ROOT ...]
Defaults to the standard sound roots when no ROOT is given.

Output: {"roots": [...], "entries": [{theme, dir, index, files}, ...]} with the
entries in root precedence order, so the same theme installed in two roots
appears twice with the higher-precedence copy first.

Every choice about the data - which subdirectory, which extension, when to walk
an Inherits= chain, what a sidecar file is - belongs to services/sound_theme.js,
which a test can reach. This script only says what exists. Deliberately no
filtering by extension for the same reason: "that file is not a sound" is a
judgement, and it is one the resolver already makes by building exact
<event><extension> names.
"""
import json
import os
import sys

# A sound theme is a few dozen small files. These bounds exist so a root that is
# not what we think it is - a symlink into $HOME, a mount point - cannot turn a
# startup scan into a filesystem crawl.
MAX_FILES_PER_THEME = 4000
MAX_DEPTH = 4
MAX_INDEX_BYTES = 64 * 1024


def default_roots():
    home = os.path.expanduser("~")
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(home, ".local", "share")
    data_dirs = os.environ.get("XDG_DATA_DIRS") or "/usr/local/share:/usr/share"
    roots = [os.path.join(data_home, "sounds"), os.path.join(home, ".sounds")]
    roots += [os.path.join(d, "sounds") for d in data_dirs.split(":") if d]
    roots.append("/usr/share/sounds")
    seen = set()
    ordered = []
    for root in roots:
        if root not in seen:
            seen.add(root)
            ordered.append(root)
    return ordered


def read_index(theme_dir):
    path = os.path.join(theme_dir, "index.theme")
    try:
        with open(path, "rb") as handle:
            return handle.read(MAX_INDEX_BYTES).decode("utf-8", "replace")
    except OSError:
        return ""


def list_files(theme_dir):
    files = []
    base_depth = theme_dir.rstrip("/").count("/")
    for current, subdirs, names in os.walk(theme_dir, followlinks=False):
        if current.rstrip("/").count("/") - base_depth >= MAX_DEPTH:
            subdirs[:] = []
        for name in names:
            files.append(os.path.relpath(os.path.join(current, name), theme_dir))
            if len(files) >= MAX_FILES_PER_THEME:
                return sorted(files)
    return sorted(files)


def scan(roots):
    entries = []
    for root in roots:
        if not os.path.isdir(root):
            continue
        try:
            names = sorted(os.listdir(root))
        except OSError:
            continue
        for name in names:
            theme_dir = os.path.join(root, name)
            if not os.path.isdir(theme_dir):
                continue
            entries.append({
                "theme": name,
                "dir": theme_dir,
                "index": read_index(theme_dir),
                "files": list_files(theme_dir),
            })
    return entries


def main():
    roots = sys.argv[1:] or default_roots()
    json.dump({"roots": roots, "entries": scan(roots)}, sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
