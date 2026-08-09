#!/usr/bin/env python3
"""The pinned SDDM_REF must be a commit on the satellite's main branch.

The satellite tags its releases, but the hub pins the SHA of the release
commit rather than the tag, because test_sddm_theme_source.py requires a
40-char SHA - a moving ref could change the theme under a pinned release. That
makes *which* SHA a live question, because this repo merges with rebase, which
rewrites every commit. So the branch head you tested
is never the commit that lands: it survives only on the merged branch ref and
vanishes when that ref is deleted. A pin naming such a commit keeps working
right up until someone tidies up branches, then installs 404 fetching setup.sh.

That is not hypothetical - it is what happened the first time this pin moved
for the staging change, which is why this check exists rather than another
comment. Pin parity between the two sites is `test_sddm_theme_source.py`; this
is about whether the SHA they agree on is one that actually landed.

Needs network, and skips without it: the suite has to stay green offline.
"""

import json
import re
import unittest
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve()
while not (ROOT / "sdata").exists():
    ROOT = ROOT.parent
INSTALL_STEP = ROOT / "sdata/subcmd-install/5.sddm-theme.sh"

REPO = "XephyLon/imi-sddm-theme"
API = f"https://api.github.com/repos/{REPO}/compare/main...{{sha}}"


def pinned_sha():
    match = re.search(r'^SDDM_REF="\$\{SDDM_REF:-([0-9a-f]{40})\}"',
                      INSTALL_STEP.read_text(), re.M)
    assert match, "SDDM_REF is not a bare 40-char SHA in 5.sddm-theme.sh"
    return match.group(1)


def compare_to_main(sha):
    """GitHub's compare status, or None when the network/API is unavailable."""
    request = urllib.request.Request(
        API.format(sha=sha), headers={"Accept": "application/vnd.github+json"})
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            return json.load(response).get("status")
    except urllib.error.HTTPError as error:
        # 404 means the SHA is not in the repository at all - a real failure,
        # and exactly what a deleted branch produces. Anything else (403 rate
        # limit, 5xx) is the API being unavailable, not a verdict.
        if error.code == 404:
            return "missing"
        return None
    except (urllib.error.URLError, TimeoutError, OSError):
        return None


class SddmPinReachableTest(unittest.TestCase):
    def test_the_pin_is_a_commit_on_the_satellites_main(self):
        sha = pinned_sha()
        status = compare_to_main(sha)
        if status is None:
            self.skipTest("no network or GitHub API unavailable")

        self.assertNotEqual(
            status, "missing",
            f"SDDM_REF {sha[:9]} does not exist in {REPO} at all - it was "
            "almost certainly a pre-rebase branch head whose branch is now "
            "deleted. Re-pin to the SHA on main.")

        # main...pin is "identical" when the pin IS main's head, and "behind"
        # when main has moved on past it. Both mean the commit landed.
        # "ahead" or "diverged" means the pin is on some other line of history -
        # a branch that was never merged, or a pre-rebase head still reachable
        # only because its branch ref survives.
        self.assertIn(
            status, ("identical", "behind"),
            f"SDDM_REF {sha[:9]} is not an ancestor of {REPO}'s main "
            f"(compare status: {status}). This repo merges with rebase, so the "
            "branch head you tested is not the commit that landed - re-read the "
            "SHA off main after merging.")


if __name__ == "__main__":
    unittest.main()
