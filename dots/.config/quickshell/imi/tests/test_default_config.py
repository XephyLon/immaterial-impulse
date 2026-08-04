#!/usr/bin/env python3
"""Guards for defaults/config.json — the curated out-of-the-box shell config
seeded by the installer on fresh installs (see 3.files.sh seed_default_config).

It is generated from a real config, so the big risks are (a) leaking
machine-specific/personal values, and (b) pinning keys whose Config.qml default
is a dynamic expression (a shipped literal would override per-user paths).
"""
import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CONFIG = ROOT / "defaults/config.json"
CONFIG_QML = ROOT / "modules/common/Config.qml"


def _strip_nested(body):
    """`body` with every nested `{...}` removed, so a regex over it only sees
    the object's own keys and not a grandchild's identically named one."""
    out, depth = [], 0
    for char in body:
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
        elif depth == 0:
            out.append(char)
    return "".join(out)


def _adapter_block(src, declaration):
    start = src.index(declaration)
    open_brace = src.index("{", start)
    depth = 0
    for i in range(open_brace, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                return src[open_brace + 1:i]
    raise AssertionError(f"unterminated block for {declaration}")


def _child_objects(block):
    """Immediate `property JsonObject <name>: JsonObject { ... }` children."""
    children, depth, name, body_start = {}, 0, None, 0
    for i, char in enumerate(block):
        if char == "{":
            if depth == 0:
                match = re.search(
                    r"property JsonObject (\w+): JsonObject\s*$", block[:i])
                name = match.group(1) if match else None
                body_start = i + 1
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0 and name:
                children[name] = block[body_start:i]
                name = None
    return children


class DefaultConfigTest(unittest.TestCase):
    def setUp(self):
        self.text = DEFAULT_CONFIG.read_text()
        self.cfg = json.loads(self.text)

    def test_parses_and_is_nonempty(self):
        self.assertIsInstance(self.cfg, dict)
        self.assertGreater(len(self.cfg), 10)

    def test_no_machine_or_personal_paths(self):
        # Any absolute home path, username, or Steam-content path is a leak
        # from the machine the file was generated on.
        self.assertIsNone(
            re.search(r"/home/|xephy|steamapps|\.local/share/Steam", self.text),
            "defaults/config.json leaks a machine-specific path",
        )

    def test_machine_state_keys_are_reset(self):
        bg = self.cfg["background"]
        for key in ("wallpaperPath", "thumbnailPath", "lockWall", "lockWallEngine"):
            self.assertEqual(bg[key], "", f"background.{key} must ship empty")
        we = self.cfg["wallpaperSelector"]["wallpaperEngine"]
        for key in ("activePath", "activePreview", "activeProject", "activeType", "libraryPath"):
            self.assertEqual(we[key], "", f"wallpaperEngine.{key} must ship empty")
        for key in ("avatarPath", "avatarPicture", "displayName"):
            self.assertEqual(self.cfg["profile"][key], "", f"profile.{key} must ship empty")

    def test_no_dynamic_default_overrides(self):
        # screenRecord.savePath's Config.qml default is the per-user videos dir
        # (a dynamic expression); shipping any literal would break it.
        self.assertNotIn("savePath", self.cfg.get("screenRecord", {}))

    def test_no_preset_metadata(self):
        self.assertNotIn("_presetMeta", self.cfg)


class ShippedDesktopWidgetsSurviveTheMigration(unittest.TestCase):
    """What a *fresh* install ends up with on its desktop.

    Every desktop widget is a bundled plugin now, so nothing reads
    `background.widgets.*` at runtime any more - but the file is still the
    input to `Config.migrateDesktopWidgetsToPlugins()`, which runs on the very
    first load of the seeded config and turns those `enable` bits into
    `plugins.enabled`. That makes the block look like dead legacy state while
    it is in fact the only thing deciding what a new user sees.

    The trap is that a `JsonAdapter` falls back to the QML-declared default for
    any key the file omits (verified against a live Quickshell instance:
    a file with no `clock` object at all still reads `clock.enable === true`).
    So deleting a block does not mean "off" - it means "whatever `Config.qml`
    says", which is `true` for the clock and `false` for the calendar and the
    visualizer. Tidying the whole block away would therefore have silently
    stripped the visualizer, and leaving a `calendar` block in would ship a
    widget the curated desktop does not want.

    The shipped desktop is the clock and the visualizer. Both sit at an edge -
    the clock centred, the visualizer full-bleed along the bottom - so neither
    claims a tile a new user has not chosen to give it. The calendar does claim
    one, which is why it ships off.
    """

    EXPECTED = {"clock", "visualizer"}

    def setUp(self):
        self.cfg = json.loads(DEFAULT_CONFIG.read_text())
        self.src = CONFIG_QML.read_text()
        self.schema = _child_objects(_adapter_block(
            self.src, "property JsonObject widgets: JsonObject {"))
        mapping = self.src[self.src.index("desktopWidgetPluginIds"):]
        self.plugin_ids = dict(re.findall(
            r'"(\w+)":\s*"([\w-]+)"', mapping[:mapping.index("})")]))
        self.shipped = self.cfg["background"].get("widgets", {})

    def adapter_enable(self, key):
        match = re.search(r"property bool enable:\s*(true|false)",
                          _strip_nested(self.schema[key]))
        self.assertIsNotNone(match, f"{key} declares no enable default")
        return match.group(1) == "true"

    def effective_enable(self, key):
        return self.shipped.get(key, {}).get("enable", self.adapter_enable(key))

    def test_the_migration_enables_exactly_the_curated_widgets(self):
        enabled = {self.plugin_ids[key] for key in self.plugin_ids
                   if self.effective_enable(key)}
        self.assertEqual(enabled, self.EXPECTED)

    def test_every_shipped_widget_key_is_declared_by_the_adapter(self):
        """A key the adapter does not declare is silently discarded on load,
        so it would ship looking authoritative and do nothing."""
        for key in self.shipped:
            self.assertIn(key, self.schema,
                          f"background.widgets.{key} is not in Config.qml")

    def test_the_clock_block_still_carries_its_settings(self):
        """The clock is the one widget whose *settings* migrate as well
        (`migrateDesktopWidgetOptionsToPlugins`), so its block seeds the
        plugin's options and its desktop position, not just an enable bit.
        Trimming it to `enable` the way the others were trimmed would repaint
        every fresh install's clock and move it to the host's generic 100,100.
        """
        clock = self.shipped.get("clock")
        self.assertIsNotNone(clock, "the clock block seeds the options migration")
        for key in ("x", "y", "placementStrategy", "style", "cookie"):
            self.assertIn(key, clock, f"clock.{key} would stop migrating")


if __name__ == "__main__":
    unittest.main()
