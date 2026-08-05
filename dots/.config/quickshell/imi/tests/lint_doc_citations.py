#!/usr/bin/env python3
"""Every commit citation in AGENT.md / CONTRIBUTING.md must resolve to a commit.

Points added to those files must cite the commit that motivated them, kernel
`Fixes:` style: `156b4703b ("fix(install): repair the RUNPATH via a rename, not
in place")`. A point with no commit behind it is unverifiable folklore - the
citation is what lets the next agent judge whether the reasoning still applies.

A citation resolves if EITHER
  - the SHA names a commit in this repository, OR
  - some commit's exact subject line matches the quoted subject.
The fallback is not a courtesy: this repo merges with "Rebase and merge", which
rewrites SHAs, so a doc entry landing in the same PR as the commit it cites will
have that SHA dangle after merge. The subject is the half a rebase preserves.

Sits in the shell's test suite rather than a repo-root harness because this is
the only test runner the repo has; the files it reads live at the repo root.
"""
import re
import subprocess
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
# Repo root = first ancestor holding AGENT.md (tests/ sits five levels deep
# under it; walking beats hardcoding the depth).
REPO = next(p for p in HERE.parents if (p / "AGENT.md").exists())
DOCS = [REPO / "AGENT.md", REPO / "CONTRIBUTING.md", REPO / "CLAUDE.md"]

# `abc1234def ("subject line")` - hex run + quoted subject. The adjacency makes
# accidental matches (hashes in URLs, hex constants) effectively impossible.
CITATION = re.compile(r'\b([0-9a-f]{7,40})\s+\("([^"\n]+)"\)')


def git(*args):
    return subprocess.run(["git", "-C", str(REPO), *args],
                          capture_output=True, text=True)


def repo_subjects():
    out = git("log", "--all", "--format=%s")
    return set(out.stdout.splitlines()) if out.returncode == 0 else set()


def sha_resolves(sha):
    return git("cat-file", "-e", f"{sha}^{{commit}}").returncode == 0


def find_citations(text):
    return CITATION.findall(text)


class DocCitationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if git("rev-parse", "--git-dir").returncode != 0:
            raise unittest.SkipTest("not a git checkout (release tarball?)")
        cls.subjects = repo_subjects()

    def test_every_citation_resolves(self):
        unresolved = []
        for doc in DOCS:
            if not doc.exists():
                continue
            for sha, subject in find_citations(doc.read_text()):
                if not sha_resolves(sha) and subject not in self.subjects:
                    unresolved.append(f"{doc.name}: {sha} (\"{subject}\")")
        self.assertEqual(unresolved, [],
                         "citations that resolve to no commit, by SHA or subject:\n  "
                         + "\n  ".join(unresolved))

    def test_the_docs_actually_carry_citations(self):
        # Guards the mechanism itself: if a rewrite strips every citation, the
        # test above passes vacuously and the rule dies silently.
        for doc in (REPO / "AGENT.md", REPO / "CONTRIBUTING.md"):
            self.assertTrue(find_citations(doc.read_text()),
                            f"{doc.name} has no commit citations at all")

    def test_the_lint_can_fail(self):
        # CONTRIBUTING.md: "Prove a new static check can fail." Permanently,
        # not just at authoring time: a fabricated citation must NOT resolve.
        sha, subject = "deadbeef123", "no commit has ever had this subject xyzzy"
        self.assertFalse(sha_resolves(sha) or subject in self.subjects,
                         "the resolver accepted a fabricated citation")

    def test_the_pattern_matches_the_documented_format(self):
        found = find_citations('as 156b4703b ("fix(install): repair the RUNPATH '
                               'via a rename, not in place") shipped')
        self.assertEqual(found, [("156b4703b", "fix(install): repair the RUNPATH "
                                  "via a rename, not in place")])


if __name__ == "__main__":
    unittest.main()
