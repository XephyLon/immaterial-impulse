#!/usr/bin/env python3
"""`restore_sddm_matugen_hook` must point at the theme that is actually there.

We ship our own `~/.config/matugen/config.toml` and deploy it with
`rsync --delete`, which removes the SDDM theme's `post_hook` on every update -
so the login screen stops following the wallpaper until the hook is put back.
`sdata/subcmd-install/3.files-legacy.sh` restores it.

The hook is a path, and the theme's directory name changed: it installs as
`imi-sddm-theme` now, and installs from before that rename are still under
`ii-sddm-theme` until the theme's own installer migrates them. So the restore
has to resolve the name rather than hardcode it, and it has to prefer the new
one - during a migrating update both directories exist for a moment, and a hook
written against the one about to be deleted is broken the instant the migration
finishes.

Hermetic: sources just this function out of 3.files-legacy.sh (the file is
meant to be sourced by ./setup and has a procedural body) and runs it against a
sandbox HOME.
"""

import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve()
while not (ROOT / "sdata").exists():
    if ROOT.parent == ROOT:
        raise AssertionError("could not locate the repo root")
    ROOT = ROOT.parent

SCRIPT = ROOT / "sdata/subcmd-install/3.files-legacy.sh"
FUNCTION = "restore_sddm_matugen_hook"

BASE_CONF = "[config]\nreload_apps = true\n"


def _extract_function(text, name):
    start = text.index(f"{name}(){{")
    end = text.index("\n}\n", start) + len("\n}\n")
    return text[start:end]


class SddmMatugenHookRestoreTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.function = _extract_function(SCRIPT.read_text(), FUNCTION)

    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-sddm-hook-"))
        self.addCleanup(
            __import__("shutil").rmtree, self.home, ignore_errors=True)
        self.config = self.home / "config"
        (self.config / "matugen").mkdir(parents=True)
        self.matugen_conf = self.config / "matugen/config.toml"
        self.matugen_conf.write_text(BASE_CONF)

    def install_theme(self, name, with_generate_settings=True):
        theme = self.config / name
        theme.mkdir(parents=True)
        (theme / "sddm-theme-apply.sh").write_text("#!/bin/sh\n")
        if with_generate_settings:
            (theme / "generate_settings.py").write_text("# stub\n")

    def run_restore(self):
        script = textwrap.dedent(f"""\
            #!/usr/bin/env bash
            set -uo pipefail
            XDG_CONFIG_HOME="{self.config}"
            STY_BLUE=""; STY_RST=""
            {self.function}
            {FUNCTION}
            """)
        path = self.home / "drive.sh"
        path.write_text(script)
        proc = subprocess.run(["bash", str(path)], capture_output=True, text=True)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        return self.matugen_conf.read_text()

    def test_the_current_name_is_used(self):
        self.install_theme("imi-sddm-theme")
        conf = self.run_restore()
        self.assertIn("~/.config/imi-sddm-theme/sddm-theme-apply.sh", conf)
        self.assertNotIn("ii-sddm-theme/", conf.replace("imi-sddm-theme/", ""))

    def test_an_unmigrated_install_still_gets_its_hook(self):
        """Pre-rename installs exist until the theme's installer migrates them,
        and they need the hook restored just as much."""
        self.install_theme("ii-sddm-theme")
        conf = self.run_restore()
        self.assertIn("~/.config/ii-sddm-theme/sddm-theme-apply.sh", conf)

    def test_with_both_present_the_current_name_wins(self):
        """A migrating update has both on disk at once. Writing the hook
        against the directory about to be removed breaks it immediately."""
        self.install_theme("ii-sddm-theme")
        self.install_theme("imi-sddm-theme")
        conf = self.run_restore()
        self.assertIn("~/.config/imi-sddm-theme/", conf)
        self.assertNotIn("~/.config/ii-sddm-theme/", conf)

    def test_the_matugen_only_mode_gets_no_generate_settings_call(self):
        """generate_settings.py ships only with the ii+matugen mode; calling it
        where it does not exist makes the hook fail every wallpaper change."""
        self.install_theme("imi-sddm-theme", with_generate_settings=False)
        conf = self.run_restore()
        self.assertIn("sudo ~/.config/imi-sddm-theme/sddm-theme-apply.sh", conf)
        self.assertNotIn("generate_settings.py", conf)

    def test_no_theme_means_no_hook(self):
        self.assertEqual(self.run_restore(), BASE_CONF)

    def test_an_existing_hook_is_not_duplicated(self):
        self.install_theme("imi-sddm-theme")
        first = self.run_restore()
        self.assertEqual(first.count("post_hook"), 1)
        self.assertEqual(self.run_restore(), first)

    def test_the_trailing_ampersand_survives(self):
        """The hook ends in `&`, and `&` in a sed replacement means the whole
        match - unescaped it expands to the literal text it was replacing."""
        self.install_theme("imi-sddm-theme")
        conf = self.run_restore()
        self.assertIn("sddm-theme-apply.sh &'", conf)
        self.assertNotIn("[config]'", conf)


if __name__ == "__main__":
    unittest.main()
