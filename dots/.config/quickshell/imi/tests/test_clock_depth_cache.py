#!/usr/bin/env python3
"""Behavioural pins for scripts/background/subject_mask.py's cache.

This is the piece the shell trusts blindly. It never computes a cache key of its
own - it asks this script and draws whatever mask comes back - so a key that
drifts, a stale hit, or a sweep that separates a key's files from each other are
all silent on screen: the wrong subject over the clock, or a declined mask
quietly re-enabled.

Nothing here loads a model. The one thing that would be catastrophic on the
shell's startup path is a status query that constructs an ONNX session, so that
is pinned by running the query with an `onnxruntime` on the path that raises the
moment it is imported.
"""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts/background/subject_mask.py"
VENV_WRAPPER = ROOT / "scripts/background/subject-mask-venv.sh"

sys.path.insert(0, str(SCRIPT.parent))
import subject_mask  # noqa: E402


def run_cli(*args, env=None):
    proc = subprocess.run([sys.executable, str(SCRIPT), *args],
                          capture_output=True, text=True, env=env)
    return proc


class CacheKeyTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.wallpaper = self.dir / "wall.png"
        self.wallpaper.write_bytes(b"pretend this is a wallpaper")
        self.addCleanup(self.tmp.cleanup)

    def test_the_key_is_stable_for_an_unchanged_file(self):
        first = subject_mask.cache_key(self.wallpaper)
        second = subject_mask.cache_key(self.wallpaper)
        self.assertEqual(first, second)
        self.assertRegex(first, r"^[0-9a-f]{32}$")

    def test_touching_the_file_changes_the_key(self):
        before = subject_mask.cache_key(self.wallpaper)
        later = time.time() + 120
        os.utime(self.wallpaper, (later, later))
        self.assertNotEqual(before, subject_mask.cache_key(self.wallpaper),
                            "an mtime change must produce a new key - this is what "
                            "keeps a mask off an image that was edited in place")

    def test_rewriting_the_file_at_a_new_size_changes_the_key(self):
        before = subject_mask.cache_key(self.wallpaper)
        stat = self.wallpaper.stat()
        self.wallpaper.write_bytes(b"a different wallpaper entirely, and longer")
        # Pin the mtime back so only the size can be doing the work here.
        os.utime(self.wallpaper, ns=(stat.st_atime_ns, stat.st_mtime_ns))
        self.assertNotEqual(before, subject_mask.cache_key(self.wallpaper))

    def test_two_paths_with_identical_contents_have_different_keys(self):
        twin = self.dir / "twin.png"
        twin.write_bytes(self.wallpaper.read_bytes())
        os.utime(twin, ns=(self.wallpaper.stat().st_atime_ns,
                           self.wallpaper.stat().st_mtime_ns))
        self.assertNotEqual(subject_mask.cache_key(self.wallpaper),
                            subject_mask.cache_key(twin))

    def test_a_symlink_keys_as_its_target(self):
        link = self.dir / "link.png"
        link.symlink_to(self.wallpaper)
        self.assertEqual(subject_mask.cache_key(self.wallpaper),
                         subject_mask.cache_key(link))


class StatusTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.cache = self.dir / "cache"
        self.cache.mkdir()
        self.wallpaper = self.dir / "wall.png"
        self.wallpaper.write_bytes(b"wallpaper")
        self.key = subject_mask.cache_key(self.wallpaper)
        self.addCleanup(self.tmp.cleanup)

    def status(self):
        return subject_mask.status(self.cache, self.wallpaper)

    def test_a_wallpaper_with_nothing_cached_is_absent(self):
        result = self.status()
        self.assertEqual(result["state"], "absent")
        self.assertNotIn("mask", result)

    def test_an_accepted_mask_is_reported_with_its_path(self):
        accepted = self.cache / f"{self.key}.png"
        accepted.write_bytes(b"mask")
        result = self.status()
        self.assertEqual(result["state"], "accepted")
        self.assertEqual(result["mask"], str(accepted))

    def test_a_declined_wallpaper_beats_an_accepted_mask(self):
        (self.cache / f"{self.key}.png").write_bytes(b"mask")
        (self.cache / f"{self.key}.off").write_text("")
        self.assertEqual(self.status()["state"], "declined",
                         "the opt-out is the user's last word; a mask left beside "
                         "it must not come back")

    def test_every_model_refusing_reads_as_none_not_as_absent(self):
        for model in subject_mask.MODELS:
            (self.cache / f"{self.key}.{model}.none").write_text("")
        result = self.status()
        self.assertEqual(result["state"], "none")
        self.assertEqual(set(result["candidates"]), set(subject_mask.MODELS))

    def test_one_model_refusing_still_leaves_the_other_a_candidate(self):
        models = sorted(subject_mask.MODELS)
        (self.cache / f"{self.key}.{models[0]}.none").write_text("")
        (self.cache / f"{self.key}.{models[1]}.png").write_bytes(b"mask")
        result = self.status()
        self.assertEqual(result["state"], "candidate")
        self.assertIsNone(result["candidates"][models[0]])
        self.assertIsNotNone(result["candidates"][models[1]])

    def test_an_unreadable_wallpaper_answers_rather_than_crashing(self):
        result = subject_mask.status(self.cache, self.dir / "not-here.png")
        self.assertEqual(result["state"], "unreadable")

    def test_status_never_constructs_a_session(self):
        """The shell's read path must not load onnxruntime.

        Proved by putting an `onnxruntime` on the path that raises on import: if
        anything on the status path touches it, this exits nonzero.
        """
        poison = self.dir / "poison"
        poison.mkdir()
        (poison / "onnxruntime.py").write_text(
            "raise AssertionError('status constructed an ONNX session')\n")
        (self.cache / f"{self.key}.png").write_bytes(b"mask")
        env = dict(os.environ, PYTHONPATH=str(poison))
        proc = run_cli("--cache-dir", str(self.cache), "status",
                       str(self.wallpaper), env=env)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout)["state"], "accepted")

    def test_a_cached_refusal_returns_without_a_session(self):
        poison = self.dir / "poison"
        poison.mkdir()
        (poison / "onnxruntime.py").write_text(
            "raise AssertionError('a cached refusal constructed an ONNX session')\n")
        (self.cache / f"{self.key}.isnet-anime.none").write_text("")
        env = dict(os.environ, PYTHONPATH=str(poison))
        proc = run_cli("--cache-dir", str(self.cache), "run", str(self.wallpaper),
                       "--model", "isnet-anime", env=env)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["state"], "none")
        self.assertTrue(payload["cached"])

    def test_a_cached_candidate_returns_without_a_session(self):
        poison = self.dir / "poison"
        poison.mkdir()
        (poison / "onnxruntime.py").write_text(
            "raise AssertionError('a cache hit constructed an ONNX session')\n")
        candidate = self.cache / f"{self.key}.isnet-anime.png"
        candidate.write_bytes(b"mask")
        env = dict(os.environ, PYTHONPATH=str(poison))
        proc = run_cli("--cache-dir", str(self.cache), "run", str(self.wallpaper),
                       "--model", "isnet-anime", env=env)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        payload = json.loads(proc.stdout)
        self.assertEqual(payload["state"], "hit")
        self.assertEqual(payload["mask"], str(candidate))


class SweepTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.cache = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def seed(self, key, mtime, suffixes=(".png",)):
        for suffix in suffixes:
            entry = self.cache / f"{key}{suffix}"
            entry.write_bytes(b"x")
            os.utime(entry, (mtime, mtime))

    def test_the_sweep_keeps_the_newest_keys(self):
        base = time.time()
        for i in range(10):
            self.seed(f"{i:032x}", base + i)
        result = subject_mask.sweep(self.cache, keep=4)
        self.assertEqual(result["kept"], 4)
        survivors = sorted(p.name for p in self.cache.iterdir())
        self.assertEqual(survivors, [f"{i:032x}.png" for i in range(6, 10)])

    def test_a_key_is_swept_whole(self):
        base = time.time()
        self.seed("a" * 32, base, (".png", ".off", ".isnet-anime.png"))
        self.seed("b" * 32, base + 100, (".png",))
        subject_mask.sweep(self.cache, keep=1)
        self.assertEqual([p.name for p in self.cache.iterdir()], ["b" * 32 + ".png"],
                         "a key's files are one decision - an .off outliving its "
                         ".png would re-enable a mask the user declined")

    def test_a_keys_age_is_its_newest_file(self):
        base = time.time()
        self.seed("a" * 32, base, (".png",))
        # The same key touched again later by an accept must not be swept as old.
        self.seed("a" * 32, base + 500, (".off",))
        self.seed("b" * 32, base + 100, (".png",))
        subject_mask.sweep(self.cache, keep=1)
        self.assertEqual(sorted(p.name for p in self.cache.iterdir()),
                         ["a" * 32 + ".off", "a" * 32 + ".png"])

    def test_the_sweep_leaves_the_models_alone(self):
        models = self.cache / "models"
        models.mkdir()
        (models / "isnet-anime.onnx").write_bytes(b"model")
        self.seed("a" * 32, time.time())
        subject_mask.sweep(self.cache, keep=0)
        self.assertTrue((models / "isnet-anime.onnx").exists(),
                        "sweeping the models would re-download 176MB on the next run")

    def test_sweeping_a_cache_that_does_not_exist_is_not_an_error(self):
        result = subject_mask.sweep(self.cache / "nope", keep=4)
        self.assertEqual(result, {"kept": 0, "removed": 0})


class ContractTest(unittest.TestCase):
    def test_every_model_declares_a_url_and_a_checksum(self):
        for model, spec in subject_mask.MODELS.items():
            self.assertTrue(spec["url"].startswith("https://"), model)
            self.assertRegex(spec["sha256"], r"^[0-9a-f]{64}$", model)
            self.assertEqual(spec["side"], 1024, model)

    def test_the_venv_wrapper_exists_and_is_executable(self):
        self.assertTrue(VENV_WRAPPER.exists())
        self.assertTrue(os.access(VENV_WRAPPER, os.X_OK))
        self.assertTrue(os.access(SCRIPT, os.X_OK))

    def test_onnxruntime_is_declared_in_the_venv_requirements(self):
        requirements = (ROOT.parents[3] / "sdata/uv/requirements.in").read_text()
        self.assertIn("onnxruntime", requirements,
                      "run needs a session; without the pin the venv has none and "
                      "the picker fails at the moment the user clicks it")

    def test_the_script_does_not_import_onnxruntime_at_module_scope(self):
        source = SCRIPT.read_text()
        head = source.split("def segment(", 1)[0]
        self.assertNotIn("import onnxruntime", head,
                         "a module-scope import makes every status query pay for "
                         "onnxruntime, which is the cost this cache exists to avoid")


if __name__ == "__main__":
    unittest.main()
