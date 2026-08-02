# Widgets-as-Plugins Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the eleven hardcoded desktop widgets in `Background.qml` to bundled plugins, so every desktop widget goes through one code path (`PluginManager` → `PluginWidget` → `PluginNode`) instead of a split between `FadeLoader` blocks and dynamically-loaded plugins.

**Architecture:** Each widget becomes `modules/common/plugins/bundled/<id>/` with a `manifest.json` and a `Widget.qml`. The host supplies position persistence, frost/blur, drag and screen gating, so the ported widget drops its screen-geometry properties and fills its host instead. A one-shot config migration translates `background.widgets.*.enable` into `plugins.enabled` so nothing a user has on disappears.

**Tech Stack:** Quickshell/QML (Qt 6), Python contract tests via `unittest`, bash test runner.

**Branch:** `proposal/widgets-as-plugins` (PR #11). This is the umbrella branch for the whole widgets-into-plugins initiative — do **not** merge to `main` or tag a release.

**Predecessor:** the Widgets page IA (v0.11.0) is already merged into this branch.

---

## Decisions already taken

Both were put to the user and chosen; do not revisit them without asking.

1. **Migration preserves what users have on.** A one-shot migration reads `background.widgets.*.enable` and appends matching plugin ids to `plugins.enabled`, guarded by a marker so it never runs twice. The alternative — letting everything fall to the `plugins.enabled: []` default — would silently remove the desktop clock from every existing install.
2. **The clock ports for real and `clock_plugin` retires.** The bundled `clock_plugin` is the older declarative-JSON generation ("a simple declarative digital clock", manifest only, no `Widget.qml`). The built-in `ClockWidget` is 19 files with cookie, digital, pixel and quote styles. Porting the built-in replaces the simple one; there must not be two clocks in the list.
3. **The clock is exempt from the grid.** Its shape places neatly without one. Its manifest omits `grid` and declares `defaultWidth`/`defaultHeight` instead — `PluginWidget.qml:107-112` already falls back to those when no `grid` is present.

---

## Survey findings that shape the work

- There are **eleven** widgets, not ten. `notes` is real: the `Config` adapter declares `background.widgets.notes.enable` (default `false`), even though `defaults/config.json` omits the key entirely. **That file is out of sync with the adapter** and should be reconciled as part of the cleanup.
- **`background.widgets.clock.enable` defaults to `true`.** It is the only built-in on by default, which is exactly why the migration in decision 1 is load-bearing.
- **`notes` genuinely duplicates.** `bundled/notes/` (with `Widget.qml`) and `modules/imi/background/widgets/notes/NotesWidget.qml` both exist and both are reachable. The port must remove the built-in, not add a second.
- **No schema-migration mechanism exists.** `tests/test_config_migration.py` covers moving the config *directory* (`illogical-impulse` → `immaterial-impulse`), not keys. The migration in decision 1 is new code.
- `Config` is a `JsonAdapter`: the schema is declared in QML and unknown keys in the file are not exposed. Old `background.widgets.*` keys can therefore be left in place harmlessly once unused.

## The porting contract

Read this before the first port; every task depends on it.

**What a built-in widget has today** (from `Background.qml`): `screenWidth`, `screenHeight`, `scaledScreenWidth`, `scaledScreenHeight`, `wallpaperScale`, and sometimes `wallpaperSafetyTriggered`. It positions itself from those.

**What a plugin widget has instead:**

- `anchors.fill: parent` — the host sizes it.
- `implicitWidth: Appearance.sizes.widgetGridSpanX(cols)` / `implicitHeight: Appearance.sizes.widgetGridSpanY(rows)` as a standalone fallback, matching the manifest `grid`. See `docs/widget-grid.md`.
- Options via `PluginState.option("<id>", "<key>", <default>)`.
- Frost: `readonly property bool blurEnabled: PluginState.option("<id>", "blurEnabled", false)`, `readonly property real backgroundOpacity: Config.options.plugins.blurOpacity`, and `readonly property bool managesBlurTint: true` when the widget draws its own tint.
- Position persistence, dragging, screen gating and blur are the host's job (`PluginWidget.qml`) — the ported widget must not re-derive them.

`modules/common/plugins/bundled/notes/Widget.qml` is the reference implementation; read it before porting anything.

---

## Widget inventory

**Revised after survey.** Five of the eleven built-ins already have an
equivalent bundled plugin, so they are *deletions*, not ports. The user
confirmed all four dedups (`resources`, `media`, `weather`, `notes`); `clock`
is a port that retires the older plugin of the same name.

The nandoroid plugins look tiny (22-line `Widget.qml`) but are thin wrappers
over substantial designsystem widgets, so in every case the surviving
implementation is comparable to or richer than the built-in:

| built-in | lines | surviving plugin renders | lines |
|---|---|---|---|
| `resources` | 161 | `DesktopSystemMonitorWidget` | 381 |
| `media` | 306 | `DesktopMediaWidget` | 522 |
| `weather` | 443 | `DesktopWeatherWidget` | 455 |

### Ports — new bundled plugin (Tasks 2–3)

Smallest first, so the recipe is proven before it meets a hard one.

| # | id | Built-in source | Lines | Config key |
|---|---|---|---|---|
| 1 | `visualizer` | `widgets/visualizer/VisualizerWidget.qml` | 116 | `visualizer` |
| 2 | `custom-image` | `widgets/images/CustomImage.qml` | 203 | `customImage` |
| 3 | `image-converter` | `widgets/images/ImageConverterWidget.qml` | — | `images` |
| 4 | `user-card` | `widgets/usercard/UserCardWidget.qml` | 240 | `userCard` |
| 5 | `world-clock` | `widgets/worldclock/WorldClockWidget.qml` | 332 | `worldClock` |
| 6 | `calendar` | `widgets/calendar/CalendarWidget.qml` | 444 | `calendar` |

### Dedups — delete the built-in (Task 4)

| built-in source | Config key | survives as |
|---|---|---|
| `widgets/resources/ResourcesWidget.qml` | `resources` | `nandoroid_system_monitor` |
| `widgets/media/MediaWidget.qml` | `media` | `nandoroid_media` |
| `widgets/weather/WeatherWidget.qml` | `weather` | `nandoroid_weather` |
| `widgets/notes/NotesWidget.qml` | `notes` | `notes` |

### Port and retire (Task 5)

`clock` — `widgets/clock/` (19 files, ~1350 lines), **no grid**, replaces the
declarative-JSON `clock_plugin`.

---

## Recipe gaps found by the visualizer pilot

The pilot exists to find these. Every remaining port must handle all of them;
none were in the original recipe.

1. **Bundled plugins are not auto-discovered.** `modules/common/plugins/PluginManager.qml`
   needs a hardcoded `FileView` per bundled plugin *and* the id added to the
   array in `rebuildFromLoadedFiles()`. Without both, the plugin silently never
   exists. Highest-impact gap — check it first when a ported widget fails to
   appear.
2. **The enable key is read outside `Background.qml`.** `background.widgets.visualizer.enable`
   also gated the cava `Process` in `modules/imi/mediaControls/MediaControls.qml`;
   left alone, the ported widget would have rendered with permanently zero data.
   **Grep the config key across the whole repo, not just `Background.qml`.**
3. **`BackgroundConfig.qml` carries a legacy toggle grid** (around lines
   913–1005): every built-in appears both in a `Repeater` model *and* in a
   parallel icon-keyed `if/else` chain in `onCheckedChanged`. Each port must
   delete **two** entries or leave a toggle writing to a dead key.
4. **Widgets that draw no background must opt out of frost explicitly.** The
   frost trio only applies when the widget draws its own surface. Otherwise
   declare `readonly property var blurRegions: []` — the host skips the blur
   surface when custom regions are declared but empty. Note this leaves a dead
   "Blur background" toggle in the widget's settings panel.
5. **Conditional-visibility widgets need their trigger active before you judge
   them missing.** The visualizer fades out after a second of silence, which
   produced two false "the widget is gone" readings when a player auto-paused.
   The cava process that feeds it is additionally gated on
   `MprisController.activePlayer !== null`, so a bare `mpv` (no MPRIS) proves
   nothing — use a player that registers on the bus.
6. **Full-bleed and non-draggable have no host support.** The grid caps at 12
   columns and every plugin is draggable and grid-sized. A widget that was
   screen-wide or edge-anchored cannot express that through `grid`; it must
   omit `grid` and size itself. `customImage` is likely to hit this hardest.

   **Half-resolved by the pilot.** *Full-bleed* now works: omit `grid`, declare
   `property string screenName: ""` (the host binds it — `PluginWidget` →
   `PluginNode` → `Widget.qml`), resolve the monitor with
   `Quickshell.screens.find(s => s.name === screenName)`, and bind `implicitWidth`
   to its width. `defaultWidth`/`defaultHeight` in the manifest are then only a
   floor. Measured: 5120px wide, 426 bars, matching the built-in exactly.

   *Anchoring is still unsolved*, and it is a real behavioural regression for
   every widget that was edge-pinned:
   - **First enable lands at `y = 100`** (the host's generic default), i.e. near
     the top, not the bottom edge the built-in was hardcoded to.
   - **It is draggable**, and `AbstractWidget` sets no drag bounds, so a
     full-bleed bar can be dragged partly off-screen and stays there for the
     session.
   - Horizontal drift is self-healing but only on reload: `applyPersistedPosition()`
     clamps x into `[0, screenWidth - width]` = `[0, 0]`. Vertical position
     persists freely in `[0, screenHeight - height]`.

   Fixing this needs a host-side anchor concept (a manifest `anchor`/`fullBleed`
   field driving default position and `draggable`), which is a separate decision.

7. **The settings nav tree mirrors `BackgroundConfig.qml`'s section list.**
   `modules/imi/settings/SettingsContent.qml:149` repeats the section titles and
   `tests/test_settings_navigation.py` pins them. Deleting a `ContentSection`
   reddens the suite until the nav entry goes too — so each port deletes **three**
   things in the settings UI, not two (Repeater model row, `onCheckedChanged`
   branch, nav tree entry). *Found by the `custom-image` port.*

8. **A widget whose value is not a scalar may need a new option type.**
   `custom-image`'s shape picker had no representable form: `choice` renders 31
   Material shapes as text chips, and `ConfigSelectionArray`'s chip `Flow` only
   wraps when the row has no label, so a labelled 31-chip row overflows the card
   unclickably. Resolved by adding a `shape` option type (commit `bb3a181e`) that
   reuses `ConfigSelectionShapeArray`. The lesson generalises: when the built-in
   used a bespoke picker, check whether `PluginOptions` can express it *before*
   settling for a degraded `choice` row. Adding an option type means editing
   three places — `PluginOptions.qml`'s `switch`, `PluginValidator.js`'s type
   whitelist (**it rejects unknown types and the manifest silently fails to
   parse**), and the type list in `docs/PLUGINS.md`.

9. **Frost is not a binary between "whole tile" and "opted out".** Gap 4 covers
   the widget that draws no surface at all; a widget whose card is smaller than
   its tile is the third case, and both of the other answers are wrong for it —
   the default full-widget region frosts empty corners, and `blurRegions: []`
   throws away frost the card actually wants. Name each surface instead, in
   local coordinates:

   ```qml
   readonly property var blurRegions: [
       { x: card.x, y: card.y, width: card.width, height: card.height, radius: card.radius },
       { x: avatar.x, y: avatar.y, width: avatar.width, height: avatar.height, radius: avatar.radius }
   ]
   ```

   Keep `managesBlurTint: true` and apply the persisted opacity to *every*
   surface named, or the ones you missed stay opaque against frosted siblings.
   The host masks one blurred texture with all regions, so a circle is just a
   region whose `radius` is half its width. *Found by the `user-card` port.*

---

## Task 1: One-shot migration from `background.widgets.*` to `plugins.enabled`

Do this **first**. Every later port depends on it, and shipping a port without it removes a user's clock.

**Files:**
- Modify: `dots/.config/quickshell/imi/modules/common/Config.qml`
- Create: `dots/.config/quickshell/imi/tests/test_widget_plugin_migration.py`
- Modify: `dots/.config/quickshell/imi/tests/run_tests.sh`

- [ ] **Step 1: Write the failing test**

Create `dots/.config/quickshell/imi/tests/test_widget_plugin_migration.py`:

```python
#!/usr/bin/env python3
"""Source contract for the desktop-widget -> plugin migration.

Existing installs carry background.widgets.*.enable; ported widgets read
plugins.enabled, which defaults to []. Without a migration every user loses
whatever they had on - including the clock, which defaults to on.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
CONFIG = ROOT / "modules/common/Config.qml"


class WidgetPluginMigration(unittest.TestCase):
    def setUp(self):
        self.src = CONFIG.read_text(encoding="utf-8")

    def test_migration_function_exists(self):
        self.assertIn("function migrateDesktopWidgetsToPlugins", self.src)

    def test_migration_has_a_marker_so_it_runs_once(self):
        """Without a marker the migration re-enables a widget every launch,
        so a user could never turn one off.
        """
        self.assertIn("migratedDesktopWidgets", self.src)

    def test_every_ported_widget_has_a_mapping(self):
        body = self.src[self.src.index("function migrateDesktopWidgetsToPlugins"):]
        for key in ("clock", "weather", "calendar", "worldClock", "notes",
                    "userCard", "images", "visualizer", "customImage",
                    "media", "resources"):
            self.assertIn(key, body, f"no migration mapping for {key}")

    def test_migration_never_drops_existing_entries(self):
        """It appends to plugins.enabled; a user's third-party plugins must
        survive it untouched.
        """
        body = self.src[self.src.index("function migrateDesktopWidgetsToPlugins"):]
        self.assertNotRegex(body, r'setNestedValue\("plugins\.enabled",\s*\[\]')


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run it, confirm it fails**

```bash
python3 dots/.config/quickshell/imi/tests/test_widget_plugin_migration.py
```
Expected: FAIL — `migrateDesktopWidgetsToPlugins` not found.

- [ ] **Step 3: Add the marker to the config schema**

In `dots/.config/quickshell/imi/modules/common/Config.qml`, inside the `plugins` `JsonObject`, alongside `enabled`/`frostMode`/`blurOpacity`, add:

```qml
                    // Set once the built-in desktop widgets have been
                    // translated into `enabled`. Without it the migration
                    // re-adds a widget on every launch and the user can never
                    // turn one off.
                    property bool migratedDesktopWidgets: false
```

- [ ] **Step 4: Add the migration function**

In the same file, next to `setNestedValue` (around line 17), add:

```qml
    // Built-in desktop widgets became bundled plugins. Existing installs
    // carry their state in `background.widgets.<key>.enable`, while ported
    // widgets read `plugins.enabled`, which defaults to []. Translate once,
    // then never again.
    //
    // The old keys are deliberately left on disk: the JsonAdapter does not
    // expose keys it has no property for, so they are inert, and leaving them
    // means a user who downgrades still has their settings.
    readonly property var desktopWidgetPluginIds: ({
        "clock": "clock",
        "weather": "weather",
        "calendar": "calendar",
        "worldClock": "world-clock",
        "notes": "notes",
        "userCard": "user-card",
        "images": "image-converter",
        "visualizer": "visualizer",
        "customImage": "custom-image",
        "media": "media",
        "resources": "resources"
    })

    function migrateDesktopWidgetsToPlugins() {
        if (root.options.plugins.migratedDesktopWidgets)
            return;
        const widgets = root.options.background.widgets;
        const enabled = [];
        for (let i = 0; i < root.options.plugins.enabled.length; i++)
            enabled.push(root.options.plugins.enabled[i]);
        for (const key in root.desktopWidgetPluginIds) {
            const id = root.desktopWidgetPluginIds[key];
            if (widgets[key]?.enable && !enabled.includes(id))
                enabled.push(id);
        }
        root.setNestedValue("plugins.enabled", enabled);
        root.setNestedValue("plugins.migratedDesktopWidgets", true);
    }
```

- [ ] **Step 5: Run it on load**

In the same file, the `FileView` has `onLoaded: root.ready = true` (around line 72). Change it to:

```qml
        onLoaded: {
            root.ready = true;
            root.migrateDesktopWidgetsToPlugins();
        }
```

- [ ] **Step 6: Run the tests**

```bash
python3 dots/.config/quickshell/imi/tests/test_widget_plugin_migration.py
```
Expected: `Ran 4 tests` / `OK`.

- [ ] **Step 7: Register the test in the runner**

In `dots/.config/quickshell/imi/tests/run_tests.sh`, after the widgets-page-filter block, insert:

```bash
echo "Running widget plugin migration tests..."
if ! python3 "$SCRIPT_DIR/test_widget_plugin_migration.py"; then
    echo "Widget plugin migration tests failed."
    exit 1
fi
```

- [ ] **Step 8: Verify against a real config, before any widget is ported**

Back up the live config, then run the shell and confirm the migration wrote what you expect:

```bash
cp ~/.config/immaterial-impulse/config.json /tmp/config-backup.json
python3 -c "
import json; c=json.load(open('/tmp/config-backup.json'))
w=c.get('background',{}).get('widgets',{})
print('enabled widgets before:', sorted(k for k,v in w.items() if isinstance(v,dict) and v.get('enable')))
print('plugins.enabled before:', c.get('plugins',{}).get('enabled'))
"
```

Deploy and restart, then:

```bash
python3 -c "
import json; c=json.load(open('$HOME/.config/immaterial-impulse/config.json'))
p=c.get('plugins',{})
print('plugins.enabled after:', p.get('enabled'))
print('marker:', p.get('migratedDesktopWidgets'))
"
```

Expected: every widget that was `enable: true` now appears in `plugins.enabled` under its mapped id, any pre-existing entries are still present, and the marker is `true`. Restart a second time and confirm the list does **not** grow again.

- [ ] **Step 9: Commit**

```bash
git add dots/.config/quickshell/imi/modules/common/Config.qml \
        dots/.config/quickshell/imi/tests/test_widget_plugin_migration.py \
        dots/.config/quickshell/imi/tests/run_tests.sh
git commit -m "feat(widgets): migrate built-in desktop widget state into plugins.enabled"
```

---

## Task 2: Port `visualizer` — the pilot

This one proves the recipe. Do it fully and carefully; Task 3 repeats it.

**Files:**
- Create: `dots/.config/quickshell/imi/modules/common/plugins/bundled/visualizer/manifest.json`
- Create: `dots/.config/quickshell/imi/modules/common/plugins/bundled/visualizer/Widget.qml`
- Modify: `dots/.config/quickshell/imi/modules/imi/background/Background.qml`
- Delete: `dots/.config/quickshell/imi/modules/imi/background/widgets/visualizer/VisualizerWidget.qml`

- [ ] **Step 1: Read the reference first**

Read `modules/common/plugins/bundled/notes/Widget.qml` and `modules/common/plugins/bundled/notes/manifest.json` in full, plus `docs/widget-grid.md`. Do not skip this — the frost and grid contracts are not obvious from the built-in widget.

- [ ] **Step 2: Determine the grid span**

Read `modules/imi/background/widgets/visualizer/VisualizerWidget.qml` and note its current `implicitWidth`/`implicitHeight`. Convert to the nearest whole grid span using `Appearance.sizes.widgetGridSpanX(cols)` / `widgetGridSpanY(rows)` (cell 132×108, gap 12 — see `docs/widget-grid.md`). Record the chosen `cols`/`rows` in the commit message.

- [ ] **Step 3: Write the manifest**

Create `modules/common/plugins/bundled/visualizer/manifest.json`, following the `notes` manifest exactly:

```json
{
  "id": "visualizer", "name": "Visualizer", "description": "Audio spectrum visualiser for the desktop", "version": "1.0.0", "apiVersion": 1,
  "author": "Immaterial Impulse contributors", "license": "AGPL-3.0",
  "grid": { "cols": 2, "rows": 1 },
  "capabilities": ["desktop-widget"], "permissions": ["settings_read"],
  "desktopWidget": { "component": "Widget.qml", "blur": false }
}
```

Adjust `grid`, `description` and `permissions` to what the widget actually needs. Keep `id` equal to the value the Task 1 migration maps to (`visualizer`).

- [ ] **Step 4: Port the widget body**

Create `modules/common/plugins/bundled/visualizer/Widget.qml` from the built-in source, changing exactly these things and nothing else:

- Drop `screenWidth`, `screenHeight`, `scaledScreenWidth`, `scaledScreenHeight`, `wallpaperScale`, `wallpaperSafetyTriggered` and anything that only existed to position the widget.
- Add `anchors.fill: parent`, and `implicitWidth`/`implicitHeight` from the grid span as a standalone fallback.
- Replace any `Config.options.background.widgets.visualizer.<opt>` read with `PluginState.option("visualizer", "<opt>", <default>)`.
- Add the frost trio if the widget draws a background: `blurEnabled`, `backgroundOpacity`, `managesBlurTint`.

This is a structural refactor, not a redesign. The rendered result must look the same.

- [ ] **Step 5: Remove the built-in**

In `modules/imi/background/Background.qml`, delete the `FadeLoader` block whose `sourceComponent` is `VisualizerWidget`. Then delete `modules/imi/background/widgets/resources/ResourcesWidget.qml` and remove any now-unused import.

- [ ] **Step 6: Run the suite**

```bash
dots/.config/quickshell/imi/tests/run_tests.sh
```
Expected: PASS.

- [ ] **Step 7: Verify live**

New plugin directories are only picked up on a full restart:

```bash
rsync -a --delete --exclude="__pycache__" dots/.config/quickshell/imi/ ~/.config/quickshell/imi/
pkill -x quickshell; sleep 2; setsid -f bash -c "qs -c imi > /tmp/imi.log 2>&1"
```

Then confirm, and report each honestly:

1. `Visualizer` appears in Settings → Widgets, tagged `Desktop`.
2. Enabling it puts the widget on the desktop.
3. It looks the same as the built-in did.
4. It can be dragged, and the position survives a restart.
5. `grep -iE "error|warning" /tmp/imi.log` mentions nothing about the plugin.

- [ ] **Step 8: Commit**

```bash
git add -A dots/.config/quickshell/imi
git commit -m "feat(widgets): port the visualizer widget to a bundled plugin"
```

---

## Task 3: Port the remaining five grid widgets

One widget per commit, in Ports-table order (2–6). For each, repeat Task 2 steps 2–8 exactly, substituting the id, source path and config key from the inventory table.

Per-widget notes, so these are not rediscovered:

- **`visualizer`** — reads audio/cava state. Check what service it depends on and declare the matching `permissions`. If it needs a process, that is a `process` permission.
- **`user-card`** — renders the user's name and avatar; needs `filesystem_read` for the avatar path.
- **`custom-image`** and **`image-converter`** both live in `widgets/images/`. They are two separate widgets sharing a directory: port them as two plugins, and only delete the shared directory once both are gone.
- **`media`** — talks to MPRIS. Confirm it works with no player running, with one, and with two.
- **`world-clock`** — carries a timezone list in config. Migrate that list into plugin options via `PluginState.option`, and say in the commit message what happens to a user's existing list.
- **`calendar`** and **`weather`** are the two largest (444/443 lines) and go last in this task. `weather` depends on the weather service and its API state.

Stop and report rather than improvising if a widget needs something the plugin API does not offer — that is a finding about the API, not a licence to widen it.

---

## Task 4: Delete the four duplicated built-ins

`notes` already exists as a bundled plugin **and** as a built-in. This task deletes the built-in; it does not create a plugin.

**Files:**
- Modify: `dots/.config/quickshell/imi/modules/imi/background/Background.qml`
- Delete: `dots/.config/quickshell/imi/modules/imi/background/widgets/notes/NotesWidget.qml`

- [ ] **Step 1: Diff the two implementations**

Compare `modules/imi/background/widgets/notes/NotesWidget.qml` against `modules/common/plugins/bundled/notes/Widget.qml`. If the built-in has behaviour the plugin lacks, port that behaviour into the plugin **first**, in its own commit, and say what you moved.

- [ ] **Step 2: Check where the note content lives**

The built-in and the plugin may persist to different paths. If they do, a user with notes in the built-in would appear to lose them. Find both paths and report before deleting anything.

- [ ] **Step 3: Delete the built-in**

Remove the `NotesWidget` `FadeLoader` from `Background.qml` and delete the source file.

- [ ] **Step 4: Suite, live check, commit**

As Task 2 steps 6–8. Commit message: `refactor(widgets): drop the built-in notes widget in favour of the bundled plugin`.

---

## Task 5: Port the clock and retire `clock_plugin`

The largest single piece: 19 files, ~1350 lines, four styles (cookie, digital, pixel, quote), nested font config and date-indicator variants. **Exempt from the grid** — free placement via `defaultWidth`/`defaultHeight`.

**Files:**
- Rewrite: `dots/.config/quickshell/imi/modules/common/plugins/bundled/clock/manifest.json`
- Create: `dots/.config/quickshell/imi/modules/common/plugins/bundled/clock/Widget.qml` (+ the supporting files it needs)
- Modify: `dots/.config/quickshell/imi/modules/imi/background/Background.qml`
- Delete: `dots/.config/quickshell/imi/modules/imi/background/widgets/clock/` (19 files)

- [ ] **Step 1: Rewrite the manifest, without `grid`**

```json
{
  "id": "clock", "name": "Clock", "description": "Desktop clock with cookie, digital and pixel styles", "version": "2.0.0", "apiVersion": 1,
  "author": "Immaterial Impulse contributors", "license": "AGPL-3.0",
  "defaultWidth": 300, "defaultHeight": 300,
  "capabilities": ["desktop-widget"], "permissions": ["settings_read", "settings_write"],
  "desktopWidget": { "component": "Widget.qml", "blur": false }
}
```

Set `defaultWidth`/`defaultHeight` from the built-in's actual size. Note the `id` stays `clock`, matching the Task 1 migration mapping, and the version goes to `2.0.0` because this replaces the declarative-JSON plugin of the same id.

- [ ] **Step 2: Move the clock sources into the plugin**

Move all 19 files from `modules/imi/background/widgets/clock/` into `modules/common/plugins/bundled/clock/`, renaming `ClockWidget.qml` to `Widget.qml` and fixing the imports. Keep the subdirectory structure (`dateIndicator/`, `minuteMarks/`).

- [ ] **Step 3: Convert the style options**

The built-in reads `Config.options.background.widgets.clock.{cookie,digital,pixel,quote}` and nested font config. Convert each read to `PluginState.option("clock", "<key>", <default>)`, and declare the corresponding `options` in the manifest so they appear in the widget's settings panel. List every option you moved in the commit message.

- [ ] **Step 4: Remove the built-in and verify all four styles**

Delete the `ClockWidget` `FadeLoader` and the old directory. Then verify **each style renders**: cookie, digital, pixel, and the quote overlay, plus each date-indicator variant. This is the one port where a regression is easy to miss, because only one style is visible at a time.

- [ ] **Step 5: Confirm there is exactly one clock**

In Settings → Widgets, confirm a single `Clock` entry. If two appear, the old `clock_plugin` manifest is still being discovered — find and remove it.

- [ ] **Step 6: Suite, live check, commit**

As Task 2 steps 6–8. Commit message: `feat(widgets): port the desktop clock to a bundled plugin, retiring clock_plugin`.

---

## Task 6: Cleanup

- [ ] **Step 1: Confirm `Background.qml` has no widget `FadeLoader`s left**

```bash
grep -n "FadeLoader" dots/.config/quickshell/imi/modules/imi/background/Background.qml
```
Expected: only the `PluginWidget` repeater remains. Any other hit is an unported widget.

- [ ] **Step 2: Reconcile `defaults/config.json` with the adapter**

`defaults/config.json` is missing `background.widgets.notes` while `Config.qml` declares it — the two are out of sync independently of this work. Bring the file in line with the adapter, and remove the `background.widgets.*` blocks for widgets that are now plugins.

Leave the migration marker and `plugins.enabled` alone.

- [ ] **Step 3: Update the docs**

- `docs/PLUGINS.md` — the bundled-plugin list now includes the ported widgets.
- `docs/proposals/widgets-as-plugins.md` — tick the checklist and note the two decisions taken.
- `CHANGELOG.md` — one `### Changed` entry for the unification and one `### Fixed` if any port fixed a real bug along the way.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "docs: record the widgets-as-plugins port"
```

---

## Verification, per port

- `dots/.config/quickshell/imi/tests/run_tests.sh` passes.
- The widget appears in Settings → Widgets tagged `Desktop`, enables, renders as before, drags, and survives a restart in place.
- `/tmp/imi.log` mentions nothing about the plugin.
- A full `qs` restart is required after adding a plugin directory — hot reload will not register it.

## Done criteria

- `Background.qml` contains no widget `FadeLoader`s.
- Settings → Widgets lists eleven bundled desktop widgets and exactly one clock.
- An existing install keeps every widget it had on, and the migration does not re-run.
- Do **not** merge to `main` and do **not** tag. This branch is PR #11; releasing is a separate decision the user makes.
