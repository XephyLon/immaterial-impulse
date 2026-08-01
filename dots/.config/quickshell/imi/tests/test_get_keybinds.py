#!/usr/bin/env python3
"""Behavioral tests for scripts/hyprland/get_keybinds.py.

The script parses keybinds.lua (hl.bind lines + --##! section-heading comments)
into the JSON tree the SUPER+/ cheatsheet renders. A silent parser regression
empties the cheatsheet without any error, so these tests run the real script
against a fixture built in a tempdir and pin the exact JSON it emits:

  - section nesting from --##! / --###! headings
  - mods/key/dispatcher/params/comment extraction (incl. multiline binds)
  - [hidden] exclusion (description marker AND trailing comment marker)
  - binds without a usable description are dropped
  - exec binds autogenerate an "Execute: ..." comment unless params look
    machine-generated (qsIpcCall etc.)
  - --#/# synthetic comment binds
  - unreadable path => {"children": [], "keybinds": [], "name": "error"}
  - empty file      => {"children": [], "keybinds": [], "name": ""}
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "hyprland" / "get_keybinds.py"

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  PASS {name}")
    else:
        print(f"  FAIL {name} {detail}")
        failures.append(name)


def run_script(path):
    """Run get_keybinds.py --path <path>; return (exit_code, parsed_json)."""
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "--path", str(path)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    parsed = None
    if proc.stdout.strip():
        try:
            parsed = json.loads(proc.stdout)
        except json.JSONDecodeError:
            pass
    return proc.returncode, parsed


FIXTURE = """\
require("hyprland.lib")
local qsIpcCall = "qs -c $qsConfig ipc call"

hl.bind("SUPER + Slash", hl.dsp.global("quickshell:cheatsheetToggle"), { description = "Toggle cheatsheet" })

--##! Window
hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Close window" })
hl.bind("SUPER + SHIFT + F", hl.dsp.window.fullscreen(1), { description = "Fullscreen" })
hl.bind("SUPER + X", hl.dsp.window.pin(), { description = "[hidden] secret pin" })
hl.bind("SUPER + Y", hl.dsp.window.hide()) -- [hidden]
hl.bind("SUPER + Z", hl.dsp.window.next())

--###! Focus
--#/# SUPER + Arrows -- Focus in direction
hl.bind("SUPER + J", hl.dsp.focus.down(), { description = "Focus down" })

--##! Apps
hl.bind("SUPER + T", hl.dsp.exec("kitty"), { description = "Terminal" })
hl.bind("SUPER + W", hl.dsp.exec("firefox"))
hl.bind("SUPER + I", hl.dsp.exec_cmd(qsIpcCall .. " settings open"))
hl.bind("CTRL + SUPER + E",
    hl.dsp.exec("nautilus"),
    { description = "File manager" })
"""


def find_section(node, name):
    for child in node.get("children", []):
        if child.get("name") == name:
            return child
    return None


def bind_by_key(section, key):
    for kb in section.get("keybinds", []):
        if kb.get("key") == key:
            return kb
    return None


def main():
    print("get_keybinds.py parser tests")

    check("script exists", SCRIPT.exists())
    if not SCRIPT.exists():
        print("1 get_keybinds test(s) failed")
        return 1

    with tempfile.TemporaryDirectory() as tmp:
        fixture_path = Path(tmp) / "keybinds.lua"
        fixture_path.write_text(FIXTURE, encoding="utf-8")

        # --- Happy path -----------------------------------------------------
        code, tree = run_script(fixture_path)
        check("exit code 0 on fixture", code == 0, f"exit={code}")
        check("stdout is valid JSON", tree is not None)
        if tree is None:
            print("get_keybinds test(s) failed: no JSON output")
            return 1

        check("root section unnamed", tree.get("name") == "")
        check(
            "top-level sections are Window and Apps",
            [c.get("name") for c in tree.get("children", [])] == ["Window", "Apps"],
            f"got {[c.get('name') for c in tree.get('children', [])]}",
        )

        # Pre-section bind lands in the root section
        root_binds = tree.get("keybinds", [])
        check("root has exactly one keybind", len(root_binds) == 1,
              f"got {len(root_binds)}")
        if root_binds:
            kb = root_binds[0]
            check("root bind mods", kb["mods"] == ["SUPER"], f"got {kb['mods']}")
            check("root bind key", kb["key"] == "Slash", f"got {kb['key']}")
            check("root bind dispatcher", kb["dispatcher"] == "hl.dsp.global",
                  f"got {kb['dispatcher']}")
            check("root bind params keep quotes",
                  kb["params"] == '"quickshell:cheatsheetToggle"',
                  f"got {kb['params']!r}")
            check("root bind comment from description",
                  kb["comment"] == "Toggle cheatsheet", f"got {kb['comment']!r}")

        # --- Window section: fields + hidden/undescribed exclusion ----------
        window = find_section(tree, "Window")
        check("Window section exists", window is not None)
        if window is not None:
            keys = [kb["key"] for kb in window["keybinds"]]
            check("Window keeps only described visible binds",
                  keys == ["Q", "F"], f"got {keys}")
            check("[hidden] in description excludes bind (X)",
                  bind_by_key(window, "X") is None)
            check("trailing -- [hidden] comment excludes bind (Y)",
                  bind_by_key(window, "Y") is None)
            check("bind with no description and non-exec dispatcher dropped (Z)",
                  bind_by_key(window, "Z") is None)

            f_bind = bind_by_key(window, "F")
            check("multi-mod bind parsed", f_bind is not None
                  and f_bind["mods"] == ["SUPER", "SHIFT"],
                  f"got {f_bind and f_bind['mods']}")
            check("dispatcher params extracted", f_bind is not None
                  and f_bind["dispatcher"] == "hl.dsp.window.fullscreen"
                  and f_bind["params"] == "1",
                  f"got {f_bind}")

            # --- Nested --###! section inside Window ------------------------
            focus = find_section(window, "Focus")
            check("--###! nests Focus under Window", focus is not None)
            if focus is not None:
                check("Focus has no grandchildren", focus["children"] == [])
                comments = [kb["comment"] for kb in focus["keybinds"]]
                check("Focus keybind comments",
                      comments == ["Focus in direction", "Focus down"],
                      f"got {comments}")
                synthetic = focus["keybinds"][0] if focus["keybinds"] else None
                check("--#/# synthetic bind uses 'comment' dispatcher",
                      synthetic is not None
                      and synthetic["dispatcher"] == "comment"
                      and synthetic["mods"] == []
                      and synthetic["key"] == "SUPER + Arrows"
                      and synthetic["params"] == "",
                      f"got {synthetic}")

        # --- Apps section: exec autogen + blacklist + multiline -------------
        apps = find_section(tree, "Apps")
        check("Apps section exists", apps is not None)
        if apps is not None:
            keys = [kb["key"] for kb in apps["keybinds"]]
            check("Apps binds", keys == ["T", "W", "E"], f"got {keys}")

            w_bind = bind_by_key(apps, "W")
            check("exec bind without description autogenerates comment",
                  w_bind is not None
                  and w_bind["comment"] == 'Execute: "firefox"',
                  f"got {w_bind and w_bind['comment']!r}")

            check("exec_cmd with qsIpcCall params dropped (I)",
                  bind_by_key(apps, "I") is None)

            e_bind = bind_by_key(apps, "E")
            check("multiline bind parsed", e_bind is not None
                  and e_bind["mods"] == ["CTRL", "SUPER"]
                  and e_bind["dispatcher"] == "hl.dsp.exec"
                  and e_bind["params"] == '"nautilus"'
                  and e_bind["comment"] == "File manager",
                  f"got {e_bind}")

        # --- Regression canary: fixture must never parse to nothing ---------
        def count_binds(node):
            total = len(node.get("keybinds", []))
            for child in node.get("children", []):
                total += count_binds(child)
            return total

        check("cheatsheet is not empty (canary)", count_binds(tree) == 8,
              f"got {count_binds(tree)} binds")

        # --- Unreadable path -------------------------------------------------
        code, tree = run_script(Path(tmp) / "does" / "not" / "exist.lua")
        check("unreadable path exits 0", code == 0, f"exit={code}")
        check("unreadable path emits error section",
              tree == {"children": [], "keybinds": [], "name": "error"},
              f"got {tree}")

        # chmod-000 variant (root can read anything, so only when not root)
        if os.geteuid() != 0:
            locked = Path(tmp) / "locked.lua"
            locked.write_text(FIXTURE, encoding="utf-8")
            locked.chmod(0)
            code, tree = run_script(locked)
            locked.chmod(0o600)  # let TemporaryDirectory clean up
            check("permission-denied path emits error section",
                  code == 0
                  and tree == {"children": [], "keybinds": [], "name": "error"},
                  f"exit={code} got {tree}")

        # --- Empty file --------------------------------------------------------
        empty = Path(tmp) / "empty.lua"
        empty.write_text("", encoding="utf-8")
        code, tree = run_script(empty)
        check("empty file exits 0", code == 0, f"exit={code}")
        check("empty file emits empty root section",
              tree == {"children": [], "keybinds": [], "name": ""},
              f"got {tree}")

    if failures:
        print(f"{len(failures)} get_keybinds test(s) failed")
        return 1
    print("All get_keybinds tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
