#!/usr/bin/env python3
"""Contracts for the experimental updater (sdata/subcmd-exp-update/0.run.sh).

Static assertions pinning the update-detection fix and the changelog display:
  - detection must key off a baseline SHA captured before the pull (PREV_HEAD),
    not the reflog's HEAD@{1}, which a stash or detached-HEAD checkout repoints
    (the bug where existing updates were not reported);
  - a pre-pull `git fetch` + `git rev-list --count` must report how many updates
    are available, straight from refs;
  - the CHANGELOG delta between baseline and new HEAD must be shown to the user.
"""
import re
import sys
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[5]
SCRIPT = REPO / "sdata" / "subcmd-exp-update" / "0.run.sh"


class ExpUpdateContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.text = SCRIPT.read_text(encoding="utf-8") if SCRIPT.exists() else ""

    def test_script_exists(self):
        self.assertTrue(SCRIPT.exists(), f"missing {SCRIPT}")

    def test_captures_prepull_baseline(self):
        self.assertRegex(self.text, r'PREV_HEAD="\$\(git rev-parse HEAD',
                         "must capture a pre-pull baseline SHA")

    def test_detection_prefers_baseline_over_reflog(self):
        # has_new_commits must compare HEAD to PREV_HEAD before falling back.
        m = re.search(r"has_new_commits\(\)\s*\{(.*?)\n\}", self.text, re.S)
        self.assertIsNotNone(m, "has_new_commits() not found")
        body = m.group(1)
        self.assertIn("PREV_HEAD", body,
                      "has_new_commits must use PREV_HEAD, not only HEAD@{1}")
        self.assertLess(body.index("PREV_HEAD"), body.index("HEAD@{1}")
                        if "HEAD@{1}" in body else len(body),
                        "PREV_HEAD must be preferred before the reflog fallback")

    def test_changed_files_diff_against_baseline(self):
        self.assertRegex(
            self.text,
            r'git diff --name-only --diff-filter=ACMR "\$base_ref" HEAD',
            "changed-file detection must diff against the baseline ref")

    def test_reports_available_updates_from_refs(self):
        self.assertIn("git fetch --quiet origin", self.text,
                      "must fetch before reporting available updates")
        self.assertRegex(self.text,
                         r'git rev-list --count "HEAD\.\.origin/\$\{current_branch\}"',
                         "must count incoming commits from refs, not the reflog")
        self.assertIn("new update(s) available", self.text)

    def test_shows_changelog_delta(self):
        self.assertIn("show_changelog_delta", self.text,
                      "must define/call a changelog display")
        m = re.search(r"show_changelog_delta\(\)\s*\{(.*?)\n\}", self.text, re.S)
        self.assertIsNotNone(m, "show_changelog_delta() not found")
        body = m.group(1)
        self.assertIn("CHANGELOG.md", body)
        self.assertRegex(body, r'git diff "\$\{PREV_HEAD\}\.\.HEAD" -- "\$changelog"',
                         "must diff CHANGELOG.md between baseline and new HEAD")
        # Guard against dumping a brand-new changelog wholesale.
        self.assertIn("git cat-file -e", body,
                      "must confirm the changelog existed at the baseline first")

    def test_changelog_shown_on_successful_pull(self):
        # The post-pull path must call show_changelog_delta when HEAD advanced.
        self.assertRegex(
            self.text,
            r'== "\$PREV_HEAD"[^\n]*\n[\s\S]{0,120}?else[\s\S]{0,120}?show_changelog_delta',
            "changelog must be shown when the pull advanced HEAD")


if __name__ == "__main__":
    unittest.main()
