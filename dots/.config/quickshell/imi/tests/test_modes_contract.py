#!/usr/bin/env python3
"""Modes & Routines (ported from the p3drovfx fork): the wiring the shell
reads, pinned.

The engine keeps its applied state in Persistent (a config reset never
strands an applied mode) and its definitions in Config; the surfaces that
show a mode - the bar pill, the two quick-panel toggles, the overlay, the
settings page, the keybind - are all wired; the pill is built on the record
indicator's grammar, not the fork's shared cards; the schema and the action
runner agree, and nothing left behind by the port (screen shaders, keyboard
backlight, earbuds, sounds, workspace profiles, calendar) is still named.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "modules/common/Config.qml"
PERSISTENT = ROOT / "modules/common/Persistent.qml"
MODES = ROOT / "services/Modes.qml"
SCHEMA = ROOT / "services/modes/ModeSchema.js"
ACTIONS = ROOT / "services/modes/ModeActions.qml"
PILL = ROOT / "modules/imi/bar/ModeIndicator.qml"
PILL_CARD = ROOT / "modules/imi/bar/ModeIndicatorPopup.qml"
RECORD = ROOT / "modules/imi/bar/RecordIndicator.qml"
TOGGLE = ROOT / "modules/common/models/quickToggles/ModesToggle.qml"
CLASSIC = ROOT / "modules/imi/sidebarRight/quickToggles/ClassicQuickPanel.qml"
ANDROID = ROOT / "modules/imi/sidebarRight/quickToggles/AndroidQuickPanel.qml"
CHOOSER = ROOT / "modules/imi/sidebarRight/quickToggles/androidStyle/AndroidToggleDelegateChooser.qml"
FAMILY = ROOT / "panelFamilies/ImmaterialImpulseFamily.qml"
SHELL = ROOT / "shell.qml"
PAGE = ROOT / "modules/imi/settings/pages/ModesConfig.qml"
INDEX = ROOT / "modules/imi/settings/SettingsContent.qml"
CATALOGUE = ROOT / "modules/common/plugins/BarWidgets.qml"
KEYBINDS = ROOT.parents[1] / "hypr/hyprland/keybinds.lua"
MODES_UI = ROOT / "modules/imi/modes"

DROPPED = ["screenShader", "keyboardBacklight", "earbudsAnc", "playSound", "workspaceProfile",
           "dnsOverTls", "CalendarCondition", "TriggerCalendar", "ActionSound",
           # the bare type strings and section headers too - a normaliser has no
           # whitelist, so a `case "calendar":` keeps a trigger the engine cannot run
           '"calendar"', "earbuds:", "lock pill"]
RULES = ROOT.parents[1] / "hypr/hyprland/rules.lua"
RESOURCE_USAGE = ROOT / "services/ResourceUsage.qml"
GAME_DETECTOR = ROOT / "services/GameDetector.qml"
LID = ROOT / "services/modes/conditions/LidCondition.qml"
CONTENT = MODES_UI / "ModesContent.qml"
OVERLAY = MODES_UI / "ModesOverlay.qml"


def _strip(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


class ModesContract(unittest.TestCase):
    def test_state_lives_in_persistent_and_definitions_in_config(self):
        cfg = _strip(CONFIG.read_text())
        block = cfg[cfg.index("property JsonObject modes: JsonObject {"):]
        for key in ("property bool enable: true", "property bool overlayEnabled: true",
                    "property bool presetsSeeded: false", "property int graceSec: 20",
                    "property list<var> modes: []", "property list<var> routines: []",
                    "property JsonObject game: JsonObject {"):
            self.assertIn(key, block[:2000], key)
        per = _strip(PERSISTENT.read_text())
        pblock = per[per.index("property JsonObject modes: JsonObject {"):]
        for key in ("property string activeId", "property real activeSince", "property list<var> snapshot",
                    "property list<var> history", "property list<var> routineRuns", "property list<var> pendingSteps"):
            self.assertIn(key, pblock[:1500], key)
        modes = _strip(MODES.read_text())
        self.assertIn("readonly property var state: Persistent.states.modes", modes)
        self.assertIn('IpcHandler', modes)
        self.assertIn('target: "modes"', modes)

    def test_every_surface_is_wired(self):
        self.assertIn("Modes.ready", SHELL.read_text(), "the engine runs whether or not a UI is open")
        fam = FAMILY.read_text()
        self.assertIn("PanelLoader { component: ModesOverlay {} }", fam)
        self.assertIn("import qs.modules.imi.modes", fam)
        self.assertIn('{ id: "modeIndicator",', CATALOGUE.read_text(), "the bar pill is a layout widget by id")
        self.assertIn("QuickToggleButton { toggleModel: ModesToggle {} }", _strip(CLASSIC.read_text()))
        self.assertIn('"modes"', ANDROID.read_text(), "the Android panel offers the tile")
        self.assertIn('roleValue: "modes"', CHOOSER.read_text())
        self.assertIn('hl.dsp.global("quickshell:modesToggle")', KEYBINDS.read_text())
        self.assertIn('name: "modesToggle"', (MODES_UI / "ModesOverlay.qml").read_text(), "the GlobalShortcut the keybind dispatches to")
        index = INDEX.read_text()
        self.assertIn('id: "modes", icon: "tune", component: Qt.resolvedUrl("pages/ModesConfig.qml")', index)

    def test_the_pill_is_the_record_indicators_grammar(self):
        pill = _strip(PILL.read_text())
        record = _strip(RECORD.read_text())
        for line in ("visible: implicitWidth > 0",
                     "anchors.verticalCenterOffset: root.vertical ? 0 : Appearance.sizes.barStandalonePillOffset",
                     "radius: Appearance.rounding.full",
                     "opacity: root.shown ? (root.containsMouse ? 0.88 : 1) : 0",
                     "scale: root.shown ? 1 : 0.7"):
            self.assertIn(line, pill, line)
            self.assertIn(line, record, f"the grammar's own source moved: {line}")
        self.assertIn("Behavior on implicitWidth {\n        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)", pill)
        for fork_only in ("qs.modules.imi.bar.shared", "shared/cards", "HeroCard", "toggleVisible", "toggleHighlight"):
            self.assertNotIn(fork_only, PILL.read_text(), f"fork-only dependency left in the pill: {fork_only}")
        self.assertIn("ModeIndicatorPopup {\n        hoverTarget: root\n    }", pill)
        card = _strip(PILL_CARD.read_text())
        self.assertIn("StyledPopup {", card)
        self.assertNotRegex(card, r"^\s*pinnedOpen: true\s*$", "a card pinned open at birth (a capture aid that leaked into a commit once)")
        self.assertIn("MaterialShapeWrappedMaterialSymbol {", card, "the card's hero is the bar popups' shaped glyph")
        self.assertNotRegex(card, r"^\s*(spacing|implicitHeight|Layout\.preferredHeight): \d+\s*$", "no raw pixel sizes on the card")
        self.assertIn("Modes.deactivate(\"manual\")", pill)
        self.assertIn("GlobalStates.modesOpen = !GlobalStates.modesOpen", pill)

    def test_the_toggle_is_the_shared_model(self):
        toggle = _strip(TOGGLE.read_text())
        self.assertIn("QuickToggleModel {", toggle)
        self.assertIn("toggled: Modes.active", toggle)
        self.assertIn("Modes.toggleLast()", toggle)

    def test_the_schema_and_the_runner_agree_and_nothing_dropped_remains(self):
        schema = SCHEMA.read_text()
        actions = _strip(ACTIONS.read_text())
        registry = actions[actions.index("readonly property var registry: ({"):]
        runner_ids = set(re.findall(r"^        (\w+): \{$", registry, re.M))
        preset_types = set(re.findall(r'type: "(\w+)"', schema))
        trigger_types = set(re.findall(r"^    (\w+): \{", schema[schema.index("var TRIGGER_TYPES = {"):], re.M))
        unknown = sorted(t for t in preset_types if t not in runner_ids and t not in trigger_types)
        self.assertEqual(unknown, [], f"presets/templates name types neither the runner nor the triggers know: {unknown}")
        # Un-stripped on purpose: a leftover section header or docstring line
        # is a leftover too.
        everything = SCHEMA.read_text() + ACTIONS.read_text() + "".join(p.read_text() for p in MODES_UI.rglob("*.qml")) + MODES.read_text()
        for name in DROPPED:
            self.assertNotIn(name, everything, f"dropped in the port but still named: {name}")
        self.assertFalse((ROOT / "services/modes/conditions/CalendarCondition.qml").exists())

    def test_the_editor_is_built_from_the_shells_controls(self):
        """A StyledSwitch beside a label, or a bare segmented choice, is the fork kit growing back."""
        # A bare StyledSwitch is allowed only where it IS the value: a
        # section header's master switch, an action's own on/off value, a
        # list row's enable. Everything with a label beside it is ConfigSwitch.
        allowed = {"ModeEditor.qml": 1, "RoutineEditor.qml": 1, "ActionRow.qml": 1, "ModeListRow.qml": 1}
        for path in MODES_UI.rglob("*.qml"):
            n = _strip(path.read_text()).count("StyledSwitch {")
            self.assertLessEqual(n, allowed.get(path.name, 0), f"{path.name}: {n} bare StyledSwitch(es); a labelled switch row is ConfigSwitch")
        # A segmented choice standing on its own in a form is labelled (the
        # settings grammar: label left, chips right); only one that shares
        # its line with another control (Layout.fillWidth: false) may not be.
        for path in (MODES_UI / "forms").glob("*.qml"):
            code = _strip(path.read_text())
            for m in re.finditer(r"FormChoice \{", code):
                i, depth = m.end(), 1
                while depth:
                    depth += (code[i] == "{") - (code[i] == "}")
                    i += 1
                block = code[m.start():i]
                if "Layout.fillWidth: false" in block:
                    continue
                self.assertRegex(block, r"\n\s*text:", f"{path.name}: a segmented choice on its own line has no label")
        # A hand-rolled pill field: the shell's field is EditorField.
        for path in MODES_UI.rglob("*.qml"):
            if path.name in ("ToolbarTextField.qml",):
                continue
            code = _strip(path.read_text())
            self.assertNotRegex(code, r"border\.width: \w+\.activeFocus", f"{path.name} draws its own focus ring; use EditorField")

    def test_settings_page_grammar(self):
        page = PAGE.read_text()
        self.assertIn("forceWidth: true", page, "every settings page takes the standard width; the notice's unwrapped text otherwise sized the column")
        self.assertNotIn("StyledToolTip", page, "rows explain themselves through description/infoText, not floating tooltips")
        self.assertIn("ContentSection {", page)
        self.assertIn("GroupedList {", page)
        self.assertIn('Config.options.modes.enable = !Config.options.modes.enable', page)
        self.assertIn('"modeIndicator"', page, "the bar switch edits the layout's widget id")
        self.assertNotIn("WindowDialog", page)


    def test_idle_cost_and_the_documented_traps(self):
        # The GPU heuristic's demand signal has a producer.
        ru = _strip(RESOURCE_USAGE.read_text())
        self.assertIn("function requestGpuMonitoring(on)", ru)
        self.assertIn("if (gpuMonitoringRequests > 0) return true;", ru)
        self.assertIn("ResourceUsage.requestGpuMonitoring(root.gpuRequested)", _strip(GAME_DETECTOR.read_text()))
        # A kernel file is read through a FileView, on the slow tier, only while armed.
        lid = _strip(LID.read_text())
        self.assertIn("FileView {", lid)
        self.assertIn("running: root.armed && root.statePath.length > 0", lid)
        self.assertNotRegex(lid, r"interval: [1-9]\d{0,3}\s*$", "a lid poll faster than a minute")
        # Automation off tears the watcher tree down.
        modes = _strip(MODES.read_text())
        self.assertEqual(modes.count("model: root.ready && root.enabled ? root."), 2)
        # The page loaders keep themselves through a written flag, never `item !== null`.
        content = _strip(CONTENT.read_text())
        self.assertNotIn("item !== null", content)
        self.assertEqual(content.count("onLoaded: built = true"), 3)
        # The manager's surface is exit-owned; no Timer holds it.
        overlay = _strip(OVERLAY.read_text())
        self.assertIn("active: root.reallyOpen", overlay)
        self.assertIn("onFinished: root.reallyOpen = false", overlay)
        self.assertNotRegex(overlay, r"interval: 400")
        self.assertNotIn("isHovered", overlay)
        for path in MODES_UI.rglob("*.qml"):
            self.assertNotRegex(_strip(path.read_text()), r"Easing\.(Out|In)\w*|duration: \d", f"raw motion in {path.name}")
        # The input regions agree with what is painted: the manager's mask
        # follows the flag (a leaving surface never eats a click), the
        # banner's mask is the banner's own box.
        self.assertIn("item: GlobalStates.modesOpen ? modesInputMask : null", overlay)
        flash = _strip((MODES_UI / "ModeFlashPopupContent.qml").read_text())
        self.assertIn("id: staticMaskTarget\n        anchors.fill: contentBackground", flash)
        self.assertNotRegex("".join(_strip(p.read_text()) for p in MODES_UI.rglob("*.qml")), r"border\.width: \d", "raw border widths")
        # Both minted namespaces carry their compositor rules.
        rules = RULES.read_text()
        for ns in ("quickshell:modes", "quickshell:modeFlashPopup"):
            self.assertIn(f'namespace = "{ns}" }}, no_anim = true', rules, ns)
            self.assertIn(f'namespace = "{ns}" }}, blur = false', rules, ns)
        self.assertIn("WindowBlurRegion {", overlay)
        # Role tokens, never the raw palette, in the ported UI.
        for path in list(MODES_UI.rglob("*.qml")) + [PILL, PILL_CARD, PAGE]:
            self.assertNotIn("m3colors.", _strip(path.read_text()), f"{path.name} reads the raw palette")
        self.assertNotIn("colErrorContainer", _strip(PILL_CARD.read_text()), "ending a mode is not an error")


if __name__ == "__main__":
    unittest.main()
