#!/usr/bin/env python3
"""`deploy-shell` refuses to deploy over an open PR's unmerged work.

~/.config/quickshell/imi is a copy, not a checkout, and the deploy that fills it
is `rsync --delete`. Run from a branch cut off main while other PRs are open, it
takes every unmerged fix off the maintainer's running shell - and the live log
stays clean while it does, because main is clean.

The guard's whole value is in which branches it names, so that is what this
drives, over a throwaway repository with a stub `gh` on PATH:

  - a branch whose commit touches the deployed subtree BLOCKS;
  - a branch whose commits are all outside it does NOT (a docs-only proposal
    cannot change the running shell, and a guard that cries about one teaches
    you to pass --anyway by reflex, which is the same as no guard);
  - a branch whose work is already in HEAD by cherry-pick does NOT, even though
    the SHAs differ - the first draft used a plain ancestor test and called
    cherry-picked work missing.

Both exemptions are regressions this file exists to hold: the first version of
the script got each of them wrong against the real tree.
"""
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = next(p for p in HERE.parents if (p / "AGENT.md").exists())
SCRIPT = REPO / "deploy-shell"
SUBTREE = "dots/.config/quickshell/imi"


def git(cwd, *args, check=True):
    return subprocess.run(["git", "-C", str(cwd), *args],
                          capture_output=True, text=True, check=check)


class DeployGuardTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="deploy-guard-"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)

        self.repo = self.tmp / "repo"
        (self.repo / SUBTREE).mkdir(parents=True)
        self.target = self.tmp / "live"
        shutil.copy2(SCRIPT, self.repo / "deploy-shell")

        git(self.repo, "init", "-q", "-b", "main")
        git(self.repo, "config", "user.email", "test@example.invalid")
        git(self.repo, "config", "user.name", "test")
        self.write(f"{SUBTREE}/shell.qml", "// base\n")
        self.commit("base")

        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.stub_gh([])

    def write(self, relpath, text):
        path = self.repo / relpath
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)

    def commit(self, subject):
        git(self.repo, "add", "-A")
        git(self.repo, "commit", "-q", "-m", subject)
        return git(self.repo, "rev-parse", "HEAD").stdout.strip()

    def branch(self, name, relpath, text, subject):
        """A branch off main holding one commit that writes `relpath`."""
        git(self.repo, "checkout", "-q", "-b", name)
        self.write(relpath, text)
        sha = self.commit(subject)
        git(self.repo, "checkout", "-q", "main")
        return sha

    def stub_gh(self, branches):
        """A `gh` that answers `pr list` with exactly these branch names."""
        stub = self.bin / "gh"
        listing = "\n".join(branches)
        stub.write_text(f'#!/usr/bin/env bash\ncat <<"EOF"\n{listing}\nEOF\n')
        stub.chmod(0o755)

    def deploy(self, *args):
        env = dict(os.environ)
        env["PATH"] = f"{self.bin}{os.pathsep}{env['PATH']}"
        env["IMI_DEPLOY_TARGET"] = str(self.target)
        return subprocess.run([str(self.repo / "deploy-shell"), *args],
                              capture_output=True, text=True, env=env)

    def test_branch_touching_the_deployed_subtree_blocks(self):
        self.branch("feat/live", f"{SUBTREE}/Widget.qml", "// new\n", "feat: widget")
        self.stub_gh(["feat/live"])

        run = self.deploy()

        self.assertEqual(run.returncode, 1, run.stdout + run.stderr)
        self.assertIn("feat/live", run.stdout)
        self.assertFalse(self.target.exists(),
                         "a refused deploy must not have written anything")

    def test_branch_outside_the_deployed_subtree_does_not_block(self):
        self.branch("proposal/docs", "docs/idea.md", "# idea\n", "docs: an idea")
        self.stub_gh(["proposal/docs"])

        run = self.deploy()

        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertNotIn("proposal/docs", run.stdout)

    def test_cherry_picked_work_counts_as_present(self):
        sha = self.branch("fix/elsewhere", f"{SUBTREE}/Fix.qml", "// fix\n", "fix: a fix")
        git(self.repo, "cherry-pick", sha)
        self.stub_gh(["fix/elsewhere"])

        run = self.deploy()

        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertNotIn("fix/elsewhere", run.stdout)

    def test_anyway_deploys_past_the_refusal(self):
        self.branch("feat/live", f"{SUBTREE}/Widget.qml", "// new\n", "feat: widget")
        self.stub_gh(["feat/live"])

        run = self.deploy("--anyway")

        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
        self.assertIn("feat/live", run.stdout)
        self.assertTrue((self.target / "shell.qml").exists())

    def test_it_records_what_it_deployed(self):
        run = self.deploy()
        self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

        head = git(self.repo, "rev-parse", "HEAD").stdout.strip()
        recorded = (self.target / ".deployed-from").read_text()
        self.assertIn(f"sha: {head}", recorded)
        self.assertIn("ref: main", recorded)

    def test_a_deploy_deletes_what_the_source_does_not_have(self):
        """Why the guard has to exist at all, rather than being advisory."""
        self.deploy()
        stray = self.target / "FromAnotherBranch.qml"
        stray.write_text("// an unmerged fix, live\n")

        self.deploy()

        self.assertFalse(stray.exists())


if __name__ == "__main__":
    unittest.main()
