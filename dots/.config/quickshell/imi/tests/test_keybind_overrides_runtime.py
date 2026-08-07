#!/usr/bin/env python3
"""The keyboard-shortcuts editor's write path against a real Quickshell.

The unit suites cover the generator (Python) and the tree/conflict logic (QML,
via the .js library), but nothing else instantiates the real singletons: a
broken Process command line, a mis-wired FileView, or a generator invocation
that races the sidecar write would all pass every unit test and fail on the
first real edit. This launches KeybindOverridesRuntimeTest.qml in a real qs
process against a throwaway XDG_CONFIG_HOME and checks, from the outside:

  - the shim is generated from the seeded sidecar (created path), carries the
    managed hash header, unbinds the overridden chords and emits the
    replacement binds
  - `hyprctl reload` is invoked exactly once for the created shim, and not
    again when a second launch finds the content unchanged (Hyprland watches
    the file; rewriting or reloading for identical content is churn)
  - a hand-edited shim flips the service to "foreign" and is left untouched

Brings its own headless weston, so it needs no display of its own. Skips when
weston or qs is missing, as in CI.
"""

import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "KeybindOverridesRuntimeTest.qml"
SOCKET = "wayland-imi-keybind-overrides"

FAKE_HYPRCTL = """#!/usr/bin/env bash
printf '%s\\n' "hyprctl $*" >> "$KEYBIND_EXEC_LOG"
exit 0
"""

# Binds live under a --##! section: the tree merge only keeps sectioned binds
# (root-level binds never render in the cheatsheet), so a root-level fixture
# would make the tree checks pass vacuously against an empty tree.
KEYBINDS_LUA = """\
--##! Window
hl.bind("SUPER + Q", hl.dsp.window.close(), { description = "Window: Close" })
--##! Apps
hl.bind("SUPER + T", hl.dsp.exec_cmd("kitty"), { description = "App: Terminal" })
hl.bind("SUPER + W", hl.dsp.exec_cmd("firefox"), { description = "App: Browser" })
"""

CUSTOM_LUA = """\
hl.bind("SUPER + ALT + U", hl.dsp.exec_cmd("custom-thing"), { description = "My custom bind" })
"""

SIDECAR = """\
{
  "version": 1,
  "overrides": {
    "SUPER|Q": {
      "action": "rebind",
      "mods": ["SUPER", "SHIFT"],
      "key": "C",
      "dispatcher": "hl.dsp.window.close",
      "params": "",
      "flags": {},
      "description": "Window: Close"
    },
    "SUPER|W": { "action": "remove" },
    "SHIFT+SUPER|F1": {
      "action": "add",
      "mods": ["SUPER", "SHIFT"],
      "key": "F1",
      "command": "notify-send hi",
      "description": "Say hi"
    }
  }
}
"""


def _stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def _runtime_available():
    return shutil.which("qs") is not None and shutil.which("weston") is not None


@unittest.skipUnless(_runtime_available(), "needs qs and weston on PATH")
class KeybindOverridesRuntimeTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.env = dict(os.environ)
        cls.env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        cls.env["WAYLAND_DISPLAY"] = SOCKET
        cls.env.pop("DISPLAY", None)
        cls.weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=800", "--height=600"],
            env=cls.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

        socket_path = Path(cls.env["XDG_RUNTIME_DIR"]) / SOCKET
        deadline = time.monotonic() + 15
        while not socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        if not socket_path.exists():
            _stop(cls.weston)
            raise AssertionError("headless weston never came up")

        cls.env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        cls.env["QT_QUICK_BACKEND"] = "software"

    @classmethod
    def tearDownClass(cls):
        _stop(cls.weston)

    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-keybind-overrides-runtime-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.config_home = self.home / "config"
        self.exec_log = self.home / "exec.log"
        self.bin = self.home / "bin"
        self.bin.mkdir(parents=True)
        hyprctl = self.bin / "hyprctl"
        hyprctl.write_text(FAKE_HYPRCTL)
        hyprctl.chmod(0o755)

        hypr = self.config_home / "hypr"
        (hypr / "hyprland").mkdir(parents=True)
        (hypr / "custom").mkdir(parents=True)
        (hypr / "hyprland" / "keybinds.lua").write_text(KEYBINDS_LUA)
        (hypr / "custom" / "keybinds.lua").write_text(CUSTOM_LUA)

        shell_config = self.config_home / "immaterial-impulse"
        shell_config.mkdir(parents=True)
        (shell_config / "keybind-overrides.json").write_text(SIDECAR)

        self.shim = hypr / "hyprland" / "shellOverrides" / "keybinds.lua"

    def launch(self, expect_status="ok"):
        env = dict(self.env)
        env["XDG_CONFIG_HOME"] = str(self.config_home)
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["PATH"] = f"{self.bin}{os.pathsep}{env['PATH']}"
        env["KEYBIND_EXEC_LOG"] = str(self.exec_log)
        env["KEYBIND_EXPECT_STATUS"] = expect_status
        proc = subprocess.run(["qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=240)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn("[KeybindOverridesRuntime] failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")
        return output

    def reload_calls(self):
        if not self.exec_log.exists():
            return []
        return [line for line in self.exec_log.read_text().splitlines()
                if line.strip() == "hyprctl reload"]

    def test_shim_is_generated_and_reloaded_once(self):
        self.launch()

        self.assertTrue(self.shim.exists(), "shim was not generated")
        content = self.shim.read_text()
        self.assertIn("imi-keybinds-sha256:", content, content)
        self.assertIn('unbind_chord("SUPER + Q")', content, content)
        self.assertIn('unbind_chord("SUPER + W")', content, content)
        self.assertIn('hl.bind("SUPER + SHIFT + C", hl.dsp.window.close(), '
                      '{ description = "Window: Close" })', content, content)
        self.assertIn('hl.bind("SUPER + SHIFT + F1", '
                      'hl.dsp.exec_cmd("notify-send hi"), '
                      '{ description = "Say hi" })', content, content)
        self.assertEqual(len(self.reload_calls()), 1,
                         f"created shim needs exactly one reload: {self.exec_log.read_text()!r}")

        # Second launch: identical sidecar means an unchanged shim, which must
        # neither rewrite the file (Hyprland watches its mtime) nor reload.
        mtime = self.shim.stat().st_mtime_ns
        self.launch()
        self.assertEqual(self.shim.stat().st_mtime_ns, mtime,
                         "unchanged shim was rewritten")
        self.assertEqual(len(self.reload_calls()), 1,
                         "unchanged shim must not trigger another reload")

    def test_hand_edited_shim_is_refused_and_untouched(self):
        self.launch()
        hand_edited = self.shim.read_text() + "\n-- my tweak\n"
        self.shim.write_text(hand_edited)

        self.launch(expect_status="foreign")

        self.assertEqual(self.shim.read_text(), hand_edited,
                         "hand-edited shim was modified")


if __name__ == "__main__":
    unittest.main(verbosity=2)
