#!/usr/bin/env python3
"""The greeter's still is grabbed off the live surface, not re-rendered.

The SDDM greeter cannot run Wallpaper Engine, so it needs a static image of the
active project. The only image a project ships is the Steam Workshop preview - a
thumbnail, often square and around 1000px - which on a wide display was cropped
to a narrow band and upscaled several times over (#113; measured at 910x910 on
5120x1440).

The first fix rendered a full-size still by launching a second
linux-wallpaperengine. That was wrong in kind: the shell already embeds Wallpaper
Engine in-process (Quickshell.WallpaperEngine / WallpaperEngineSurface), so it
meant loading a second copy of the renderer and libcef, and spending seconds of
GPU, to photograph a frame that was already on screen - and, in window mode, to
do it in a window that stole focus.

The surface is a QQuickItem. The still is grabToImage() on it, which the
wallpaper transition was already doing for its own snapshot.

These pin the properties that would silently regress: that nothing spawns a
renderer, that exactly one output writes the file, and that the grab waits for a
settled frame rather than the first one.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKGROUND = ROOT / "modules/imi/background/Background.qml"
SERVICE = ROOT / "services/WallpaperEngine.qml"
CONFIG = ROOT / "modules/common/Config.qml"
DIRECTORIES = ROOT / "modules/common/Directories.qml"
SCRIPT = ROOT / "scripts/wallpapers/we_still.sh"


class NoSecondRendererTests(unittest.TestCase):
    """The point of the change: no second Wallpaper Engine, by any route."""

    def test_the_render_script_is_gone(self):
        self.assertFalse(
            SCRIPT.exists(),
            "we_still.sh is back - the still comes from the live surface now")

    def test_nothing_spawns_a_renderer(self):
        # Any reintroduction would go through a Process running the binary or a
        # script wrapping it. Checked across the whole shell, not just the two
        # files this change touched.
        #
        # Comment lines are dropped first. The code that explains why the second
        # renderer is gone necessarily names it, so scanning raw text reports the
        # explanation as the offence - which it did on the first run of this.
        offenders = []
        for path in list(ROOT.rglob("*.qml")) + list(ROOT.rglob("scripts/**/*.sh")):
            if "tests/" in str(path.relative_to(ROOT)):
                continue
            code = "\n".join(
                line for line in path.read_text(errors="ignore").splitlines()
                if not line.lstrip().startswith(("//", "#")))
            if "linux-wallpaperengine" in code or "we_still" in code:
                offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual(offenders, [], f"a second renderer crept back in: {offenders}")

    def test_the_service_no_longer_queues_renders(self):
        service = SERVICE.read_text()
        for gone in ("enqueueStill", "stillProcess"):
            self.assertNotIn(gone, service, f"{gone} survived the removal")


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.bg = BACKGROUND.read_text()
        body = self.bg.index("function captureGreeterStill()")
        self.capture = self.bg[body:self.bg.index("\n        }", body)]

    def test_the_still_is_grabbed_from_the_surface(self):
        self.assertIn("grabToImage", self.capture)
        self.assertIn("saveToFile", self.capture)

    def test_exactly_one_output_writes_the_still(self):
        # Background is instantiated per screen by Variants. Without this guard
        # every monitor grabs its own frame and races to the same path, so the
        # greeter gets whichever finished last.
        self.assertIn("ownsGreeterStill", self.capture)
        self.assertRegex(self.bg, r"ownsGreeterStill:.*Quickshell\.screens\[0\]")

    def test_the_still_is_recorded_only_when_the_write_succeeded(self):
        # A path recorded for a file that was never written is worse than no
        # path: the greeter would prefer it over the preview and find nothing.
        self.assertRegex(self.capture,
                         r"if \(result\.saveToFile\(target\)\)\s*\n\s*Config\.")

    def test_the_grab_waits_for_a_settled_frame(self):
        # `rendered` flips on the FIRST frame, which can be warmup or black -
        # the same reason the shader transition holds the outgoing still. A grab
        # fired directly off onRenderedChanged captures the black one.
        self.assertRegex(self.bg, r"id: greeterStillDelay\s*\n\s*interval: \d+")
        self.assertIn("greeterStillDelay.restart()", self.bg)
        self.assertNotRegex(
            self.bg, r"onRenderedChanged\(\) \{[^}]*captureGreeterStill\(\)",
            "grab fired on the first frame instead of a settled one")

    def test_a_still_is_captured_without_a_transition(self):
        # The session's first project takes the no-transition path, and needs a
        # still just as much as a switch does. Guarding the restart on
        # weTransitioning would leave that case with no still at all.
        rendered = self.bg[self.bg.index("function onRenderedChanged()"):]
        rendered = rendered[:rendered.index("\n                    }")]
        restart = rendered[rendered.index("greeterStillDelay.restart()"):]
        self.assertNotIn("weTransitioning", restart)

    def test_the_still_is_named_for_the_project_it_shows(self):
        self.assertRegex(self.capture,
                         r"\$\{Directories\.wallpaperEngineStills\}/\$\{id\}\.png")

    def test_the_still_is_written_losslessly(self):
        # saveToFile takes no quality argument, so the extension IS the quality
        # setting: .jpg gets Qt's default q75, measured at 35.0 dB PSNR against
        # the lossless grab where the script it replaced produced q94. On a
        # full-screen login background over dark gradients that shows.
        #
        # Comments stripped: the line explaining why .jpg is wrong contains
        # ".jpg", so scanning the raw body fails on its own justification.
        code = "\n".join(l for l in self.capture.splitlines()
                         if not l.lstrip().startswith("//"))
        self.assertNotIn(".jpg", code,
                         "a lossy extension here silently drops the still to q75")


class ConfigTests(unittest.TestCase):
    def test_stop_clears_the_still(self):
        # A still naming a project that is no longer active is exactly the
        # stale-field failure #103 was about.
        service = SERVICE.read_text()
        stop = service[service.index("function stop()"):]
        stop = stop[:stop.index("\n    }")]
        self.assertIn('activeStill = ""', stop)

    def test_config_declares_the_field(self):
        self.assertIn("property string activeStill:", CONFIG.read_text())

    def test_the_directory_is_created_and_never_wiped(self):
        # saveToFile fails silently on a missing directory, and the deleted
        # script was what used to mkdir -p it. The other media caches here are
        # rm -rf'd at startup; this one must not be, because the greeter reads
        # it while the shell is not running.
        dirs = DIRECTORIES.read_text()
        self.assertIn("property string wallpaperEngineStills:", dirs)
        self.assertRegex(dirs, r'mkdir", "-p", `\$\{wallpaperEngineStills\}`')
        self.assertNotRegex(dirs, r"rm -rf '\$\{wallpaperEngineStills\}'")


if __name__ == "__main__":
    unittest.main()
