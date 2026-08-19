#!/usr/bin/env python3
"""The `Changelog:` PR-body receipt: what it accepts, and when it is required.

`CHANGELOG.md`'s `[Unreleased]` section was found EMPTY at two consecutive
releases - 43d1ffd01 ("release: 0.25.0"), 61 PRs behind it, and 58bd53a30
("release: 0.26.0"), five more - so both releases reconstructed the changelog
from the git log after the fact. Writing the rule down a third time is the one
thing already known not to work; this is the failing check.

The rule, beside CONTRIBUTING.md's `Docs:` receipt and in the same shape:

- a PR that changes nothing under `dots/` carries no receipt at all. Docs-only
  and CI-only PRs are the common case, and taxing them is how a receipt becomes
  noise people paste without reading;
- otherwise the body carries one of
    Changelog: updated
    Changelog: not user-visible - <reason>
  where the separator may be a hyphen, an en dash or an em dash, spaced however
  the author likes, and the reason must carry at least one letter or digit.
  Liberal about the separator, strict about the reason: the reason is the whole
  content of the second form, and a lone dash after a dash is punctuation;
- `updated` is VERIFIED against the diff. A receipt that is satisfied by typing
  the line is not a check - it is the prose rule again, with a green tick.

This module is the ONE implementation. `.github/workflows/changelog-receipt.yml`
does not carry a second copy of the pattern in a `grep -E`; it checks the repo
out and runs `main()` here, so the CI half and the local half cannot drift into
two answers. `test_changelog_receipt.py` covers the matching over in-memory
fixtures and pins that the workflow still delegates rather than re-spelling it.
"""

from __future__ import annotations

import argparse
import re
import sys

# Anchored per line. `updated` may carry trailing detail the way `Docs: updated
# AGENT.md §<section>` does. The second form's tail is not detail, it is the
# reason, so it has to contain something a reader can read: `[0-9A-Za-z]` is
# what separates a reason from a second dash and a shrug.
RECEIPT_PATTERN = (
    r"^Changelog: (updated( .*)?|not user-visible *(-|–|—) *[^ ]*[0-9A-Za-z].*)$"
)

# What makes a PR owe a receipt. The shell, the installer data and the docs all
# live in this repo; only the first ships behaviour a user can notice.
SHELL_PREFIX = "dots/"

# The file the `updated` claim is checked against, repo-relative - the same
# spelling the diff's file list uses.
CHANGELOG_PATH = "CHANGELOG.md"

_RECEIPT_RE = re.compile(RECEIPT_PATTERN)

MISSING_MESSAGE = (
    'PR body needs a Changelog receipt line: either "Changelog: updated" (and '
    'the diff must touch CHANGELOG.md) or "Changelog: not user-visible — '
    '<reason>". See CONTRIBUTING.md → "Keep CHANGELOG.md fed".'
)

UNBACKED_MESSAGE = (
    'The Changelog receipt says "updated" but the diff does not touch '
    "CHANGELOG.md. Add the entry under [Unreleased], or say "
    '"Changelog: not user-visible — <reason>".'
)


def receipt_line(body: str) -> str | None:
    """The first accepted receipt line in a PR body, or None.

    GitHub delivers bodies with CRLF endings and authors leave trailing spaces,
    so both are normalized away before matching - a receipt defeated by an
    invisible character is a receipt that fails for the wrong reason.
    """
    for raw in (body or "").replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        line = raw.rstrip()
        if _RECEIPT_RE.match(line):
            return line
    return None


def claims_updated(line: str) -> bool:
    return line.startswith("Changelog: updated")


def touches_shell(changed_files) -> bool:
    return any(path.startswith(SHELL_PREFIX) for path in changed_files)


def verdict(body: str, changed_files) -> tuple[bool, str]:
    """(ok, message) for one PR. The message is printed either way."""
    files = [path.strip() for path in changed_files if path.strip()]

    if not touches_shell(files):
        return True, (
            f"No file under {SHELL_PREFIX} changed - no Changelog receipt required."
        )

    line = receipt_line(body)
    if line is None:
        return False, MISSING_MESSAGE

    if claims_updated(line) and CHANGELOG_PATH not in files:
        return False, UNBACKED_MESSAGE

    return True, f"Changelog receipt found: {line}"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--body-file", required=True, help="file holding the PR body")
    parser.add_argument(
        "--changed-files-file",
        required=True,
        help="file holding the PR's changed paths, one per line",
    )
    args = parser.parse_args(argv)

    with open(args.body_file, encoding="utf-8") as handle:
        body = handle.read()
    with open(args.changed_files_file, encoding="utf-8") as handle:
        changed_files = handle.read().splitlines()

    ok, message = verdict(body, changed_files)
    if ok:
        print(message)
        return 0
    # GitHub Actions renders this as an annotation on the PR rather than
    # burying it in the step log, which is what docs-receipt.yml already does.
    print(f"::error::{message}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
