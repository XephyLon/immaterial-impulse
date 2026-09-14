#!/usr/bin/env python3
"""The installer's update contract, end to end, in a throwaway home.

docs/proposals/integration-tests.md, scope 1: install -> user-modify -> update
-> assert. The files step has real data-loss semantics - the shell tree is
synced with --delete by contract - while the user's own files must survive:
hypr/custom, hyprland/shellOverrides, hyprlock.conf and hypridle.conf (the
shipped version lands beside them as .new), the shell config and presets.
This runs the real `./setup install-files` twice against a fake $HOME, edits
the user-owned and the shipped files in between, and asserts per path. The
legacy step always; the yaml-driven `--exp-files` step when `yq` is present.

Network and the compositor are stubbed on PATH: fc-list (so the font fetch
is skipped), hyprctl, notify-send, and git (so an uninitialised submodule in
a worktree never triggers a fetch).
"""
import json
import os
import shutil
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # sdata/
REPO = ROOT.parent
SETUP = REPO / "setup"

STUBS = {
    "fc-list": "#!/bin/sh\necho 'Google Sans Flex'\n",
    "hyprctl": "#!/bin/sh\nexit 0\n",
    "notify-send": "#!/bin/sh\nexit 0\n",
    "git": "#!/bin/sh\n# submodule status: nothing out of date, so nothing is fetched\nexit 0\n",
}


class InstallLifecycle(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name) / "home"
        self.cfg = self.home / ".config"
        self.data = self.home / ".local/share"
        for d in (self.cfg, self.data, self.home / ".cache", self.home / ".local/state", self.home / ".local/bin"):
            d.mkdir(parents=True)
        self.bin = Path(self.tmp.name) / "bin"
        self.bin.mkdir()
        for name, body in STUBS.items():
            p = self.bin / name
            p.write_text(body)
            p.chmod(p.stat().st_mode | stat.S_IEXEC)

    def _install(self, *extra):
        env = {
            "PATH": f"{self.bin}:{os.environ['PATH']}", "HOME": str(self.home), "TERM": "dumb",
            "XDG_CONFIG_HOME": str(self.cfg), "XDG_DATA_HOME": str(self.data),
            "XDG_CACHE_HOME": str(self.home / ".cache"), "XDG_STATE_HOME": str(self.home / ".local/state"),
            "XDG_BIN_HOME": str(self.home / ".local/bin"), "BACKUP_DIR": str(self.home / "backup"),
        }
        args = ["install-files", "-f", "--skip-allgreeting", "--skip-fish", "--skip-tmux", "--skip-fontconfig",
                "--skip-miscconf", "--skip-plasmaintg", *extra]
        r = subprocess.run([str(SETUP), *args], cwd=str(REPO), env=env, capture_output=True, text=True, timeout=600)
        self.assertEqual(r.returncode, 0, (r.stdout + r.stderr)[-3000:])
        return r.stdout + r.stderr

    # ---- the user's edits between two installs ----
    def _mutate(self):
        hypr = self.cfg / "hypr"
        (hypr / "custom/keybinds.lua").write_text("-- my binds\n")
        existing_custom = sorted((hypr / "custom").glob("*.lua"))
        self.custom_existing = existing_custom[0] if existing_custom else None
        if self.custom_existing:
            self.custom_existing.write_text("-- edited by the user\n")
        (hypr / "hyprlock.conf").write_text("# my lock\n")
        (hypr / "hyprland/shellOverrides/mine.lua").write_text("-- written by the shell for me\n")
        shipped_overrides = sorted((hypr / "hyprland/shellOverrides").glob("*.lua"))
        self.override_existing = shipped_overrides[0] if shipped_overrides else None
        if self.override_existing:
            self.override_existing.write_text("-- my override edits\n")
        self.shipped_main = hypr / "hyprland/general.lua"
        self.shipped_main_original = self.shipped_main.read_text()
        self.shipped_main.write_text("-- I edited a shipped file, which the update owns\n")
        cfg = json.loads((self.cfg / "immaterial-impulse/config.json").read_text())
        cfg["bar"] = dict(cfg.get("bar", {}), style="probe-style")
        (self.cfg / "immaterial-impulse/config.json").write_text(json.dumps(cfg))
        (self.cfg / "immaterial-impulse/presets").mkdir(exist_ok=True)
        (self.cfg / "immaterial-impulse/presets/mine.json").write_text("{}")
        (self.cfg / "quickshell/imi/stray.qml").write_text("// not shipped\n")
        (hypr / "hyprland.conf").write_text("# a pre-lua config\n")

    def _assert_contract(self, first_run_output):
        hypr = self.cfg / "hypr"
        # Shipped trees are the update's: restored and pruned.
        self.assertEqual(self.shipped_main.read_text(), self.shipped_main_original, "a shipped hyprland file is restored")
        self.assertFalse((self.cfg / "quickshell/imi/stray.qml").exists(), "the shell tree is synced with --delete")
        self.assertTrue((self.cfg / "quickshell/imi/shell.qml").is_file())
        # The user's own files survive.
        self.assertEqual((hypr / "custom/keybinds.lua").read_text(), "-- my binds\n")
        if self.custom_existing:
            self.assertEqual(self.custom_existing.read_text(), "-- edited by the user\n", "custom/ is never overwritten")
        self.assertEqual((hypr / "hyprlock.conf").read_text(), "# my lock\n", "hyprlock.conf is kept")
        self.assertTrue((hypr / "hyprlock.conf.new").is_file(), "the shipped hyprlock lands beside it as .new")
        self.assertFalse((hypr / "hypridle.conf.new").exists(),
                         "an untouched hypridle.conf matches the shipped file: no .new noise")
        self.assertEqual((hypr / "hyprland/shellOverrides/mine.lua").read_text(), "-- written by the shell for me\n")
        if self.override_existing:
            self.assertEqual(self.override_existing.read_text(), "-- my override edits\n",
                             "shellOverrides is the shell's runtime state, never reset")
        cfg = json.loads((self.cfg / "immaterial-impulse/config.json").read_text())
        self.assertEqual(cfg["bar"]["style"], "probe-style", "config.json is the user's")
        self.assertTrue((self.cfg / "immaterial-impulse/presets/mine.json").is_file())
        self.assertFalse((hypr / "hyprland.conf").exists(), "a pre-lua hyprland.conf is moved aside")
        self.assertTrue((hypr / "hyprland.conf.old").is_file())
        self.assertTrue((self.cfg / "immaterial-impulse/installed_true").is_file())
        self.assertTrue((self.cfg / "immaterial-impulse/installed_listfile").is_file())

    def test_legacy_files_step_keeps_the_users_files_and_owns_the_shipped_ones(self):
        out = self._install()
        self.assertTrue((self.cfg / "quickshell/imi/shell.qml").is_file(), out[-2000:])
        self.assertTrue((self.cfg / "immaterial-impulse/config.json").is_file(), "a fresh install seeds the curated config")
        self.assertTrue((self.cfg / "hypr/hyprland/shellOverrides").is_dir())
        self.assertTrue((self.cfg / "hypr/custom").is_dir())
        self._mutate()
        self._install()
        self._assert_contract(out)

    @unittest.skipUnless(shutil.which("yq"), "the yaml files step needs yq")
    def test_yaml_files_step_honours_the_same_contract(self):
        self._install("--exp-files")
        self.assertTrue((self.cfg / "quickshell/imi/shell.qml").is_file())
        self._mutate()
        self._install("--exp-files")
        self._assert_contract("")


if __name__ == "__main__":
    unittest.main()
