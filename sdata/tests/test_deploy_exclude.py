#!/usr/bin/env python3
import subprocess, tempfile, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # sdata/
REPO = ROOT.parent                                   # repo root
EXCLUDE = ROOT / "lib/deploy-exclude.txt"
SRC = REPO / "dots/.config/quickshell/ii"


class DeployExcludeTests(unittest.TestCase):
    def test_dev_files_excluded_runtime_kept(self):
        with tempfile.TemporaryDirectory() as d:
            dest = Path(d) / "ii"
            subprocess.run(
                ["rsync", "-a", f"--exclude-from={EXCLUDE}", f"{SRC}/", f"{dest}/"],
                check=True,
            )
            self.assertTrue((dest / "shell.qml").is_file())
            self.assertTrue((dest / "modules").is_dir())
            self.assertTrue((dest / "scripts/migrate-config-dir.sh").is_file())
            # Runtime .md (AI system prompts) must survive the filter
            self.assertTrue((dest / "defaults/ai/prompts/ii-Default.md").is_file())
            self.assertFalse((dest / "tests").exists())
            self.assertFalse((dest / "screenshots").exists())
            self.assertFalse((dest / "DesignSystemCompile.qml").exists())
            self.assertFalse(any(dest.glob("*RuntimeTest.qml")))


if __name__ == "__main__":
    unittest.main()
