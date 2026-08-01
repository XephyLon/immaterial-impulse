# Expandable Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship `ExpandablePanel.qml`, a plugin-facing component that implements the seven Expandable Content rules in `docs/M3_GUIDELINES.md`, and migrate the two in-tree surfaces that currently re-derive them.

**Architecture:** A `StyledRectangle`-derived card holding a header slot, an optional hairline divider, and a clipped panel whose `implicitHeight` animates between zero and its content height. The trigger is external — `expanded` is a plain property the call site drives — because existing surfaces trigger from a `ConfigSwitch`, a chevron, and nav-rail state respectively. Five visual traits are opt-in properties; defaults reproduce `PluginsPage` as it ships today.

**Tech Stack:** QML (Quickshell, no build step), Python `unittest` for source contracts, `qs -p` runtime harnesses for behaviour that greppable tests cannot reach.

**Spec:** `docs/superpowers/specs/2026-08-01-expandable-panel-design.md`

---

## Naming decision made at plan time

The spec called the surface property `contentLayer`. `StyledRectangle` already
declares `contentLayer`, so a derived component cannot redeclare it without
shadowing the inherited one. The public property is therefore **`surfaceLayer`**,
and the component binds the inherited `contentLayer` from it — which is also
what makes `tonalLift` implementable, since lifting is just `surfaceLayer - 1`.

Because these names are a plugin compatibility surface (see the spec), this is
the moment to settle them. Final API:

| Property | Type | Default | Meaning |
| --- | --- | --- | --- |
| `expanded` | bool | `false` | Driven by the call site; the component never sets it |
| `header` | alias | — | Header row content; always visible |
| `content` | alias (default) | — | Revealed content |
| `surfaceLayer` | int | `ContentLayer.Pane` | Card surface depth |
| `outline` | bool | `false` | 1px border, `colPrimary` while open |
| `divider` | bool | `true` | Hairline rule between header and content |
| `shapeMorph` | bool | `false` | `rounding.normal` → `rounding.large` while open |
| `tonalLift` | bool | `false` | Surface steps up one layer while open |
| `staggerStep` | int | `0` | ms between content children; `0` disables |

## File Structure

- **Create** `modules/common/widgets/ExpandablePanel.qml` — the component. Sole responsibility: the card surface, the header slot, and the animated/clipped/gated panel.
- **Create** `tests/test_expandable_panel.py` — source contract pinning the seven rules.
- **Create** `ExpandablePanelRuntimeTest.qml` (shell root) — proves the height actually animates and that collapsed content is disabled. Mirrors `DockerRuntimeTest.qml`.
- **Modify** `tests/run_tests.sh` — register the contract test.
- **Modify** `modules/imi/settings/pages/PluginsPage.qml:369-425` — replace the inline divider + `optionsRevealer`.
- **Modify** `modules/common/plugins/bundled/docker/DockerPopup.qml` — replace the `Revealer` in `Card`.
- **Modify** `tests/test_docker_memory_safety.py` — the Revealer pin becomes an ExpandablePanel pin.
- **Modify** `docs/PLUGINS.md`, `docs/M3_GUIDELINES.md`, `CHANGELOG.md`.

All paths are relative to `dots/.config/quickshell/imi/` unless they start with `docs/` or are repo-root files.

---

### Task 1: The component

**Files:**
- Create: `dots/.config/quickshell/imi/tests/test_expandable_panel.py`
- Create: `dots/.config/quickshell/imi/modules/common/widgets/ExpandablePanel.qml`
- Modify: `dots/.config/quickshell/imi/tests/run_tests.sh`

- [ ] **Step 1: Write the failing contract test**

Create `tests/test_expandable_panel.py`:

```python
#!/usr/bin/env python3
"""Source contract for ExpandablePanel.

The QML suite instantiates pure-logic singletons and never builds widgets, so
these are greppable pins on the parts of the Expandable Content contract
(docs/M3_GUIDELINES.md) that fail silently when they regress.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
PANEL = ROOT / "modules/common/widgets/ExpandablePanel.qml"


class ExpandablePanelContract(unittest.TestCase):
    def setUp(self):
        self.src = PANEL.read_text(encoding="utf-8")

    def test_exists_and_is_a_styled_rectangle(self):
        self.assertTrue(PANEL.exists())
        self.assertRegex(self.src, r"(?m)^StyledRectangle\s*\{")

    def test_public_api(self):
        for decl in ("property bool expanded",
                     "property alias header",
                     "default property alias content",
                     "property int surfaceLayer",
                     "property bool outline",
                     "property bool divider",
                     "property bool shapeMorph",
                     "property bool tonalLift",
                     "property int staggerStep"):
            self.assertIn(decl, self.src, f"missing public property: {decl}")

    def test_component_never_drives_its_own_expanded(self):
        # The trigger belongs to the call site. An internal assignment would
        # make ConfigSwitch-driven and chevron-driven adopters fight it.
        self.assertNotRegex(self.src, r"(?<!property bool )\bexpanded\s*=")

    def test_rule2_asymmetric_motion(self):
        self.assertIn("elementMoveEnter.duration", self.src)
        self.assertIn("elementMoveExit.duration", self.src)
        self.assertIn("elementMoveEnter.bezierCurve", self.src)
        self.assertIn("elementMoveExit.bezierCurve", self.src)

    def test_rule3_opacity_paired_on_fast(self):
        self.assertIn("elementMoveFast", self.src)

    def test_rule4_clipped(self):
        self.assertIn("clip: true", self.src)

    def test_rule5_alive_until_zero_height(self):
        self.assertRegex(self.src, r"visible:\s*root\.expanded\s*\|\|\s*implicitHeight\s*>\s*0")

    def test_rule6_indent_is_leading_only(self):
        # Symmetric insets are what PluginsPage did wrong: the trailing edge
        # must stay aligned with the header.
        left = re.search(r"Layout\.leftMargin:\s*Appearance\.spacing\.(\w+)", self.src)
        right = re.search(r"Layout\.rightMargin:\s*Appearance\.spacing\.(\w+)", self.src)
        self.assertIsNotNone(left)
        self.assertIsNotNone(right)
        self.assertNotEqual(left.group(1), right.group(1),
                            "leading and trailing insets must differ")

    def test_rule7_collapsed_content_is_disabled(self):
        self.assertIn("enabled: root.expanded", self.src)

    def test_no_raw_durations_or_curves(self):
        body = re.sub(r"//.*", "", self.src)
        self.assertNotRegex(body, r"duration:\s*\d+")
        self.assertNotRegex(body, r"easing\.type:\s*Easing\.(?!BezierSpline)")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `cd dots/.config/quickshell/imi && python3 tests/test_expandable_panel.py -v`
Expected: errors — `FileNotFoundError` for `ExpandablePanel.qml`.

- [ ] **Step 3: Write the component**

Create `modules/common/widgets/ExpandablePanel.qml`:

```qml
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A card whose content animates into and out of the layout, implementing the
 * Expandable Content contract in docs/M3_GUIDELINES.md so call sites do not
 * re-derive it.
 *
 * `expanded` is driven by the call site, never by this component: existing
 * surfaces trigger from a ConfigSwitch, a chevron button and nav-rail state,
 * so a built-in trigger would fit none of them.
 *
 * Plugin-facing. The property names here are a compatibility surface for
 * third-party plugins - see docs/PLUGINS.md before renaming any of them.
 */
StyledRectangle {
    id: root

    property bool expanded: false
    property alias header: headerRow.data
    default property alias content: contentColumn.data

    property int surfaceLayer: StyledRectangle.ContentLayer.Pane
    property bool outline: false
    property bool divider: true
    property bool shapeMorph: false
    property bool tonalLift: false
    property int staggerStep: 0

    // Fixed: the container needs a visible head start, otherwise staggered
    // children race the reveal instead of landing in space that exists.
    readonly property int staggerLeadIn: 120

    // Lifting is one step toward the viewer; Background (0) has nowhere to go.
    contentLayer: (root.tonalLift && root.expanded) ? Math.max(0, root.surfaceLayer - 1) : root.surfaceLayer

    implicitHeight: cardColumn.implicitHeight
    radius: (root.shapeMorph && root.expanded) ? Appearance.rounding.large : Appearance.rounding.normal
    border.width: root.outline ? Appearance.borderWidth.standard : 0
    border.color: root.expanded ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

    Behavior on radius {
        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
    }
    Behavior on border.color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }
    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    onExpandedChanged: {
        if (root.staggerStep > 0)
            root.runStagger();
    }

    function runStagger() {
        const kids = contentColumn.children;
        for (let i = 0; i < kids.length; i++) {
            if (!root.expanded) {
                // Collapsing runs everything out together - the panel's own
                // fade carries them - so reset for the next open.
                kids[i].opacity = 1;
                continue;
            }
            kids[i].opacity = 0;
            staggerFade.createObject(root, {
                item: kids[i],
                delay: root.staggerLeadIn + i * root.staggerStep
            }).start();
        }
    }

    Component {
        id: staggerFade
        SequentialAnimation {
            id: seq
            property Item item
            property int delay: 0
            PauseAnimation { duration: seq.delay }
            NumberAnimation {
                target: seq.item
                property: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
            onFinished: seq.destroy()
        }
    }

    ColumnLayout {
        id: cardColumn
        anchors { left: parent.left; right: parent.right; top: parent.top }
        spacing: 0

        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            Layout.margins: Appearance.spacing.space100
            spacing: Appearance.spacing.space100
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.leftMargin: Appearance.spacing.space100
            Layout.rightMargin: Appearance.spacing.space100
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
            visible: root.divider && opacity > 0
            opacity: root.expanded ? 1 : 0
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }

        Item {
            id: panel
            Layout.fillWidth: true
            // Leading indent only: the trailing edge stays aligned with the
            // header so nested content keeps its usable width.
            Layout.leftMargin: Appearance.spacing.space300
            Layout.rightMargin: Appearance.spacing.space100
            Layout.bottomMargin: root.expanded ? Appearance.spacing.space50 : 0

            implicitHeight: root.expanded ? contentColumn.implicitHeight : 0
            opacity: root.expanded ? 1 : 0
            visible: root.expanded || implicitHeight > 0
            enabled: root.expanded
            clip: true

            Behavior on implicitHeight {
                NumberAnimation {
                    duration: root.expanded
                        ? Appearance.animation.elementMoveEnter.duration
                        : Appearance.animation.elementMoveExit.duration
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.expanded
                        ? Appearance.animation.elementMoveEnter.bezierCurve
                        : Appearance.animation.elementMoveExit.bezierCurve
                }
            }
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            ColumnLayout {
                id: contentColumn
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: Appearance.spacing.space100
            }
        }
    }
}
```

- [ ] **Step 4: Run the contract test to confirm it passes**

Run: `cd dots/.config/quickshell/imi && python3 tests/test_expandable_panel.py -v`
Expected: `OK`, 10 tests.

- [ ] **Step 5: Register the test in the runner**

In `tests/run_tests.sh`, immediately after the `plugin process lifecycle lint` block (ends with the `fi` following `lint_plugin_processes.py`), insert:

```bash
echo "Running expandable panel contract tests..."
if ! python3 "$SCRIPT_DIR/test_expandable_panel.py"; then
    echo "Expandable panel contract tests failed."
    exit 1
fi
```

- [ ] **Step 6: Run the full suite**

Run: `cd dots/.config/quickshell/imi && ./tests/run_tests.sh`
Expected: `All tests passed successfully!` and `Totals: 200 passed, 0 failed`.

- [ ] **Step 7: Commit**

```bash
git add dots/.config/quickshell/imi/modules/common/widgets/ExpandablePanel.qml \
        dots/.config/quickshell/imi/tests/test_expandable_panel.py \
        dots/.config/quickshell/imi/tests/run_tests.sh
git commit -m "feat(widgets): add ExpandablePanel

Every surface that expands has re-derived its own subset of the seven
Expandable Content rules in M3_GUIDELINES.md, and none implements all of
them. This is the shared implementation: asymmetric enter/exit motion,
paired opacity, clipping, content that stays instantiated until its exit
reaches zero height, a leading-edge indent, and - the rule everything
except PluginsPage missed - collapsed content that takes no focus.

The trigger stays with the call site. Existing surfaces expand from a
ConfigSwitch, a chevron and nav-rail state, so a built-in trigger fits
none of them.

The five visual traits are opt-in for plugin authors rather than for the
in-tree adopters; the property names are a compatibility surface once
third-party plugins bind them."
```

---

### Task 2: Runtime harness

Greppable tests cannot prove the height actually animates or that `enabled` follows `expanded` — the same gap that hid the Docker popup's real behaviour. This harness builds the component for real.

**Files:**
- Create: `dots/.config/quickshell/imi/ExpandablePanelRuntimeTest.qml`

- [ ] **Step 1: Write the harness**

```qml
import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

ShellRoot {
    property int failures: 0

    function check(label, ok) {
        console.log(`[ExpandablePanel] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok) failures++;
    }

    // Qt's `enabled` reads an item's OWN value, not the effective state
    // inherited from ancestors, so asking a content child whether it is
    // enabled always answers true. Find the clipped panel itself instead -
    // it is the item that carries `enabled: root.expanded`.
    function clippedPanel(item, depth) {
        if (!item || depth > 6) return null;
        const kids = item.children ?? [];
        for (let i = 0; i < kids.length; i++) {
            if (kids[i].clip === true) return kids[i];
            const found = clippedPanel(kids[i], depth + 1);
            if (found) return found;
        }
        return null;
    }

    FloatingWindow {
        visible: true
        implicitWidth: 420
        implicitHeight: 240
        color: "transparent"

        ExpandablePanel {
            id: panel
            anchors.centerIn: parent
            width: 360
            outline: true

            header: [
                Text { text: "Header"; color: Appearance.colors.colOnLayer1 }
            ]

            Rectangle { id: filler; implicitHeight: 80; implicitWidth: 200; color: "transparent" }
        }
    }

    property real collapsedHeight: 0

    Timer {
        interval: 600; running: true
        onTriggered: {
            collapsedHeight = panel.implicitHeight;
            check("collapsed content is disabled", clippedPanel(panel, 0)?.enabled === false);
            panel.expanded = true;
        }
    }

    Timer {
        interval: 1400; running: true
        onTriggered: {
            check("expanding grows the panel", panel.implicitHeight > collapsedHeight);
            check("expanded content is enabled", clippedPanel(panel, 0)?.enabled === true);
            panel.expanded = false;
        }
    }

    Timer {
        interval: 2200; running: true
        onTriggered: {
            check("collapsing returns to the original height",
                  Math.abs(panel.implicitHeight - collapsedHeight) < 2);
            check("collapsed content is disabled again", clippedPanel(panel, 0)?.enabled === false);
            Qt.exit(failures === 0 ? 0 : 1);
        }
    }
}
```

- [ ] **Step 2: Run it**

Run: `cd dots/.config/quickshell/imi && timeout 30 quickshell -p ExpandablePanelRuntimeTest.qml; echo "exit=$?"`
Expected: five `ok` lines and `exit=0`. Any `FAIL` line means the component is wrong — fix the component, not the harness.

- [ ] **Step 3: Commit**

```bash
git add dots/.config/quickshell/imi/ExpandablePanelRuntimeTest.qml
git commit -m "test(widgets): runtime harness for ExpandablePanel

The QML suite never builds widgets and the contract test only greps
source, so neither can prove the height actually animates or that
collapsed content is disabled. This builds the component, drives it
through expand and collapse, and exits non-zero on any failed check."
```

---

### Task 3: Migrate PluginsPage

**Files:**
- Modify: `dots/.config/quickshell/imi/modules/imi/settings/pages/PluginsPage.qml:369-425`

- [ ] **Step 1: Replace the divider and `optionsRevealer`**

Delete the standalone divider `Rectangle` (currently around line 369, the one with `opacity: optionsRevealer.expanded ? 1 : 0`) **and** the `Item { id: optionsRevealer ... }` block through its closing brace, together with the `GroupedList { id: optionsList ... }` nested inside it. Replace all of it with content hosted by the new component.

The surrounding `pluginCard` `Rectangle` and its `cardColumn` are what `ExpandablePanel` now provides, so `pluginCard` becomes:

```qml
ExpandablePanel {
    id: pluginCard
    required property var modelData

    // Unchanged from the current pluginCard - reproduced so this block can be
    // applied without cross-referencing:
    readonly property var storeEntry: {
        if (!root.storeAvailable)
            return null;
        for (const entry of PluginStore.entries)
            if (entry.id === pluginCard.modelData.id)
                return entry;
        return null;
    }
    readonly property bool updateAvailable: storeEntry !== null
        && PluginStore.statusForEntry(storeEntry) === "update"

    Layout.fillWidth: true
    Layout.topMargin: Appearance.spacing.space100
    expanded: configSwitch.checked

    header: [
        ConfigSwitch { /* the existing configSwitch, unchanged */ },
        /* the existing update / uninstall controls, unchanged */
    ]

    GroupedList {
        id: optionsList
        Layout.fillWidth: true
        bgcolor: "transparent"

        PluginOptions {
            manifest: pluginCard.modelData
        }
    }
}
```

Note the two mechanical changes inside: `GroupedList` moves from `anchors.left/right` to `Layout.fillWidth` because the panel's content is a `ColumnLayout`, and the header children move into the `header:` list.

- [ ] **Step 2: Deploy and verify live**

```bash
cd /home/xephy/dev/imi-unify
rsync -a --delete --exclude="__pycache__" dots/.config/quickshell/imi/ ~/.config/quickshell/imi/
sleep 3
LOG=$(ls -t /run/user/1000/quickshell/by-id/*/log.log | head -1)
tail -40 "$LOG" | grep -iE "error|WARN scene"
```
Expected: no new `WARN scene` or `ERROR` lines mentioning `PluginsPage`.

- [ ] **Step 3: Confirm the intended visual change**

Open Settings → Plugins and toggle a plugin on. The options list is now indented `space300` from the leading edge while its trailing edge stays aligned with the header — where it previously sat at a symmetric `space100`. Because `GroupedList` adds its own `space100` row padding, the visible left inset moves 16px → 32px and the right stays 16px.

**Ask the user to confirm this reads correctly before continuing.** If it is too deep, change `Layout.leftMargin` in `ExpandablePanel.qml` to `Appearance.spacing.space250` and re-verify — do not reintroduce a symmetric inset, which is the rule-6 violation being fixed.

- [ ] **Step 4: Run the suite**

Run: `cd dots/.config/quickshell/imi && ./tests/run_tests.sh`
Expected: `All tests passed successfully!`

- [ ] **Step 5: Commit**

```bash
git add dots/.config/quickshell/imi/modules/imi/settings/pages/PluginsPage.qml
git commit -m "refactor(settings): build plugin cards on ExpandablePanel

PluginsPage hand-rolled the expansion this component now owns - it was
the closest thing the shell had to a shared implementation, and the only
one that gated input on the collapsed state.

The one deliberate visual change: options were inset symmetrically by
space100, which is the leading-edge indent rule the guidelines describe
and PluginsPage failed. They now indent from the leading edge only, with
the trailing edge staying aligned to the header."
```

---

### Task 4: Migrate the Docker popup

**Files:**
- Modify: `dots/.config/quickshell/imi/modules/common/plugins/bundled/docker/DockerPopup.qml`
- Modify: `dots/.config/quickshell/imi/tests/test_docker_memory_safety.py`

- [ ] **Step 1: Replace the `Card` component's internals**

`Card` currently wraps its detail content in a `Revealer`. Replace the whole `component Card: StyledRectangle { ... }` definition with:

```qml
    // Shared card chrome. ExpandablePanel owns the motion, clipping, input
    // gating and indent; this only supplies the header and the detail rows.
    component Card: ExpandablePanel {
        id: card
        property var itemData: ({})

        outline: true
        surfaceLayer: StyledRectangle.ContentLayer.Subgroup
        staggerStep: 40
    }
```

`ExpandablePanel` provides `expanded` and `content` itself, so `Card` no longer
declares them. At both use sites (`containerCard` and `projectCard`):

- the status icon, name/subtitle `ColumnLayout` and `ExpandButton` move inside a
  `header: [ ... ]` list;
- the `detailContent: [ ... ]` assignment is deleted and its elements become
  plain children of the `Card`, since `content` is the default property;
- `card.expanded` / `project.expanded` bindings are unchanged.

Do **not** alias `content` to a second name — QML alias-to-alias chains are
fragile, and the default property already does the job.

- [ ] **Step 2: Choose the stagger interval against the live shell**

Deploy, open the Docker popup, expand a container card, and compare
`staggerStep: 40` against `80`. A container row carries five action buttons, so
at 120ms the last lands 600ms after the header moves — longer than the panel's
own 400ms opening. **Ask the user which reads best** and set that value.

- [ ] **Step 3: Update the Docker contract test**

In `tests/test_docker_memory_safety.py`, in `test_popup_uses_shared_components_not_its_own`, replace `"Revealer"` in the widget list with `"ExpandablePanel"`, and add below it:

```python
        # The panel owns the motion contract now; the popup must not re-declare it.
        self.assertNotIn("Behavior on implicitHeight", popup)
        self.assertIn("staggerStep", popup)
```

- [ ] **Step 4: Run tests and the Docker runtime harnesses**

```bash
cd dots/.config/quickshell/imi
./tests/run_tests.sh
timeout 180 ./tests/run_docker_memory_test.sh
```
Expected: suite green; all three harnesses report success within the memory cap.

- [ ] **Step 5: Commit**

```bash
git add dots/.config/quickshell/imi/modules/common/plugins/bundled/docker/DockerPopup.qml \
        dots/.config/quickshell/imi/tests/test_docker_memory_safety.py
git commit -m "refactor(docker): build container cards on ExpandablePanel

The cards used the shared Revealer, which runs the entrance curve in both
directions, never fades, and leaves collapsed action buttons in the tab
order. Moving to ExpandablePanel fixes all three and adds the leading
indent.

Container cards are also where the staggered reveal was wanted, so this
is what puts staggerStep to use rather than leaving the trait theoretical."
```

---

### Task 5: Documentation

**Files:**
- Modify: `docs/PLUGINS.md`
- Modify: `docs/M3_GUIDELINES.md`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Document it for plugin authors**

Add to `docs/PLUGINS.md`, as a new `## Expandable panels` section placed after `## Desktop blur surfaces`:

```markdown
## Expandable panels

`ExpandablePanel` (`qs.modules.common.widgets`) is the supported way to build a
row that expands. It implements the Expandable Content rules in
`docs/M3_GUIDELINES.md` — asymmetric enter/exit motion, paired opacity,
clipping, a leading-edge indent, and collapsed content that takes no focus —
so a plugin does not have to reproduce them.

`expanded` is driven by your own trigger; the component never sets it.

| Property | Default | Meaning |
| --- | --- | --- |
| `expanded` | `false` | Bind to your chevron, switch or state |
| `header` | — | Header row content; always visible |
| `surfaceLayer` | `ContentLayer.Pane` | Card surface depth |
| `outline` | `false` | 1px border, primary while open |
| `divider` | `true` | Hairline rule under the header |
| `shapeMorph` | `false` | Corner radius opens with the panel |
| `tonalLift` | `false` | Surface steps up a layer while open |
| `staggerStep` | `0` | ms between content children; `0` disables |

```qml
import qs.modules.common.widgets

ExpandablePanel {
    expanded: chevron.toggled
    outline: true
    header: [
        StyledText { text: "Container name" }
    ]

    StyledText { text: "Detail row" }
}
```

Children are the revealed content. These property names are stable API —
they will not be renamed without a deprecation path.
```

- [ ] **Step 2: Point the guidelines at the component**

In `docs/M3_GUIDELINES.md`, at the top of the `### Expandable Content` section (line 114), insert:

```markdown
> Use `ExpandablePanel` (`modules/common/widgets/ExpandablePanel.qml`) rather
> than re-deriving the rules below. It implements all of them, and its
> properties cover the visual variations. The rules remain documented here
> because the component's own implementation has to satisfy them.
```

- [ ] **Step 3: Changelog**

Add under `## [Unreleased]`:

```markdown
### Added
- **`ExpandablePanel`** — a shared, plugin-facing component for rows that
  expand, implementing every Expandable Content rule in the M3 guidelines.
  Plugin authors get correct motion, clipping and input handling by default,
  with the outline, hairline rule, shape morph, tonal lift and staggered
  reveal available as options. The settings page's plugin cards and the Docker
  popup's container cards are built on it; the Docker cards use the stagger.

### Fixed
- Collapsed expandable rows no longer hand keyboard focus to their hidden
  controls, and collapse animates on the exit curve rather than the entrance
  curve. The settings page's plugin options now indent from the leading edge
  instead of being inset symmetrically.
```

- [ ] **Step 4: Commit**

```bash
git add docs/PLUGINS.md docs/M3_GUIDELINES.md CHANGELOG.md
git commit -m "docs: document ExpandablePanel for plugin authors

An undocumented plugin-facing widget is one nobody finds, which leaves
every plugin re-deriving the motion contract - the situation the
component exists to end. PLUGINS.md gains the API and an example, and the
Expandable Content section now points at the component so the next widget
author reaches for it instead of re-deriving the rules a fifth time."
```

---

### Task 6: Close out

- [ ] **Step 1: Full verification**

```bash
cd /home/xephy/dev/imi-unify/dots/.config/quickshell/imi
./tests/run_tests.sh
timeout 30 quickshell -p ExpandablePanelRuntimeTest.qml; echo "exit=$?"
timeout 180 ./tests/run_docker_memory_test.sh
```

- [ ] **Step 2: Deploy and restart the live shell**

```bash
cd /home/xephy/dev/imi-unify
rsync -a --delete --exclude="__pycache__" dots/.config/quickshell/imi/ ~/.config/quickshell/imi/
pkill -x quickshell; sleep 2
setsid -f bash -c "qs -c imi > /tmp/qs-imi.log 2>&1"
sleep 6; pgrep -x quickshell >/dev/null && echo RUNNING
grep -icE "configuration loaded" /tmp/qs-imi.log
```

Never `pkill -f "quickshell -c imi"` — it matches the tool's own shell and kills the command chain.

- [ ] **Step 3: Evaluate `BluetoothDeviceItem`**

The spec lists `modules/imi/sidebarRight/bluetoothDevices/BluetoothDeviceItem.qml`
as a possible third adopter, to judge once the component exists rather than
assumed up front. Read it and decide:

- If its row is a header plus revealed detail, migrate it as a fourth commit
  following Task 3's shape.
- If its expansion is entangled with sidebar layout or per-device state the way
  `NotificationGroup`'s is with stack collapsing, **leave it alone** and say so
  in the final report. A forced migration that distorts the call site is worse
  than a fourth implementation.

Do not migrate it silently either way — the decision and its reason belong in
the summary.

- [ ] **Step 4: Ask the user to confirm** the settings plugin rows and the Docker container cards both look and feel right, then stop. The release (VERSION bump, changelog roll, tag, push) is a separate decision.
