#!/usr/bin/env python3
"""Installer housekeeping: the caches an install leaves behind get pruned.

Quickshell's QML disk cache keys entries by source hash, so every shipped
change to a .qml leaves the old compiled entry behind for good; one machine
carried 44,745 entries (798 MB), 580 of them touched in the last week, next
to 70 crash dumps (465 MB) and 57 install logs. `setup` now prunes the two
cache directories after deploying files, and the TUI rotates its logs.
"""
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # sdata/


class ShellCacheHousekeeping(unittest.TestCase):
    """qmlcache/crash entries untouched for 30 days go; fresh ones stay."""

    FUNCTIONS = ROOT / "lib/functions.sh"
    SETUP = ROOT.parent / "setup"
    TUI = ROOT / "subcmd-install/tui.sh"

    def _prune(self, cache_home: Path):
        script = (f"source '{self.FUNCTIONS}'\n"
                  f"XDG_CACHE_HOME='{cache_home}' prune_shell_caches\n")
        subprocess.run(["bash", "-eo", "pipefail", "-c", script],
                       env={"PATH": os.environ["PATH"], "HOME": str(cache_home)},
                       capture_output=True, text=True, check=True)

    def test_qmlcache_is_wiped_and_only_old_crash_dumps_go(self):
        import time
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            qml = home / "quickshell/qmlcache"; crashes = home / "quickshell/crashes/abc"
            qml.mkdir(parents=True); crashes.mkdir(parents=True)
            old = time.time() - 40 * 86400
            for f in (qml / "old.qmlc", crashes / "old.dump"):
                f.write_text("x"); os.utime(f, (old, old))
            (qml / "fresh.qmlc").write_text("x")
            (crashes / "fresh.dump").write_text("x")
            (home / "quickshell/other.txt").write_text("x")
            os.utime(home / "quickshell/other.txt", (old, old))
            self._prune(home)
            self.assertFalse((qml / "old.qmlc").exists())
            self.assertFalse((qml / "fresh.qmlc").exists(),
                             "stale qmlcache entries are mostly young; the cache is wiped")
            self.assertTrue(qml.is_dir(), "the directory itself stays")
            self.assertFalse((crashes / "old.dump").exists())
            self.assertTrue((crashes / "fresh.dump").exists())
            self.assertTrue((home / "quickshell/other.txt").exists(),
                            "only qmlcache/ and crashes/ are ours to prune")

    def test_missing_directories_are_fine(self):
        with tempfile.TemporaryDirectory() as tmp:
            self._prune(Path(tmp) / "nowhere")   # must not raise

    def test_setup_prunes_after_deploying_files(self):
        src = self.SETUP.read_text(encoding="utf-8")
        files_step = src.index("3.files.sh")
        self.assertIn("prune_shell_caches", src[files_step:files_step + 400],
                      "setup must prune the QML cache right after the files step")

    def test_install_logs_are_rotated(self):
        src = self.TUI.read_text(encoding="utf-8")
        body = src[src.index("run_quiet_install(){"):]
        self.assertRegex(body, r"ls -1t .*install-\*\.log.*\| tail -n \+5 \| xargs -r rm -f",
                         "run_quiet_install must drop all but the newest install logs")



if __name__ == "__main__":
    unittest.main()
