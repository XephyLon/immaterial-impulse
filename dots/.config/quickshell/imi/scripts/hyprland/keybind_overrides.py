#!/usr/bin/env python3
"""Generate the shell-owned keybind override shim from its JSON sidecar.

The keyboard-shortcuts editor never edits Lua the user wrote. The shell owns a
declarative sidecar (~/.config/immaterial-impulse/keybind-overrides.json) and
this script renders it into ~/.config/hypr/hyprland/shellOverrides/keybinds.lua,
which hyprland.lua sources last - after the shipped defaults and after
custom/keybinds.lua. Overriding a default works because hl.bind() returns a
keybind object whose :unbind() removes every bind on that chord (Hyprland
removes by modmask+key, see CKeybindManager::removeKeybind), so binding a
dummy on a chord and unbinding it immediately is a chord-level unbind.

Generated-file discipline mirrors hyprconfigurator.py: atomic writes, and no
rewrite when content is unchanged (Hyprland reloads on file change). On top of
that, the file carries a content hash in its header; if the file on disk does
not hash-match, someone hand-edited it, and this script refuses to touch it
(exit 4) rather than clobber. An empty sidecar deletes the shim.

Exit codes: 0 ok (prints created/updated/unchanged/deleted/absent),
3 invalid sidecar entry, 4 foreign (hand-edited) shim.
"""
import argparse
import hashlib
import json
import os
import re
import sys
import tempfile

HEADER_LINE = "-- Managed by Immaterial Impulse (Settings > Hyprland > Keybinds)."
WARNING_LINE = "-- Do not edit: hand edits are detected and stop the shell writing here."
HASH_PREFIX = "-- imi-keybinds-sha256: "

KNOWN_MODS = {"SUPER", "SHIFT", "CTRL", "ALT", "META", "SUPER_L", "SUPER_R"}

KNOWN_FLAGS = {
    "locked", "repeating", "mouse", "release", "non_consuming",
    "ignore_mods", "transparent", "submap_universal", "click", "drag",
}

# Globals defined by hypr/hyprland/variables.lua (or overridden by
# custom/variables.lua). The shim is sourced after both, so these identifiers
# resolve at Lua load time. Anything else - notably keybinds.lua's own locals
# (qsIsAlive, hyprScripts, ...) - would evaluate to nil in the shim and turn
# the whole config load into an error, so params referencing them are rejected
# and the UI offers remove-only for such binds.
KNOWN_GLOBALS = {
    "terminal", "fileManager", "browser", "codeEditor", "officeSoftware",
    "textEditor", "volumeMixer", "settingsApp", "taskManager",
}

KEY_RE = re.compile(r"^(?:[A-Za-z0-9_]+|code:\d+|mouse:\d+)$")
DISPATCHER_RE = re.compile(r"^hl\.dsp(?:\.[A-Za-z_][A-Za-z0-9_]*)+$")
IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


class SidecarError(Exception):
    pass


def validate_chord(mods, key, where):
    if not isinstance(mods, list) or not all(isinstance(m, str) for m in mods):
        raise SidecarError(f"{where}: mods must be a list of strings")
    for m in mods:
        if m.upper() not in KNOWN_MODS:
            raise SidecarError(f"{where}: unknown modifier {m!r}")
    if not isinstance(key, str) or not KEY_RE.match(key):
        raise SidecarError(f"{where}: invalid key {key!r}")


def chord_string(mods, key):
    return " + ".join([*mods, key]) if mods else key


def validate_params(params, where):
    """Accept only expressions that cannot smuggle statements or calls into the
    generated Lua: string literals, numbers, booleans, table syntax, `..`
    concatenation, and identifiers naming known variables.lua globals. No
    parentheses means no function calls; rejecting unknown identifiers means no
    nil surprises from file-local variables the shim cannot see."""
    if not isinstance(params, str):
        raise SidecarError(f"{where}: params must be a string")
    i = 0
    depth = 0
    n = len(params)
    while i < n:
        ch = params[i]
        if ch == '"':
            i += 1
            while i < n:
                if params[i] == "\\":
                    i += 2
                    continue
                if params[i] == '"':
                    break
                i += 1
            if i >= n:
                raise SidecarError(f"{where}: unterminated string in params")
            i += 1
            continue
        if ch.isspace() or ch in ",=":
            i += 1
            continue
        if ch == "{":
            depth += 1
            i += 1
            continue
        if ch == "}":
            depth -= 1
            if depth < 0:
                raise SidecarError(f"{where}: unbalanced braces in params")
            i += 1
            continue
        if ch == ".":
            if params[i:i + 2] == "..":
                i += 2
                continue
            raise SidecarError(f"{where}: stray '.' in params")
        if ch.isdigit() or (ch == "-" and i + 1 < n and params[i + 1].isdigit()):
            i += 1
            while i < n and (params[i].isdigit() or params[i] == "."):
                i += 1
            continue
        m = IDENT_RE.match(params, i)
        if m:
            ident = m.group(0)
            i = m.end()
            # Table keys (`ident =`) are field names, not variable reads.
            j = i
            while j < n and params[j].isspace():
                j += 1
            is_table_key = j < n and params[j] == "=" and params[j:j + 2] != "=="
            if ident in ("true", "false") or is_table_key or ident in KNOWN_GLOBALS:
                continue
            raise SidecarError(
                f"{where}: identifier {ident!r} is not a known "
                f"variables.lua global; this binding cannot be re-emitted")
        raise SidecarError(f"{where}: unsupported character {ch!r} in params")
    if depth != 0:
        raise SidecarError(f"{where}: unbalanced braces in params")


def lua_quote(s):
    out = s.replace("\\", "\\\\").replace('"', '\\"')
    out = out.replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
    return f'"{out}"'


def options_table(description, flags, where):
    parts = []
    if description:
        if not isinstance(description, str):
            raise SidecarError(f"{where}: description must be a string")
        parts.append(f"description = {lua_quote(description)}")
    for name in sorted(flags or {}):
        if name not in KNOWN_FLAGS:
            raise SidecarError(f"{where}: unknown bind flag {name!r}")
        if not isinstance(flags[name], bool):
            raise SidecarError(f"{where}: flag {name!r} must be a boolean")
        parts.append(f"{name} = {'true' if flags[name] else 'false'}")
    return "{ " + ", ".join(parts) + " }" if parts else ""


def emit_bind(mods, key, dispatcher, params, description, flags, where):
    validate_chord(mods, key, where)
    if not isinstance(dispatcher, str) or not DISPATCHER_RE.match(dispatcher):
        raise SidecarError(f"{where}: dispatcher {dispatcher!r} is not re-emittable")
    validate_params(params, where)
    opts = options_table(description, flags, where)
    call = f"{dispatcher}({params})"
    chord = lua_quote(chord_string(mods, key))
    if opts:
        return f"hl.bind({chord}, {call}, {opts})"
    return f"hl.bind({chord}, {call})"


def parse_identity(identity):
    if "|" not in identity:
        raise SidecarError(f"override key {identity!r} is not a mods|key identity")
    mods_part, key = identity.rsplit("|", 1)
    mods = [m for m in mods_part.split("+") if m]
    return mods, key


def render_body(sidecar):
    if not isinstance(sidecar, dict):
        raise SidecarError("sidecar root must be an object")
    overrides = sidecar.get("overrides", {})
    if not isinstance(overrides, dict):
        raise SidecarError("sidecar 'overrides' must be an object")

    unbinds = []
    binds = []
    for identity in sorted(overrides):
        entry = overrides[identity]
        where = f"override {identity!r}"
        if not isinstance(entry, dict):
            raise SidecarError(f"{where}: entry must be an object")
        action = entry.get("action")
        default_mods, default_key = parse_identity(identity)
        validate_chord(default_mods, default_key, where)

        if action == "remove":
            unbinds.append(chord_string(default_mods, default_key))
        elif action == "rebind":
            unbinds.append(chord_string(default_mods, default_key))
            binds.append(emit_bind(
                entry.get("mods", []), entry.get("key", ""),
                entry.get("dispatcher", ""), entry.get("params", ""),
                entry.get("description", ""), entry.get("flags", {}), where))
        elif action == "add":
            command = entry.get("command")
            if not isinstance(command, str) or not command.strip():
                raise SidecarError(f"{where}: 'add' needs a non-empty command")
            add_mods = entry.get("mods", [])
            add_key = entry.get("key", "")
            validate_chord(add_mods, add_key, where)
            opts = options_table(entry.get("description", ""), entry.get("flags", {}), where)
            chord = lua_quote(chord_string(add_mods, add_key))
            call = f"hl.dsp.exec_cmd({lua_quote(command)})"
            binds.append(f"hl.bind({chord}, {call}, {opts})" if opts
                         else f"hl.bind({chord}, {call})")
        else:
            raise SidecarError(f"{where}: unknown action {action!r}")

    if not unbinds and not binds:
        return ""

    lines = [
        "local function unbind_chord(chord)",
        "    hl.bind(chord, function() end):unbind()",
        "end",
    ]
    lines += [f'unbind_chord({lua_quote(chord)})' for chord in dict.fromkeys(unbinds)]
    lines += binds
    return "\n".join(lines) + "\n"


def render_file(body):
    digest = hashlib.sha256(body.encode("utf-8")).hexdigest()
    return f"{HEADER_LINE}\n{WARNING_LINE}\n{HASH_PREFIX}{digest}\n{body}"


def shim_status(path):
    """absent | managed | foreign"""
    try:
        with open(path, encoding="utf-8") as f:
            content = f.read()
    except FileNotFoundError:
        return "absent"
    lines = content.split("\n")
    for index, line in enumerate(lines):
        if line.startswith(HASH_PREFIX):
            claimed = line[len(HASH_PREFIX):].strip()
            body = "\n".join(lines[index + 1:])
            actual = hashlib.sha256(body.encode("utf-8")).hexdigest()
            return "managed" if claimed == actual else "foreign"
    return "foreign"


def write_atomic(path, content):
    dir_name = os.path.dirname(os.path.abspath(path))
    os.makedirs(dir_name, exist_ok=True)
    tmp_path = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", dir=dir_name, delete=False) as f:
            f.write(content)
            tmp_path = f.name
        if os.path.exists(path):
            os.chmod(tmp_path, os.stat(path).st_mode)
        else:
            os.chmod(tmp_path, 0o644)
        os.replace(tmp_path, path)
    except Exception:
        if tmp_path and os.path.exists(tmp_path):
            os.remove(tmp_path)
        raise


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--sidecar", help="path to keybind-overrides.json")
    p.add_argument("--sidecar-json", help="sidecar content passed inline "
                   "(avoids racing the shell's debounced sidecar write)")
    p.add_argument("--out", required=True, help="path of the generated shim")
    p.add_argument("--check", action="store_true",
                   help="report the shim's state (absent/managed/foreign) and exit")
    args = p.parse_args()

    out_path = os.path.expanduser(args.out)

    if args.check:
        print(shim_status(out_path))
        return 0

    if args.sidecar_json is not None:
        raw = args.sidecar_json
    elif args.sidecar:
        try:
            with open(os.path.expanduser(args.sidecar), encoding="utf-8") as f:
                raw = f.read()
        except FileNotFoundError:
            raw = "{}"
    else:
        print("Error: need --sidecar or --sidecar-json", file=sys.stderr)
        return 2

    try:
        sidecar = json.loads(raw) if raw.strip() else {}
        body = render_body(sidecar)
    except json.JSONDecodeError as e:
        print(f"Invalid sidecar JSON: {e}", file=sys.stderr)
        return 3
    except SidecarError as e:
        print(f"Invalid sidecar: {e}", file=sys.stderr)
        return 3

    status = shim_status(out_path)
    if status == "foreign":
        print(f"Refusing to write: {out_path} was edited by hand. "
              f"Delete or rename it to let the shell manage keybind overrides again.",
              file=sys.stderr)
        return 4

    if not body:
        if status == "managed":
            os.remove(out_path)
            print("deleted")
        else:
            print("absent")
        return 0

    content = render_file(body)
    if status == "managed":
        with open(out_path, encoding="utf-8") as f:
            if f.read() == content:
                print("unchanged")
                return 0
        write_atomic(out_path, content)
        print("updated")
    else:
        write_atomic(out_path, content)
        print("created")
    return 0


if __name__ == "__main__":
    sys.exit(main())
