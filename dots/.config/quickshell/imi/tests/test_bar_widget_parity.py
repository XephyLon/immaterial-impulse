#!/usr/bin/env python3
"""The two bars resolve a widget to a file the same way, or the suite reddens.

The horizontal bar and the vertical bar draw the same `Config.options.bar.
layouts.*` out of the same `modules/imi/bar/` directory, and each used to carry
its own `getWidgetUrl`. Only the horizontal one ever learned the `plugin:`
branch 2a3801a62 ("feat(plugins): support installable QML packages") added, so
a layout holding `plugin:docker_plugin` reached the vertical bar's fallback -
which capitalises a widget name into a file name, and produced
`Plugin:docker_plugin.qml`. Measured with a `qml6` probe: `Loader.status` 3
(`Loader.Error`), `item` null, and one `No such file or directory` line per
widget - not a `WARN scene:` and not an `ERROR:`, so the configuration still
loaded and the bar simply drew the empty BarGroup stub around nothing
(an empty group collapses entirely now, so not even that shows).

The defect class is not the missing branch, it is that a capability could be
added to one bar and not the other at all. So the resolution is one module,
`modules/imi/bar/bar_widget_source.js` (behaviour pinned by
`tst_bar_widget_source.qml`), and these checks are what stop a second copy
growing back:

  - each bar's `getWidgetUrl` must ASK the module, not decide anything itself;
  - the two bodies must be identical once the directory literal - the one
    thing that legitimately differs, since the two bars sit at different depths
    - is normalised away. Any divergence in the kinds they support is a
    divergence in that text;
  - the same for the layout filter, which carried the second copy of "is this a
    plugin, and is it still enabled";
  - and every file name the module can name must exist, which is the check that
    would have caught the original bug from the other end.

Nothing here reads raw file text: `_qml_source` blanks comments and matches
braces, for the reason recorded in `test_background_fullscreen_suppression.py`
- a text pattern over QML decays into one that matches nothing after a reformat,
and a comment mentioning the word being grepped for defeats it outright.
"""
import re
import unittest
from pathlib import Path

from test_background_fullscreen_suppression import _qml_source

ROOT = Path(__file__).resolve().parents[1]
BAR_DIR = ROOT / "modules/imi/bar"
HORIZONTAL = BAR_DIR / "BarContent.qml"
VERTICAL = ROOT / "modules/imi/verticalBar/VerticalBarContent.qml"
MODULE = BAR_DIR / "bar_widget_source.js"

MODULE_NAMESPACE = "BarWidgetSource"

# A relative directory literal: `"./"`, `"../bar/"`. The only part of the two
# resolutions that is allowed to differ.
_DIR_LITERAL = re.compile(r'"[^"\n]*/"')

# `"DockerPlugin.qml"` on the right of a `:` or an `=` in the shared module.
_COMPONENT_LITERAL = re.compile(r'"([A-Za-z][\w.-]*\.qml)"')

# A call to the shared enabled rule, whatever it is handed.
_SHARED_ENABLED_CALL = re.compile(
    re.escape(MODULE_NAMESPACE) + r"\.isDisabledPlugin\([^()]*\)")

# What a bar must not spell for itself any more - each is one half of a copy
# that had already drifted once.
_OWN_DECISION = (
    ("plugin:", "the plugin layout-token prefix"),
    ("charAt(0).toUpperCase()", "the widget-name capitalisation"),
    (".substring(7)", "the hardcoded plugin-prefix length"),
)


def _normalised(body):
    """A function body with its directory literal and layout collapsed."""
    return " ".join(_DIR_LITERAL.sub('"<dir>"', body).split())


class BarWidgetResolutionParityTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.bars = {}
        for label, path in (("horizontal", HORIZONTAL), ("vertical", VERTICAL)):
            qml = _qml_source(path)
            assert qml.unclosed == 0, (
                f"unbalanced braces in {path} - the pins below would silently "
                f"stop covering anything.")
            cls.bars[label] = (path, qml)

    def _function_body(self, label, name):
        path, qml = self.bars[label]
        body = qml.function_body(name)
        self.assertIsNotNone(
            body, f"{path} declares no `function {name}` - the pins below "
                  f"cover nothing without it.")
        return body

    def test_both_bars_import_the_shared_resolver(self):
        for label, (path, qml) in self.bars.items():
            imports = re.findall(
                r'^\s*import\s+"([^"]+)"\s+as\s+(\w+)\s*$', qml.text, re.M)
            resolved = {
                (path.parent / target).resolve(): alias
                for target, alias in imports
            }
            self.assertIn(
                MODULE.resolve(), resolved,
                f"the {label} bar does not import {MODULE.name}; it is "
                f"resolving widget files on its own again.")
            self.assertEqual(
                resolved[MODULE.resolve()], MODULE_NAMESPACE,
                f"the {label} bar imports {MODULE.name} under a different "
                f"namespace, so the pins below cannot see the call sites.")

    def test_neither_bar_decides_a_widget_kind_for_itself(self):
        for label in self.bars:
            body = self._function_body(label, "getWidgetUrl")
            self.assertIn(
                f"{MODULE_NAMESPACE}.fileNameFor", body,
                f"the {label} bar's getWidgetUrl does not ask "
                f"{MODULE.name} which file draws the widget.")
            for token, what in _OWN_DECISION:
                self.assertNotIn(
                    token, body,
                    f"the {label} bar's getWidgetUrl spells {what} itself - "
                    f"that is the second copy this module replaced, and the "
                    f"copy the other bar will not get.")

    def test_the_two_bars_resolve_a_widget_identically(self):
        horizontal = _normalised(self._function_body("horizontal", "getWidgetUrl"))
        vertical = _normalised(self._function_body("vertical", "getWidgetUrl"))
        self.assertEqual(
            horizontal, vertical,
            "the two bars' widget-url resolution has diverged. Everything "
            "except the directory each bar reaches modules/imi/bar/ by must "
            "be the same text, or one bar supports a kind of widget the other "
            "does not.\n"
            f"  horizontal: {horizontal}\n"
            f"  vertical:   {vertical}")

    def test_both_bars_drop_a_disabled_plugin_through_the_shared_rule(self):
        # Scoped to the enabled decision rather than to every mention of the
        # prefix: the horizontal bar's `suppressDockerForMemoryTest` hook names
        # one specific layout token on purpose, which is a fact about Docker
        # and not a rule about what a plugin id is.
        for label in self.bars:
            body = self._function_body(label, "filterLayout")
            self.assertIn(
                f"{MODULE_NAMESPACE}.isDisabledPlugin", body,
                f"the {label} bar's filterLayout does not ask {MODULE.name} "
                f"whether a layout entry is a disabled plugin - a plugin the "
                f"user switched off would keep its bar slot.")
            residue = _SHARED_ENABLED_CALL.sub("", body)
            self.assertNotIn(
                "plugins.enabled", residue,
                f"the {label} bar's filterLayout reads plugins.enabled outside "
                f"{MODULE_NAMESPACE}.isDisabledPlugin - that is the second copy "
                f"of the rule, and the copy the other bar will not get.")
            self.assertNotIn(
                ".substring(", residue,
                f"the {label} bar's filterLayout takes a plugin id apart "
                f"itself; ask {MODULE_NAMESPACE}.pluginIdOf.")

    def test_every_component_the_resolver_can_name_exists(self):
        # The original bug was a resolution to a file that is not there, which
        # a Loader reports as one easily-missed log line. Read the names the
        # module can produce back off disk.
        source = MODULE.read_text()
        named = sorted(set(_COMPONENT_LITERAL.findall(source)))
        self.assertGreaterEqual(
            len(named), 3,
            f"{MODULE.name} names {named}, which is fewer components than the "
            f"two native plugin widgets plus the package host - the pin below "
            f"has stopped covering the mapping.")
        for component in named:
            self.assertTrue(
                (BAR_DIR / component).is_file(),
                f"{MODULE.name} can resolve a bar widget to {component}, which "
                f"does not exist in {BAR_DIR.relative_to(ROOT)} - both bars "
                f"would draw an empty group and log one 'No such file or "
                f"directory' line per widget.")

    def test_every_palette_id_resolves_to_a_file(self):
        """The other direction: not what the resolver can NAME, what the
        user can PICK. Settings > Bar offers every id in BarWidgets.qml, a
        layout stores it, and both bars resolve it through fileNameFor - so
        an id whose file is gone is a widget that silently vanishes from
        every bar that has it. e2f25db06 deleted LeftSidebarButton.qml and
        PowerButton.qml as orphans 'nothing named'; the maintainer's own
        layout named both, and the only trace was one WARN line per reload."""
        palette = (ROOT / "modules/common/plugins/BarWidgets.qml").read_text()
        ids = re.findall(r'\{\s*id:\s*"([A-Za-z]+)"', palette)
        self.assertGreaterEqual(len(ids), 20, "the palette lost most of its rows")
        missing = []
        for widget_id in ids:
            component = widget_id[0].upper() + widget_id[1:] + ".qml"
            if not (BAR_DIR / component).is_file():
                missing.append(f"{widget_id} -> {component}")
        self.assertEqual(missing, [], "\n".join([
            "Settings > Bar offers these, and no file draws them:",
            *(f"  {entry}" for entry in missing),
        ]))


if __name__ == "__main__":
    unittest.main()
