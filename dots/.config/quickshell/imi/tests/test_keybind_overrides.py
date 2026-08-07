#!/usr/bin/env python3
"""Contract tests for scripts/hyprland/keybind_overrides.py.

The generator turns the shell's keybind-overrides sidecar (JSON) into the Lua
shim Hyprland sources last. Its failure modes are all silent at the compositor:
a bad emission is a config error the shell never sees, a clobbered hand edit is
destroyed user work, and a rewrite of unchanged content makes Hyprland reload
for nothing. So this pins:

  - emission: remove -> unbind_chord, rebind -> unbind + re-emitted bind with
    flags, add -> exec_cmd bind; unbinds before binds; deterministic order
  - Lua string escaping (quotes/backslashes/newlines cannot break the literal)
  - validation refusals (exit 3): unknown mods/keys, non-hl.dsp dispatchers,
    params with calls or unknown identifiers, unknown flags/actions
  - params referencing variables.lua globals (terminal, browser, ...) pass
  - hand-edit protection (exit 4): a file without a matching content hash is
    never touched, including by the delete-on-empty path
  - generated-file discipline: identical content is not rewritten (mtime
    stable), an empty sidecar deletes the shim, --check reports
    absent/managed/foreign
"""
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "hyprland" / "keybind_overrides.py"

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  PASS {name}")
    else:
        print(f"  FAIL {name} {detail}")
        failures.append(name)


def run(sidecar, out, extra=None):
    proc = subprocess.run(
        [sys.executable, str(SCRIPT),
         "--sidecar-json", json.dumps(sidecar), "--out", str(out),
         *(extra or [])],
        capture_output=True, text=True, timeout=30)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def run_check(out):
    proc = subprocess.run(
        [sys.executable, str(SCRIPT), "--check", "--out", str(out)],
        capture_output=True, text=True, timeout=30)
    return proc.stdout.strip()


def main():
    print("keybind_overrides.py generator tests")
    check("script exists", SCRIPT.exists())
    if not SCRIPT.exists():
        return 1

    sidecar = {
        "version": 1,
        "overrides": {
            "SUPER|W": {"action": "remove"},
            "SUPER|Q": {
                "action": "rebind",
                "mods": ["SUPER", "SHIFT"], "key": "C",
                "dispatcher": "hl.dsp.window.close", "params": "",
                "flags": {"locked": True},
                "description": 'Window: "Close"',
            },
            "SUPER+SHIFT|F1": {
                "action": "add",
                "mods": ["SUPER", "SHIFT"], "key": "F1",
                "command": 'notify-send "hi\\there"',
                "description": "My binding",
            },
        },
    }

    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "shellOverrides" / "keybinds.lua"

        # --- Fresh generation ------------------------------------------------
        code, stdout, stderr = run(sidecar, out)
        check("fresh generation exits 0 and reports created",
              code == 0 and stdout == "created", f"exit={code} out={stdout!r} err={stderr!r}")
        check("shim file exists", out.exists())
        content = out.read_text(encoding="utf-8")
        lines = content.splitlines()

        check("shim carries the managed header + hash line",
              lines[0].startswith("-- Managed by Immaterial Impulse")
              and any(l.startswith("-- imi-keybinds-sha256: ") for l in lines[:4]),
              f"got {lines[:4]}")
        check("remove emits unbind_chord",
              'unbind_chord("SUPER + W")' in content, content)
        check("rebind unbinds the default chord",
              'unbind_chord("SUPER + Q")' in content, content)
        check("rebind re-emits dispatcher, flags and escaped description",
              'hl.bind("SUPER + SHIFT + C", hl.dsp.window.close(), '
              '{ description = "Window: \\"Close\\"", locked = true })' in content,
              content)
        check("add emits an exec_cmd bind with escaped command",
              'hl.bind("SUPER + SHIFT + F1", '
              'hl.dsp.exec_cmd("notify-send \\"hi\\\\there\\""), '
              '{ description = "My binding" })' in content,
              content)
        body = content.split("\n")
        first_bind = next(i for i, l in enumerate(body) if l.startswith("hl.bind(\""))
        last_unbind = max(i for i, l in enumerate(body) if l.startswith("unbind_chord("))
        check("all unbinds precede all binds", last_unbind < first_bind,
              f"last_unbind={last_unbind} first_bind={first_bind}")
        check("--check reports managed", run_check(out) == "managed")

        # --- Unchanged content is not rewritten ------------------------------
        before = out.stat().st_mtime_ns
        code, stdout, _ = run(sidecar, out)
        check("identical rerun reports unchanged", code == 0 and stdout == "unchanged",
              f"exit={code} out={stdout!r}")
        check("identical rerun leaves mtime alone",
              out.stat().st_mtime_ns == before)

        # --- Deterministic output --------------------------------------------
        reordered = {"version": 1,
                     "overrides": dict(reversed(list(sidecar["overrides"].items())))}
        code, stdout, _ = run(reordered, out)
        check("entry order in the sidecar does not change the output",
              code == 0 and stdout == "unchanged", f"exit={code} out={stdout!r}")

        # --- Updates ----------------------------------------------------------
        sidecar2 = json.loads(json.dumps(sidecar))
        sidecar2["overrides"]["SUPER|E"] = {"action": "remove"}
        code, stdout, _ = run(sidecar2, out)
        check("changed sidecar reports updated", code == 0 and stdout == "updated",
              f"exit={code} out={stdout!r}")
        check("update is hash-consistent", run_check(out) == "managed")

        # --- Empty sidecar deletes the shim ----------------------------------
        code, stdout, _ = run({"version": 1, "overrides": {}}, out)
        check("empty sidecar deletes the managed shim",
              code == 0 and stdout == "deleted" and not out.exists(),
              f"exit={code} out={stdout!r} exists={out.exists()}")
        check("--check reports absent after delete", run_check(out) == "absent")
        code, stdout, _ = run({"version": 1, "overrides": {}}, out)
        check("empty sidecar with no shim reports absent",
              code == 0 and stdout == "absent", f"exit={code} out={stdout!r}")

        # --- Hand-edit protection --------------------------------------------
        code, _, _ = run(sidecar, out)
        hand_edited = out.read_text(encoding="utf-8") + "\n-- my tweak\n"
        out.write_text(hand_edited, encoding="utf-8")
        check("--check reports foreign after a hand edit", run_check(out) == "foreign")
        code, stdout, stderr = run(sidecar2, out)
        check("hand-edited shim refuses the write with exit 4",
              code == 4 and "hand" in stderr.lower(), f"exit={code} err={stderr!r}")
        check("hand-edited shim content is untouched",
              out.read_text(encoding="utf-8") == hand_edited)
        code, stdout, stderr = run({"version": 1, "overrides": {}}, out)
        check("empty sidecar never deletes a hand-edited shim",
              code == 4 and out.exists(), f"exit={code} out={stdout!r}")
        pre_header = "-- some other tool's file\nhl.bind(...)\n"
        out.write_text(pre_header, encoding="utf-8")
        check("a file with no hash line is foreign", run_check(out) == "foreign")
        os.remove(out)

        # --- Validation refusals ----------------------------------------------
        def refuses(name, entry, needle=""):
            bad = {"version": 1, "overrides": {"SUPER|Q": entry}}
            code, _, stderr = run(bad, out)
            check(name, code == 3 and (needle in stderr) and not out.exists(),
                  f"exit={code} err={stderr!r}")

        refuses("unknown action is refused", {"action": "frobnicate"}, "unknown action")
        refuses("unknown modifier is refused",
                {"action": "rebind", "mods": ["HYPER"], "key": "C",
                 "dispatcher": "hl.dsp.window.close", "params": ""},
                "unknown modifier")
        refuses("invalid key is refused",
                {"action": "rebind", "mods": ["SUPER"], "key": 'a"b',
                 "dispatcher": "hl.dsp.window.close", "params": ""},
                "invalid key")
        refuses("non-hl.dsp dispatcher is refused",
                {"action": "rebind", "mods": ["SUPER"], "key": "C",
                 "dispatcher": "os.execute", "params": ""},
                "not re-emittable")
        refuses("function binds are not re-emittable",
                {"action": "rebind", "mods": ["SUPER"], "key": "C",
                 "dispatcher": "function", "params": ""},
                "not re-emittable")
        refuses("params with a call are refused even on a known global",
                {"action": "rebind", "mods": ["SUPER"], "key": "C",
                 "dispatcher": "hl.dsp.exec_cmd", "params": 'terminal("x")'},
                "unsupported character")
        refuses("params reaching for stdlib tables are refused",
                {"action": "rebind", "mods": ["SUPER"], "key": "C",
                 "dispatcher": "hl.dsp.exec_cmd", "params": 'os.getenv("HOME")'},
                "not a known")
        refuses("params referencing a file-local identifier are refused",
                {"action": "rebind", "mods": ["SUPER"], "key": "C",
                 "dispatcher": "hl.dsp.exec_cmd", "params": 'qsIsAlive .. " || foo"'},
                "qsIsAlive")
        refuses("unknown flags are refused",
                {"action": "rebind", "mods": ["SUPER"], "key": "C",
                 "dispatcher": "hl.dsp.window.close", "params": "",
                 "flags": {"sneaky": True}},
                "unknown bind flag")
        refuses("add without a command is refused",
                {"action": "add", "mods": ["SUPER"], "key": "C", "command": "  "},
                "non-empty command")

        # --- variables.lua globals stay usable --------------------------------
        ok_globals = {"version": 1, "overrides": {
            "SUPER|Return": {
                "action": "rebind", "mods": ["SUPER", "ALT"], "key": "Return",
                "dispatcher": "hl.dsp.exec_cmd", "params": "terminal",
                "description": "App: Terminal",
            },
            "SUPER|D": {
                "action": "rebind", "mods": ["SUPER"], "key": "D",
                "dispatcher": "hl.dsp.window.fullscreen",
                "params": '{ mode = "maximized", action = "toggle" }',
                "description": "Window: Maximize",
            },
        }}
        code, stdout, stderr = run(ok_globals, out)
        content = out.read_text(encoding="utf-8") if out.exists() else ""
        check("variables.lua globals and literal tables are re-emittable",
              code == 0 and "hl.dsp.exec_cmd(terminal)" in content
              and 'fullscreen({ mode = "maximized", action = "toggle" })' in content,
              f"exit={code} err={stderr!r} content={content!r}")

    if failures:
        print(f"{len(failures)} keybind_overrides test(s) failed")
        return 1
    print("All keybind_overrides tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
