#!/usr/bin/env python3
"""Regression guard: Material Symbol icon names must exist in the installed font.

Multiple copies of "Material Symbols Rounded" can be installed (the SDDM theme
ships its own vintage), and fontconfig may resolve the family to the OLDEST
one - icon names added to Google's font later then render as raw ligature
text ("VIDEO_TE□LATE" instead of an icon). So every literal icon name used by
the shell must exist in EVERY installed copy of the font, not just the newest.

Checked literals (unambiguously Material names):
  - MaterialSymbol { text: "..." }  (same-line form)
  - text: "..." directly inside a MaterialSymbol block (next-line form)
  - buttonIcon: "..." / materialIcon: "..."

Dynamic expressions are skipped - only plain string literals are validated.
Exits 0 with a notice when fontTools or the font is unavailable (CI-safe).
"""

import glob
import os
import re
import subprocess
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

try:
    from fontTools.ttLib import TTFont
except ImportError:
    print("Material icon lint skipped: fontTools not installed")
    sys.exit(0)


def installed_fonts() -> list[str]:
    try:
        out = subprocess.run(["fc-list"], capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return []
    return sorted({
        line.split(":")[0]
        for line in out.splitlines()
        if "Material Symbols Rounded" in line
    })


fonts = installed_fonts()
if not fonts:
    print("Material icon lint skipped: Material Symbols Rounded not installed")
    sys.exit(0)

def ligature_names(path: str) -> set[str]:
    """Icon names an icon font actually renders: its GSUB ligatures.

    Glyph-order names are NOT reliable here - classic icons like location_on
    keep their ligature while their glyph is named differently. Walk the GSUB
    ligature substitutions and reconstruct each name from the cmap instead.
    """
    font = TTFont(path)
    to_char = {glyph: chr(code) for code, glyph in font.getBestCmap().items()}
    names = set()
    gsub = font.get("GSUB")
    if gsub is None:
        return names
    for lookup in gsub.table.LookupList.Lookup:
        for sub in lookup.SubTable:
            table = getattr(sub, "ExtSubTable", sub)
            ligatures = getattr(table, "ligatures", None)
            if not ligatures:
                continue
            for first, entries in ligatures.items():
                if first not in to_char:
                    continue
                for lig in entries:
                    components = [to_char.get(c) for c in lig.Component]
                    if None in components:
                        continue
                    names.add(to_char[first] + "".join(components))
    return names


# Names must exist in EVERY installed copy - fontconfig may pick any of them.
ligature_sets = []
for path in fonts:
    try:
        ligature_sets.append(ligature_names(path))
    except Exception as error:  # unreadable/corrupt copy: ignore it
        print(f"note: skipping unreadable font {path}: {error}")
if not any(ligature_sets):
    print("Material icon lint skipped: no readable font copy")
    sys.exit(0)
known = set.intersection(*(s for s in ligature_sets if s))

INLINE = re.compile(r'MaterialSymbol\s*\{[^}\n]*\btext:\s*"([a-z0-9_]+)"')
PROP = re.compile(r'\b(?:buttonIcon|materialIcon):\s*"([a-z0-9_]+)"')
BLOCK_TEXT = re.compile(r'\btext:\s*"([a-z0-9_]+)"')

violations = []
for f in glob.glob(ROOT + "/**/*.qml", recursive=True):
    if "/tests/" in f:
        continue
    rel = os.path.relpath(f, ROOT)
    lines = open(f).readlines()
    in_symbol_depth = None
    depth = 0
    for i, line in enumerate(lines, 1):
        for m in INLINE.finditer(line):
            if m.group(1) not in known:
                violations.append((rel, i, m.group(1)))
        for m in PROP.finditer(line):
            if m.group(1) not in known:
                violations.append((rel, i, m.group(1)))
        # Track multi-line MaterialSymbol { ... text: "..." ... } blocks.
        if in_symbol_depth is None and re.search(r"\bMaterialSymbol\s*\{", line) and "}" not in line.split("MaterialSymbol", 1)[1]:
            in_symbol_depth = depth
        depth += line.count("{") - line.count("}")
        if in_symbol_depth is not None:
            if depth <= in_symbol_depth:
                in_symbol_depth = None
            else:
                m = BLOCK_TEXT.search(line)
                if m and m.group(1) not in known:
                    violations.append((rel, i, m.group(1)))

# The inline regex and block scan can both hit the same line; dedupe.
violations = sorted(set(violations))

if violations:
    print("Material icon lint FAILED: names missing from an installed "
          "Material Symbols Rounded copy (oldest installed font wins in "
          "fontconfig - use a name every copy knows, or update the stale font):")
    for rel, line, name in violations:
        print(f"  {rel}:{line}  {name}")
    sys.exit(1)

print(f"Material icon lint passed: all literal icon names exist in {len(fonts)} installed font cop{'ies' if len(fonts) > 1 else 'y'}")
