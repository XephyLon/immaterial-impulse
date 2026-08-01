#!/usr/bin/env python3
"""Lock-palette parity guards (regression pin for commit 61ff70d9).

The lock color generation used to diverge from the desktop's for the same
image/mode/scheme in two ways:
  - lockThemeProc passed --smart, which silently swaps the configured scheme
    to 'neutral' for low-chroma images (switchwall.sh never does), and
  - currentScheme() mapped palette type "auto" to a hardcoded
    scheme-tonal-spot while the desktop runs scheme_for_image.py detection.

Static contracts always run. The behavioral golden half needs the color venv
(materialyoucolor + PIL); without it those cases SKIP and the suite exits 0.
"""
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
THEME_LOADER = ROOT / "services/MaterialThemeLoader.qml"
WRAPPER = ROOT / "scripts/colors/generate-colors-venv.sh"
GENERATOR = ROOT / "scripts/colors/generate_colors_material.py"
SCHEME_DETECTOR = ROOT / "scripts/colors/scheme_for_image.py"
FIXTURE = ROOT / "tests/fixtures/colorful_64.png"
LOW_CHROMA_FIXTURE = ROOT / "tests/fixtures/low_chroma_64.png"

def _has(module):
    try:
        return importlib.util.find_spec(module) is not None
    except (ImportError, ValueError):
        return False

HAVE_GENERATOR_DEPS = _has("materialyoucolor") and _has("PIL")
HAVE_DETECTOR_DEPS = _has("cv2") and _has("numpy")
SKIP_GENERATOR = "SKIP: materialyoucolor/PIL not importable (color venv not active)"

if not HAVE_GENERATOR_DEPS:
    print(f"{SKIP_GENERATOR} - running static contracts only", flush=True)


def extract_block(text, start_marker, end_marker):
    start = text.index(start_marker)
    end = text.index(end_marker, start)
    return text[start:end + len(end_marker)]


def run_generator(args, env=None):
    return subprocess.run(
        [sys.executable, str(GENERATOR), *args],
        capture_output=True, text=True, env=env, timeout=120,
    )


def make_stub_venv(directory):
    """A no-op 'venv' for the wrapper: activate only pins our interpreter
    first on PATH so the wrapper's python3 is the one whose deps we probed."""
    bindir = Path(directory) / "bin"
    bindir.mkdir(parents=True)
    (bindir / "activate").write_text(
        'export PATH="%s:$PATH"\n' % Path(sys.executable).parent
    )
    return str(directory)


def run_wrapper(args, stub_venv):
    env = dict(os.environ, IMMATERIAL_IMPULSE_VIRTUAL_ENV=stub_venv)
    return subprocess.run(
        ["bash", str(WRAPPER), *args],
        capture_output=True, text=True, env=env, timeout=120,
    )


class StaticContracts(unittest.TestCase):
    """Grep-able pins on the fixed sources; run everywhere, no deps."""

    def setUp(self):
        self.loader = THEME_LOADER.read_text()
        self.wrapper = WRAPPER.read_text()

    def test_lock_command_does_not_pass_smart(self):
        command = extract_block(self.loader, "lockThemeProc.command = [", "];")
        self.assertNotIn("--smart", command,
                         "lockThemeProc must not pass --smart: it silently swaps "
                         "the scheme to 'neutral' for low-chroma images, which "
                         "the desktop path never does")

    def test_lock_command_forwards_image_mode_and_scheme(self):
        command = extract_block(self.loader, "lockThemeProc.command = [", "];")
        self.assertIn("generate-colors-venv.sh", command)
        for flag in ("--path", "--mode", "--scheme"):
            self.assertIn(f'"{flag}"', command,
                          f"lockThemeProc must forward {flag}")

    def test_current_scheme_passes_auto_through_verbatim(self):
        match = re.search(
            r"function currentScheme\(\)\s*\{(.*?)\n    \}", self.loader, re.S)
        self.assertIsNotNone(match, "currentScheme() missing from theme loader")
        body = match.group(1)
        self.assertNotIn('"scheme-tonal-spot"', body,
                         "currentScheme() must not map 'auto' to a hardcoded "
                         "scheme; the venv wrapper resolves it via "
                         "scheme_for_image.py like the desktop path")
        self.assertIn("return Config.options.appearance.palette.type", body)

    def test_wrapper_resolves_auto_via_scheme_detection(self):
        self.assertIn("scheme_for_image.py", self.wrapper,
                      "wrapper must resolve --scheme auto with the same "
                      "detector switchwall.sh uses for the desktop palette")
        self.assertRegex(self.wrapper, r'==\s*"auto"',
                         "wrapper must special-case the literal scheme 'auto'")
        self.assertIn("scheme-tonal-spot", self.wrapper,
                      "wrapper must keep a deterministic fallback when "
                      "detection produces no output")

    def test_wrapper_exec_preserves_argument_boundaries(self):
        self.assertRegex(
            self.wrapper,
            r'exec python3 .*generate_colors_material\.py.* ("\$@"|"\$\{args\[@\]\}")',
            "wrapper must exec with a quoted array (\"$@\" or \"${args[@]}\") "
            "so wallpaper paths with spaces survive")


@unittest.skipUnless(HAVE_GENERATOR_DEPS, SKIP_GENERATOR)
class LockDesktopParity(unittest.TestCase):
    """Golden behavioral half: the same image/mode/scheme must yield
    byte-identical scheme output on the lock path and the desktop path."""

    def setUp(self):
        self.assertTrue(FIXTURE.is_file(), f"missing fixture {FIXTURE}")

    def test_wrapper_output_is_byte_identical_to_desktop_invocation(self):
        # Desktop style: switchwall.sh runs the generator directly inside the
        # activated venv. Lock style: MaterialThemeLoader runs the wrapper
        # with exactly --path/--mode/--scheme.
        args = ["--path", str(FIXTURE), "--mode", "dark",
                "--scheme", "scheme-content"]
        desktop = run_generator(args)
        self.assertEqual(desktop.returncode, 0, desktop.stderr)
        with tempfile.TemporaryDirectory() as directory:
            lock = run_wrapper(args, make_stub_venv(directory))
        self.assertEqual(lock.returncode, 0, lock.stderr)
        self.assertEqual(desktop.stdout, lock.stdout,
                         "lock palette diverged from the desktop palette for "
                         "the same image/mode/scheme")
        self.assertIn("$primary:", desktop.stdout)

    def test_smart_flag_would_change_low_chroma_output(self):
        # Documents why the static --smart pin matters: on a low-chroma image
        # --smart rewrites the requested scheme, so passing it on the lock
        # path breaks parity with the desktop.
        self.assertTrue(LOW_CHROMA_FIXTURE.is_file(),
                        f"missing fixture {LOW_CHROMA_FIXTURE}")
        base = ["--path", str(LOW_CHROMA_FIXTURE), "--mode", "dark",
                "--scheme", "scheme-content"]
        plain = run_generator(base)
        smart = run_generator(base + ["--smart"])
        self.assertEqual(plain.returncode, 0, plain.stderr)
        self.assertEqual(smart.returncode, 0, smart.stderr)
        self.assertNotEqual(plain.stdout, smart.stdout,
                            "--smart no longer changes low-chroma output; "
                            "revisit whether this pin is still needed")

    def test_wrapper_scheme_auto_matches_desktop_auto_resolution(self):
        # Replicate the wrapper's documented auto contract: detect via
        # scheme_for_image.py, fall back to scheme-tonal-spot when detection
        # fails (e.g. detector deps missing), then feed the generator.
        if HAVE_DETECTOR_DEPS:
            detected = subprocess.run(
                [sys.executable, str(SCHEME_DETECTOR), str(FIXTURE)],
                capture_output=True, text=True, timeout=120)
            expected_scheme = (detected.stdout.strip()
                               if detected.returncode == 0 and detected.stdout.strip()
                               else "scheme-tonal-spot")
        else:
            expected_scheme = "scheme-tonal-spot"

        desktop = run_generator(["--path", str(FIXTURE), "--mode", "dark",
                                 "--scheme", expected_scheme])
        self.assertEqual(desktop.returncode, 0, desktop.stderr)
        with tempfile.TemporaryDirectory() as directory:
            lock = run_wrapper(["--path", str(FIXTURE), "--mode", "dark",
                                "--scheme", "auto"], make_stub_venv(directory))
        self.assertEqual(lock.returncode, 0, lock.stderr)
        self.assertEqual(desktop.stdout, lock.stdout,
                         f"wrapper --scheme auto did not resolve to the "
                         f"desktop's detected scheme ({expected_scheme})")


if __name__ == "__main__":
    unittest.main()
