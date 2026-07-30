#!/usr/bin/env python3
"""Drop shelf summon pins: shake detector behavior + QML/config wiring.

The shake detector is pure logic imported straight from the script; the QML
pins guard the wiring that only breaks silently (config keys, shortcut name,
gating conditions, coordinate conversion).
"""
import importlib.util
import json
import random
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

spec = importlib.util.spec_from_file_location(
    "shake_detector", ROOT / "scripts/dropshelf/shake_detector.py")
shake_detector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shake_detector)
ShakeDetector = shake_detector.ShakeDetector


def run_zigzag(detector, legs=8, leg_px=80.0, leg_ms=100.0, hz=60.0, start_x=500.0):
    """Feed a synthetic horizontal zigzag; returns times at which it fired."""
    t, x, direction, fired = 0.0, start_x, 1, []
    step_ms = 1000.0 / hz
    steps = max(1, int(leg_ms / step_ms))
    for _ in range(legs):
        for _ in range(steps):
            t += step_ms
            x += direction * leg_px / steps
            if detector.feed(t, x, 300.0):
                fired.append(t)
        direction *= -1
    return fired


class ShakeDetectorTests(unittest.TestCase):
    def test_vigorous_zigzag_fires(self):
        self.assertTrue(run_zigzag(ShakeDetector()))

    def test_straight_drag_never_fires(self):
        d = ShakeDetector()
        t, x = 0.0, 0.0
        for _ in range(300):
            t += 16.7
            x += 15.0
            self.assertFalse(d.feed(t, x, 300.0))

    def test_pixel_jitter_never_fires(self):
        d = ShakeDetector()
        rng = random.Random(1)
        t, x = 0.0, 500.0
        for _ in range(600):
            t += 16.7
            x += rng.uniform(-8.0, 8.0)
            self.assertFalse(d.feed(t, x, 300.0))

    def test_slow_zigzag_outside_window_never_fires(self):
        # Same shape as a shake but each leg takes 500ms - the sliding
        # window must forget earlier reversals.
        self.assertFalse(run_zigzag(ShakeDetector(), legs=10, leg_ms=500.0))

    def test_short_legs_never_fire(self):
        self.assertFalse(run_zigzag(ShakeDetector(), leg_px=40.0))

    def test_sensitivity_lowers_leg_threshold(self):
        self.assertTrue(run_zigzag(ShakeDetector(sensitivity=2.0), leg_px=40.0))

    def test_cooldown_swallows_continued_shaking(self):
        d = ShakeDetector()
        fired = run_zigzag(d, legs=40)
        self.assertGreaterEqual(len(fired), 2)
        for i in range(1, len(fired)):
            self.assertGreaterEqual(fired[i] - fired[i - 1], d.COOLDOWN_MS)

    def test_vertical_movement_ignored(self):
        d = ShakeDetector()
        t, y = 0.0, 0.0
        for _ in range(300):
            t += 16.7
            y += 15.0 if (int(t) // 100) % 2 == 0 else -15.0
            self.assertFalse(d.feed(t, 500.0, y))


class ScriptContractTests(unittest.TestCase):
    def setUp(self):
        self.script = (ROOT / "scripts/dropshelf/shake_detector.py").read_text()

    def test_raw_socket_not_hyprctl_fork(self):
        # Polling must use the raw request socket - forking hyprctl at 60Hz
        # is a process spawn per frame.
        self.assertIn('b"j/cursorpos"', self.script)
        self.assertIn(".socket.sock", self.script)

    def test_output_line_shape(self):
        self.assertIn('print(f"SHAKE {x:.0f} {y:.0f}", flush=True)', self.script)

    def test_shake_armed_only_while_button_held(self):
        # A Wayland client cannot see drags globally, but every pointer drag
        # holds BTN_LEFT - the detector must gate on it (EVIOCGKEY state
        # poll) and reset the gesture when the button is released.
        self.assertIn("BTN_LEFT = 0x110", self.script)
        self.assertIn("buttons.available and not buttons.pressed()", self.script)
        self.assertIn("detector.reset()", self.script)
        # Missing 'input'-group access must degrade loudly, not die.
        self.assertIn("shake armed even outside drags", self.script)


class ButtonWatcherTests(unittest.TestCase):
    def test_no_devices_degrades_to_unavailable(self):
        real_glob = shake_detector.glob.glob
        shake_detector.glob.glob = lambda pattern: []
        try:
            watcher = shake_detector.ButtonWatcher()
            self.assertFalse(watcher.available)
            self.assertFalse(watcher.pressed())
        finally:
            shake_detector.glob.glob = real_glob

    def test_released_button_resets_gesture_state(self):
        d = ShakeDetector()
        run_zigzag(d, legs=2)  # partial gesture accumulated
        self.assertTrue(d.legs or d.direction)
        d.reset()
        self.assertEqual(d.legs, [])
        self.assertEqual(d.direction, 0)


class QmlWiringTests(unittest.TestCase):
    def setUp(self):
        self.panel = (ROOT / "modules/common/plugins/bundled/dropShelf/DropShelfPanel.qml").read_text()
        self.shelf = (ROOT / "modules/common/widgets/DropShelf.qml").read_text()
        self.bar = (ROOT / "modules/ii/bar/Bar.qml").read_text()

    def test_global_shortcut_name(self):
        self.assertIn('name: "dropShelfSummon"', self.panel)

    def test_keybind_registered(self):
        keybinds = (ROOT.parents[1] / "hypr/hyprland/keybinds.lua").read_text()
        self.assertIn('quickshell:dropShelfSummon', keybinds)

    def test_ipc_handler(self):
        self.assertIn('target: "dropShelf"', self.panel)

    def test_shake_process_gated(self):
        for gate in ("root.shakeToSummon",
                     "!GlobalStates.screenLocked",
                     "!HyprlandData.focusedMonitorHasFullscreen"):
            self.assertIn(gate, self.panel)

    def test_shake_process_runs_detector_script(self):
        self.assertIn("dropshelf/shake_detector.py", self.panel)
        self.assertIn('"--sensitivity"', self.panel)

    def test_summon_converts_global_to_monitor_coords(self):
        self.assertIn("HyprlandData.monitors.find", self.shelf)
        self.assertIn('["hyprctl", "-j", "cursorpos"]', self.shelf)

    def test_bar_reveal_gated_and_accepts_uri_list(self):
        # Bar is core; the reveal must stay behind the plugin being enabled.
        self.assertIn('Config.options.plugins.enabled.includes("drop_shelf")', self.bar)
        self.assertIn('PluginState.option("drop_shelf", "dragToBarReveal", true)', self.bar)
        self.assertIn('keys: ["text/uri-list"]', self.bar)
        self.assertIn("DropShelf.addItems(drop.urls)", self.bar)

    def test_anchor_below_positioning(self):
        self.assertIn("dropShelfAnchorBelow", self.bar)
        self.assertIn("GlobalStates.dropShelfAnchorBelow", self.panel)


class PluginContractTests(unittest.TestCase):
    def setUp(self):
        self.manifest = json.loads(
            (ROOT / "modules/common/plugins/bundled/dropShelf/manifest.json").read_text())

    def test_manifest_shape(self):
        self.assertEqual(self.manifest["id"], "drop_shelf")
        self.assertIn("panel", self.manifest["capabilities"])
        self.assertEqual(self.manifest["panel"], {"component": "DropShelfPanel.qml"})
        self.assertIn("process", self.manifest["permissions"])

    def test_manifest_options_cover_all_knobs(self):
        options = {o["key"]: o for o in self.manifest["options"]}
        self.assertEqual(set(options), {
            "dragToBarReveal", "shakeToSummon", "shakeSensitivity",
            "autoDismissSeconds", "blurBackground", "backgroundOpacity"})
        self.assertEqual(options["shakeSensitivity"]["default"], 100)
        self.assertEqual(options["shakeSensitivity"]["enabledWhen"], "shakeToSummon")
        # Fractional slider needs a fractional step or PluginOptions rounds to 0/1.
        self.assertEqual(options["backgroundOpacity"]["step"], 0.05)

    def test_bundled_plugin_enabled_by_default(self):
        defaults = json.loads((ROOT / "defaults/config.json").read_text())
        self.assertNotIn("dropShelf", defaults)
        self.assertIn("drop_shelf", defaults["plugins"]["enabled"])

    def test_core_config_has_no_dropshelf_section(self):
        adapter = (ROOT / "modules/common/Config.qml").read_text()
        self.assertNotIn("JsonObject dropShelf", adapter)

    def test_panel_reads_plugin_options(self):
        panel = (ROOT / "modules/common/plugins/bundled/dropShelf/DropShelfPanel.qml").read_text()
        for pin in ('PluginState.option(pluginId, "shakeToSummon", false)',
                    'PluginState.option(pluginId, "shakeSensitivity", 100) / 100',
                    'PluginState.option(pluginId, "blurBackground", true)',
                    'PluginState.option(pluginId, "backgroundOpacity", 0.5)'):
            self.assertIn(pin, panel)

    def test_blurable_background(self):
        panel = (ROOT / "modules/common/plugins/bundled/dropShelf/DropShelfPanel.qml").read_text()
        self.assertIn("ColorUtils.transparentize(Appearance.colors.colLayer0, 1 - root.backgroundOpacity)", panel)

    def test_registered_with_plugin_manager(self):
        # Bundled plugins are a hardcoded FileView list - forgetting the
        # registration silently makes the plugin not exist.
        manager = (ROOT / "modules/common/plugins/PluginManager.qml").read_text()
        self.assertIn("dropShelfManifestFile", manager)
        self.assertIn('bundled/dropShelf', manager)
        self.assertRegex(manager, r"screenshotResultManifestFile,\s*\n\s*dropShelfManifestFile\]")

    def test_desktop_menu_gated_on_plugin(self):
        menu = (ROOT / "modules/ii/desktopMenu/DesktopMenu.qml").read_text()
        self.assertIn('Config.options.plugins.enabled.includes("drop_shelf")', menu)


if __name__ == "__main__":
    unittest.main()
