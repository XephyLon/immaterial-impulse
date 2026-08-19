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

import re
import unittest
from pathlib import Path

import changelog_receipt as receipt

HERE = Path(__file__).resolve().parent
REPO = next(p for p in HERE.parents if (p / "AGENT.md").exists())
WORKFLOW = REPO / ".github" / "workflows" / "changelog-receipt.yml"
CONTRIBUTING = REPO / "CONTRIBUTING.md"

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


class OneImplementation(unittest.TestCase):
    """The workflow delegates to the module; it does not re-spell the rule.

    Two copies of one decision is what this repo keeps paying for -
    `PluginValidator.js`'s whitelist against `PluginNode.qml`'s renderer switch,
    `registry_validate.py`'s vocabulary against `PluginManager`'s, the two bars'
    two answers to one widget url. The usual repair is a source contract pinning
    the two spellings to each other (`test_phone_connect_contract.py`); the
    cheaper one, available here because the CI half can check the repo out, is
    to have one spelling. These checks are what keeps it that way: a `grep -E`
    inlined back into the workflow reddens the suite instead of quietly becoming
    a second answer that agrees today.
    """

    def test_the_workflow_runs_the_module(self):
        text = WORKFLOW.read_text()
        self.assertIn("changelog_receipt.py", text)
        self.assertIn("--body-file", text)
        self.assertIn("--changed-files-file", text)

    def test_the_workflow_carries_no_pattern_of_its_own(self):
        text = WORKFLOW.read_text()
        for spelling in ("Changelog: (", "not user-visible", "^Changelog:"):
            self.assertNotIn(
                spelling,
                text,
                f"{WORKFLOW.name} spells the receipt itself ({spelling!r}); the "
                "pattern lives in changelog_receipt.py and nowhere else",
            )

    def test_the_workflow_asks_github_for_the_changed_files(self):
        # The `dots/` exemption and the `updated` verification are both
        # functions of the diff. A workflow that never fetched the file list
        # would pass every PR and look exactly like this one.
        text = WORKFLOW.read_text()
        self.assertIn("/files", text)
        self.assertIn("pull-requests: read", text)

    def test_the_module_is_reachable_from_the_repository_root(self):
        # The workflow runs it by repo-relative path from the checkout, which a
        # move under tests/ would break with nothing else noticing.
        invoked = REPO / "dots/.config/quickshell/imi/tests/changelog_receipt.py"
        self.assertTrue(invoked.exists())
        self.assertIn(str(invoked.relative_to(REPO)), WORKFLOW.read_text())


class ContributingExamples(unittest.TestCase):
    """Every receipt CONTRIBUTING.md offers must be one the module accepts.

    The workflow delegating to the module removes one second spelling; the doc
    is the other, and it cannot delegate - an author copies the form out of
    CONTRIBUTING.md and CI answers with the module. So the doc's own examples
    are extracted and run through the matcher, which is the same pin
    `test_bar_widget_parity.py` puts on the two bars: not "both exist" but
    "both say the same thing".
    """

    def _examples(self):
        found = re.findall(r"`(Changelog: [^`]+)`", CONTRIBUTING.read_text())
        self.assertTrue(found, "CONTRIBUTING.md documents no Changelog receipt")
        return found

    def test_every_documented_form_is_accepted(self):
        for example in self._examples():
            with self.subTest(example=example):
                self.assertIsNotNone(
                    receipt.receipt_line(example),
                    f"CONTRIBUTING.md offers {example!r}, which the matcher rejects",
                )

    def test_both_forms_are_documented(self):
        # A doc that lost the `not user-visible` half would push every
        # refactor toward a `updated` claim it cannot back, or toward silence.
        examples = self._examples()
        self.assertTrue(any(receipt.claims_updated(e) for e in examples))
        self.assertTrue(any(not receipt.claims_updated(e) for e in examples))

    def test_the_rule_names_its_own_workflow_and_module(self):
        text = CONTRIBUTING.read_text()
        self.assertIn(WORKFLOW.name, text)
        self.assertIn("changelog_receipt.py", text)


if __name__ == "__main__":
    unittest.main()
