#!/usr/bin/env python3
"""The SDDM login theme is installed from our fork, not from upstream.

`sdata/subcmd-install/5.sddm-theme.sh` fetches the theme's own `setup.sh` at a
pinned commit and hands off. That makes the source of the installed theme a
two-link chain, and the second link is invisible from this repo:

    5.sddm-theme.sh  --SDDM_REPO_RAW/SDDM_REF-->  fork's setup.sh
    fork's setup.sh  --THEME_REPO-->              the theme actually installed

Retargeting only the first link is what shipped once and installed upstream's
theme verbatim, silently reverting every fork change (the immaterial-impulse
config path, the Wallpaper Engine resolution) on every install. The second link
lives in the fork and cannot be checked here without network, so this pins what
can be checked offline: the first link points at the fork, the pin is a full
commit SHA rather than a branch, and no upstream URL has crept back in.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve()
while not (ROOT / "sdata").exists():
    if ROOT.parent == ROOT:
        raise AssertionError("could not locate the repo root")
    ROOT = ROOT.parent

INSTALLER = ROOT / "sdata/subcmd-install/5.sddm-theme.sh"
FORK = "XephyLon/imi-sddm-theme"
UPSTREAM = "3d3f/ii-sddm-theme"


class SddmThemeSourceTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = INSTALLER.read_text()

    def test_the_installer_is_fetched_from_our_fork(self):
        match = re.search(r'^SDDM_REPO_RAW="\$\{SDDM_REPO_RAW:-([^}"]+)\}"',
                          self.text, re.M)
        self.assertIsNotNone(match, "SDDM_REPO_RAW is not set in the expected form")
        self.assertIn(FORK, match.group(1))

    def test_no_upstream_url_is_used_as_a_source(self):
        """Attribution is fine in prose; a fetch URL is not."""
        for line in self.text.splitlines():
            if UPSTREAM in line and not line.lstrip().startswith("#"):
                self.fail(f"upstream is used as a source: {line.strip()}")

    def test_the_pin_is_a_full_commit_sha(self):
        """A branch name here would make installs unreproducible and would let
        the theme change under a pinned release."""
        match = re.search(r'^SDDM_REF="\$\{SDDM_REF:-([^}"]+)\}"', self.text, re.M)
        self.assertIsNotNone(match, "SDDM_REF is not set in the expected form")
        self.assertRegex(match.group(1), r"^[0-9a-f]{40}$")


if __name__ == "__main__":
    unittest.main()
