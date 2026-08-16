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


class AcceptDeclineTest(unittest.TestCase):
    """The picker's two verdicts, and the transitions between them.

    Both are files at the key rather than config entries, so they invalidate with
    the key: edit the wallpaper in place and the decision goes with the mask it
    was about. That is only true if each verdict also clears the other - which is
    where this can go silently wrong, because `status` checks the opt-out FIRST,
    so an accept that left a `.off` behind would do nothing at all.
    """
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.cache = self.dir / "cache"
        self.cache.mkdir()
        self.wallpaper = self.dir / "wall.png"
        self.wallpaper.write_bytes(b"wallpaper")
        self.key = subject_mask.cache_key(self.wallpaper)
        self.candidate = self.cache / f"{self.key}.isnet-anime.png"
        self.candidate.write_bytes(b"a candidate mask")
        self.addCleanup(self.tmp.cleanup)

    def test_accepting_makes_the_candidate_the_mask_the_shell_draws(self):
        result = subject_mask.accept(self.cache, self.wallpaper, "isnet-anime")
        self.assertEqual(result["state"], "accepted")
        accepted = self.cache / f"{self.key}.png"
        self.assertEqual(accepted.read_bytes(), self.candidate.read_bytes())
        self.assertEqual(subject_mask.status(self.cache, self.wallpaper)["mask"],
                         str(accepted))

    def test_the_candidate_survives_being_accepted(self):
        subject_mask.accept(self.cache, self.wallpaper, "isnet-anime")
        self.assertTrue(self.candidate.exists(),
                        "the picker must be able to offer it again after a decline")

    def test_accepting_clears_a_previous_decline(self):
        subject_mask.decline(self.cache, self.wallpaper)
        subject_mask.accept(self.cache, self.wallpaper, "isnet-anime")
        self.assertEqual(subject_mask.status(self.cache, self.wallpaper)["state"],
                         "accepted",
                         "an opt-out left beside a fresh accept makes the accept "
                         "a no-op, because the refusal is checked first")

    def test_declining_clears_a_previous_accept(self):
        subject_mask.accept(self.cache, self.wallpaper, "isnet-anime")
        subject_mask.decline(self.cache, self.wallpaper)
        self.assertEqual(subject_mask.status(self.cache, self.wallpaper)["state"],
                         "declined")
        self.assertFalse((self.cache / f"{self.key}.png").exists())

    def test_accepting_a_candidate_that_does_not_exist_fails_loudly(self):
        with self.assertRaises(RuntimeError):
            subject_mask.accept(self.cache, self.wallpaper, "isnet-general-use")

    def test_the_verdict_moves_with_the_wallpaper_file(self):
        subject_mask.accept(self.cache, self.wallpaper, "isnet-anime")
        later = time.time() + 120
        os.utime(self.wallpaper, (later, later))
        self.assertEqual(subject_mask.status(self.cache, self.wallpaper)["state"],
                         "absent",
                         "a wallpaper edited in place must not keep the mask that "
                         "was cut from what it used to be")

    def test_neither_verdict_leaves_a_partial_file_behind(self):
        subject_mask.accept(self.cache, self.wallpaper, "isnet-anime")
        subject_mask.decline(self.cache, self.wallpaper)
        leftovers = [p.name for p in self.cache.iterdir() if p.name.endswith(".part")]
        self.assertEqual(leftovers, [])

    def test_the_cli_exposes_both_verdicts(self):
        proc = run_cli("--cache-dir", str(self.cache), "accept", str(self.wallpaper),
                       "--model", "isnet-anime")
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout)["state"], "accepted")
        proc = run_cli("--cache-dir", str(self.cache), "decline", str(self.wallpaper))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(json.loads(proc.stdout)["state"], "declined")

    def test_a_failed_accept_still_answers_in_json(self):
        proc = run_cli("--cache-dir", str(self.cache), "accept", str(self.wallpaper),
                       "--model", "isnet-general-use")
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(json.loads(proc.stdout)["state"], "error",
                         "the picker parses stdout; a traceback on stderr is a "
                         "button that does nothing with no explanation")


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


class MaskFileTest(unittest.TestCase):
    """The mask has to mask, and only its alpha channel can do that.

    Qt's OpacityMask reads the maskSource's alpha and nothing else, so a plain
    grayscale mask - the obvious thing to write, and what a mask looks like - is
    opaque everywhere. The layer then paints the whole wallpaper flat over the
    clock: the loudest possible version of this feature's own failure, and one
    that no amount of correct geometry prevents.
    """
    def setUp(self):
        try:
            import numpy  # noqa: F401
            from PIL import Image  # noqa: F401
        except ImportError:
            self.skipTest("needs numpy and pillow (the shell's uv venv)")
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)

    def written(self):
        import numpy as np
        from PIL import Image

        mask = np.zeros((8, 8), dtype="float32")
        mask[:, 4:] = 1.0
        mask[:, 2] = 0.5
        path = Path(self.tmp.name) / "mask.png"
        subject_mask.write_mask(path, mask)
        with Image.open(path) as opened:
            return opened.copy()

    def test_the_mask_carries_an_alpha_channel(self):
        image = self.written()
        self.assertIn("A", image.getbands(),
                      "a mask with no alpha is opaque everywhere, and the depth "
                      "layer would draw the whole wallpaper over the clock")

    def test_the_alpha_is_the_mask(self):
        image = self.written()
        alpha = image.getchannel("A")
        self.assertEqual(alpha.getpixel((0, 0)), 0, "background must be transparent")
        self.assertEqual(alpha.getpixel((7, 0)), 255, "subject must be opaque")
        # Not a number: the edge is the one thing that must not be thresholded,
        # since a hard boundary against a clock is what reads as a sticker.
        self.assertTrue(0 < alpha.getpixel((2, 0)) < 255,
                        f"a soft edge must stay soft, got {alpha.getpixel((2, 0))}")

    def test_the_luminance_matches_the_alpha(self):
        image = self.written()
        luminance = image.getchannel("L")
        alpha = image.getchannel("A")
        # tobytes() rather than getdata(): Pillow is deprecating the latter,
        # and a warning printed by a green test is the noise that hides the
        # next real one.
        self.assertEqual(luminance.tobytes(), alpha.tobytes(),
                         "the file is meant to be looked at as well as masked with")

    def test_the_mask_keeps_the_models_own_resolution(self):
        self.assertEqual(self.written().size, (8, 8))


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
