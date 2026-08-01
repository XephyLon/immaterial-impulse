# Widgets Page IA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rename the Plugins settings page to Widgets, give it a search field and capability filter chips, and promote the store's page-local `FilterChip` into a shared component.

**Architecture:** Three moves, in dependency order. First promote `FilterChip` from a page-local `component` inside `PluginStorePage.qml` to a real file in `modules/common/widgets/`, so both pages use one type. Then expose the capability vocabulary once from the `PluginManager` singleton so both pages read the same list. Then build the filter UI on the Widgets page from those two pieces and rename the user-facing strings. No plugin data, config keys, or type names change.

**Tech Stack:** Quickshell/QML (Qt 6), Python contract tests via `unittest`, bash test runner.

**Spec:** `docs/superpowers/specs/2026-08-01-widgets-page-ia-design.md`
**Branch:** `feat/widgets-page-ia` (already created, spec committed at `57b47e3b`)

---

## Environment notes for the implementer

Read these before starting; they will save you a wasted cycle.

- **Repo root:** `/home/xephy/dev/imi-unify`. All QML paths below are relative to
  `dots/.config/quickshell/imi/`. All test paths are relative to
  `dots/.config/quickshell/imi/tests/`.
- **Run the suite with:** `dots/.config/quickshell/imi/tests/run_tests.sh`
  (it `cd`s to its own project root, so the caller's working directory does not
  matter).
- **`modules/common/widgets/` has no `qmldir`.** It is a directory import.
  Adding a new `.qml` file there needs no registration entry — but the new type
  is only registered on a **full `qs` restart**, never on hot reload.
- **Restarting the shell** (only needed for the runtime checks in Task 6):
  ```bash
  pkill -x quickshell; sleep 2; setsid -f bash -c "qs -c imi > /tmp/imi.log 2>&1"
  ```
  Never use `pkill -f` with a pattern that also matches your own command line —
  it kills the command chain.
- **Two linters will judge your code:** `tests/lint_spacing.py` rejects raw
  spacing/padding/margin literals (use `Appearance.spacing.*`), and
  `tests/lint_material_icons.py` rejects icon names that are not real ligatures
  in the installed Material Symbols font. The four icon names used in this plan
  (`widgets`, `toast`, `layers`, `side_navigation`) are already in use elsewhere
  in the repo and pass.
- **Commit style:** separate logical commits, no agent/Claude attribution in
  commit messages or PR bodies.

---

## File structure

| File | Responsibility | Change |
|---|---|---|
| `modules/common/widgets/FilterChip.qml` | A single toggleable filter chip: icon + label, styled for both filter surfaces | **Create** (moved from `PluginStorePage.qml:99`) |
| `modules/common/plugins/PluginManager.qml` | Owns the canonical list of filterable surface capabilities | Modify — add `surfaceCapabilities` + `pluginSurfaces()` |
| `modules/imi/settings/pages/PluginStorePage.qml` | Store catalog; stops defining its own chip and its own capability list | Modify — delete local component, read shared vocabulary, rename strings |
| `modules/imi/settings/pages/PluginsPage.qml` | The Widgets page: search + chips + filtered list | Modify — add filter state, filter UI, filtered model, empty state, PlainText |
| `modules/common/widgets/ConfigSwitch.qml` | Renders every settings label + description; the actual render site for manifest strings | Modify — `textFormat: Text.PlainText` on both `StyledText`s |
| `modules/imi/settings/SettingsContent.qml` | Settings navigation registry | Modify — line 147 nav entry rename |
| `tests/test_widgets_page_filters.py` | Contract pins for everything above | **Create** |
| `tests/run_tests.sh` | Test runner registry | Modify — register the new test |
| `CHANGELOG.md` | Release notes | Modify — add entry |

---

## Task 1: Promote `FilterChip` to a shared widget

**Files:**
- Create: `dots/.config/quickshell/imi/modules/common/widgets/FilterChip.qml`
- Modify: `dots/.config/quickshell/imi/modules/imi/settings/pages/PluginStorePage.qml:99-129`
- Create: `dots/.config/quickshell/imi/tests/test_widgets_page_filters.py`
- Modify: `dots/.config/quickshell/imi/tests/run_tests.sh`

- [ ] **Step 1: Write the failing test**

Create `dots/.config/quickshell/imi/tests/test_widgets_page_filters.py`:

```python
#!/usr/bin/env python3
"""Source contract for the Widgets page filter UI.

The QML suite instantiates pure-logic singletons and never builds widgets, so
these are greppable pins on the parts of the Widgets page IA that fail silently
when they regress.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CHIP = ROOT / "modules/common/widgets/FilterChip.qml"
STORE = ROOT / "modules/imi/settings/pages/PluginStorePage.qml"


class FilterChipIsShared(unittest.TestCase):
    def test_chip_is_a_shared_widget_file(self):
        self.assertTrue(CHIP.exists(),
                        "FilterChip must live in modules/common/widgets")

    def test_chip_is_a_ripple_button(self):
        src = CHIP.read_text(encoding="utf-8")
        self.assertRegex(src, r"(?m)^RippleButton\s*\{")

    def test_chip_exposes_label_and_icon(self):
        src = CHIP.read_text(encoding="utf-8")
        self.assertIn("property string label", src)
        self.assertIn("property string chipIcon", src)

    def test_store_no_longer_declares_a_local_chip(self):
        """A page-local `component FilterChip` is how the chip got trapped in a
        gated-off page in the first place. If it comes back, the two filter
        surfaces can drift apart again.
        """
        src = STORE.read_text(encoding="utf-8")
        self.assertNotRegex(src, r"component\s+FilterChip\s*:",
                            "PluginStorePage must use the shared FilterChip")


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it to make sure it fails**

Run:
```bash
python3 dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
```
Expected: FAIL — 4 failures. The first three fail on the missing file
(`FilterChip must live in modules/common/widgets`, then `FileNotFoundError`),
and `test_store_no_longer_declares_a_local_chip` fails because the local
component still exists.

- [ ] **Step 3: Create the shared component**

Create `dots/.config/quickshell/imi/modules/common/widgets/FilterChip.qml` with
the body moved verbatim from the page-local component, converted from a
`component FilterChip: RippleButton { ... }` declaration to a root `RippleButton`:

```qml
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A toggleable filter chip: optional leading icon plus a label. Used by both
 * plugin filter surfaces (the Widgets page and the plugin store) so the two
 * cannot drift apart - this was a page-local component in PluginStorePage,
 * which meant the only working implementation lived behind a feature gate.
 *
 * Selection state is the caller's: bind `toggled` and handle `clicked`.
 */
RippleButton {
    id: chip
    property string label
    property string chipIcon: ""
    implicitHeight: 32
    implicitWidth: chipRow.implicitWidth + Appearance.spacing.space200
    buttonRadius: Appearance.rounding.small
    colBackground: Appearance.colors.colLayer2
    colBackgroundToggled: Appearance.colors.colSecondaryContainer

    contentItem: RowLayout {
        id: chipRow
        anchors.centerIn: parent
        spacing: Appearance.spacing.space50

        MaterialSymbol {
            visible: chip.chipIcon.length > 0
            text: chip.chipIcon
            iconSize: Appearance.font.pixelSize.normal
            color: chip.toggled
                ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colOnLayer2
        }
        StyledText {
            text: chip.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: chip.toggled
                ? Appearance.colors.colOnSecondaryContainer
                : Appearance.colors.colOnLayer2
        }
    }
}
```

- [ ] **Step 4: Delete the page-local component**

In `dots/.config/quickshell/imi/modules/imi/settings/pages/PluginStorePage.qml`,
delete the entire block that currently starts at line 99 with
`component FilterChip: RippleButton {` and ends with its closing brace (the
block immediately preceding `ContentSection { title: Translation.tr("Plugin store")`).

Do not touch the `FilterChip { ... }` *usages* further down the file — they now
resolve to the shared type via the file's existing
`import qs.modules.common.widgets`.

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
python3 dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
```
Expected: PASS — `Ran 4 tests` / `OK`.

- [ ] **Step 6: Register the test in the runner**

In `dots/.config/quickshell/imi/tests/run_tests.sh`, immediately after the
existing expandable-panel block (which ends with `fi` at line 107), insert:

```bash
echo "Running widgets page filter contract tests..."
if ! python3 "$SCRIPT_DIR/test_widgets_page_filters.py"; then
    echo "Widgets page filter contract tests failed."
    exit 1
fi
```

- [ ] **Step 7: Run the full suite**

Run:
```bash
dots/.config/quickshell/imi/tests/run_tests.sh
```
Expected: PASS, including the line
`Running widgets page filter contract tests...` and
`Material icon lint passed`.

- [ ] **Step 8: Commit**

```bash
git add dots/.config/quickshell/imi/modules/common/widgets/FilterChip.qml \
        dots/.config/quickshell/imi/modules/imi/settings/pages/PluginStorePage.qml \
        dots/.config/quickshell/imi/tests/test_widgets_page_filters.py \
        dots/.config/quickshell/imi/tests/run_tests.sh
git commit -m "refactor(widgets): promote FilterChip to a shared common widget"
```

---

## Task 2: Canonical capability vocabulary on `PluginManager`

The store hardcodes its own three-entry capability list at
`PluginStorePage.qml:39`. It omits `overlay-widget`, which `discordVoice`
actually declares, and duplicating it onto a second page would guarantee they
drift. Move it to the singleton and add the fallback rule that keeps `clock`
visible.

**Files:**
- Modify: `dots/.config/quickshell/imi/modules/common/plugins/PluginManager.qml`
- Modify: `dots/.config/quickshell/imi/modules/imi/settings/pages/PluginStorePage.qml:39-43`
- Modify: `dots/.config/quickshell/imi/tests/test_widgets_page_filters.py`

- [ ] **Step 1: Write the failing test**

Append to `dots/.config/quickshell/imi/tests/test_widgets_page_filters.py`,
before the `if __name__` block. Also add `MANAGER` to the constants at the top
of the file:

```python
MANAGER = ROOT / "modules/common/plugins/PluginManager.qml"
```

```python
class CapabilityVocabulary(unittest.TestCase):
    def setUp(self):
        self.src = MANAGER.read_text(encoding="utf-8")

    def test_manager_owns_the_vocabulary(self):
        self.assertIn("readonly property var surfaceCapabilities", self.src)

    def test_vocabulary_covers_every_surface_in_use(self):
        """overlay-widget is declared by discordVoice but was missing from the
        store's hardcoded list, so that plugin matched no filter at all.
        """
        for value in ("desktop-widget", "bar-widget", "overlay-widget", "panel"):
            self.assertIn(f'"{value}"', self.src,
                          f"surfaceCapabilities is missing {value}")

    def test_settings_is_not_a_surface(self):
        """`settings` means "this plugin has options", not "this plugin draws
        on surface X". It must never become a filter chip.
        """
        block = re.search(r"surfaceCapabilities:\s*\[.*?\]", self.src, re.S)
        self.assertIsNotNone(block, "surfaceCapabilities must be a list literal")
        self.assertNotIn('"settings"', block.group(0))

    def test_manifests_without_capabilities_fall_back_to_desktop_widget(self):
        """clock/manifest.json is the older declarative-JSON generation: it has
        a desktopWidget block and no capabilities array. Without this fallback
        it matches no chip and vanishes from every filtered view.
        """
        self.assertIn("function pluginSurfaces", self.src)
        surfaces = self.src[self.src.index("function pluginSurfaces"):]
        self.assertIn("desktopWidget", surfaces)
        self.assertIn("desktop-widget", surfaces)

    def test_store_reads_the_shared_vocabulary(self):
        store = STORE.read_text(encoding="utf-8")
        self.assertIn("PluginManager.surfaceCapabilities", store)
        self.assertNotRegex(
            store, r"readonly property var capabilityOptions",
            "the store must not keep a second copy of the vocabulary")
```

- [ ] **Step 2: Run it to make sure it fails**

Run:
```bash
python3 dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
```
Expected: FAIL — 5 failures in `CapabilityVocabulary`, starting with
`surfaceCapabilities` not being found in `PluginManager.qml`.

- [ ] **Step 3: Add the vocabulary and the fallback to `PluginManager`**

In `dots/.config/quickshell/imi/modules/common/plugins/PluginManager.qml`,
directly after the `readonly property int apiVersion: 1` declaration (line 15),
insert:

```qml
    // The filterable surfaces a plugin can draw on, in display order. Both
    // filter surfaces (the Widgets page and the plugin store) read this list,
    // so a new surface is added in exactly one place.
    //
    // `settings` is deliberately absent: manifests declare it to mean "this
    // plugin has options", which is not a surface and must not become a chip.
    readonly property var surfaceCapabilities: [
        { value: "desktop-widget", label: Translation.tr("Desktop"), icon: "widgets" },
        { value: "bar-widget", label: Translation.tr("Bar"), icon: "toast" },
        { value: "overlay-widget", label: Translation.tr("Overlay"), icon: "layers" },
        { value: "panel", label: Translation.tr("Panel"), icon: "side_navigation" }
    ]

    // The surfaces a single manifest occupies.
    //
    // Manifests of the older declarative-JSON generation (clock) carry a
    // `desktopWidget` block and no `capabilities` array at all. Without the
    // fallback they match no chip and disappear from every filtered view.
    function pluginSurfaces(manifest) {
        const declared = manifest?.capabilities ?? [];
        if (declared.length > 0) return declared;
        return manifest?.desktopWidget ? ["desktop-widget"] : [];
    }
```

`Translation` is already available: `PluginManager.qml` imports
`qs.modules.common` at the top of the file.

- [ ] **Step 4: Point the store at the shared vocabulary**

In `dots/.config/quickshell/imi/modules/imi/settings/pages/PluginStorePage.qml`,
delete the `readonly property var capabilityOptions: [ ... ]` block at lines
39-43 entirely, and change its one usage — the `Repeater` at line 186 — from:

```qml
                    model: root.capabilityOptions
```

to:

```qml
                    model: PluginManager.surfaceCapabilities
```

`PluginManager` is already in scope: the file imports `qs.modules.common.plugins`.

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
python3 dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
```
Expected: PASS — `Ran 9 tests` / `OK`.

- [ ] **Step 6: Run the full suite**

Run:
```bash
dots/.config/quickshell/imi/tests/run_tests.sh
```
Expected: PASS. The Material icon lint must still report
`all literal icon names exist`.

- [ ] **Step 7: Commit**

```bash
git add dots/.config/quickshell/imi/modules/common/plugins/PluginManager.qml \
        dots/.config/quickshell/imi/modules/imi/settings/pages/PluginStorePage.qml \
        dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
git commit -m "feat(widgets): canonical surface-capability vocabulary on PluginManager"
```

---

## Task 3: Filter state and filtered model on the Widgets page

Build the logic before the UI, so the filtering can be reasoned about on its own.

**Files:**
- Modify: `dots/.config/quickshell/imi/modules/imi/settings/pages/PluginsPage.qml`
- Modify: `dots/.config/quickshell/imi/tests/test_widgets_page_filters.py`

- [ ] **Step 1: Write the failing test**

Add `PAGE` to the constants at the top of
`dots/.config/quickshell/imi/tests/test_widgets_page_filters.py`:

```python
PAGE = ROOT / "modules/imi/settings/pages/PluginsPage.qml"
```

Append this class before the `if __name__` block:

```python
class WidgetsPageFiltering(unittest.TestCase):
    def setUp(self):
        self.src = PAGE.read_text(encoding="utf-8")

    def test_filter_state_exists(self):
        self.assertIn("property string capabilityFilter", self.src)
        self.assertIn("property bool thirdPartyOnly", self.src)

    def test_filtered_model_is_used_by_the_list(self):
        """The Repeater must render the filtered list, not the raw one."""
        self.assertIn("readonly property var filteredPlugins", self.src)
        self.assertRegex(self.src, r"model:\s*root\.filteredPlugins")

    def test_capability_match_uses_the_shared_helper(self):
        """Re-deriving the surface list here would reintroduce the clock bug."""
        self.assertIn("PluginManager.pluginSurfaces", self.src)

    def test_search_is_case_insensitive_over_name_and_description(self):
        block = self.src[self.src.index("filteredPlugins"):]
        self.assertIn("toLowerCase", block)
        self.assertIn("name", block)
        self.assertIn("description", block)

    def test_third_party_uses_the_same_origin_test_as_the_badge(self):
        self.assertIn('_origin === "installed"', self.src)
```

- [ ] **Step 2: Run it to make sure it fails**

Run:
```bash
python3 dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
```
Expected: FAIL — 5 failures in `WidgetsPageFiltering`, starting with
`property string capabilityFilter` not found.

- [ ] **Step 3: Add filter state and the filtered model**

In `dots/.config/quickshell/imi/modules/imi/settings/pages/PluginsPage.qml`,
directly after the `property bool showingStore: false` declaration (line 20),
insert:

```qml
    // Filter state. Capability is single-select: clicking the active chip
    // clears it, matching the store's behaviour exactly.
    property string searchQuery: ""
    property string capabilityFilter: "" // "" = all surfaces
    property bool thirdPartyOnly: false

    // Filters combine with AND. Capability matching goes through
    // PluginManager.pluginSurfaces() rather than reading `capabilities`
    // directly, so manifests of the older declarative-JSON generation (clock)
    // still match the Desktop chip.
    readonly property var filteredPlugins: {
        const query = root.searchQuery.trim().toLowerCase();
        return PluginManager.availablePlugins.filter(plugin => {
            if (root.thirdPartyOnly && plugin._origin !== "installed")
                return false;
            if (root.capabilityFilter.length > 0
                    && !PluginManager.pluginSurfaces(plugin).includes(root.capabilityFilter))
                return false;
            if (query.length > 0) {
                const haystack = `${plugin.name ?? ""} ${plugin.description ?? ""}`.toLowerCase();
                if (!haystack.includes(query)) return false;
            }
            return true;
        });
    }
```

- [ ] **Step 4: Point the list at the filtered model**

In the same file, change the `Repeater` at line 205 from:

```qml
                Repeater {
                    model: PluginManager.availablePlugins
```

to:

```qml
                Repeater {
                    model: root.filteredPlugins
```

- [ ] **Step 5: Run the test to verify it passes**

Run:
```bash
python3 dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
```
Expected: PASS — `Ran 14 tests` / `OK`.

- [ ] **Step 6: Commit**

```bash
git add dots/.config/quickshell/imi/modules/imi/settings/pages/PluginsPage.qml \
        dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
git commit -m "feat(widgets): filter state and filtered plugin model"
```

---

## Task 4: Filter UI — search field, chips, empty state

**Files:**
- Modify: `dots/.config/quickshell/imi/modules/imi/settings/pages/PluginsPage.qml`
- Modify: `dots/.config/quickshell/imi/tests/test_widgets_page_filters.py`

- [ ] **Step 1: Write the failing test**

Append this class to
`dots/.config/quickshell/imi/tests/test_widgets_page_filters.py`, before the
`if __name__` block:

```python
class WidgetsPageFilterUi(unittest.TestCase):
    def setUp(self):
        self.src = PAGE.read_text(encoding="utf-8")

    def test_search_field_is_bound_to_the_query(self):
        """ConfigTextArea.text is the *label*; the typed value is `.value`.
        Binding the wrong one silently produces a search box that never
        filters anything.
        """
        self.assertRegex(self.src, r"searchQuery:\s*Qt\.binding|searchQuery\s*=\s*\w+\.value|onValueChanged")

    def test_chips_come_from_the_shared_vocabulary(self):
        self.assertRegex(self.src, r"model:\s*PluginManager\.surfaceCapabilities")

    def test_chip_click_clears_when_already_active(self):
        self.assertIn('capabilityFilter === modelData.value ? "" : modelData.value',
                      self.src)

    def test_empty_state_exists(self):
        """A filter that matches nothing must say so, not render a blank gap."""
        self.assertRegex(self.src, r"filteredPlugins\.length === 0")
```

- [ ] **Step 2: Run it to make sure it fails**

Run:
```bash
python3 dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
```
Expected: FAIL — 4 failures in `WidgetsPageFilterUi`.

- [ ] **Step 3: Add the filter UI**

In `dots/.config/quickshell/imi/modules/imi/settings/pages/PluginsPage.qml`,
insert the following immediately **before** the `Repeater` (which after Task 3
begins with `model: root.filteredPlugins`), i.e. after the `StyledText` that
shows `PluginManager.installMessage`:

```qml
                ConfigTextArea {
                    id: searchField
                    Layout.fillWidth: true
                    Layout.bottomMargin: Appearance.spacing.space100
                    buttonIcon: "search"
                    text: Translation.tr("Search widgets")
                    placeholderText: Translation.tr("Name or description")
                    fieldWidth: 300
                    singleLine: true
                    // `text` is this control's label; `value` is what the user
                    // typed.
                    onValueChanged: root.searchQuery = searchField.value
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Appearance.spacing.space100
                    spacing: Appearance.spacing.space50

                    Repeater {
                        model: PluginManager.surfaceCapabilities

                        FilterChip {
                            required property var modelData
                            label: modelData.label
                            chipIcon: modelData.icon
                            toggled: root.capabilityFilter === modelData.value
                            onClicked: root.capabilityFilter =
                                root.capabilityFilter === modelData.value ? "" : modelData.value
                        }
                    }

                    FilterChip {
                        label: Translation.tr("Third-party")
                        chipIcon: "extension"
                        toggled: root.thirdPartyOnly
                        onClicked: root.thirdPartyOnly = !root.thirdPartyOnly
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.filteredPlugins.length === 0
                    text: Translation.tr("No widgets match these filters.")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
```

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
python3 dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
```
Expected: PASS — `Ran 18 tests` / `OK`.

- [ ] **Step 5: Run the full suite**

Run:
```bash
dots/.config/quickshell/imi/tests/run_tests.sh
```
Expected: PASS. Both `lint_spacing.py` and `lint_material_icons.py` must pass —
the new code uses only `Appearance.spacing.*` tokens and the icon names
`search`, `extension`, `widgets`, `toast`, `layers`, `side_navigation`, all of
which already exist in the repo.

- [ ] **Step 6: Commit**

```bash
git add dots/.config/quickshell/imi/modules/imi/settings/pages/PluginsPage.qml \
        dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
git commit -m "feat(widgets): search field and capability filter chips"
```

---

## Task 5: Plain-text hardening for settings labels

The store already renders every registry-sourced string with
`textFormat: Text.PlainText` so a malicious index cannot inject rich text. The
Widgets page renders strings from **locally installed** manifests, which are
attacker-controlled in exactly the same way — but the fix does **not** belong on
the page.

The page never renders manifest strings itself. `PluginsPage.qml:244` and
`:249-257` feed `modelData.name`, `.description`, `.author` and `.version` into
a `ConfigSwitch`, and `ConfigSwitch.qml:34-47` renders both through `StyledText`.
`StyledText` declares no `textFormat`, so it inherits Qt's default
`Text.AutoText`, which **auto-detects and renders rich text**. A manifest with
`"name": "<img src=…>"` renders as markup today.

Fixing it in `ConfigSwitch` closes the hole for every settings surface at once,
not just this page. This is safe: all 168 `ConfigSwitch` call sites pass plain
strings, and the codebase convention is to opt *into* rich text explicitly
(`modules/common/widgets/NotificationItem.qml:174` sets
`textFormat: Text.StyledText` deliberately).

**Files:**
- Modify: `dots/.config/quickshell/imi/modules/common/widgets/ConfigSwitch.qml:34-47`
- Modify: `dots/.config/quickshell/imi/tests/test_widgets_page_filters.py`

- [ ] **Step 1: Write the failing test**

Add `SWITCH` to the constants at the top of
`dots/.config/quickshell/imi/tests/test_widgets_page_filters.py`:

```python
SWITCH = ROOT / "modules/common/widgets/ConfigSwitch.qml"
```

Append this class before the `if __name__` block:

```python
class SettingsLabelsArePlainText(unittest.TestCase):
    def test_config_switch_renders_both_strings_as_plain_text(self):
        """ConfigSwitch renders its label and description through StyledText,
        which has no textFormat and so inherits Text.AutoText - Qt auto-detects
        and renders rich text. Plugin manifests are attacker-controlled, so a
        manifest name of "<img src=...>" would render as markup.
        """
        src = SWITCH.read_text(encoding="utf-8")
        self.assertEqual(
            src.count("textFormat: Text.PlainText"), 2,
            "both the label and the description StyledText need PlainText")

    def test_page_still_feeds_manifest_strings_through_config_switch(self):
        """Pins why the fix lives in ConfigSwitch rather than on the page: if
        the page ever renders manifest strings directly, this test's premise is
        stale and the new render site needs its own textFormat.
        """
        page = PAGE.read_text(encoding="utf-8")
        self.assertIn("text: modelData.name", page)
        self.assertNotRegex(
            page, r"StyledText\s*\{[^}]*text:\s*modelData\.(name|description)",
            "the page renders a manifest string directly - harden it too")
```

- [ ] **Step 2: Run it to make sure it fails**

Run:
```bash
python3 dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
```
Expected: FAIL — `both the label and the description StyledText need PlainText`
(`ConfigSwitch.qml` currently contains zero occurrences).

- [ ] **Step 3: Harden `ConfigSwitch`**

In `dots/.config/quickshell/imi/modules/common/widgets/ConfigSwitch.qml`, add
`textFormat: Text.PlainText` to **both** `StyledText` blocks — the label at
line 34 (`text: root.text`) and the description at line 42
(`text: root.description`). For example, the label becomes:

```qml
            StyledText {
                text: root.text
                textFormat: Text.PlainText
```

Change nothing else in the file.

- [ ] **Step 4: Run the test to verify it passes**

Run:
```bash
python3 dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
```
Expected: PASS — `Ran 20 tests` / `OK`.

- [ ] **Step 5: Run the full suite**

Run:
```bash
dots/.config/quickshell/imi/tests/run_tests.sh
```
Expected: PASS. `ConfigSwitch` is used in 168 places, so a suite failure here
means a caller did rely on rich text — report it rather than reverting the
hardening.

- [ ] **Step 6: Commit**

```bash
git add dots/.config/quickshell/imi/modules/common/widgets/ConfigSwitch.qml \
        dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
git commit -m "fix(settings): render ConfigSwitch labels as plain text"
```

---

## Task 6: Rename user-facing strings

Strings only. No type, file, or config-key renames — see the spec's "Renaming
policy" for why.

**Files:**
- Modify: `dots/.config/quickshell/imi/modules/imi/settings/SettingsContent.qml:147`
- Modify: `dots/.config/quickshell/imi/modules/imi/settings/pages/PluginsPage.qml`
- Modify: `dots/.config/quickshell/imi/modules/imi/settings/pages/PluginStorePage.qml`
- Modify: `dots/.config/quickshell/imi/tests/test_widgets_page_filters.py`

- [ ] **Step 1: Write the failing test**

Append to `dots/.config/quickshell/imi/tests/test_widgets_page_filters.py`,
adding `NAV` to the constants at the top:

```python
NAV = ROOT / "modules/imi/settings/SettingsContent.qml"
```

```python
class UserFacingRename(unittest.TestCase):
    def test_nav_entry_says_widgets(self):
        src = NAV.read_text(encoding="utf-8")
        self.assertIn('Translation.tr("Widgets")', src)
        self.assertIn('Translation.tr("Available Widgets")', src)

    def test_nav_entry_still_points_at_the_unrenamed_page_file(self):
        """Types, files and config keys deliberately keep their Plugin* names;
        renaming them would break every existing install for no user benefit.
        """
        src = NAV.read_text(encoding="utf-8")
        self.assertIn("pages/PluginsPage.qml", src)

    def test_config_key_is_untouched(self):
        page = PAGE.read_text(encoding="utf-8")
        self.assertIn("Config.options.plugins", page)
```

- [ ] **Step 2: Run it to make sure it fails**

Run:
```bash
python3 dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
```
Expected: FAIL — `test_nav_entry_says_widgets` fails; the other two already pass.

- [ ] **Step 3: Rename the navigation entry**

In `dots/.config/quickshell/imi/modules/imi/settings/SettingsContent.qml`,
change line 147 from:

```qml
            { name: Translation.tr("Plugins"), icon: "extension", component: Qt.resolvedUrl("pages/PluginsPage.qml"), sections: [Translation.tr("Available Plugins")] },
```

to:

```qml
            { name: Translation.tr("Widgets"), icon: "widgets", component: Qt.resolvedUrl("pages/PluginsPage.qml"), sections: [Translation.tr("Available Widgets")] },
```

- [ ] **Step 4: Rename the page's own strings**

In `dots/.config/quickshell/imi/modules/imi/settings/pages/PluginsPage.qml`,
change the `ContentSection` title from
`Translation.tr("Available Plugins")` to `Translation.tr("Available Widgets")`,
and change `icon: "extension"` on that same `ContentSection` to
`icon: "widgets"`.

Then update the remaining user-visible strings on the page so the noun is
consistent — the store entry button `Translation.tr("Browse plugins")` becomes
`Translation.tr("Browse widgets")`, and the install-dialog warning text
`Translation.tr("Plugins run with the same access as the shell itself. Only install plugins from authors you trust.")`
in `dots/.config/quickshell/imi/modules/imi/settings/PluginInstallDialog.qml:123`
becomes
`Translation.tr("Widgets run with the same access as the shell itself. Only install widgets from authors you trust.")`.

- [ ] **Step 5: Rename the store page's user-facing strings**

In `dots/.config/quickshell/imi/modules/imi/settings/pages/PluginStorePage.qml`,
change the user-visible noun from "plugin" to "widget" in the `ContentSection`
title (`Translation.tr("Plugin store")` → `Translation.tr("Widget store")`), the
search field label (`Translation.tr("Search plugins")` →
`Translation.tr("Search widgets")`) and its placeholder
(`Translation.tr("Name, description or tag")` is already noun-free — leave it).

The store is gated off behind `Config.options.plugins.storeEnabled`, so this is
not user-visible today; it is done now so the surface is consistent whenever the
gate is flipped.

- [ ] **Step 6: Run the test to verify it passes**

Run:
```bash
python3 dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
```
Expected: PASS — `Ran 23 tests` / `OK`.

- [ ] **Step 7: Run the full suite**

Run:
```bash
dots/.config/quickshell/imi/tests/run_tests.sh
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add dots/.config/quickshell/imi/modules/imi/settings/SettingsContent.qml \
        dots/.config/quickshell/imi/modules/imi/settings/pages/PluginsPage.qml \
        dots/.config/quickshell/imi/modules/imi/settings/pages/PluginStorePage.qml \
        dots/.config/quickshell/imi/modules/imi/settings/PluginInstallDialog.qml \
        dots/.config/quickshell/imi/tests/test_widgets_page_filters.py
git commit -m "feat(widgets): rename the Plugins page to Widgets in the UI"
```

---

## Task 7: Runtime verification

The contract tests are source greps; they cannot prove the page renders. This
task is the only one that runs the shell.

**Files:** none modified.

- [ ] **Step 1: Deploy the working tree to the live config**

```bash
rsync -a --delete --exclude="__pycache__" \
  dots/.config/quickshell/imi/ ~/.config/quickshell/imi/
```

- [ ] **Step 2: Full restart (required — `FilterChip` is a newly registered type)**

```bash
pkill -x quickshell; sleep 2; setsid -f bash -c "qs -c imi > /tmp/imi.log 2>&1"
```

- [ ] **Step 3: Check the log for QML errors**

```bash
grep -iE "error|warning|not a type|cannot assign" /tmp/imi.log | head -20
```
Expected: no lines referencing `FilterChip`, `PluginsPage`, `PluginStorePage`,
or `PluginManager`.

- [ ] **Step 4: Verify the page by hand**

Open Settings and confirm each of the following. Report any that fail rather
than working around them:

1. The navigation entry reads **Widgets** with a widgets icon.
2. The section header reads **Available Widgets**.
3. Filtering by **Desktop** returns `clock`. *This is the one that silently
   regresses* — `clock`'s manifest has no `capabilities` array, so it only
   matches via the `pluginSurfaces()` fallback.
4. Filtering by **Bar** returns `Docker Manager`.
5. Filtering by **Overlay** returns `Discord Voice` — the capability the store's
   old hardcoded list omitted entirely.
6. Clicking the active chip clears the filter and restores the full list.
7. Typing in the search field narrows by name, and also by description (search
   `container` — it appears only in Docker's description, not its name).
8. A filter combination that matches nothing shows
   "No widgets match these filters." rather than a blank gap.

- [ ] **Step 5: Commit nothing; record the result**

This task produces no commit. If any check fails, fix it in the task that owns
that behaviour and re-run this one.

---

## Task 8: Changelog

**Files:**
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Add the entry**

Add to the unreleased section of `CHANGELOG.md`, matching the file's existing
formatting:

```markdown
### Changed
- The **Plugins** settings page is now **Widgets**, with a search field and
  capability filter chips (Desktop, Bar, Overlay, Panel). Type and config-key
  names are unchanged, so existing installs are unaffected.

### Fixed
- Plugins declaring `overlay-widget` (Discord Voice) were absent from the
  capability vocabulary and matched no filter.
- Installed manifest names and descriptions now render as plain text, so a
  malicious manifest cannot inject rich text into the settings UI.
```

- [ ] **Step 2: Commit**

```bash
git add CHANGELOG.md
git commit -m "docs: changelog for the Widgets page IA"
```

---

## Done criteria

- `dots/.config/quickshell/imi/tests/run_tests.sh` passes.
- All eight manual checks in Task 7 pass, especially check 3 (`clock` under the
  Desktop filter).
- `git log --oneline gh/main..HEAD` shows the spec commit plus seven
  implementation commits, no squashing.
- Do **not** push. Pushing is a release: it requires a `VERSION` bump, a
  changelog roll, and a tag, and is the user's call.
