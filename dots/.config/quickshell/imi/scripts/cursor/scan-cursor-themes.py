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
Each theme also gets a PNG preview of its pointer, extracted from the theme's
own Xcursor file (left_ptr/default/arrow) into --preview-dir. Qt cannot decode
the Xcursor container, but the format is trivial - "Xcur" magic, a TOC, and
raw premultiplied ARGB32 frames - so it is parsed here with the stdlib and
written out as PNG (struct + zlib; no PIL, no xcur2png). Preview extraction is
best-effort: a theme whose pointer cannot be parsed simply ships no
previewPath, and the UI falls back to an icon.

Usage: scan-cursor-themes.py [--preview-dir DIR] [ROOT ...]
Output: JSON array of {id, name, path, xcursor, hyprcursor, previewPath}
sorted by name.
"""
import configparser
import json
import os
import re
import struct
import sys
import zlib

EXCLUDE_IDS = {"default", "hicolor", "locolor"}
HYPRCURSOR_MANIFESTS = ("manifest.hl", "manifest.toml")
POINTER_NAMES = ("left_ptr", "default", "arrow")
XCURSOR_MAGIC = b"Xcur"
XCURSOR_IMAGE_TYPE = 0xFFFD0002
PREVIEW_NOMINAL = 64  # frame size to prefer; QML scales it down crisply


def parse_xcursor_frame(path, nominal=PREVIEW_NOMINAL):
    """Return (width, height, rgba_bytes) for the frame nearest `nominal`,
    or None. Pixels convert from premultiplied ARGB32-LE to the straight
    RGBA that PNG wants."""
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        return None
    if len(data) < 16 or data[:4] != XCURSOR_MAGIC:
        return None
    ntoc = struct.unpack_from("<I", data, 12)[0]
    best = None  # (size_distance, position)
    for i in range(min(ntoc, 4096)):
        off = 16 + i * 12
        if off + 12 > len(data):
            return None
        ctype, subtype, position = struct.unpack_from("<III", data, off)
        if ctype != XCURSOR_IMAGE_TYPE:
            continue
        dist = abs(subtype - nominal)
        if best is None or dist < best[0]:
            best = (dist, position)
    if best is None:
        return None
    pos = best[1]
    if pos + 36 > len(data):
        return None
    (_, _, _, _, width, height, _, _, _) = struct.unpack_from("<9I", data, pos)
    if not (0 < width <= 512 and 0 < height <= 512):
        return None
    npix = width * height
    if pos + 36 + npix * 4 > len(data):
        return None
    argb = data[pos + 36: pos + 36 + npix * 4]
    rgba = bytearray(npix * 4)
    for p in range(npix):
        b, g, r, a = argb[p * 4: p * 4 + 4]
        if a not in (0, 255):
            r = min(255, r * 255 // a)
            g = min(255, g * 255 // a)
            b = min(255, b * 255 // a)
        rgba[p * 4: p * 4 + 4] = bytes((r, g, b, a))
    return width, height, bytes(rgba)


def write_png(path, width, height, rgba):
    def chunk(tag, payload):
        out = struct.pack(">I", len(payload)) + tag + payload
        return out + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    raw = b"".join(b"\x00" + rgba[y * width * 4:(y + 1) * width * 4]
                   for y in range(height))
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n")
        f.write(chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)))
        f.write(chunk(b"IDAT", zlib.compress(raw, 9)))
        f.write(chunk(b"IEND", b""))


def extract_preview(theme_dir, preview_dir, theme_id):
    cursors = os.path.join(theme_dir, "cursors")
    for name in POINTER_NAMES:
        cur = os.path.join(cursors, name)
        if not os.path.isfile(cur):
            continue
        frame = parse_xcursor_frame(os.path.realpath(cur))
        if frame is None:
            continue
        out = os.path.join(preview_dir, f"{theme_id}.png")
        try:
            write_png(out, *frame)
        except OSError:
            return ""
        return out
    return ""


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


def scan(roots, preview_dir=""):
    if preview_dir:
        os.makedirs(preview_dir, exist_ok=True)
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
            preview = ""
            if preview_dir and xcursor:
                preview = extract_preview(theme_dir, preview_dir, entry)
            themes.append({
                "id": entry,
                "name": name,
                "path": theme_dir,
                "xcursor": xcursor,
                "hyprcursor": hyprcursor,
                "previewPath": preview,
            })
    themes.sort(key=lambda t: t["name"].lower())
    return themes


def main():
    args = sys.argv[1:]
    preview_dir = ""
    if "--preview-dir" in args:
        i = args.index("--preview-dir")
        preview_dir = args[i + 1]
        del args[i:i + 2]
    roots = args or default_roots()
    json.dump(scan(roots, preview_dir), sys.stdout)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
