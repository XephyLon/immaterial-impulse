#!/usr/bin/env python3
"""Guards for defaults/config.json — the curated out-of-the-box shell config
seeded by the installer on fresh installs (see 3.files.sh seed_default_config).

It is generated from a real config, so the big risks are (a) leaking
machine-specific/personal values, and (b) pinning keys whose Config.qml default
is a dynamic expression (a shipped literal would override per-user paths).
"""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "defaults/config.json"


class DefaultConfigTest(unittest.TestCase):
    def setUp(self):
        self.text = DEFAULT_CONFIG.read_text()
        self.cfg = json.loads(self.text)

    def test_parses_and_is_nonempty(self):
        self.assertIsInstance(self.cfg, dict)
        self.assertGreater(len(self.cfg), 10)

    def test_no_machine_or_personal_paths(self):
        # Any absolute home path, username, or Steam-content path is a leak
        # from the machine the file was generated on.
        self.assertIsNone(
            re.search(r"/home/|xephy|steamapps|\.local/share/Steam", self.text),
            "defaults/config.json leaks a machine-specific path",
        )

    def test_machine_state_keys_are_reset(self):
        bg = self.cfg["background"]
        for key in ("wallpaperPath", "thumbnailPath", "lockWall", "lockWallEngine"):
            self.assertEqual(bg[key], "", f"background.{key} must ship empty")
        we = self.cfg["wallpaperSelector"]["wallpaperEngine"]
        for key in ("activePath", "activePreview", "activeProject", "activeStill", "activeType", "libraryPath"):
            self.assertEqual(we[key], "", f"wallpaperEngine.{key} must ship empty")
        for key in ("avatarPath", "avatarPicture", "displayName"):
            self.assertEqual(self.cfg["profile"][key], "", f"profile.{key} must ship empty")

    def test_no_dynamic_default_overrides(self):
        # screenRecord.savePath's Config.qml default is the per-user videos dir
        # (a dynamic expression); shipping any literal would break it.
        self.assertNotIn("savePath", self.cfg.get("screenRecord", {}))

    def test_no_preset_metadata(self):
        self.assertNotIn("_presetMeta", self.cfg)


if __name__ == "__main__":
    unittest.main()
