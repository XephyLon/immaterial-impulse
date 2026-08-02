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
        self.panel = (ROOT / "modules/imi/dropShelf/DropShelfPanel.qml").read_text()
        self.shelf = (ROOT / "modules/common/widgets/DropShelf.qml").read_text()
        self.bar = (ROOT / "modules/imi/bar/Bar.qml").read_text()

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
        self.assertIn("Config.options.dropShelf.dragToBarReveal", self.bar)
        self.assertIn('keys: ["text/uri-list"]', self.bar)
        self.assertIn("DropShelf.addItems(drop.urls)", self.bar)

    def test_anchor_below_positioning(self):
        self.assertIn("dropShelfAnchorBelow", self.bar)
        self.assertIn("GlobalStates.dropShelfAnchorBelow", self.panel)


class CoreIntegrationTests(unittest.TestCase):
    """The shelf is core shell (de-pluginized): always loaded, config-driven."""

    def setUp(self):
        self.panel = (ROOT / "modules/imi/dropShelf/DropShelfPanel.qml").read_text()

    def test_loaded_by_the_panel_family(self):
        fam = (ROOT / "panelFamilies/ImmaterialImpulseFamily.qml").read_text()
        self.assertIn("PanelLoader { component: DropShelfPanel {} }", fam)
        self.assertIn("import qs.modules.imi.dropShelf", fam)

    def test_no_plugin_remnants(self):
        self.assertNotIn("PluginState", self.panel)
        self.assertFalse((ROOT / "modules/common/plugins/bundled/dropShelf").exists())
        manager = (ROOT / "modules/common/plugins/PluginManager.qml").read_text()
        self.assertNotIn("dropShelf", manager)

    def test_panel_reads_core_config(self):
        for pin in ("Config.options.dropShelf.shakeToSummon",
                    "Config.options.dropShelf.shakeSensitivity",
                    "Config.options.dropShelf.blurBackground",
                    "Config.options.dropShelf.backgroundOpacity"):
            self.assertIn(pin, self.panel)

    def test_defaults_and_adapter_agree(self):
        defaults = json.loads((ROOT / "defaults/config.json").read_text())
        self.assertEqual(defaults["dropShelf"], {
            "autoDismissSeconds": 5, "backgroundOpacity": 0.5,
            "blurBackground": True, "dragToBarReveal": True,
            "shakeSensitivity": 1.0, "shakeToSummon": False})
        self.assertNotIn("drop_shelf", defaults["plugins"]["enabled"])
        # `plugins.enabled` ships empty, but that no longer means a fresh
        # install shows nothing: `Config.migrateDesktopWidgetsToPlugins()` runs
        # on the first load of the seeded config and turns the curated
        # `background.widgets.*.enable` bits into plugin ids. The shipped set is
        # asserted by test_default_config.ShippedDesktopWidgetsSurviveTheMigration;
        # what matters *here* is only that the drop shelf is not in it.
        #
        # The original rule was "no plugin may be enabled in the shipped
        # defaults", justified by plugin widgets living under a Plugins page a
        # new user would not think to search. That page is now Settings ->
        # Widgets (SettingsContent.qml), so the discoverability argument the
        # rule rested on no longer holds.
        #
        # Bar layouts keep their `plugin:` entries either way: the bar filters
        # disabled ones out, so enabling later restores them in place.
        self.assertEqual(defaults["plugins"]["enabled"], [],
                         "the shipped file enables plugins through the widget "
                         "migration, never by listing them directly")
        adapter = (ROOT / "modules/common/Config.qml").read_text()
        self.assertIn("property JsonObject dropShelf", adapter)

    def test_settings_section_present(self):
        page = (ROOT / "modules/imi/settings/pages/SidebarsPanelsConfig.qml").read_text()
        self.assertIn('Translation.tr("Drop shelf")', page)
        self.assertIn("Config.options.dropShelf.dragToBarReveal", page)

    def test_bar_and_menu_ungated(self):
        bar = (ROOT / "modules/imi/bar/Bar.qml").read_text()
        self.assertIn("Config.options.dropShelf.dragToBarReveal", bar)
        self.assertNotIn("drop_shelf", bar)
        menu = (ROOT / "modules/imi/desktopMenu/DesktopMenu.qml").read_text()
        self.assertNotIn("drop_shelf", menu)


if __name__ == "__main__":
    unittest.main()
