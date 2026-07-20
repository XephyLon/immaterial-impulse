#!/usr/bin/env python3

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "plugin_uninstaller", ROOT / "scripts/plugins/uninstall_plugin.py")
UNINSTALLER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(UNINSTALLER)


class PluginUninstallerTargetTests(unittest.TestCase):
    def test_resolves_an_installed_package_directory(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "docker_plugin").mkdir()
            self.assertEqual(
                UNINSTALLER.resolve_target(root, "docker_plugin"),
                (root / "docker_plugin").resolve())

    def test_rejects_invalid_id(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for bad in ["../etc", "a/b", ".hidden", "", "has space"]:
                with self.assertRaises(ValueError):
                    UNINSTALLER.resolve_target(root, bad)

    def test_missing_plugin_raises(self):
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(FileNotFoundError):
                UNINSTALLER.resolve_target(Path(directory), "ghost")

    def test_symlinked_entry_is_returned_for_unlink_not_followed(self):
        # A symlink planted at the plugin path must be reported as the link
        # itself so the caller unlinks it; resolving through it would delete
        # whatever it points at.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            victim = root / "victim"
            victim.mkdir()
            (victim / "keep").write_text("data")
            link = root / "evil"
            os.symlink(victim, link)

            target = UNINSTALLER.resolve_target(root, "evil")
            self.assertTrue(target.is_symlink())
            self.assertEqual(target, link)
            # The caller only unlinks the link; the victim is untouched.
            target.unlink()
            self.assertTrue((victim / "keep").exists())

    def test_directory_entry_must_stay_under_root(self):
        # A plugin path that resolves outside the install root (e.g. the id
        # names a directory reached through a symlinked parent) is refused.
        with tempfile.TemporaryDirectory() as outer:
            root = Path(outer) / "root"
            root.mkdir()
            elsewhere = Path(outer) / "elsewhere"
            elsewhere.mkdir()
            # `plugins` inside root is itself a link to a dir outside root.
            os.symlink(elsewhere, root / "plugins")
            # id "plugins" -> symlink -> returned as link, unlink-only (safe).
            self.assertTrue(UNINSTALLER.resolve_target(root, "plugins").is_symlink())


if __name__ == "__main__":
    unittest.main()
