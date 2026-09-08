#!/usr/bin/env python3
"""`setup backup` / `setup restore`: the user's own config, round-tripped.

The installer never overwrites these files on an update, so they are the
part of a machine that is not reproducible from the repo: the shell's
config/plugins/presets, hypr/custom, shellOverrides, hyprlock/hypridle.
Backup archives them; restore puts them back, moving anything already there
aside instead of deleting it, and refuses to run under a live shell.
"""
import json
import os
import subprocess
import tarfile
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # sdata/
SETUP = ROOT.parent / "setup"


def _seed(cfg: Path):
    (cfg / "immaterial-impulse/presets").mkdir(parents=True)
    (cfg / "immaterial-impulse/config.json").write_text('{"bar":{"style":"hug"}}')
    (cfg / "immaterial-impulse/presets/mine.json").write_text("{}")
    (cfg / "immaterial-impulse/installed_true").write_text("")
    (cfg / "immaterial-impulse/installed_listfile").write_text("x\n")
    (cfg / "hypr/custom").mkdir(parents=True)
    (cfg / "hypr/custom/keybinds.lua").write_text("-- mine")
    (cfg / "hypr/hyprland/shellOverrides").mkdir(parents=True)
    (cfg / "hypr/hyprland/shellOverrides/main.lua").write_text("-- override")
    (cfg / "hypr/hyprlock.conf").write_text("lock")
    # The installer's own files must not travel with the backup.
    (cfg / "hypr/hyprland/main.lua").write_text("-- shipped")
    (cfg / "quickshell/imi").mkdir(parents=True)


class BackupRestore(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name) / "home"
        self.cfg = self.home / ".config"
        self.bin = Path(self.tmp.name) / "bin"
        self.bin.mkdir(parents=True)
        self.cfg.mkdir(parents=True)
        # a pgrep that says "no shell running" unless a test swaps it
        self._fake_pgrep(running=False)

    def tearDown(self):
        self.tmp.cleanup()

    def _fake_pgrep(self, running: bool):
        p = self.bin / "pgrep"
        p.write_text("#!/bin/sh\nexit %d\n" % (0 if running else 1))
        p.chmod(0o755)

    def _setup(self, *args, cwd=None):
        env = {"PATH": f"{self.bin}:{os.environ['PATH']}", "HOME": str(self.home),
               "XDG_CONFIG_HOME": str(self.cfg), "IMI_PGREP": str(self.bin / "pgrep"),
               "TERM": "dumb"}
        return subprocess.run([str(SETUP), *args], cwd=cwd or self.tmp.name, env=env,
                              capture_output=True, text=True)

    def test_backup_carries_the_users_files_and_nothing_shipped(self):
        _seed(self.cfg)
        r = self._setup("backup", "-o", "out/b.tar.gz")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        archive = Path(self.tmp.name) / "out/b.tar.gz"     # relative to the invoking cwd
        self.assertTrue(archive.is_file(), "a relative -o is relative to where the user typed it")
        with tarfile.open(archive) as t:
            names = set(t.getnames())
            manifest = json.load(t.extractfile("./imi-backup.json"))
        self.assertIn("./immaterial-impulse/config.json", names)
        self.assertIn("./immaterial-impulse/presets/mine.json", names)
        self.assertIn("./hypr/custom/keybinds.lua", names)
        self.assertIn("./hypr/hyprland/shellOverrides/main.lua", names)
        self.assertIn("./hypr/hyprlock.conf", names)
        self.assertNotIn("./hypr/hyprland/main.lua", names, "shipped hyprland files are the repo's, not the user's")
        self.assertNotIn("./immaterial-impulse/installed_true", names, "install state must not travel")
        self.assertNotIn("./immaterial-impulse/installed_listfile", names)
        self.assertNotIn("./quickshell", names)
        self.assertEqual(manifest["format"], 1)
        self.assertIn("immaterial-impulse", manifest["paths"])

    def test_restore_round_trips_and_keeps_what_was_there(self):
        _seed(self.cfg)
        r = self._setup("backup", "-o", "b.tar.gz")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        # Simulate a new machine: different config, some paths missing.
        (self.cfg / "immaterial-impulse/config.json").write_text('{"bar":{"style":"m3"}}')
        (self.cfg / "immaterial-impulse/config.json.bak").write_text("keep me")
        import shutil; shutil.rmtree(self.cfg / "hypr/custom")
        r = self._setup("restore", "b.tar.gz")
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual((self.cfg / "immaterial-impulse/config.json").read_text(), '{"bar":{"style":"hug"}}')
        self.assertEqual((self.cfg / "hypr/custom/keybinds.lua").read_text(), "-- mine")
        self.assertEqual((self.cfg / "hypr/hyprland/main.lua").read_text(), "-- shipped", "untouched: not in the archive")
        aside = list(self.cfg.glob("immaterial-impulse.pre-restore-*"))
        self.assertEqual(len(aside), 1, "the previous config dir is moved aside, not deleted")
        self.assertEqual((aside[0] / "config.json").read_text(), '{"bar":{"style":"m3"}}')
        self.assertTrue((aside[0] / "config.json.bak").is_file())
        self.assertFalse((self.cfg / "immaterial-impulse/installed_true").exists(),
                         "install state is neither archived nor resurrected")

    def test_restore_refuses_a_live_shell_unless_forced(self):
        _seed(self.cfg)
        self.assertEqual(self._setup("backup", "-o", "b.tar.gz").returncode, 0)
        self._fake_pgrep(running=True)
        r = self._setup("restore", "b.tar.gz")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("shell is running", r.stderr + r.stdout)
        self.assertEqual(self._setup("restore", "--force", "b.tar.gz").returncode, 0)

    def test_restore_refuses_a_foreign_tarball(self):
        (self.cfg / "immaterial-impulse").mkdir()
        foreign = Path(self.tmp.name) / "foreign.tar.gz"
        with tarfile.open(foreign, "w:gz") as t:
            t.add(self.cfg / "immaterial-impulse", arcname="./immaterial-impulse")
        r = self._setup("restore", str(foreign))
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("not an Immaterial Impulse backup", r.stderr + r.stdout)
        self.assertFalse(list(self.cfg.glob("*.pre-restore-*")), "nothing moved before the refusal")

    def test_backup_with_nothing_to_save_fails_loudly(self):
        r = self._setup("backup", "-o", "b.tar.gz")
        self.assertNotEqual(r.returncode, 0)
        self.assertIn("Nothing to back up", r.stderr + r.stdout)
        self.assertFalse((Path(self.tmp.name) / "b.tar.gz").exists())


if __name__ == "__main__":
    unittest.main()
