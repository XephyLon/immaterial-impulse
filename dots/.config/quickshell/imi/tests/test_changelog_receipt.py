#!/usr/bin/env python3
"""The Changelog receipt's matching logic, over in-memory fixtures.

`changelog_receipt.py` is the one implementation of the rule; this is what
proves it, without a push and without a PR. The fixtures are the four things
the rule has to get right: the accepted forms, the rejected ones, an `updated`
claim the diff does not back, and the exemption for a PR that touches nothing
under `dots/`.

Subclasses `unittest.TestCase` deliberately: `run_tests.sh` invokes each Python
check as `python3 <file>`, so a module of bare `test_*` functions defines them
and exits zero without running one - three modules shipped as silent no-ops
that way (CONTRIBUTING.md → "New features and bugfixes need tests").
"""

import unittest

import changelog_receipt as receipt

SHELL_FILE = "dots/.config/quickshell/imi/shell.qml"


class ReceiptMatching(unittest.TestCase):
    def test_the_accepted_forms_are_accepted(self):
        for body in (
            "Changelog: updated",
            "Changelog: updated — one Fixed entry under [Unreleased]",
            "Changelog: not user-visible — CI plumbing only",
            "Changelog: not user-visible - a plain hyphen is fine",
            "Changelog: not user-visible – and so is an en dash",
            "Changelog: not user-visible—no spaces around the dash",
            "Changelog: not user-visible   —   generously spaced",
            "Some prose.\n\nChangelog: updated\nDocs: updated CONTRIBUTING.md",
            "Changelog: updated\r\nDocs: updated CONTRIBUTING.md\r\n",
            "Changelog: not user-visible — trailing spaces on the line   ",
        ):
            with self.subTest(body=body):
                self.assertIsNotNone(receipt.receipt_line(body))

    def test_the_rejected_forms_are_rejected(self):
        for body in (
            "",
            "No receipt anywhere in this body.",
            # The second form's whole content is its reason.
            "Changelog: not user-visible",
            "Changelog: not user-visible —",
            "Changelog: not user-visible —    ",
            # A verdict, not a form: "nothing to add" is what the two empty
            # releases were made of.
            "Changelog: n/a",
            "Changelog: none",
            "Changelog: not needed — wrong receipt's wording",
            # Must own its line, the way `Docs:` does.
            "  Changelog: updated",
            "See also Changelog: updated",
            "changelog: updated",
        ):
            with self.subTest(body=body):
                self.assertIsNone(receipt.receipt_line(body))

    def test_a_reason_may_not_be_only_a_dash(self):
        # Liberal about the separator is not liberal about the reason: a second
        # dash is punctuation, so the reason after it must still be there.
        self.assertIsNone(receipt.receipt_line("Changelog: not user-visible — -"))
        self.assertIsNotNone(receipt.receipt_line("Changelog: not user-visible — -ish"))


class Verdict(unittest.TestCase):
    def test_a_pr_touching_nothing_under_dots_needs_no_receipt(self):
        for files in (
            ["CONTRIBUTING.md"],
            [".github/workflows/tests.yml"],
            ["docs/PLUGINS.md", "README.md"],
            [],
        ):
            with self.subTest(files=files):
                ok, message = receipt.verdict("no receipt here", files)
                self.assertTrue(ok, message)

    def test_a_shell_change_without_a_receipt_fails(self):
        ok, message = receipt.verdict("A body with no receipt.", [SHELL_FILE])
        self.assertFalse(ok)
        self.assertEqual(message, receipt.MISSING_MESSAGE)

    def test_updated_must_be_backed_by_a_changelog_diff(self):
        ok, message = receipt.verdict("Changelog: updated", [SHELL_FILE])
        self.assertFalse(ok)
        self.assertEqual(message, receipt.UNBACKED_MESSAGE)

        ok, message = receipt.verdict(
            "Changelog: updated", [SHELL_FILE, receipt.CHANGELOG_PATH]
        )
        self.assertTrue(ok, message)

    def test_not_user_visible_needs_no_changelog_diff(self):
        ok, message = receipt.verdict(
            "Changelog: not user-visible — a lint and its fixtures", [SHELL_FILE]
        )
        self.assertTrue(ok, message)

    def test_the_exemption_is_by_prefix_not_by_substring(self):
        # `sdata/` and `docs/` are not the shell, and a path merely CONTAINING
        # "dots/" is not under it.
        ok, _ = receipt.verdict("", ["sdata/uv/requirements.in"])
        self.assertTrue(ok)
        ok, _ = receipt.verdict("", ["docs/dots/notes.md"])
        self.assertTrue(ok)
        ok, _ = receipt.verdict("", ["dots/.config/hypr/hyprland.conf"])
        self.assertFalse(ok)


if __name__ == "__main__":
    unittest.main()
