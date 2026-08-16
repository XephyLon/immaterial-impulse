#!/usr/bin/env python3
"""get.sh must land on $REF without destroying work that exists nowhere else.

The updater's checkout (`~/.local/share/immaterial-impulse/src` by default) is
a normal git repository the user can work in - and hacking on your own shell is
exactly what someone with that checkout does. `git checkout -f` plus
`git reset --hard FETCH_HEAD` used to run over all of it: commits made there,
uncommitted edits, and untracked files the incoming tree overwrites.

Every test drives a throwaway origin repo and a throwaway DEST in a tempdir.
Nothing here may look at the machine's real checkout: the fixtures set IMI_REPO,
IMI_REF and IMI_DEST, plus HOME and GIT_CONFIG_*, so a run cannot reach the
user's data or their git config. The absent git identity is deliberate - a
machine being set up for the first time has none, and the stash the rescue
writes needs one.

What is pinned:
  - a local commit survives, on a named branch, and the update still lands;
  - uncommitted changes survive in a stash and pop back cleanly;
  - an untracked file the incoming tree would overwrite is preserved, while an
    untracked file it does not touch is left alone in the working tree;
  - a clean, up-to-date-ish checkout updates in silence - no rescue branch, no
    stash, no note file (the fix must not tax the normal user);
  - the rescue works with no git identity configured anywhere.
"""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve()
while not (ROOT / "get.sh").exists():
    ROOT = ROOT.parent
GET_SH = ROOT / "get.sh"

SETUP_STUB = """#!/usr/bin/env bash
echo "SETUP RAN $*"
"""

# Identity for the fixtures' own commits only. get.sh runs without one.
IDENT = ["-c", "user.name=Fixture", "-c", "user.email=fixture@example.com"]


def git(cwd, *args, check=True):
    return subprocess.run(
        ["git", "-C", str(cwd), *args],
        capture_output=True, text=True, check=check,
        env={**os.environ, "GIT_CONFIG_GLOBAL": "/dev/null",
             "GIT_CONFIG_SYSTEM": "/dev/null"})


def git_out(cwd, *args):
    return git(cwd, *args).stdout.strip()


class GetShLocalWorkTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="imi-get-sh-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        self.home = self.tmp / "home"
        self.home.mkdir()
        self.origin = self.tmp / "origin"
        self.dest = self.tmp / "dest" / "src"

        self.origin.mkdir()
        git(self.origin, "init", "-q", "-b", "main")
        (self.origin / "setup").write_text(SETUP_STUB, encoding="utf-8")
        (self.origin / "setup").chmod(0o755)
        (self.origin / "README.md").write_text("upstream v1\n", encoding="utf-8")
        self.commit(self.origin, "first commit")

    # ------------------------------------------------------------- fixtures
    def commit(self, repo, message):
        git(repo, "add", "-A")
        git(repo, *IDENT, "commit", "-q", "-m", message)
        return git_out(repo, "rev-parse", "HEAD")

    def advance_origin(self, filename="README.md", content="upstream v2\n"):
        (self.origin / filename).write_text(content, encoding="utf-8")
        return self.commit(self.origin, f"upstream change to {filename}")

    def run_get_sh(self, expect_success=True):
        """Run get.sh against the throwaway origin/DEST, with no git identity."""
        env = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.home),
            "IMI_REPO": f"file://{self.origin}",
            "IMI_REF": "main",
            "IMI_DEST": str(self.dest),
            # No global/system git config, and none of the identity env vars:
            # this is what a freshly installed machine looks like.
            "GIT_CONFIG_GLOBAL": "/dev/null",
            "GIT_CONFIG_SYSTEM": "/dev/null",
            "GIT_TERMINAL_PROMPT": "0",
        }
        proc = subprocess.run(["bash", str(GET_SH)], capture_output=True,
                              text=True, env=env, stdin=subprocess.DEVNULL)
        if expect_success:
            self.assertEqual(proc.returncode, 0,
                             f"get.sh failed:\n{proc.stdout}\n{proc.stderr}")
            self.assertIn("SETUP RAN", proc.stdout,
                          "get.sh never reached the installer")
        return proc

    def rescue_branches(self):
        out = git_out(self.dest, "for-each-ref", "--format=%(refname:short)",
                      "refs/heads/imi-rescue/")
        return [line for line in out.splitlines() if line]

    def stash_entries(self):
        out = git_out(self.dest, "stash", "list")
        return [line for line in out.splitlines() if line]

    # ---------------------------------------------------------------- tests
    def test_a_local_commit_survives_the_update(self):
        self.run_get_sh()
        (self.dest / "README.md").write_text("my own work\n", encoding="utf-8")
        local = self.commit(self.dest, "my local commit")
        target = self.advance_origin()

        self.run_get_sh()

        self.assertEqual(git_out(self.dest, "rev-parse", "HEAD"), target,
                         "the update did not land on $REF")
        branches = self.rescue_branches()
        self.assertEqual(len(branches), 1,
                         f"expected one rescue branch, got {branches}")
        self.assertEqual(git_out(self.dest, "rev-parse", branches[0]), local,
                         "the rescue branch does not point at the local commit")
        self.assertEqual(
            git_out(self.dest, "show", f"{branches[0]}:README.md"),
            "my own work",
            "the rescued commit does not carry the local content")

    def test_the_user_is_told_where_the_rescued_work_went(self):
        self.run_get_sh()
        (self.dest / "README.md").write_text("my own work\n", encoding="utf-8")
        self.commit(self.dest, "my local commit")
        (self.dest / "README.md").write_text("and an edit on top\n",
                                             encoding="utf-8")
        self.advance_origin()

        proc = self.run_get_sh()

        branch = self.rescue_branches()[0]
        self.assertIn(branch, proc.stdout,
                      "the rescue branch is never named on screen")
        self.assertIn("stash pop", proc.stdout,
                      "the way back to the stashed work is never spelled out")
        # whiptail replaces the terminal seconds later, so the trail on disk is
        # the half that survives.
        note = self.dest.parent / "rescued-local-work.log"
        self.assertTrue(note.exists(), "no rescue note was written")
        note_text = note.read_text(encoding="utf-8")
        self.assertIn(branch, note_text)
        self.assertIn(str(self.dest), note_text)

    def test_uncommitted_changes_survive_and_pop_back(self):
        self.run_get_sh()
        # The one test that runs with an identity available, so the branch that
        # does NOT borrow one is exercised too.
        git(self.dest, "config", "user.name", "Local User")
        git(self.dest, "config", "user.email", "local@example.com")
        (self.dest / "README.md").write_text("edited, never committed\n",
                                             encoding="utf-8")
        # Upstream moves a different file, so the pop is a clean one. (An
        # upstream change to the same file conflicts on pop - that is git
        # working, and the next test pins that the content is still there.)
        target = self.advance_origin(filename="CHANGELOG.md",
                                     content="upstream changelog\n")

        self.run_get_sh()

        self.assertEqual(git_out(self.dest, "rev-parse", "HEAD"), target)
        self.assertEqual((self.dest / "README.md").read_text(encoding="utf-8"),
                         "upstream v1\n", "the update did not land on $REF")
        self.assertEqual(len(self.stash_entries()), 1,
                         "the uncommitted edit was not stashed")
        git(self.dest, *IDENT, "stash", "pop")
        self.assertEqual((self.dest / "README.md").read_text(encoding="utf-8"),
                         "edited, never committed\n",
                         "the stash did not carry the user's edit back")

    def test_an_edit_to_a_file_upstream_also_changed_is_still_in_the_stash(self):
        self.run_get_sh()
        (self.dest / "README.md").write_text("edited, never committed\n",
                                             encoding="utf-8")
        target = self.advance_origin()

        self.run_get_sh()

        self.assertEqual(git_out(self.dest, "rev-parse", "HEAD"), target)
        self.assertEqual((self.dest / "README.md").read_text(encoding="utf-8"),
                         "upstream v2\n", "the update did not land on $REF")
        self.assertEqual(
            git_out(self.dest, "show", "refs/stash:README.md"),
            "edited, never committed",
            "the edit is not recoverable from the stash")

    def test_the_stash_is_written_without_a_configured_git_identity(self):
        self.run_get_sh()
        (self.dest / "README.md").write_text("edited\n", encoding="utf-8")
        self.advance_origin()

        self.run_get_sh()

        self.assertEqual(len(self.stash_entries()), 1)
        self.assertEqual(git_out(self.dest, "log", "-1", "--format=%ae",
                                 "refs/stash"), "imi@localhost",
                         "the fallback identity is not what wrote the stash")

    def test_a_colliding_untracked_file_is_kept_and_an_innocent_one_is_left(self):
        self.run_get_sh()
        (self.dest / "NEW.md").write_text("mine\n", encoding="utf-8")
        (self.dest / "scratch.txt").write_text("my notes\n", encoding="utf-8")
        self.advance_origin(filename="NEW.md", content="upstream's NEW\n")

        self.run_get_sh()

        self.assertEqual((self.dest / "NEW.md").read_text(encoding="utf-8"),
                         "upstream's NEW\n", "the update did not land on $REF")
        self.assertEqual(len(self.stash_entries()), 1)
        # A stash's untracked files live on its third parent, and popping one
        # over a file that now exists is refused - which is why the recovery
        # the message points at is `git show`/`git checkout` from the stash,
        # not only a pop.
        self.assertEqual(git_out(self.dest, "show", "refs/stash^3:NEW.md"),
                         "mine", "the overwritten untracked file was lost")
        # Nothing threatened this one, so nothing should have moved it.
        self.assertTrue((self.dest / "scratch.txt").exists(),
                        "an untracked file the update never touched was stashed")
        self.assertEqual((self.dest / "scratch.txt").read_text(encoding="utf-8"),
                         "my notes\n")

    def test_updating_again_from_the_rescue_branch_still_works(self):
        """Recovering means checking the rescue branch out. Then updating again.

        `git branch -f` refuses to move a branch that is checked out, so a
        rescue that re-creates its own branch unconditionally kills the update
        of the user who has just recovered - the one person guaranteed to be
        standing on it.
        """
        self.run_get_sh()
        (self.dest / "README.md").write_text("my own work\n", encoding="utf-8")
        local = self.commit(self.dest, "my local commit")
        self.advance_origin()
        self.run_get_sh()
        branch = self.rescue_branches()[0]

        git(self.dest, "checkout", "-q", branch)
        target = self.advance_origin(content="upstream v3\n")

        self.run_get_sh()

        self.assertEqual(git_out(self.dest, "rev-parse", "HEAD"), target)
        self.assertEqual(git_out(self.dest, "rev-parse", branch), local,
                         "the recovered branch was moved or lost")

    def test_a_clean_checkout_updates_in_silence(self):
        self.run_get_sh()
        target = self.advance_origin()

        proc = self.run_get_sh()

        self.assertEqual(git_out(self.dest, "rev-parse", "HEAD"), target)
        self.assertEqual(self.rescue_branches(), [],
                         "a clean checkout was given a rescue branch")
        self.assertEqual(self.stash_entries(), [],
                         "a clean checkout was stashed")
        self.assertNotIn("set aside", proc.stdout)
        self.assertFalse((self.dest.parent / "rescued-local-work.log").exists(),
                         "a clean update wrote a rescue note")

    def test_a_checkout_from_before_the_marker_is_rescued_conservatively(self):
        """A --depth 1 checkout cannot prove its HEAD came from the remote.

        Without the marker ref (checkouts made by an older get.sh) both sides
        are grafted, so `merge-base --is-ancestor` cannot answer and the script
        saves the old HEAD rather than guessing. It costs one ref, once - the
        marker is written on the way out, so the next update is silent.
        """
        self.run_get_sh()
        before = git_out(self.dest, "rev-parse", "HEAD")
        git(self.dest, "update-ref", "-d", "refs/imi/installed")
        self.assertTrue(
            (self.dest / ".git" / "shallow").exists(),
            "fixture is not a shallow checkout - the marker case is untested")
        target = self.advance_origin()

        self.run_get_sh()

        self.assertEqual(git_out(self.dest, "rev-parse", "HEAD"), target)
        branches = self.rescue_branches()
        self.assertEqual(len(branches), 1, "the old HEAD was not saved")
        self.assertEqual(git_out(self.dest, "rev-parse", branches[0]), before)

        # ... and the next update, with the marker back in place, is silent.
        second = self.advance_origin(content="upstream v3\n")
        self.run_get_sh()
        self.assertEqual(git_out(self.dest, "rev-parse", "HEAD"), second)
        self.assertEqual(len(self.rescue_branches()), 1,
                         "the marker did not quiet the next update")


if __name__ == "__main__":
    unittest.main()
