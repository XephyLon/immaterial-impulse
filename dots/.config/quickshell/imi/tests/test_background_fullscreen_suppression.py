#!/usr/bin/env python3
"""Wallpaper suppression pins: never destroy the background's surface.

`hideWhenFullscreen` once hid the wallpaper with `visible: false` on its
PanelWindow. Under WlrLayershell that does not hide a window, it destroys it
(window reuse is forbidden there), so every fullscreen transition tore the
layer surface down and brought it back on a fresh scene-graph GL context. The
embedded Wallpaper Engine renderer had to rebuild against that context, and the
observable result was a desktop strobing at 30Hz - a photosensitive-seizure
hazard, not a cosmetic bug.

These pins guard the shape of the fix rather than its details: the window must
stay mapped, suppression must act on the contents, and the wallpaper must come
back animating. They are deliberately blunt - a future edit that reintroduces a
fullscreen-conditional `visible` on the window should fail here loudly.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKGROUND = ROOT / "modules/imi/background/Background.qml"
CORNERS = ROOT / "modules/imi/screenCorners/ScreenCorners.qml"
HYPRLAND_DATA = ROOT / "services/HyprlandData.qml"


class BackgroundSuppressionTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.background = BACKGROUND.read_text()
        cls.corners = CORNERS.read_text()
        cls.hyprland_data = HYPRLAND_DATA.read_text()

    def test_window_visible_is_never_bound_to_fullscreen(self):
        """The PanelWindow's own `visible` must not depend on fullscreen state.

        Binding it destroys and recreates the surface on every transition. This
        is the pin that matters most: it is the exact regression that strobed.
        """
        # `visible:` at PanelWindow indent (8 spaces), i.e. a direct child of the
        # window rather than of some Item nested inside it.
        window_level = re.findall(r"^        visible:.*$", self.background, re.M)
        for line in window_level:
            self.assertNotRegex(
                line, r"[Ff]ullscreen",
                "Background's PanelWindow binds `visible` to a fullscreen "
                "condition. That destroys the layer surface on every fullscreen "
                "transition - suppress the contents instead.")

    def test_contents_are_suppressed_instead(self):
        self.assertIn("visible: !bgRoot.suppressContents", self.background,
                      "The background's content item should be what "
                      "hideWhenFullscreen switches off.")

    def test_suppression_respects_lock_and_the_config_option(self):
        match = re.search(r"readonly property bool suppressContents:(.*?)\n\n",
                          self.background, re.S)
        self.assertIsNotNone(match, "suppressContents should still exist")
        body = match.group(1)
        self.assertIn("screenLocked", body,
                      "The wallpaper must stay drawn on the lock screen.")
        self.assertIn("hideWhenFullscreen", body,
                      "Suppression must remain opt-out via the config option.")

    def test_suppression_never_clears_the_wallpaper_renderer(self):
        """Suppression stops at not drawing; it does not touch `live`.

        `live` only gates the surface's repaint timer, and `updatePaintNode` -
        which the timer drives - is the one place the surface re-shares against
        a recreated GL context and the one place a project switch queued while
        suppressed gets applied. Stopping the timer on an item that is already
        not drawn buys nothing and can strand both.

        (`live` is not what froze video wallpapers behind a fullscreen window on
        another workspace. That is linux-wallpaperengine's own fullscreen pause,
        fixed in the embed's argv - see the comment in Background.qml.)
        """
        self.assertNotRegex(
            self.background, r"\.live\s*=",
            "Background assigns the WE surface's `live`. Suppression must only "
            "stop drawing, or a queued project switch and the GL-context "
            "recovery both lose the repaint that would apply them.")

    def test_unsuppress_is_immediate_and_only_hiding_is_debounced(self):
        """Delaying the wallpaper's return would read as a black flash."""
        match = re.search(r"onMonitorHasFullscreenChanged:\s*\{(.*?)\n        \}",
                          self.background, re.S)
        self.assertIsNotNone(match)
        body = match.group(1)
        else_branch = body.split("else", 1)
        self.assertEqual(len(else_branch), 2, "expected an else branch")
        self.assertIn("suppressedForFullscreen = false", else_branch[1],
                      "Leaving fullscreen must clear suppression directly, not "
                      "through the delay timer.")

    def test_a_switch_requested_while_suppressed_is_deferred(self):
        """The surface only builds a project while it is being drawn."""
        self.assertIn("wePendingProject", self.background,
                      "A wallpaper switch arriving while suppressed must be "
                      "held and replayed, not dropped onto a surface that "
                      "cannot act on it.")

    def test_transition_cannot_hang_forever(self):
        self.assertIn("weTransitionWatchdog", self.background,
                      "A stalled wallpaper transition must settle itself.")

    def test_fullscreen_test_ignores_maximized(self):
        """Maximized is not fullscreen; only the polled int tells them apart."""
        self.assertIn("w.fullscreen >= 2", self.hyprland_data)
        for name, source in (("Background", self.background),
                             ("ScreenCorners", self.corners)):
            self.assertIn("fullscreenByMonitorName", source,
                          f"{name} should read the polled per-monitor map.")
            self.assertNotIn("wayland?.fullscreen", source,
                             f"{name} still uses the toplevel's own fullscreen "
                             "flag, which is true for maximized windows too.")


if __name__ == "__main__":
    unittest.main()
