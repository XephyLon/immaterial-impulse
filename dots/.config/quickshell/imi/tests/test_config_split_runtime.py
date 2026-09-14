#!/usr/bin/env python3
"""The appearance domain lives in config.d/appearance.json (config split, stage 1).

A fresh start with an old-style config.json splits appearance out once and
never loses it; appearance writes land in the new file and nowhere else;
every other domain stays in config.json; an existing appearance.json wins
over the stale copy config.json keeps for downgrades.
"""
import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import nested_display

ROOT = Path(__file__).resolve().parent.parent
HARNESS = ROOT / "ConfigSplitRuntimeTest.qml"
SHIPPED_DEFAULT = ROOT / "defaults/config.json"


@unittest.skipUnless(nested_display.available(),
                     "needs qs, weston and dbus-run-session on PATH")
class ConfigSplitRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-config-split-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)
        self.cfg_dir = self.home / "config" / "immaterial-impulse"
        self.cfg_dir.mkdir(parents=True)
        self.config = json.loads(SHIPPED_DEFAULT.read_text())
        self.config["migratedUpstreamSchema"] = True
        self.config.setdefault("osd", {})["timeout"] = 1700
        self.config.setdefault("appearance", {})["iconTheme"] = "probe-theme"

    def run_shell(self, mode, expected_checks):
        (self.cfg_dir / "config.json").write_text(json.dumps(self.config, indent=2))
        env = nested_display.start(self, f"config-split-{mode}")
        env["XDG_CONFIG_HOME"] = str(self.home / "config")
        env["XDG_STATE_HOME"] = str(self.home / "state")
        env["XDG_CACHE_HOME"] = str(self.home / "cache")
        env["XDG_DATA_HOME"] = str(self.home / "data")
        env["CONFIGSPLIT_MODE"] = mode
        proc = subprocess.run(["dbus-run-session", "--", "qs", "-p", str(HARNESS)], cwd=str(ROOT),
                              env=env, capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        for line in output.splitlines():
            if "[ConfigSplit]" in line or "[Config]" in line:
                print(line.strip())
        failed = [line for line in output.splitlines() if "[ConfigSplit]" in line and "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output[-4000:]}")
        self.assertIn(f"[ConfigSplit] checks: {expected_checks} failures: 0", output, output[-4000:])
        ready = [line for line in output.splitlines() if "readyAfterMs:" in line]
        print(f"[measure] {mode}: Config.ready after {ready[0].split('readyAfterMs:')[1].strip() if ready else '?'} ms of harness time")

    def test_a_fresh_start_splits_appearance_out_once(self):
        self.run_shell("split", 4)
        split = json.loads((self.cfg_dir / "config.d" / "appearance.json").read_text())
        self.assertEqual(split["appearance"]["iconTheme"], "probe-theme", "the seeded value travelled into the file")
        self.assertEqual(split["appearance"]["fakeScreenRounding"], 1, "an appearance write landed in the file")
        self.assertFalse(split["appearance"]["extraBackgroundTint"])
        main = json.loads((self.cfg_dir / "config.json").read_text())
        self.assertEqual(main["osd"]["timeout"], 1900, "the other domain's write landed in config.json")
        self.assertNotIn("appearance", main, "the adapter writes the schema it has: appearance leaves config.json")
        self.assertTrue(main["migratedUpstreamSchema"])
        backups = list(self.cfg_dir.glob("config.json.pre-split-*"))
        self.assertEqual(len(backups), 1, "one downgrade copy, taken before the first write")
        old = json.loads(backups[0].read_text())
        self.assertEqual(old["appearance"]["iconTheme"], "probe-theme")
        self.assertEqual(old["osd"]["timeout"], 1700, "the copy predates this session's writes")

    def test_an_arriving_upstream_config_still_gets_an_unstripped_downgrade_copy(self):
        """No migratedUpstreamSchema marker: the raw-text migration asks for
        a config.json write before ready. The split's copy must still hold
        appearance, and the write must land after ready (the marker persists)."""
        del self.config["migratedUpstreamSchema"]
        self.run_shell("unmarked", 5)
        backups = list(self.cfg_dir.glob("config.json.pre-split-*"))
        self.assertEqual(len(backups), 1)
        old = json.loads(backups[0].read_text())
        self.assertEqual(old["appearance"]["iconTheme"], "probe-theme", "the copy predates the first write")
        self.assertNotIn("migratedUpstreamSchema", old)
        main = json.loads((self.cfg_dir / "config.json").read_text())
        self.assertTrue(main["migratedUpstreamSchema"], "the early write was flushed once ready")
        self.assertNotIn("appearance", main)
        self.assertEqual(json.loads((self.cfg_dir / "config.d" / "appearance.json").read_text())["appearance"]["fakeScreenRounding"], 1)

    def test_an_existing_split_file_wins_over_the_stale_copy(self):
        (self.cfg_dir / "config.d").mkdir()
        (self.cfg_dir / "config.d" / "appearance.json").write_text(json.dumps({"appearance": {"iconTheme": "from-the-split-file"}}))
        self.config["appearance"]["iconTheme"] = "stale-in-config-json"
        self.run_shell("existing", 4)
        split = json.loads((self.cfg_dir / "config.d" / "appearance.json").read_text())
        self.assertEqual(split["appearance"]["iconTheme"], "from-the-split-file")
        self.assertEqual(split["appearance"]["fakeScreenRounding"], 1)
        main = json.loads((self.cfg_dir / "config.json").read_text())
        self.assertNotIn("appearance", main, "the stale copy is dropped on the first write, never rewritten from the split file")
        self.assertEqual(list(self.cfg_dir.glob("config.json.pre-split-*")), [], "no split happened, so no downgrade copy")


if __name__ == "__main__":
    unittest.main()
