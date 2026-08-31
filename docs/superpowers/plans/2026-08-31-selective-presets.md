# Selective Preset Application Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply opens a popup that applies the whole preset by default and lets the user apply only chosen groups, with `apps.*` launch commands never applied unasked.

**Architecture:** One partition table (`preset_groups.js`, pure JS) is read by the popup for rows and resolved into concrete section names passed to `presets.sh --apply <name> --only <spec,...>`, which jq-filters the preset before the existing, unchanged merge. Spec: `docs/superpowers/specs/2026-08-31-selective-presets-design.md`.

**Tech Stack:** QML (Quickshell), bash + jq, qmltestrunner, python unittest. All paths below are relative to `dots/.config/quickshell/imi/` unless they start with `docs/`.

**Conventions that bind every task:** commit with `git commit --only -F - -- <paths>` (new files need `git add -N` first); no Claude/agent attribution; comments explain *why*; run only the named tests, never `run_tests.sh` (suite is parked by the maintainer).

---

### Task 1: the partition table

**Files:**
- Create: `modules/common/functions/preset_groups.js`
- Test: `tests/tst_preset_groups.qml`

- [ ] **Step 1: Write the failing test**

`tests/tst_preset_groups.qml`:

```qml
import QtTest
import "../modules/common/functions/preset_groups.js" as Groups

// The Apply popup's partition. One table, read by the popup for rows and
// resolved into the --only list presets.sh consumes. The commands group is
// the injection fence: `apps.*` are shell-executed strings, and with online
// presets planned they must never apply unasked.
TestCase {
    name: "PresetGroupsTest"

    // A trimmed real preset's shape (Bench.json, 2026-08-31).
    readonly property var preset: ({
        _presetMeta: { description: "x" },
        _pluginState: { version: 2 },
        appearance: { palette: {}, fonts: {}, clock: {}, iconTheme: "a",
                      transparency: {}, mediaWidget: {}, terminal: {} },
        apps: { terminal: "kitty -1" },
        background: {}, bar: {}, dock: {}, sidebar: {}, tray: {},
        light: {}, plugins: {}, policies: {}, sounds: {}, time: {}
    })

    function test_every_group_exists_and_commands_is_the_only_default_off() {
        const offByDefault = Groups.GROUPS.filter(g => !g.defaultOn);
        compare(offByDefault.length, 1);
        compare(offByDefault[0].id, "commands");
        verify(Groups.GROUPS.some(g => g.id === "rest"), "the implicit remainder group");
    }

    function test_every_preset_key_is_claimed_exactly_once() {
        // `rest` claims what nothing else does, so nothing can escape the
        // popup - but no key may be claimed twice either.
        for (const key in preset) {
            if (key === "_presetMeta") continue; // metadata never applies
            const owners = Groups.GROUPS.filter(g =>
                Groups.sectionsOfGroup(g.id, preset).some(s => s === key || s.startsWith(key + ":")));
            compare(owners.length >= 1, true, key + " unclaimed");
        }
        compare(Groups.groupOf("apps"), "commands");
        compare(Groups.groupOf("policies"), "rest", "unlisted keys land in rest");
        compare(Groups.groupOf("appearance.palette"), "theming");
        compare(Groups.groupOf("appearance.clock"), "widgets");
    }

    function test_sections_for_resolves_groups_to_script_specs() {
        const all = Groups.sectionsFor(preset, Groups.GROUPS.map(g => g.id));
        verify(all.includes("apps"), "commands included when its group is chosen");
        verify(all.includes("_pluginState"), "widgets brings the plugin state");
        verify(all.includes("appearance:palette"), "partial appearance spelled with a colon");
        const noWidgets = Groups.sectionsFor(preset,
            Groups.GROUPS.map(g => g.id).filter(id => id !== "widgets"));
        verify(!noWidgets.includes("_pluginState"));
        verify(!noWidgets.includes("appearance:clock"));
        const noCommands = Groups.sectionsFor(preset,
            Groups.GROUPS.map(g => g.id).filter(id => id !== "commands"));
        verify(!noCommands.includes("apps"));
    }

    function test_counts_reflect_what_the_preset_actually_holds() {
        const counts = Groups.presentCounts(preset);
        verify(counts.wallpaper >= 1, "background is in this preset");
        compare(counts.fonts >= 2, true, "fonts + iconTheme + terminal");
        const empty = Groups.presentCounts({ background: {} });
        compare(empty.commands, 0, "no apps section, disabled row");
    }
}
```

- [ ] **Step 2: Run it — must fail**

Run: `cd dots/.config/quickshell/imi && QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_preset_groups.qml`
Expected: compile FAIL (preset_groups.js missing).

- [ ] **Step 3: Write `modules/common/functions/preset_groups.js`**

```js
.pragma library

// The Apply popup's partition of a preset, and the resolver that turns a
// selection into `presets.sh --only` specs. ONE table: the popup reads it
// for rows, the resolver reads it for the script, so the two cannot drift.
//
// A spec is either a top-level config key ("background"), an appearance
// subsection spelled "appearance:<sub>" (the script deep-merges those over
// the live appearance rather than replacing it), or "_pluginState".
//
// The commands group is the injection fence (spec 2026-08-31): apps.* are
// shell-executed strings, so with online presets planned they are NEVER
// preselected, and "select all" means "all but commands".

var GROUPS = [
    { id: "wallpaper", icon: "wallpaper", label: "Wallpaper & background",
      defaultOn: true, sections: ["background", "wallpaperSelector"] },
    { id: "theming", icon: "palette", label: "Colors & theming",
      defaultOn: true, sections: ["appearance.palette", "appearance.autoTheme",
        "appearance.wallpaperTheming", "appearance.transparency",
        "appearance.extraBackgroundTint", "appearance.fakeScreenRounding", "light"] },
    { id: "fonts", icon: "text_fields", label: "Fonts & icons",
      defaultOn: true, sections: ["appearance.fonts", "appearance.iconTheme",
        "appearance.clockFonts", "appearance.terminal"] },
    { id: "panels", icon: "toolbar", label: "Bar, dock & sidebars",
      defaultOn: true, sections: ["bar", "dock", "sidebar", "tray", "osd",
        "overview", "panelFamily"] },
    { id: "widgets", icon: "widgets", label: "Desktop widgets",
      defaultOn: true, sections: ["_pluginState", "plugins", "appearance.clock",
        "appearance.atAGlance", "appearance.mediaWidget", "appearance.currencyWidget",
        "appearance.weatherWidget", "appearance.systemMonitor", "appearance.openrgb",
        "appearance.motion", "appearance.lyrics"] },
    { id: "rest", icon: "tune", label: "Everything else",
      defaultOn: true, sections: [] },   // implicit: whatever nothing claims
    { id: "commands", icon: "terminal", label: "App launch commands",
      defaultOn: false, sections: ["apps"] }
];

function _claimed() {
    var map = {};
    for (var i = 0; i < GROUPS.length; i++)
        for (var j = 0; j < GROUPS[i].sections.length; j++)
            map[GROUPS[i].sections[j]] = GROUPS[i].id;
    return map;
}

// "background" -> "wallpaper"; "appearance.palette" -> "theming"; a key no
// group names -> "rest", so a future config section cannot escape the popup.
function groupOf(sectionKey) {
    var claimed = _claimed();
    if (claimed[sectionKey] !== undefined) return claimed[sectionKey];
    if (sectionKey.indexOf("appearance.") === 0) return "rest";
    return "rest";
}

// The keys a preset holds for one group, spelled as sections. For `rest`
// that is every unclaimed top-level key plus every unclaimed appearance
// subsection - _presetMeta never applies and is nobody's.
function sectionsOfGroup(groupId, preset) {
    var claimed = _claimed();
    var out = [];
    var group = null;
    for (var i = 0; i < GROUPS.length; i++)
        if (GROUPS[i].id === groupId) group = GROUPS[i];
    if (!group) return out;
    if (groupId !== "rest") {
        for (var j = 0; j < group.sections.length; j++) {
            var section = group.sections[j];
            if (section === "_pluginState") {
                if (preset && preset._pluginState !== undefined) out.push("_pluginState");
            } else if (section.indexOf("appearance.") === 0) {
                var sub = section.slice("appearance.".length);
                if (preset && preset.appearance && preset.appearance[sub] !== undefined)
                    out.push("appearance:" + sub);
            } else if (preset && preset[section] !== undefined) {
                out.push(section);
            }
        }
        return out;
    }
    for (var key in (preset || {})) {
        if (key === "_presetMeta" || key === "_pluginState") continue;
        if (key === "appearance") {
            for (var subKey in preset.appearance)
                if (claimed["appearance." + subKey] === undefined)
                    out.push("appearance:" + subKey);
            continue;
        }
        if (claimed[key] === undefined) out.push(key);
    }
    return out;
}

// The --only list for a selection: concrete, present-in-this-preset specs.
function sectionsFor(preset, selectedGroupIds) {
    var out = [];
    for (var i = 0; i < (selectedGroupIds || []).length; i++) {
        var sections = sectionsOfGroup(selectedGroupIds[i], preset);
        for (var j = 0; j < sections.length; j++)
            if (out.indexOf(sections[j]) === -1) out.push(sections[j]);
    }
    return out;
}

// { groupId: how many of its sections this preset holds } - the popup's
// subtitles, and its disabled state for absent groups.
function presentCounts(preset) {
    var counts = {};
    for (var i = 0; i < GROUPS.length; i++)
        counts[GROUPS[i].id] = sectionsOfGroup(GROUPS[i].id, preset).length;
    return counts;
}
```

- [ ] **Step 4: Run the test — must pass**

Same command as Step 2. Expected: `Totals: 4 passed`.

- [ ] **Step 5: Commit**

```bash
cd ~/dev/imi-unify
git add -N dots/.config/quickshell/imi/modules/common/functions/preset_groups.js \
  dots/.config/quickshell/imi/tests/tst_preset_groups.qml
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/common/functions/preset_groups.js \
  dots/.config/quickshell/imi/tests/tst_preset_groups.qml <<'MSG'
feat(presets): the Apply popup's partition table

One table for the selective-apply popup and the --only resolver both
(spec docs/superpowers/specs/2026-08-31-selective-presets-design.md):
six ordinary groups, the never-preselected commands group as the
apps.* injection fence, and `rest` claiming every key nothing else
does so a future config section cannot escape the popup.
MSG
```

---

### Task 2: `presets.sh --only`

**Files:**
- Modify: `scripts/presets.sh` (the `--apply` case, lines ~89–170)
- Test: `tests/test_presets_apply_only.py` (new)

- [ ] **Step 1: Write the failing test**

`tests/test_presets_apply_only.py`:

```python
#!/usr/bin/env python3
"""presets.sh --apply --only applies exactly the named sections.

Runs the real script in a temp HOME (the test_presets.py harness pattern:
copied script beside stub helpers, so $0-derived paths resolve there).
The fence assertion is the one that matters: `apps` survives untouched
unless named, whatever else is applied.
"""
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PRESETS = ROOT / "scripts/presets.sh"


def harness(directory):
    home = Path(directory)
    config_dir = home / ".config/immaterial-impulse"
    script_dir = home / ".config/quickshell/imi/scripts"
    (script_dir / "colors").mkdir(parents=True)
    config_dir.mkdir(parents=True)
    (script_dir / "colors/switchwall.sh").write_text("#!/usr/bin/env bash\nexit 0\n")
    (script_dir / "colors/switchwall.sh").chmod(0o755)
    script = script_dir / "presets.sh"
    shutil.copy(PRESETS, script)
    script.chmod(0o755)
    live = {
        "background": {"wallpaperPath": "/live.jpg"},
        "appearance": {"palette": {"type": "auto"}, "fonts": {"main": "LiveFont"},
                        "clock": {"style": "cookie"}},
        "apps": {"terminal": "live-terminal"},
        "bar": {"cornerStyle": 0},
        "sounds": {"enable": True},
        "wallpaperSelector": {"wallpaperEngine": {"activePath": ""}},
    }
    preset = {
        "_presetMeta": {"description": "d"},
        "_pluginState": {"version": 2, "pluginOptions": {"notes": {"blurEnabled": True}}},
        "background": {"wallpaperPath": "/preset.jpg"},
        "appearance": {"palette": {"type": "scheme-neutral"}, "fonts": {"main": "PresetFont"},
                        "clock": {"style": "digital"}},
        "apps": {"terminal": "evil --rm -rf"},
        "bar": {"cornerStyle": 3},
        "sounds": {"enable": False},
    }
    (config_dir / "config.json").write_text(json.dumps(live))
    (config_dir / "plugin-state.json").write_text(json.dumps({"version": 2, "pluginOptions": {}}))
    (config_dir / "presets").mkdir()
    (config_dir / "presets/mix.json").write_text(json.dumps(preset))
    return home, config_dir, script


def run(script, home, *args):
    return subprocess.run(["bash", str(script), *args],
                          env=dict(os.environ, HOME=str(home)),
                          capture_output=True, text=True)


class ApplyOnlyTests(unittest.TestCase):
    def test_only_applies_exactly_the_named_sections(self):
        with tempfile.TemporaryDirectory() as directory:
            home, config_dir, script = harness(directory)
            result = run(script, home, "--apply", "mix",
                         "--only", "background,appearance:palette")
            self.assertEqual(result.returncode, 0, result.stderr)
            config = json.loads((config_dir / "config.json").read_text())
            self.assertEqual(config["background"]["wallpaperPath"], "/preset.jpg")
            self.assertEqual(config["appearance"]["palette"]["type"], "scheme-neutral")
            # Unnamed sections keep the live values - the fence included.
            self.assertEqual(config["appearance"]["fonts"]["main"], "LiveFont")
            self.assertEqual(config["apps"]["terminal"], "live-terminal")
            self.assertEqual(config["bar"]["cornerStyle"], 0)
            # _pluginState was not named, so the plugin state is untouched.
            state = json.loads((config_dir / "plugin-state.json").read_text())
            self.assertEqual(state["pluginOptions"], {})

    def test_plugin_state_applies_only_when_named(self):
        with tempfile.TemporaryDirectory() as directory:
            home, config_dir, script = harness(directory)
            result = run(script, home, "--apply", "mix", "--only", "_pluginState")
            self.assertEqual(result.returncode, 0, result.stderr)
            state = json.loads((config_dir / "plugin-state.json").read_text())
            self.assertEqual(state["pluginOptions"]["notes"]["blurEnabled"], True)
            config = json.loads((config_dir / "config.json").read_text())
            self.assertEqual(config["background"]["wallpaperPath"], "/live.jpg")

    def test_commands_apply_when_deliberately_named(self):
        with tempfile.TemporaryDirectory() as directory:
            home, config_dir, script = harness(directory)
            run(script, home, "--apply", "mix", "--only", "apps")
            config = json.loads((config_dir / "config.json").read_text())
            self.assertEqual(config["apps"]["terminal"], "evil --rm -rf")

    def test_no_only_is_todays_full_apply(self):
        with tempfile.TemporaryDirectory() as directory:
            home, config_dir, script = harness(directory)
            run(script, home, "--apply", "mix")
            config = json.loads((config_dir / "config.json").read_text())
            self.assertEqual(config["apps"]["terminal"], "evil --rm -rf")
            self.assertEqual(config["bar"]["cornerStyle"], 3)
            state = json.loads((config_dir / "plugin-state.json").read_text())
            self.assertEqual(state["pluginOptions"]["notes"]["blurEnabled"], True)

    def test_unknown_spec_refuses_without_writing(self):
        with tempfile.TemporaryDirectory() as directory:
            home, config_dir, script = harness(directory)
            before = (config_dir / "config.json").read_text()
            result = run(script, home, "--apply", "mix", "--only", "background,$(rm -rf /)")
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((config_dir / "config.json").read_text(), before)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run — must fail**

Run: `cd dots/.config/quickshell/imi && python3 tests/test_presets_apply_only.py`
Expected: FAIL (`--only` unknown; the script treats `--only` as no-op today, so section assertions fail).

- [ ] **Step 3: Implement `--only` in `scripts/presets.sh`**

In the `--apply)` case, immediately after the `preset_file` existence check, insert:

```bash
        # Selective application (spec 2026-08-31): --only <spec,...> filters
        # the preset to the named sections BEFORE the existing merge, which
        # then behaves exactly as it does for an old partial preset - omitted
        # keys keep their live values. A spec is a top-level key, an
        # "appearance:<sub>" subsection, or "_pluginState". Specs are
        # validated against [A-Za-z0-9_:], and one bad spec refuses the whole
        # apply rather than guessing.
        only_specs=""
        if [ "$3" = "--only" ]; then
            only_specs="$4"
            if [ -z "$only_specs" ] || ! printf '%s' "$only_specs" | grep -Eq '^[A-Za-z0-9_:]+(,[A-Za-z0-9_:]+)*$'; then
                echo "Error: bad --only spec: $only_specs" >&2
                exit 1
            fi
            keep_top="$(printf '%s' "$only_specs" | tr ',' '\n' \
                | grep -v ':' | grep -v '^_pluginState$' | jq -R . | jq -sc .)"
            keep_appearance="$(printf '%s' "$only_specs" | tr ',' '\n' \
                | grep '^appearance:' | cut -d: -f2 | jq -R . | jq -sc .)"
            filtered_preset="$(jq -c --argjson top "$keep_top" --argjson app "$keep_appearance" \
                '. as $p
                 | (reduce $top[] as $k ({}; if ($p | has($k)) then .[$k] = $p[$k] else . end))
                 | if ($app | length) > 0 and ($p.appearance? != null) then
                       .appearance = (reduce $app[] as $k ({};
                           if ($p.appearance | has($k)) then .[$k] = $p.appearance[$k] else . end))
                   else . end' "$preset_file")"
            preset_file="$(mktemp "${PRESETS_DIR}/.apply-XXXXXX.json")"
            printf '%s' "$filtered_preset" > "$preset_file"
            trap 'rm -f "$preset_file"' EXIT
            if printf '%s' "$only_specs" | tr ',' '\n' | grep -qx '_pluginState'; then
                jq -c --slurpfile orig <(jq '._pluginState // empty' "$PRESETS_DIR/${name}.json") \
                    'if ($orig | length) > 0 then ._pluginState = $orig[0] else . end' \
                    "$preset_file" > "${preset_file}.tmp" && mv "${preset_file}.tmp" "$preset_file"
            fi
        fi
```

Then two adjustments below it:
1. The line `preset_plugin_state="$(jq -c '._pluginState // empty' "$preset_file")"` already reads the (possibly filtered) file — no change.
2. In the appearance-partial case the filtered preset REPLACES `appearance` wholesale on merge; that is wrong for partials. Change the final config merge from `'.[0] * .[1] | ...'` to a deep merge for appearance:

```bash
        jq -s --argjson persistIds "$persist_ids" --argjson curEnabled "$current_enabled" \
            '.[0] as $live | .[1] as $preset
                | ($live * $preset)
                | if ($preset.appearance? != null) and ($live.appearance? != null) then
                      .appearance = ($live.appearance * $preset.appearance)
                  else . end
                | del(._presetMeta, ._pluginState)
                | if (.plugins.enabled? != null) and ($persistIds | length > 0) then
                    .plugins.enabled = (
                        (.plugins.enabled | map(select(. as $x | ($persistIds | index($x)) | not)))
                        + ($persistIds | map(select(. as $x | ($curEnabled | index($x)) != null))))
                  else . end' \
            "$CONFIG_FILE" "$preset_file" \
            > "${CONFIG_FILE}.tmp" \
            && replace_if_changed "${CONFIG_FILE}.tmp" "$CONFIG_FILE" || true
```

(Note: `$live * $preset` is already a deep merge in jq — the explicit appearance line documents intent and keeps behaviour identical; keep it for readability or drop it if diff-shy. The REAL change in this block is nothing — jq `*` is recursive — so verify with the test and leave the original block untouched if the partial-appearance test passes without it.)

- [ ] **Step 4: Run the tests — must pass**

Run: `python3 tests/test_presets_apply_only.py` → `OK (5 tests)`.
Also rerun the existing harness: `python3 tests/test_presets.py` → unchanged pass.

- [ ] **Step 5: Commit**

```bash
git add -N dots/.config/quickshell/imi/tests/test_presets_apply_only.py
git commit --only -F - -- dots/.config/quickshell/imi/scripts/presets.sh \
  dots/.config/quickshell/imi/tests/test_presets_apply_only.py <<'MSG'
feat(presets): --apply --only filters the preset before the merge

A spec list (top-level keys, appearance:<sub> subsections,
_pluginState) validated against [A-Za-z0-9_:], one bad spec refusing
the whole apply without writing. The filtered preset rides the
existing merge, which already keeps live values for omitted keys - the
proven old-partial-preset semantics. Five harness cases pin it, the
apps fence loudest: commands survive untouched unless named.
MSG
```

---

### Task 3: `Presets.apply(name, sections)`

**Files:**
- Modify: `services/Presets.qml` (the `apply` function)

- [ ] **Step 1: Change apply**

```qml
    // `sections` comes from PresetGroups.sectionsFor - config keys and
    // appearance:<sub> spellings, sanitized by construction, but still
    // passed as ONE argv element after --only, never shell-spliced.
    function apply(name, sections) {
        GlobalStates.settingsOpen = false
        // Clearing the wallpaper preview belongs to the wallpaper group:
        // an apply that keeps the current wallpaper must not blank it.
        const wallpaperIncluded = !sections
            || sections.some(s => s === "background" || s === "wallpaperSelector")
        if (wallpaperIncluded) {
            Wallpapers.confirmedPath = ""
            Wallpapers.previewPath = ""
        }
        const argv = ["bash", Directories.presetsScriptPath, "--apply", name]
        if (sections && sections.length > 0)
            argv.push("--only", sections.join(","))
        Quickshell.execDetached(argv)
    }
```

- [ ] **Step 2: Verify nothing else calls apply with one argument expecting full**

Run: `grep -rn "Presets.apply(" modules/ services/`
Expected: only `Profile.qml:330`. A missing `sections` (undefined) means full apply — back-compatible by the `!sections` branch.

- [ ] **Step 3: Commit**

```bash
git commit --only -F - -- dots/.config/quickshell/imi/services/Presets.qml <<'MSG'
feat(presets): apply() takes the popup's section list

Undefined stays a full apply; a list rides --only as one argv element.
The wallpaper-preview reset moves behind the wallpaper group - a
partial apply that keeps the wallpaper must not blank it.
MSG
```

---

### Task 4: the popup

**Files:**
- Create: `modules/imi/settings/pages/PresetApplyDialog.qml`
- Modify: `modules/imi/settings/pages/Profile.qml` (delegate `onApply`, host the dialog)
- Test: extend `tests/test_presets_apply_only.py` with structural pins

- [ ] **Step 1: Write `PresetApplyDialog.qml`**

```qml
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "../../../common/functions/preset_groups.js" as PresetGroups
import QtQuick
import QtQuick.Layouts

/**
 * The selective-apply dialog (spec 2026-08-31). Opens with every ordinary
 * group preselected, so Enter is a whole-preset apply - except the commands
 * row, which is the apps.* injection fence and never preselects. Groups a
 * preset does not hold render disabled rather than vanishing, so a partial
 * preset still shows the whole vocabulary.
 */
WindowDialog {
    id: root
    property string presetName: ""
    property var presetData: null   // parsed preset JSON, from the card
    signal applied()

    readonly property var counts: PresetGroups.presentCounts(root.presetData ?? ({}))
    property var selected: ({})
    onShowChanged: if (root.show) {
        const initial = {};
        for (const group of PresetGroups.GROUPS)
            initial[group.id] = group.defaultOn && (root.counts[group.id] ?? 0) > 0;
        root.selected = initial;
    }
    readonly property int selectedCount: PresetGroups.GROUPS
        .filter(g => root.selected[g.id] === true).length

    function confirm() {
        const ids = PresetGroups.GROUPS.map(g => g.id).filter(id => root.selected[id]);
        Presets.apply(root.presetName,
            PresetGroups.sectionsFor(root.presetData ?? ({}), ids));
        root.applied();
        root.dismiss();
    }

    WindowDialogTitle {
        text: Translation.tr("Apply %1").arg(root.presetName)
    }

    Repeater {
        model: PresetGroups.GROUPS.filter(g => g.id !== "commands")
        delegate: ConfigSwitch {
            required property var modelData
            Layout.fillWidth: true
            buttonIcon: modelData.icon
            text: Translation.tr(modelData.label)
            enabled: (root.counts[modelData.id] ?? 0) > 0
            description: (root.counts[modelData.id] ?? 0) > 0
                ? Translation.tr("%1 sections").arg(root.counts[modelData.id])
                : Translation.tr("not in this preset")
            checked: root.selected[modelData.id] === true
            onToggleRequested: {
                const next = Object.assign({}, root.selected);
                next[modelData.id] = !next[modelData.id];
                root.selected = next;
            }
        }
    }

    WindowDialogSeparator {}

    // The fence. Never preselected, whatever the preset's origin.
    ConfigSwitch {
        Layout.fillWidth: true
        buttonIcon: "terminal"
        text: Translation.tr("App launch commands")
        enabled: (root.counts.commands ?? 0) > 0
        description: Translation.tr("Runs shell commands from the preset — review before enabling")
        checked: root.selected.commands === true
        onToggleRequested: {
            const next = Object.assign({}, root.selected);
            next.commands = !next.commands;
            root.selected = next;
        }
    }

    WindowDialogButtonRow {
        DialogButton {
            buttonText: Translation.tr("Cancel")
            onClicked: root.dismiss()
        }
        DialogButton {
            buttonText: Translation.tr("Apply")
            enabled: root.selectedCount > 0
            onClicked: root.confirm()
        }
    }
}
```

(Adjust `WindowDialogButtonRow`/`DialogButton` property names to the widgets' actual API — read both files first; `SelectionDialog.qml:114` is the reference user. `ConfigSwitch.description`: if ConfigSwitch has no `description`, use the `StyledText` sub-label pattern from the drawer instead — check `modules/common/widgets/ConfigSwitch.qml` before writing.)

- [ ] **Step 2: Wire `Profile.qml`**

At the page root add state + dialog:

```qml
    property string applyDialogPreset: ""
    property var applyDialogData: null
```

Change the delegate's `onApply` (line ~330) from `Presets.apply(presetDelegate.presetName)` to:

```qml
    onApply: () => {
        root.applyDialogPreset = presetDelegate.presetName;
        root.applyDialogData = presetDelegate.presetJson;  // parsed in the existing FileView handler
        applyDialog.show = true;
    }
```

The delegate's FileView `onLoaded` already parses the JSON (line ~300s) — store the parsed object into a new `property var presetJson` beside `presetWallpaper`/`presetDescription`.

At the page bottom:

```qml
    PresetApplyDialog {
        id: applyDialog
        anchors.fill: parent
        presetName: root.applyDialogPreset
        presetData: root.applyDialogData
        onDismiss: applyDialog.show = false
    }
```

(If `WindowDialog` must live at the settings-window level rather than inside a scrollable page — check how `SelectionDialog` is hosted — hoist it to the page's outermost non-scrolled Item.)

- [ ] **Step 3: Structural pins**

Append to `tests/test_presets_apply_only.py`:

```python
QML_ROOT = ROOT / "modules/imi/settings/pages"


class DialogPins(unittest.TestCase):
    def test_the_commands_row_is_never_preselected(self):
        dialog = (QML_ROOT / "PresetApplyDialog.qml").read_text()
        self.assertIn('group.defaultOn && (root.counts[group.id] ?? 0) > 0', dialog)
        groups = (ROOT / "modules/common/functions/preset_groups.js").read_text()
        self.assertIn('id: "commands"', groups)
        self.assertIn("defaultOn: false", groups)
        self.assertEqual(groups.count("defaultOn: false"), 1,
                         "commands is the one default-off group")

    def test_apply_goes_through_the_dialog(self):
        profile = (QML_ROOT / "Profile.qml").read_text()
        self.assertNotIn("Presets.apply(presetDelegate.presetName)", profile,
                         "the card must open the dialog, not bypass it")
        self.assertIn("PresetApplyDialog", profile)
```

- [ ] **Step 4: Run everything**

```
python3 tests/test_presets_apply_only.py           -> OK
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -import tests/mocks -import tests/imports -input tests/tst_preset_groups.qml  -> pass
/usr/lib/qt6/bin/qmllint -I . -I /usr/lib/qt6/qml modules/imi/settings/pages/PresetApplyDialog.qml modules/imi/settings/pages/Profile.qml  -> no errors
```

- [ ] **Step 5: Visual verification (probe, not the live session)**

Launch a FloatingWindow probe hosting `PresetApplyDialog { show: true; presetData: <parsed Bench.json>; presetName: "Bench" }`, grim the window, view: seven rows, commands row off and below the separator, counts real. Then deploy (`./deploy-shell`) and drive the real flow once: open Settings > Profile, click Apply on a preset, confirm the popup and a partial apply (e.g. wallpaper only) — the maintainer verifies visually.

- [ ] **Step 6: Commit**

```bash
git add -N dots/.config/quickshell/imi/modules/imi/settings/pages/PresetApplyDialog.qml
git commit --only -F - -- \
  dots/.config/quickshell/imi/modules/imi/settings/pages/PresetApplyDialog.qml \
  dots/.config/quickshell/imi/modules/imi/settings/pages/Profile.qml \
  dots/.config/quickshell/imi/tests/test_presets_apply_only.py <<'MSG'
feat(presets): Apply opens the selective-apply dialog

Every ordinary group preselected so Enter stays a whole-preset apply;
absent groups render disabled; the commands row sits under its own
separator with the warning subtitle and never preselects - the pins
hold the fence and that the card cannot bypass the dialog.
MSG
```

---

### Task 5: receipts

**Files:**
- Modify: `CHANGELOG.md` (repo root), `docs/tests-README.md`

- [ ] **Step 1: CHANGELOG entry (under `### Added`)**

```markdown
- **Apply a preset selectively.** Apply opens a dialog: six groups -
  wallpaper, theming, fonts, panels, widgets, everything else - all
  preselected so Enter still applies the whole preset, each showing how
  many sections the preset holds. App launch commands sit apart and are
  never preselected: a preset's apps.* strings are shell-executed, and
  with online presets planned they only ever apply when deliberately
  ticked.
```

- [ ] **Step 2: docs/tests-README.md entry**

```markdown
* **Selective preset tests (`tst_preset_groups.qml`, `test_presets_apply_only.py`)**: the Apply popup's partition table - every preset key claimed, `apps` alone in the never-preselected commands group - and the script's `--only` filtering run against the real presets.sh in a temp HOME: named sections apply, unnamed keep live values, `_pluginState` only when asked, one bad spec refuses without writing, and no `--only` reproduces today's full apply.
```

- [ ] **Step 3: Commit, deploy**

```bash
git commit --only -F - -- CHANGELOG.md docs/tests-README.md <<'MSG'
docs: receipts for selective preset application
MSG
cd ~/dev/imi-unify && ./deploy-shell
```

---

## Self-review notes

- Spec coverage: partition table (T1), script `--only` + validation + atomic refuse (T2), wallpaper-reset gating + argv hygiene (T3), popup incl. disabled rows, fence row, Enter/Escape via WindowDialog (T4), tests (T1/T2/T4), receipts (T5). `_presetMeta` never applies: enforced by the existing merge (`del(._presetMeta)`) and excluded from every group.
- Known verify-before-trust points, called out inline: `ConfigSwitch.description` existence, `DialogButton`/`WindowDialogButtonRow` exact API, dialog hosting location. The implementer reads those three files before Task 4 Step 1 and adapts spellings only.
- jq `*` is a deep merge; the Task 2 appearance note explains why no extra merge logic is expected — the test decides.
