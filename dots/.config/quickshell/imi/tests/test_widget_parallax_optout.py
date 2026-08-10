#!/usr/bin/env python3
"""The `followParallax` opt-out, in two halves.

A widget on the desktop travels because the *canvas* travels: the widget canvas
is one item whose x/y are the parallax pan (`Background.qml`). Opting a single
widget out is therefore a cancellation, not a smaller offset, and that has one
consequence worth guarding beyond the sign: the drag runs in canvas coordinates
while `PluginState` holds placement coordinates, and the gap between them is
exactly the cancellation. A `commitPosition` that stored the drawn coordinate
would move an opted-out widget by a whole pan every time it was dragged -
silently, because it looks right until the pan next changes.

The source half below is static and runs everywhere, CI included.

The runtime half drives `WidgetParallaxOptOutRuntimeTest.qml`: two real
`PluginWidget`s on a real `WidgetCanvas`, panned the way `Background.qml` pans
it and dragged while panned. It brings its own headless weston, so it needs no
display of its own - but it does need weston, and skips without it. `tst_parallax`
covers the arithmetic; only a live host can show what it does to the store.
"""

import os
import re
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HARNESS = ROOT / "WidgetParallaxOptOutRuntimeTest.qml"
HOST = ROOT / "modules/common/plugins/PluginWidget.qml"
BASE_WIDGET = ROOT / "modules/common/widgets/widgetCanvas/AbstractWidget.qml"
OPTIONS = ROOT / "modules/common/plugins/PluginOptions.qml"
VALIDATOR = ROOT / "modules/common/plugins/PluginValidator.js"
MATHS = ROOT / "modules/common/functions/parallax.js"
SOCKET = "wayland-imi-widget-parallax"


def squashed(path: Path) -> str:
    return re.sub(r"\s+", " ", path.read_text(encoding="utf-8"))


class TheArithmeticIsExtracted(unittest.TestCase):
    """Beside `widgetOffset`, where it can be driven without a compositor."""

    def test_the_cancellation_lives_in_parallax_js(self):
        self.assertIn("function parallaxCancel(canvasOffset, follows)",
                      MATHS.read_text(encoding="utf-8"))

    def test_both_directions_of_the_conversion_live_beside_it(self):
        """Applying the cancellation by hand at each call site is what let the
        render and the save disagree about which frame they were in.
        """
        maths = MATHS.read_text(encoding="utf-8")
        self.assertIn("function drawnFromPlacement(placement, cancel)", maths)
        self.assertIn("function placementFromDrawn(drawn, cancel)", maths)

    def test_the_host_does_not_reimplement_it(self):
        """A `-canvas.x` written inline in the host is the same expression with
        nowhere to test it, and it is one sign away from doubling the pan.
        """
        host = squashed(HOST)
        self.assertIn("ParallaxMath.parallaxCancel(", host)
        self.assertNotRegex(host, r"x:\s*-\s*\w*[Cc]anvas\.x")

    def test_the_host_applies_it_through_the_named_conversions(self):
        host = squashed(HOST)
        self.assertNotRegex(
            host, r"placedX \+ rootWidget\.parallaxCancelX",
            "the drawn position goes through ParallaxMath.drawnFromPlacement")
        self.assertNotRegex(
            host, r"rootWidget\.x - rootWidget\.parallaxCancelX",
            "the stored position goes through ParallaxMath.placementFromDrawn")


class TheHostCancelsRatherThanOffsets(unittest.TestCase):
    def setUp(self):
        self.host = squashed(HOST)

    def test_the_flag_is_a_plugin_state_option_seeded_by_the_manifest(self):
        self.assertIn(
            'PluginState.option(manifest.id, "followParallax", '
            "manifest.desktopWidget?.followParallax !== false)",
            self.host,
            "following is the default, so the manifest seed can only opt OUT")

    def test_both_axes_are_cancelled(self):
        for axis in ("parallaxCancelX", "parallaxCancelY"):
            self.assertIn(f"readonly property real {axis}", self.host)

    def test_the_drawn_position_is_placement_plus_cancellation(self):
        self.assertIn(
            "x: ParallaxMath.drawnFromPlacement(rootWidget.placedX, "
            "rootWidget.parallaxCancelX)", self.host)
        self.assertIn(
            "y: ParallaxMath.drawnFromPlacement(rootWidget.placedY, "
            "rootWidget.parallaxCancelY)", self.host)

    def test_the_drag_release_rebinding_keeps_the_cancellation(self):
        """`restoreXYBinding` is what runs after every drag. Rebinding to the
        placement alone would drop an opted-out widget back onto the pan for
        the rest of the session, with nothing reporting it.
        """
        body = self.host[self.host.index("function restoreXYBinding()"):]
        body = body[:body.index("function commitPosition")]
        for axis in ("X", "Y"):
            self.assertIn(f"ParallaxMath.drawnFromPlacement( rootWidget.placed{axis}, "
                          f"rootWidget.parallaxCancel{axis})", body)

    def test_the_stored_position_has_the_cancellation_taken_back_out(self):
        """The drift bug. `x` is where the widget is drawn on the canvas; the
        store holds where it was placed.
        """
        body = self.host[self.host.index("function commitPosition()"):]
        for axis in ("X", "Y"):
            self.assertIn(f"rootWidget.target{axis} = ParallaxMath.placementFromDrawn( "
                          f"rootWidget.{axis.lower()}, rootWidget.parallaxCancel{axis})", body)

    def test_an_opted_out_widget_does_not_animate_its_position(self):
        """The bug that made the opt-out inert on a real desktop.

        `Background.qml` animates the pan over 600ms, so an opted-out widget's
        x/y binding re-evaluates on every frame of it - and a `Behavior` whose
        target moves every frame restarts every frame and never ticks. The
        widget sat at its pre-pan canvas coordinate for the whole transition,
        which is to say it travelled the full pan on screen, and any release
        landing in that window saved the stale coordinate.
        """
        self.assertIn("animatePosition: rootWidget.followParallax", self.host)
        base = squashed(BASE_WIDGET)
        self.assertIn("property bool animatePosition: true", base)
        self.assertEqual(
            2, base.count("enabled: root.animatePosition && !root.dragging"),
            "both position Behaviors have to honour it, or one axis still freezes")


class TheSettingsSideExists(unittest.TestCase):
    """A persisted option with no UI silently does nothing (CONTRIBUTING:
    "Settings additions are two-sided")."""

    def test_the_row_is_offered_and_seeded_the_same_way(self):
        options = squashed(OPTIONS)
        self.assertIn('key: "followParallax"', options)
        self.assertIn("default: manifest.desktopWidget?.followParallax !== false", options)

    def test_the_manifest_field_is_type_checked(self):
        """The other four seeds are validated; an unvalidated fifth would
        accept a string and seed a truthy default nobody can account for.
        """
        self.assertIn('"followParallax"', VALIDATOR.read_text(encoding="utf-8"))


def _stop(proc):
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()


def _runtime_available():
    return shutil.which("qs") is not None and shutil.which("weston") is not None


@unittest.skipUnless(_runtime_available(), "needs qs and weston on PATH")
class WidgetParallaxOptOutRuntimeTest(unittest.TestCase):
    def setUp(self):
        self.home = Path(tempfile.mkdtemp(prefix="imi-widget-parallax-"))
        self.addCleanup(shutil.rmtree, self.home, ignore_errors=True)

    def test_an_opted_out_widget_holds_its_place_and_stores_its_placement(self):
        env = dict(os.environ)
        env.setdefault("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
        env["WAYLAND_DISPLAY"] = SOCKET
        env.pop("DISPLAY", None)

        weston = subprocess.Popen(
            ["weston", "--backend=headless", "--renderer=pixman",
             f"--socket={SOCKET}", "--width=1400", "--height=900"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(_stop, weston)

        socket_path = Path(env["XDG_RUNTIME_DIR"]) / SOCKET
        deadline = time.monotonic() + 15
        while not socket_path.exists() and time.monotonic() < deadline:
            time.sleep(0.2)
        self.assertTrue(socket_path.exists(), "headless weston never came up")

        # This box's headless EGL has no driver, so force software rendering.
        env["LIBGL_ALWAYS_SOFTWARE"] = "1"
        env["QT_QUICK_BACKEND"] = "software"
        env["XDG_CONFIG_HOME"] = str(self.home / "config")
        env["XDG_STATE_HOME"] = str(self.home / "state")

        proc = subprocess.run(["qs", "-p", str(HARNESS)], cwd=str(ROOT), env=env,
                              capture_output=True, text=True, timeout=180)
        output = proc.stdout + proc.stderr
        failed = [line for line in output.splitlines() if "FAIL" in line]
        self.assertEqual(failed, [], f"harness reported failures:\n{output}")
        self.assertIn("[WidgetParallax] failures: 0", output,
                      f"harness did not finish cleanly:\n{output}")

        # A cancellation folded back into the placement it is derived from
        # shows up here rather than as a failed check.
        self.assertNotIn("Binding loop", output,
                         f"the host tree grew a binding loop:\n{output}")


if __name__ == "__main__":
    unittest.main()
