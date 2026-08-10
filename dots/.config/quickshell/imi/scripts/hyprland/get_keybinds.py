#!/usr/bin/env python3
import argparse
import re
import os
import json
from typing import Dict, List, Optional

HIDE_MARKERS = ["[hidden]", "# [hidden]"]

# Boolean options an hl.bind() call may carry besides `description`. The
# keyboard-shortcuts editor re-emits these verbatim when it rebinds a default,
# so a rebound `locked` bind keeps working on the lockscreen.
KNOWN_BIND_FLAGS = {
    "locked", "repeating", "mouse", "release", "non_consuming",
    "ignore_mods", "transparent", "submap_universal", "click", "drag",
}

parser = argparse.ArgumentParser(description='Hyprland Lua keybind reader')
parser.add_argument('--path', type=str, default="$HOME/.config/hypr/hyprland/keybinds.lua")
parser.add_argument('--flat', action='store_true',
                    help='Emit every statically parseable bind (hidden and '
                         'undescribed included) as {"binds": [...]}, tagged '
                         'with the submap it is defined in. Used for conflict '
                         'detection, not for the cheatsheet.')
args = parser.parse_args()

content_lines = []
reading_line = 0


def parse_pseudo_bind(text):
    """Split a hand-written cheatsheet bind line into (mods, key).

    These are documentation rows, not real binds: `--#/#` marks one conceptual
    shortcut standing in for a family of real ones that cannot be listed
    individually (Hash for workspaces 1-9, the four arrows, both Page keys).
    They are written in Hyprland's own config syntax:

        bind = SUPER, Hash,,          -> (["SUPER"], "Hash")
        bind = SUPER+ALT, Hash,,      -> (["SUPER", "ALT"], "Hash")
        bind = SUPER + <arrows>,,     -> (["SUPER"], "<arrows>")
        binde = SUPER, ;/',,          -> (["SUPER"], ";/'")

    Unparsed, the whole literal string became the key and rendered as one very
    wide keycap reading `bind = SUPER, Hash,,` - config syntax, trailing commas
    and all, on screen.
    """
    rest = re.sub(r'^bind[a-z]*\s*=\s*', '', text.strip())
    rest = rest.rstrip(",").strip()
    if not rest:
        return [], text.strip()

    if "," in rest:
        # `MODS, KEY` - the common form.
        mod_part, key_part = rest.split(",", 1)
    elif " + " in rest:
        # `MODS + KEY` with no comma; the key is whatever follows the last
        # separator, since mods are always single tokens.
        mod_part, key_part = rest.rsplit(" + ", 1)
    else:
        return [], rest

    mods = [m.strip() for m in re.split(r'[+\s]+', mod_part) if m.strip()]
    key = key_part.strip().rstrip(",").strip()
    if not key:
        return [], mod_part.strip()
    return mods, key


class KeyBinding(dict):
    def __init__(self, mods, key, dispatcher, params, comment, flags=None, submap=""):
        self["mods"]       = mods
        self["key"]        = key
        self["dispatcher"] = dispatcher
        self["params"]     = params
        self["comment"]    = comment
        self["flags"]      = flags or {}
        self["submap"]     = submap


class Section(dict):
    def __init__(self, children, keybinds, name):
        self["children"] = children
        self["keybinds"] = keybinds
        self["name"]     = name


def read_content(path: str) -> str:
    expanded = os.path.expanduser(os.path.expandvars(path))
    if not os.access(expanded, os.R_OK):
        return "error"
    with open(expanded, "r") as f:
        return f.read()


def parse_key_string(key_str: str):
    """Parse 'SUPER + SHIFT + Q' into (['SUPER', 'SHIFT'], 'Q')"""
    known_mods = {"SUPER", "SHIFT", "CTRL", "ALT", "META", "SUPER_L", "SUPER_R"}
    parts = [p.strip() for p in key_str.split("+")]
    mods, key = [], ""
    for p in parts:
        if p.upper() in known_mods:
            mods.append(p)
        else:
            key = p
    return mods, key

def autogenerate_comment(dispatcher: str, params: str = "") -> str:
    d = dispatcher.lower()
    if "exec_cmd" in d or "exec" in d:
        if any(x in params for x in ["qsIsAlive", "qsIpcCall", "qsScripts", "hyprScripts", "grimhyprctl", "mediaNextCommand", ".."]):
            return ""
        return "Execute: {}".format(params[:60] + "..." if len(params) > 60 else params)

def is_hidden(line: str) -> bool:
    for marker in HIDE_MARKERS:
        if marker in line:
            return True
    return False


def extract_bind_flags(rest: str) -> Dict[str, bool]:
    """Pull known boolean options out of an hl.bind() call's trailing options
    table. The naive approach (regex over the whole call) misreads dispatcher
    params like `window.move({ follow = false })` as options, so this walks the
    call's top-level arguments (escape-aware, depth-counted) and only reads the
    trailing `{ ... }` argument."""
    depth = 0
    in_string = False
    escaped = False
    arg_start = 0
    args = []
    for i, ch in enumerate(rest):
        if in_string:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                in_string = False
            continue
        if ch == '"':
            in_string = True
        elif ch in "({[":
            depth += 1
        elif ch in ")}]":
            depth -= 1
            if depth < 0:
                args.append(rest[arg_start:i])
                break
        elif ch == "," and depth == 0:
            args.append(rest[arg_start:i])
            arg_start = i + 1
    else:
        args.append(rest[arg_start:])

    options = args[-1].strip() if len(args) >= 2 else ""
    if not options.startswith("{"):
        return {}
    flags = {}
    for m in re.finditer(r'([A-Za-z_]\w*)\s*=\s*(true|false)', options):
        if m.group(1) in KNOWN_BIND_FLAGS:
            flags[m.group(1)] = m.group(2) == "true"
    return flags


def parse_lua_bind(line: str, override_comment: str = "",
                   include_all: bool = False, submap: str = "") -> Optional[KeyBinding]:
    """
    Handles:
      hl.bind("SUPER + Q", hl.dsp.window.close(), {description = "Close"})
      hl.bind("SUPER + Q", function() ... end, {description = "..."})

    include_all keeps hidden and undescribed binds (for --flat conflict scans).
    """
    if is_hidden(line) and not include_all:
        return None

    m = re.match(r'\s*hl\.bind\s*\(\s*"([^"]+)"\s*,\s*(.*)', line, re.DOTALL)
    if not m:
        return None

    key_str = m.group(1).strip()
    rest    = m.group(2)

    # Extract description from options table
    desc_match = re.search(r'description\s*=\s*"([^"]+)"', rest)
    comment    = override_comment or (desc_match.group(1) if desc_match else "")

    if (is_hidden(rest) or is_hidden(comment)) and not include_all:
        return None

    # Extract dispatcher name
    disp_match = re.match(r'(hl\.dsp\.[a-zA-Z_.]+)', rest)
    if disp_match:
        dispatcher = disp_match.group(1)
        # Extract params inside dispatcher call parens
        params_match = re.search(r'hl\.dsp\.[a-zA-Z_.]+\(([^)]*)\)', rest)
        params = params_match.group(1).strip() if params_match else ""
    elif rest.strip().startswith("function"):
        dispatcher = "function"
        params     = ""
    else:
        dispatcher = rest.split(",")[0].strip()
        params     = ""

    if not comment:
        comment = autogenerate_comment(dispatcher, params)

    if not comment and not include_all:
        return None  # Skip binds with no useful description

    mods, key = parse_key_string(key_str)
    return KeyBinding(mods, key, dispatcher, params, comment or "",
                      flags=extract_bind_flags(rest), submap=submap)


def get_binds_recursive(current_content: Section, scope: int) -> Section:
    global content_lines, reading_line

    while reading_line < len(content_lines):
        line = content_lines[reading_line]

        # ── Section headings ──────────────────────────────────────────
        # --##! Title  (scope 2)
        # --###! Title (scope 3)
        heading_match = re.match(r'^(-+#+)!\s*(.*)', line)
        if heading_match:
            heading_scope = heading_match.group(1).count("#")
            section_name  = heading_match.group(2).strip()
            if heading_scope <= scope:
                reading_line -= 1
                return current_content
            reading_line += 1
            current_content["children"].append(
                get_binds_recursive(Section([], [], section_name), heading_scope)
            )
            reading_line += 1
            continue

        # ── Special comment bind: --#/# hl.bind(...) ─────────────────
        # Used for loop-generated binds that need a custom label
        # e.g.: --#/# bind = SUPER + ←/↑/→/↓,, -- Focus in direction
        comment_bind_match = re.match(r'^--#/#\s*(.*)', line)
        if comment_bind_match:
            rest = comment_bind_match.group(1).strip()
            # It might be a descriptive comment like "bind = SUPER + ←, -- Focus left"
            # Extract the comment after "--"
            comment_part = ""
            if " -- " in rest:
                comment_part = rest.split(" -- ", 1)[1].strip()
                if is_hidden(comment_part):
                    reading_line += 1
                    continue
            # Try to parse as hl.bind if it starts with hl.bind
            if rest.startswith("hl.bind"):
                kb = parse_lua_bind(rest, override_comment=comment_part)
                if kb:
                    current_content["keybinds"].append(kb)
            elif comment_part:
                # It's a descriptive placeholder like "bind = SUPER + ←/→ -- Focus in direction"
                # Extract key hint from before " -- "
                key_hint = rest.split(" -- ")[0].strip()
                # Split the config syntax into mods and key so it renders as
                # keycaps rather than as a literal `bind = SUPER, Hash,,`.
                # Flagged documentation so the cheatsheet can say these stand
                # for several real binds and cannot be reassigned - one of
                # them is not a chord the shell could rebind even in principle.
                mods, key = parse_pseudo_bind(key_hint)
                kb = KeyBinding(mods, key, "comment", "", comment_part,
                                flags={"documentation": True})
                current_content["keybinds"].append(kb)
            reading_line += 1
            continue

        # ── Normal hl.bind(...) ───────────────────────────────────────
        if re.match(r'\s*hl\.bind\s*\(', line):
            # Handle multiline binds by collecting until closing paren+bracket
            full_line = line
            depth = full_line.count("(") - full_line.count(")")
            lookahead = reading_line + 1
            while depth > 0 and lookahead < len(content_lines):
                next_line = content_lines[lookahead]
                full_line += " " + next_line.strip()
                depth += next_line.count("(") - next_line.count(")")
                lookahead += 1

            # Check trailing comment for hidden marker
            # e.g. ) -- # [hidden]
            if is_hidden(full_line):
                reading_line = lookahead
                continue

            kb = parse_lua_bind(full_line)
            if kb:
                current_content["keybinds"].append(kb)
            reading_line = lookahead
            continue

        reading_line += 1

    return current_content


def parse_keys(path: str) -> Section:
    global content_lines, reading_line
    raw = read_content(path)
    if raw == "error":
        return Section([], [], "error")
    content_lines = raw.splitlines()
    reading_line  = 0
    return get_binds_recursive(Section([], [], ""), 0)


def parse_flat(path: str) -> Dict[str, List[KeyBinding]]:
    """Every statically parseable hl.bind in the file, hidden and undescribed
    included, tagged with the hl.define_submap block it sits in. Loop-generated
    binds (chords built from Lua variables) are invisible to a static parse, so
    a consumer must treat this as "conflicts detected", never "no conflicts"."""
    raw = read_content(path)
    if raw == "error":
        return {"binds": [], "error": True}

    lines = raw.splitlines()
    binds: List[KeyBinding] = []
    submap = ""
    i = 0
    while i < len(lines):
        line = lines[i]

        submap_match = re.match(r'\s*hl\.define_submap\s*\(\s*"([^"]+)"', line)
        if submap_match:
            submap = submap_match.group(1)
            i += 1
            continue
        # define_submap blocks in this config close with `end)` at top level.
        if submap and re.match(r'end\s*\)', line):
            submap = ""
            i += 1
            continue

        if re.match(r'\s*hl\.bind\s*\(', line):
            full_line = line
            depth = full_line.count("(") - full_line.count(")")
            lookahead = i + 1
            while depth > 0 and lookahead < len(lines):
                next_line = lines[lookahead]
                full_line += " " + next_line.strip()
                depth += next_line.count("(") - next_line.count(")")
                lookahead += 1
            kb = parse_lua_bind(full_line, include_all=True, submap=submap)
            if kb:
                binds.append(kb)
            i = lookahead
            continue

        i += 1

    return {"binds": binds}


if __name__ == "__main__":
    if args.flat:
        result = parse_flat(args.path)
    else:
        result = parse_keys(args.path)
    print(json.dumps(result))