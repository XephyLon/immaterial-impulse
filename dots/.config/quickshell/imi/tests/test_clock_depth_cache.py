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

    def test_the_accepted_mask_names_the_model_it_came_from(self):
        """Which of the two models the desktop is actually drawing.

        Derived from the bytes rather than recorded, so it cannot drift from the
        file the shell draws - and the picker needs it, because two candidates
        shown side by side with no mark on either leaves "what is on my screen"
        unanswerable from the one surface built to answer it.
        """
        (self.cache / f"{self.key}.isnet-general-use.png").write_bytes(b"photographic")
        (self.cache / f"{self.key}.isnet-anime.png").write_bytes(b"illustration")
        (self.cache / f"{self.key}.png").write_bytes(b"illustration")
        self.assertEqual(self.status()["acceptedModel"], "isnet-anime")

    def test_a_mask_matching_neither_candidate_names_no_model(self):
        """Re-running a model overwrites its candidate, so this is reachable.

        None is the honest answer there: crediting whichever candidate it most
        resembles would put a check mark on a cutout the desktop is not drawing.
        """
        (self.cache / f"{self.key}.isnet-anime.png").write_bytes(b"illustration")
        (self.cache / f"{self.key}.png").write_bytes(b"something else entirely")
        self.assertIsNone(self.status()["acceptedModel"])

    def test_two_candidates_of_the_same_size_are_told_apart_by_content(self):
        """Size is a shortcut past a read, never the decision.

        Two 1024x1024 masks are routinely both about 300 KB, so deciding on the
        size alone would credit whichever model happened to be listed first.
        """
        (self.cache / f"{self.key}.isnet-anime.png").write_bytes(b"aaaaaaaa")
        (self.cache / f"{self.key}.isnet-general-use.png").write_bytes(b"bbbbbbbb")
        (self.cache / f"{self.key}.png").write_bytes(b"bbbbbbbb")
        self.assertEqual(self.status()["acceptedModel"], "isnet-general-use")

    def test_nothing_accepted_reports_no_model(self):
        (self.cache / f"{self.key}.isnet-anime.png").write_bytes(b"illustration")
        result = self.status()
        self.assertEqual(result["state"], "candidate")
        self.assertNotIn("acceptedModel", result)

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

    def test_every_mask_is_reported_with_a_revision_that_moves_with_its_bytes(self):
        """Qt caches a pixmap by URL, and both mask files are rewritten in place.

        Measured with a qml6 probe: a 32x8 PNG rewritten at 99x17 and
        re-assigned to the identical URL still reported 32x8, and clearing the
        source to "" first did not help. So without a token that changes, a
        click-refined candidate and a re-accepted mask both keep drawing
        whichever version loaded first, for the rest of the session, with
        nothing in any log. A string, because these are nanoseconds and 1.8e18
        does not survive a JSON round trip through a double.
        """
        candidate = self.cache / f"{self.key}.mobile-sam.png"
        candidate.write_bytes(b"first")
        accepted = self.cache / f"{self.key}.png"
        accepted.write_bytes(b"first")
        before = self.status()
        self.assertIsInstance(before["revisions"]["mobile-sam"], str)
        self.assertIsInstance(before["maskRevision"], str)

        later = time.time() + 120
        candidate.write_bytes(b"second")
        os.utime(candidate, (later, later))
        accepted.write_bytes(b"second")
        os.utime(accepted, (later, later))
        after = self.status()
        self.assertNotEqual(before["revisions"]["mobile-sam"],
                            after["revisions"]["mobile-sam"])
        self.assertNotEqual(before["maskRevision"], after["maskRevision"])

    def test_a_refusal_carries_no_revision_because_it_has_no_file(self):
        (self.cache / f"{self.key}.isnet-anime.none").write_text("")
        self.assertNotIn("isnet-anime", self.status()["revisions"])

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


class PromptTest(unittest.TestCase):
    """The clicks, and the two arrays the decoder takes them as.

    Every one of these fails silently rather than loudly when it is wrong: a
    mask somewhere else in the picture, or a mask of the whole frame, with
    nothing in any log and a picker that looks like it simply mis-segments.
    """
    def test_a_bare_point_is_a_point_the_subject_must_contain(self):
        self.assertEqual(subject_mask.parse_point("0.5,0.25"),
                         {"x": 0.5, "y": 0.25, "label": 1})

    def test_a_zero_label_is_a_point_the_subject_must_not_contain(self):
        self.assertEqual(subject_mask.parse_point("0.1,0.2,0")["label"], 0)

    def test_a_point_outside_the_picture_is_refused(self):
        for bad in ("1.5,0.2", "-0.1,0.2", "0.2,2", "0.2", "0.2,0.3,7", "a,b"):
            with self.assertRaises(ValueError, msg=bad):
                subject_mask.parse_point(bad)

    def test_the_longest_side_is_scaled_and_the_aspect_is_kept(self):
        """SAM resizes and pads; the isnet models squash. That is the whole
        reason a prompted mask comes out at the picture's own shape."""
        self.assertEqual(subject_mask.resize_longest_side(3840, 1594, 1024),
                         (1024, 425))
        self.assertEqual(subject_mask.resize_longest_side(1080, 1920, 1024),
                         (576, 1024))
        self.assertEqual(subject_mask.resize_longest_side(1024, 1024, 1024),
                         (1024, 1024))
        # The short side ROUNDS, it does not truncate: SAM's own
        # ResizeLongestSide is `int(x * scale + 0.5)`, and the point coordinates
        # the decoder was traced against are scaled by the rounded size divided
        # by the original. 700 * 1024 / 1000 is 716.8, so this is the one case
        # in the set that can tell the two apart - the others land on whole
        # pixels and pass either way.
        self.assertEqual(subject_mask.resize_longest_side(1000, 700, 1024),
                         (1024, 717))

    def test_a_prompted_masks_aspect_is_the_pictures_aspect(self):
        """Confirmed rather than assumed, because `coverRect` exists precisely
        because the salient models' masks are NOT the picture's aspect.

        A mask at the picture's own aspect stretched into the rectangle the
        whole picture would occupy is a uniform scale, so the registration needs
        no case for it - which is the claim this pins on the producer's side and
        `tst_clock_depth_eligibility.qml` pins on the shell's.
        """
        for width, height in ((3840, 1594), (7680, 2160), (1080, 1920), (8400, 4725)):
            mask = subject_mask.resize_longest_side(width, height, 1024)
            self.assertAlmostEqual(mask[0] / mask[1], width / height, places=2,
                                   msg=f"{width}x{height} -> {mask}")

    def test_an_image_with_no_size_is_refused_rather_than_divided_by(self):
        with self.assertRaises(ValueError):
            subject_mask.resize_longest_side(0, 100, 1024)

    def test_the_coordinates_are_in_the_resized_images_pixels(self):
        """Not the original's and not the padded square's - the space the
        encoder saw. A point in either of the other two lands somewhere else in
        the picture, and the mask that comes back is a perfectly good mask of
        the wrong thing."""
        try:
            import numpy  # noqa: F401
        except ImportError:
            self.skipTest("needs numpy (the shell's uv venv)")
        coords, labels = subject_mask.encode_prompt(
            [{"x": 0.5, "y": 0.5, "label": 1}], (1024, 425))
        self.assertAlmostEqual(float(coords[0][0][0]), 512.0)
        self.assertAlmostEqual(float(coords[0][0][1]), 212.5)

    def test_a_padding_point_is_appended_because_there_is_no_box(self):
        """The decoder's graph has a fixed slot for a box. With no box the
        (0,0)/-1 padding point is what says so; omitting it does not raise, it
        makes the decoder read the first click as a box corner."""
        try:
            import numpy  # noqa: F401
        except ImportError:
            self.skipTest("needs numpy (the shell's uv venv)")
        points = [{"x": 0.2, "y": 0.3, "label": 1}, {"x": 0.8, "y": 0.4, "label": 0}]
        coords, labels = subject_mask.encode_prompt(points, (1024, 512))
        self.assertEqual(coords.shape, (1, 3, 2))
        self.assertEqual(labels.shape, (1, 3))
        self.assertEqual([float(v) for v in labels[0]], [1.0, 0.0, -1.0])
        self.assertEqual([float(v) for v in coords[0][2]], [0.0, 0.0])

    def test_both_arrays_are_float32(self):
        try:
            import numpy as np
        except ImportError:
            self.skipTest("needs numpy (the shell's uv venv)")
        coords, labels = subject_mask.encode_prompt(
            [{"x": 0.5, "y": 0.5, "label": 1}], (1024, 425))
        self.assertEqual(coords.dtype, np.float32)
        self.assertEqual(labels.dtype, np.float32)


class PromptInTheMaskTest(unittest.TestCase):
    """A prompted mask carries its own clicks, inside the PNG.

    The alternatives are all pairs that have to agree - a key per click needing
    a sixth file to say which was accepted, a sidecar a byte-for-byte `accept`
    would have to copy by hand, a config map the JsonAdapter cannot hold. In the
    file, the prompt cannot arrive without its mask or outlive it.
    """
    def setUp(self):
        try:
            import numpy  # noqa: F401
            from PIL import Image  # noqa: F401
        except ImportError:
            self.skipTest("needs numpy and pillow (the shell's uv venv)")
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)

    def mask_array(self):
        import numpy as np
        mask = np.zeros((8, 8), dtype="float32")
        mask[:, 4:] = 1.0
        return mask

    def test_the_clicks_survive_a_round_trip_through_the_file(self):
        prompt = [{"x": 0.5, "y": 0.25, "label": 1}, {"x": 0.9, "y": 0.8, "label": 0}]
        path = self.dir / "mask.png"
        subject_mask.write_mask(path, self.mask_array(), prompt=prompt)
        self.assertEqual(subject_mask.read_prompt(path), prompt)

    def test_reading_the_prompt_back_needs_no_pillow(self):
        """`status` is the shell's read path and may import nothing outside the
        standard library - which is the reason the chunk is read by hand rather
        than by opening the image."""
        path = self.dir / "mask.png"
        subject_mask.write_mask(path, self.mask_array(),
                                prompt=[{"x": 0.5, "y": 0.5, "label": 1}])
        poison = self.dir / "poison"
        poison.mkdir()
        for module in ("PIL", "numpy", "onnxruntime"):
            (poison / f"{module}.py").write_text(
                f"raise AssertionError('reading a prompt imported {module}')\n")
        proc = subprocess.run(
            [sys.executable, "-c",
             f"import sys; sys.path.insert(0, {str(SCRIPT.parent)!r}); "
             f"import subject_mask; print(subject_mask.read_prompt({str(path)!r}))"],
            capture_output=True, text=True,
            env=dict(os.environ, PYTHONPATH=str(poison)))
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("0.5", proc.stdout)

    def test_a_salient_masks_file_carries_no_prompt(self):
        path = self.dir / "mask.png"
        subject_mask.write_mask(path, self.mask_array())
        self.assertIsNone(subject_mask.read_prompt(path))

    def test_a_file_that_is_not_a_png_answers_none_rather_than_raising(self):
        broken = self.dir / "broken.png"
        broken.write_bytes(b"not a png at all")
        self.assertIsNone(subject_mask.read_prompt(broken))
        self.assertIsNone(subject_mask.read_prompt(self.dir / "absent.png"))

    def test_the_prompt_travels_with_the_pixels_through_an_accept(self):
        """`accept` is a byte copy, so this is free - and it is the property
        that makes the acceptance survive a restart with the clicks that
        produced it, rather than as an unexplained cutout."""
        cache = self.dir / "cache"
        cache.mkdir()
        wallpaper = self.dir / "wall.png"
        wallpaper.write_bytes(b"wallpaper")
        key = subject_mask.cache_key(wallpaper)
        prompt = [{"x": 0.4, "y": 0.6, "label": 1}]
        subject_mask.write_mask(cache / f"{key}.mobile-sam.png", self.mask_array(),
                                prompt=prompt)
        subject_mask.accept(cache, wallpaper, "mobile-sam")
        result = subject_mask.status(cache, wallpaper)
        self.assertEqual(result["state"], "accepted")
        self.assertEqual(result["acceptedPrompt"], prompt)
        self.assertEqual(result["acceptedModel"], "mobile-sam")

    def test_refining_the_candidate_leaves_the_accepted_prompt_alone(self):
        """The one case a prompt recorded beside the mask gets wrong.

        Clicking again overwrites the candidate; the accepted mask and its
        clicks are a frozen copy, so what the desktop is drawing keeps saying
        what it was cut with. A shared record would start describing a mask
        nothing is showing, and `acceptedModel` already goes to None here
        because the bytes have moved apart - which is the honest answer.
        """
        cache = self.dir / "cache"
        cache.mkdir()
        wallpaper = self.dir / "wall.png"
        wallpaper.write_bytes(b"wallpaper")
        key = subject_mask.cache_key(wallpaper)
        first = [{"x": 0.4, "y": 0.6, "label": 1}]
        subject_mask.write_mask(cache / f"{key}.mobile-sam.png", self.mask_array(),
                                prompt=first)
        subject_mask.accept(cache, wallpaper, "mobile-sam")
        second = first + [{"x": 0.7, "y": 0.2, "label": 0}]
        subject_mask.write_mask(cache / f"{key}.mobile-sam.png", self.mask_array() * 0.5,
                                prompt=second)
        result = subject_mask.status(cache, wallpaper)
        self.assertEqual(result["acceptedPrompt"], first)
        self.assertEqual(result["prompts"]["mobile-sam"], second)


class PromptedCacheTest(unittest.TestCase):
    """The prompted model inside the four states, and the embedding beside them."""
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.cache = self.dir / "cache"
        self.cache.mkdir()
        self.wallpaper = self.dir / "wall.png"
        self.wallpaper.write_bytes(b"wallpaper")
        self.key = subject_mask.cache_key(self.wallpaper)
        self.addCleanup(self.tmp.cleanup)

    def in_a_fresh_interpreter(self, body, poison):
        """Run `body` against the producer with `poison` first on the path.

        A separate process rather than a monkeypatch: the thing being pinned is
        that a module is never IMPORTED, and this one is already imported here.
        """
        return subprocess.run(
            [sys.executable, "-c",
             f"import sys; sys.path.insert(0, {str(SCRIPT.parent)!r})\n"
             f"import subject_mask\n{body}"],
            capture_output=True, text=True,
            env=dict(os.environ, PYTHONPATH=str(poison)))

    def test_a_click_mask_is_a_candidate_even_when_both_detectors_refused(self):
        """The state this whole feature exists for. Measured over this library:
        45 of 91 wallpapers return nothing from BOTH salient models, and every
        one of them read as `none` - a verdict on the picture, with nowhere to
        go."""
        for model in subject_mask.salient_models():
            (self.cache / f"{self.key}.{model}.none").write_text("")
        self.assertEqual(subject_mask.status(self.cache, self.wallpaper)["state"],
                         "none")
        (self.cache / f"{self.key}.mobile-sam.png").write_bytes(b"a clicked mask")
        self.assertEqual(subject_mask.status(self.cache, self.wallpaper)["state"],
                         "candidate")

    def test_an_opt_out_still_beats_a_clicked_mask(self):
        (self.cache / f"{self.key}.mobile-sam.png").write_bytes(b"a clicked mask")
        (self.cache / f"{self.key}.png").write_bytes(b"a clicked mask")
        (self.cache / f"{self.key}.off").write_text("")
        self.assertEqual(subject_mask.status(self.cache, self.wallpaper)["state"],
                         "declined")

    def test_clicking_nothing_clears_the_candidate(self):
        (self.cache / f"{self.key}.mobile-sam.png").write_bytes(b"a clicked mask")
        result = subject_mask.select(self.cache, self.wallpaper, "mobile-sam", [])
        self.assertEqual(result["state"], "cleared")
        self.assertFalse((self.cache / f"{self.key}.mobile-sam.png").exists())
        self.assertEqual(subject_mask.status(self.cache, self.wallpaper)["state"],
                         "absent")

    def test_a_cleared_candidate_leaves_no_refusal_marker_behind(self):
        """A click that finds nothing is one attempt, not a verdict.

        `<key>.<model>.none` means "this model looked and there is nothing in
        this picture", which is worth not re-learning. Writing one for a click
        would tell the picker to stop offering the one column the user aims.
        """
        subject_mask.select(self.cache, self.wallpaper, "mobile-sam", [])
        self.assertFalse((self.cache / f"{self.key}.mobile-sam.none").exists())

    def test_a_click_keeps_a_subject_the_detectors_floor_would_discard(self):
        """The two floors answer different questions and must not be one number.

        The salient floor divides "this model found a subject in this picture"
        from "it found a stray fragment", and 0.5% of the frame is a plausible
        place to put that. A click is the user asserting there IS something and
        pointing at it, so the only thing left to detect is a decoder that
        returned nothing.

        Measured rather than argued: excluding part of a hillside on
        `aishot-1206.jpg` left a mask at 0.46% of the frame - 76000 pixels on
        that 7680x2160 wallpaper, a plainly visible object - which the salient
        floor discarded as "nothing there". And a click on flat sky comes back
        at 1.6-10% because SAM answers with the sky, so the high floor was not
        even buying the refusal it looked like it was for.
        """
        self.assertLess(subject_mask.EMPTY_PROMPTED_FOREGROUND,
                        subject_mask.EMPTY_FOREGROUND / 10)
        self.assertGreater(subject_mask.EMPTY_PROMPTED_FOREGROUND, 0,
                           "a decoder returning nothing must still be refused")
        # The case that was thrown away, at the size it actually came back.
        self.assertGreater(0.0046, subject_mask.EMPTY_PROMPTED_FOREGROUND)
        self.assertLess(0.0046, subject_mask.EMPTY_FOREGROUND)

    def test_the_two_kinds_of_model_refuse_each_others_verb(self):
        with self.assertRaises(RuntimeError):
            subject_mask.select(self.cache, self.wallpaper, "isnet-anime",
                                [{"x": 0.5, "y": 0.5, "label": 1}])
        with self.assertRaises(RuntimeError):
            subject_mask.run(self.cache, self.wallpaper, "mobile-sam")

    def test_a_refused_verb_answers_in_json_rather_than_a_traceback(self):
        proc = run_cli("--cache-dir", str(self.cache), "select", str(self.wallpaper),
                       "--model", "mobile-sam", "--point", "5,5")
        self.assertEqual(proc.returncode, 1)
        self.assertEqual(json.loads(proc.stdout)["state"], "error",
                         "the picker parses stdout; a traceback on stderr is a "
                         "click that does nothing with no explanation")

    def test_a_second_click_reuses_the_embedding_instead_of_encoding_again(self):
        """The reason SAM is the right tool, pinned rather than asserted.

        Proved by removing the encoder from the equation entirely: the model
        file does not exist and `onnxruntime` raises on import, so anything that
        reaches the encoder fails. A cached embedding must come back regardless,
        because encoding costs seconds and refinement is the whole interaction.
        """
        try:
            import numpy as np
        except ImportError:
            self.skipTest("needs numpy (the shell's uv venv)")
        embedding = np.arange(2 * 3, dtype=np.float32).reshape(1, 2, 3)
        np.savez(self.cache / f"{self.key}.mobile-sam.embedding.npz",
                 embedding=embedding.astype(np.float16),
                 resized=np.array((1024, 425), np.int32))
        poison = self.dir / "poison"
        poison.mkdir()
        (poison / "onnxruntime.py").write_text(
            "raise AssertionError('a cached embedding re-encoded the image')\n")
        proc = self.in_a_fresh_interpreter(
            "from pathlib import Path\n"
            f"embedding, resized = subject_mask.image_embedding("
            f"Path({str(self.cache)!r}), {str(self.wallpaper)!r}, 'mobile-sam', "
            f"{self.key!r})\n"
            "print([int(v) for v in resized], [float(v) for v in embedding.reshape(-1)])",
            poison)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("[1024, 425]", proc.stdout)
        self.assertIn("5.0", proc.stdout)

    def test_the_embedding_is_swept_with_the_key_it_belongs_to(self):
        """It is derived from the same wallpaper and worthless the moment the
        key changes, so leaving it behind is a 2MB leak per wallpaper the user
        ever clicked on."""
        old = "a" * 32
        (self.cache / f"{old}.mobile-sam.embedding.npz").write_bytes(b"x")
        (self.cache / f"{old}.png").write_bytes(b"x")
        newer = self.cache / f"{'b' * 32}.png"
        newer.write_bytes(b"x")
        os.utime(newer, (time.time() + 100, time.time() + 100))
        subject_mask.sweep(self.cache, keep=1)
        self.assertEqual([p.name for p in self.cache.iterdir()], [newer.name])


class MissingRuntimeTest(unittest.TestCase):
    """A venv with no onnxruntime must say what to run, not raise Python at the user.

    It was pinned in `requirements.in` and never compiled into the lock the
    installer installs, so this is not hypothetical: every venv the installer
    has built is in exactly this state, and what the picker showed was
    `ModuleNotFoundError: No module named 'onnxruntime'`.
    """
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self.tmp.name)
        self.cache = self.dir / "cache"
        self.cache.mkdir()
        self.wallpaper = self.dir / "wall.png"
        self.wallpaper.write_bytes(b"wallpaper")
        self.addCleanup(self.tmp.cleanup)

    def test_the_error_names_the_environment_and_the_command_that_repairs_it(self):
        missing = self.dir / "missing"
        missing.mkdir()
        (missing / "onnxruntime.py").write_text(
            "raise ImportError(\"No module named 'onnxruntime'\")\n")
        proc = subprocess.run(
            [sys.executable, "-c",
             f"import sys; sys.path.insert(0, {str(SCRIPT.parent)!r}); "
             f"import subject_mask; subject_mask.session_for('/nowhere.onnx')"],
            capture_output=True, text=True,
            env=dict(os.environ, PYTHONPATH=str(missing)))
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("onnxruntime is missing", proc.stderr)
        self.assertIn("uv pip install", proc.stderr,
                      "a user reading this has to be able to act on it")
        self.assertIn("IMMATERIAL_IMPULSE_VIRTUAL_ENV", proc.stderr)


class ContractTest(unittest.TestCase):
    def test_every_model_file_declares_a_url_and_a_checksum(self):
        for model, spec in subject_mask.MODELS.items():
            self.assertIn(spec["kind"], ("salient", "prompted"), model)
            self.assertEqual(spec["side"], 1024, model)
            self.assertTrue(spec["files"], model)
            for role, file in spec["files"].items():
                self.assertTrue(file["url"].startswith("https://"), f"{model}.{role}")
                self.assertRegex(file["sha256"], r"^[0-9a-f]{64}$", f"{model}.{role}")

    def test_a_single_file_model_keeps_the_name_it_already_occupies_on_disk(self):
        """The two 176MB isnet files are already fetched on every machine.

        Putting a role in their filename would orphan both and re-download 350MB
        the first time anyone opened the picker after the update - silently, as
        a several-minute hang behind a button that used to be instant.
        """
        root = Path("/cache")
        self.assertEqual(subject_mask.model_path(root, "isnet-anime"),
                         root / "models/isnet-anime.onnx")
        self.assertEqual(subject_mask.model_path(root, "mobile-sam", "encoder"),
                         root / "models/mobile-sam.encoder.onnx")

    def test_the_prompted_model_ships_the_encoder_and_the_decoder_separately(self):
        """The split IS the feature, so it is a contract rather than a detail.

        One fused file would re-encode the image on every click - seconds each,
        for a gesture whose whole value is that the second click is instant.
        """
        for model in subject_mask.prompted_models():
            self.assertEqual(set(subject_mask.MODELS[model]["files"]),
                             {"encoder", "decoder"}, model)

    def test_run_and_select_are_offered_for_different_models(self):
        self.assertTrue(subject_mask.salient_models())
        self.assertTrue(subject_mask.prompted_models())
        self.assertEqual(set(subject_mask.salient_models())
                         & set(subject_mask.prompted_models()), set())

    def test_the_venv_wrapper_exists_and_is_executable(self):
        self.assertTrue(VENV_WRAPPER.exists())
        self.assertTrue(os.access(VENV_WRAPPER, os.X_OK))
        self.assertTrue(os.access(SCRIPT, os.X_OK))

    def test_onnxruntime_is_declared_in_the_venv_requirements(self):
        requirements = (ROOT.parents[3] / "sdata/uv/requirements.in").read_text()
        self.assertIn("onnxruntime", requirements,
                      "run needs a session; without the pin the venv has none and "
                      "the picker fails at the moment the user clicks it")

    def test_onnxruntime_reaches_the_file_the_installer_actually_installs(self):
        """The declaration and the lock are two files, and only one is installed.

        `sdata/lib/package-installers.sh` runs `uv pip install -r
        requirements.txt`; `requirements.in` is the input a human edits and
        nothing reads at install time. onnxruntime was added to the `.in` when
        the producer landed and the lock was never recompiled, so every venv the
        installer has ever built lacks it - and the only symptom is a raw
        `ModuleNotFoundError` at the moment the user clicks Run in the picker,
        on a machine where the feature has never worked. The old version of this
        check read the `.in` and was green throughout.
        """
        lock = ROOT.parents[3] / "sdata/uv/requirements.txt"
        self.assertRegex(lock.read_text(), r"(?m)^onnxruntime==",
                         "the installer installs the compiled lock, not the .in - "
                         "recompile with `uv pip compile requirements.in -o "
                         "requirements.txt` after adding a dependency")

    def test_the_script_does_not_import_onnxruntime_at_module_scope(self):
        source = SCRIPT.read_text()
        head = source.split("def segment(", 1)[0]
        self.assertNotIn("import onnxruntime", head,
                         "a module-scope import makes every status query pay for "
                         "onnxruntime, which is the cost this cache exists to avoid")


if __name__ == "__main__":
    unittest.main()
