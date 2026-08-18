#!/usr/bin/env python3
"""Edit Mode may change placement, order, span, and presence - nothing else.

Spec §9's boundary, mechanized: Settings is one click away FROM Edit Mode, so a
settings row duplicated into the editor is a second call site for a config
write, and this repo has already paid for exactly that - `ConfigSwitch`'s
binding bug reached 159 call sites (69c15279a), and the `activeStill`
re-declaration re-armed six presets (03b8b0298). The rule written only in the
spec lasts until the second contributor; the allowlist below is the spec, and
this lint is the receipt.

What it polices, over every QML file under the edit-mode directories:

- a write to any `Config.options.*` path - direct assignment, in-place
  `push`/`splice`, or `Config.setNestedValue` - outside the placement and
  presence keys of §7.1's table (`plugins.enabled`, the bar's three layout
  arrays, `dock.pinnedApps`, `lock.show*`);
- a `PluginState.setOption` whose key is not one of the three the mode may
  touch: `__gridSize` (span), `positionLocked` and `clickThrough` (both
  placement decisions, §9's two deliberate edge cases);
- a write it cannot verify at all - a computed `setNestedValue` path or a
  computed option key - because an allowlist that can be reached through a
  variable is not an allowlist.

`PluginState.setPosition` is not policed: it can only ever write placement.

The detector is proven against in-memory fixtures below, so the machinery is
checked independently of what the tree happens to contain - a sweep that finds
no files, or a regex a reformat quietly defeats, fails here rather than going
green forever.
"""

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# The lock module joined for stage 9b: the island reorder commits its lists
# from LockSurface's own edit machinery, which lives beside the surface rather
# than under editMode/ - and a scope rule that stops at a directory boundary is
# an invitation to move the write one directory sideways.
EDIT_MODE_DIRS = [ROOT / "modules/imi/editMode", ROOT / "modules/imi/lock"]

ALLOWED_CONFIG_PATHS = {
    "plugins.enabled",
    "bar.layouts.leftLayout",
    "bar.layouts.middleLayout",
    "bar.layouts.rightLayout",
    "dock.pinnedApps",
    # Stage 9b: the islands' ORDER is placement (spec §9's rule admits order
    # by name), and the three lists are spelled out rather than a prefix so a
    # future lock.islands.* key does not inherit the licence unreviewed.
    "lock.islands.main",
    "lock.islands.left",
    "lock.islands.right",
    # The edge-snap toggle on the mode's toolbar (maintainer, 2026-08-18). It
    # is the SAME key Settings offers and stage 10's detent rides - the mode
    # surfaces the switch where the snapping happens, it does not mint one -
    # and it is a preference rather than a layout mutation, so it records no
    # undo entry (like the global widget lock). Spelled out, not a prefix.
    "background.showSnapLines",
}
# `lock.showWidgets` / `showToolbars` / `showMedia` are presence-on-a-surface,
# which the rule admits (spec §9's second edge case).
ALLOWED_CONFIG_PREFIXES = ("lock.show",)

ALLOWED_OPTION_KEYS = {"__gridSize", "positionLocked", "clickThrough"}


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(re.sub(r"//.*$", "", line) for line in text.splitlines())


def path_allowed(path: str) -> bool:
    clean = path.replace("?", "")
    if clean in ALLOWED_CONFIG_PATHS:
        return True
    return any(clean.startswith(prefix) for prefix in ALLOWED_CONFIG_PREFIXES)


def violations_in(name: str, raw: str) -> list:
    text = strip_comments(raw)
    found = []

    # A direct assignment to a Config.options leaf - plain or compound
    # (`+=`, `||=`, `??=`, ...). `=` but not `==`/`===`/`>=` etc; comparisons
    # carry a second `=` or a preceding comparison character.
    for match in re.finditer(
            r"Config\.options\.([A-Za-z0-9_.?]+?)\s*"
            r"(?:[-+*/%]|\|\||&&|\?\?)?=(?![=])", text):
        before = text[:match.start()].rstrip()[-1:]
        if before in ("!", "<", ">", "="):
            continue
        path = match.group(1)
        if not path_allowed(path):
            found.append(f"{name}: writes Config.options.{path}")

    # Bracket access cannot be resolved to a path, so it cannot be checked
    # against an allowlist - which makes it a violation outright rather than a
    # hole: an allowlist reachable through a computed key is not an allowlist.
    if re.search(r"Config\.options\s*\[", text):
        found.append(f"{name}: reaches Config.options through a computed key")

    # An in-place mutation reaches the same store without an `=`.
    for match in re.finditer(
            r"Config\.options\.([A-Za-z0-9_.?]+?)\.(push|splice|pop|shift|unshift)\(",
            text):
        if not path_allowed(match.group(1)):
            found.append(
                f"{name}: mutates Config.options.{match.group(1)} in place")

    # setNestedValue: the path must be a literal, and an allowed one.
    for match in re.finditer(r"Config\.setNestedValue\(\s*([^\s,)]+)", text):
        argument = match.group(1)
        literal = re.fullmatch(r"[\"']([^\"']+)[\"']", argument)
        if not literal:
            found.append(
                f"{name}: setNestedValue with a computed path ({argument})")
            continue
        if not path_allowed(literal.group(1)):
            found.append(f"{name}: setNestedValue writes {literal.group(1)}")

    # setOption: the key must be a literal in the mode's three.
    for match in re.finditer(
            r"PluginState\.setOption\(\s*[^,]+,\s*([^\s,)]+)", text):
        argument = match.group(1)
        literal = re.fullmatch(r"[\"']([^\"']+)[\"']", argument)
        if not literal:
            found.append(f"{name}: setOption with a computed key ({argument})")
            continue
        if literal.group(1) not in ALLOWED_OPTION_KEYS:
            found.append(f"{name}: setOption writes {literal.group(1)}")

    return found


def edit_mode_files() -> list:
    # .js as well as .qml: a helper library under the mode's directory writes
    # through exactly the same singletons, and a sweep that reads only QML is
    # an invitation to move the write one file sideways.
    files = []
    for directory in EDIT_MODE_DIRS:
        files.extend(sorted(directory.rglob("*.qml")))
        files.extend(sorted(directory.rglob("*.js")))
    return files


class EditModeScopeLint(unittest.TestCase):
    def test_the_sweep_still_finds_the_edit_mode_files(self):
        files = edit_mode_files()
        self.assertGreaterEqual(
            len(files), 4,
            "the edit-mode directory moved out from under this lint - a sweep "
            "over nothing is green forever")

    def test_every_write_in_the_mode_is_placement_span_or_presence(self):
        problems = []
        for path in edit_mode_files():
            problems.extend(
                violations_in(str(path.relative_to(ROOT)), path.read_text()))
        self.assertEqual(problems, [])

    # ---- the detector, proven against fixtures -------------------------------

    def test_the_detector_flags_a_settings_write(self):
        fixture = 'Config.options.appearance.transparency.enable = true\n'
        self.assertEqual(len(violations_in("fixture", fixture)), 1)

    def test_the_detector_flags_an_in_place_mutation(self):
        fixture = 'Config.options.bar.autoHide.pinnedApps.push(id)\n'
        self.assertEqual(len(violations_in("fixture", fixture)), 1)

    def test_the_detector_flags_a_nested_write_outside_the_allowlist(self):
        fixture = 'Config.setNestedValue("bar.autoHide.enable", false)\n'
        self.assertEqual(len(violations_in("fixture", fixture)), 1)

    def test_the_detector_flags_a_computed_path_or_key(self):
        fixture = ('Config.setNestedValue(somePath, value)\n'
                   'PluginState.setOption(id, someKey, value)\n')
        self.assertEqual(len(violations_in("fixture", fixture)), 2)

    def test_the_detector_flags_a_host_option_outside_the_modes_three(self):
        fixture = 'PluginState.setOption(manifest.id, "blurEnabled", true)\n'
        self.assertEqual(len(violations_in("fixture", fixture)), 1)

    def test_the_detector_flags_a_compound_assignment(self):
        fixture = ('Config.options.appearance.fakeDarkMode.wallpaperDetect += 1\n'
                   'Config.options.bar.autoHide.enable ||= true\n')
        self.assertEqual(len(violations_in("fixture", fixture)), 2)

    def test_the_detector_flags_a_bracket_access(self):
        fixture = 'Config.options["appearance"].transparency.enable = false\n'
        self.assertEqual(len(violations_in("fixture", fixture)), 1)

    def test_the_detector_accepts_the_sanctioned_writes(self):
        fixture = (
            'Config.setNestedValue("plugins.enabled", next)\n'
            'Config.options.plugins.enabled = next\n'
            'Config.setNestedValue("dock.pinnedApps", apps)\n'
            'Config.setNestedValue("lock.showWidgets", true)\n'
            'Config.options.lock.islands.left = next\n'
            'PluginState.setOption(id, "positionLocked", true)\n'
            'PluginState.setOption(id, "__gridSize", "2x1")\n'
            'PluginState.setPosition(id, screen, { x: 0, y: 0 })\n'
            'if (Config.options.plugins.enabled.includes(id)) return\n'
            'readonly property bool on: Config.options.background.showGrid === true\n')
        self.assertEqual(violations_in("fixture", fixture), [])


if __name__ == "__main__":
    unittest.main()
