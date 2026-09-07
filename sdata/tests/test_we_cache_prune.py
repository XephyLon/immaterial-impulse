#!/usr/bin/env python3
"""The Wallpaper Engine installer step must not hoard dead renderers.

Every prebuilt install extracted its ~1.4 GB tarball into a fresh
~/.cache/immaterial-impulse/prebuilt/<ref> and left every earlier <ref> on
disk, and a source-build fallback left its ~5 GB checkout behind for good.
A machine that followed the pin from v0.2.0 to v0.3.0 carried 9.6 GB of
prebuilts plus the checkout, none of it reachable from the wrapper.

These run the prune helpers for real against a scratch tree (the helpers are
sourced out of the script by name), and pin that every path that writes the
stamp also prunes.
"""
import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]          # sdata/
SCRIPT = Path(os.environ.get("WE_SCRIPT_UNDER_TEST",
                             ROOT / "subcmd-install/4.wallpaperengine.sh"))


def _function_source(name: str) -> str:
    src = SCRIPT.read_text(encoding="utf-8")
    m = re.search(rf"(?ms)^{re.escape(name)}\(\)\{{.*?^\}}", src)
    if not m:
        raise AssertionError(f"{SCRIPT.name} defines no {name}()")
    return m.group(0)


def _run(fn: str, env: dict, args=()):
    """Source one helper out of the script and call it in a bare bash."""
    script = "say(){ printf '%s\\n' \"$*\"; }\n" + _function_source(fn) + \
        "\n" + fn + " " + " ".join(f"'{a}'" for a in args) + "\n"
    return subprocess.run(["bash", "-euo", "pipefail", "-c", script],
                          env={**env, "PATH": os.environ["PATH"]},
                          capture_output=True, text=True, check=True)


class PrunePrebuilt(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "prebuilt"
        for ref in ("v0.2.0", "v0.2.6", "v0.3.0"):
            (self.root / ref / "bin").mkdir(parents=True)
            (self.root / ref / "bin" / "quickshell").write_text("x")
        (self.root / "SHA256SUMS").write_text("not a tree")

    def tearDown(self):
        self.tmp.cleanup()

    def env(self):
        return {"PREBUILT_ROOT": str(self.root)}

    def test_keeps_the_named_ref_and_removes_the_rest(self):
        out = _run("prune_prebuilt", self.env(), ["v0.3.0"]).stdout
        self.assertEqual(sorted(p.name for p in self.root.iterdir()),
                         ["SHA256SUMS", "v0.3.0"])
        self.assertTrue((self.root / "v0.3.0/bin/quickshell").exists())
        self.assertIn("v0.2.0", out)
        self.assertIn("v0.2.6", out)

    def test_plain_files_under_the_root_are_left_alone(self):
        _run("prune_prebuilt", self.env(), ["v0.3.0"])
        self.assertTrue((self.root / "SHA256SUMS").exists())

    def test_empty_ref_is_a_noop_not_a_wipe(self):
        _run("prune_prebuilt", self.env(), [""])
        self.assertEqual(len(list(self.root.iterdir())), 4)

    def test_missing_root_is_a_noop(self):
        env = {"PREBUILT_ROOT": str(Path(self.tmp.name) / "absent")}
        _run("prune_prebuilt", env, ["v0.3.0"])   # must not raise

    def test_ref_that_is_not_present_still_prunes_others(self):
        # A source-built install stamps a ref that has no prebuilt tree.
        _run("prune_prebuilt", self.env(), ["deadbeef"])
        self.assertEqual([p.name for p in self.root.iterdir()], ["SHA256SUMS"])


class PruneBuildDir(unittest.TestCase):
    def test_removes_a_checkout_and_ignores_anything_else(self):
        with tempfile.TemporaryDirectory() as tmp:
            checkout = Path(tmp) / "qs-wallpaperengine-build"
            (checkout / ".git").mkdir(parents=True)
            (checkout / "build").mkdir()
            _run("prune_build_dir", {"BUILD_DIR": str(checkout)})
            self.assertFalse(checkout.exists())

            plain = Path(tmp) / "not-a-checkout"
            plain.mkdir()
            (plain / "keep").write_text("x")
            _run("prune_build_dir", {"BUILD_DIR": str(plain)})
            self.assertTrue((plain / "keep").exists(),
                            "a directory without .git is not ours to delete")


class EveryStampWriterPrunes(unittest.TestCase):
    """Three paths write the stamp; each must prune right after."""

    def test_prune_follows_every_write_stamp_call(self):
        src = SCRIPT.read_text(encoding="utf-8")
        calls = [m.start() for m in re.finditer(r"(?m)^\s*write_stamp ", src)]
        self.assertEqual(len(calls), 3, "expected the three stamp-writing paths")
        for pos in calls:
            following = src[pos:pos + 200]
            self.assertIn("prune_prebuilt \"$WE_REF\"", following,
                          f"no prune after: {following.splitlines()[0].strip()}")

    def test_prebuilt_success_also_drops_the_source_tree(self):
        src = SCRIPT.read_text(encoding="utf-8")
        body = src[src.index("try_prebuilt(){"):src.index("source_build(){")]
        self.assertIn("prune_build_dir", body)

    def test_already_installed_prebuilt_also_drops_the_source_tree(self):
        """Every Update Dots with an unchanged pin takes this path; the first
        prune left the checkout standing there."""
        src = SCRIPT.read_text(encoding="utf-8")
        tail = src[src.index("if up_to_date; then"):]
        tail = tail[:tail.index("exit 0")]
        self.assertRegex(tail, r'case "\$_stamp_bin" in "\$PREBUILT_ROOT"/\*\) prune_build_dir',
                         "the already-installed path must drop the checkout when the live binary is a prebuilt")


if __name__ == "__main__":
    unittest.main()
