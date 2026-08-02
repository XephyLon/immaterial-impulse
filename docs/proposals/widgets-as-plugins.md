# Proposal: port all built-in desktop widgets to bundled plugins

> **Done.** Implemented on `proposal/widgets-as-plugins` (PR #11). The
> implementation plan, including the seventeen recipe gaps the ports uncovered,
> is `docs/superpowers/plans/2026-08-02-widgets-as-plugins.md`.

## Goal

Unify the desktop widget system by porting the built-in background widgets to
**bundled plugins** (the same model as `nandoroid_*`), so every desktop widget
goes through one code path (`PluginManager` → `PluginWidget` → `PluginNode`)
instead of the current split between hardcoded `FadeLoader` widgets in
`Background.qml` and dynamically-loaded plugins.

## Built-in widgets to port

From `modules/imi/background/Background.qml` (the `FadeLoader` blocks inside
`WidgetCanvas`). The survey found **eleven**, not ten — `notes` existed as both
a built-in and a bundled plugin — and five of them already had an equivalent
plugin, so they were deletions rather than ports.

Ported to a new bundled plugin:

- [x] Clock (`ClockWidget` / cookie clock) → `clock`, retiring the old
      declarative `clock_plugin`
- [x] Calendar (`CalendarWidget`) → `calendar`
- [x] World clock (`WorldClockWidget`) → `world-clock`
- [x] Visualizer (`VisualizerWidget`) → `visualizer`
- [x] User card (`UserCardWidget`) → `user-card`
- [x] Custom image (`CustomImage`) → `custom-image`
- [x] Image converter (`ImageConverterWidget`) → `image-converter`

Deleted as duplicates of a plugin that already shipped:

- [x] Resources (`ResourcesWidget`) → `nandoroid_system_monitor`
- [x] Media (`MediaWidget`) → `nandoroid_media`
- [x] Weather (`WeatherWidget`) → `nandoroid_weather`
- [x] Notes (`NotesWidget`) → `notes`

`Background.qml` now has one `FadeLoader`, inside the plugin `Repeater`.
`modules/imi/background/widgets/` holds one file, `AbstractBackgroundWidget.qml`,
which is the plugin host's own base class (`PluginWidget.qml` imports it) rather
than a widget.

## Why

- **One frost/blur path.** The in-shell Wallpaper Engine frost
  (`WallpaperBlurSurface` via `PluginWidget`) is wired for plugins; the built-in
  widgets each frosted differently (e.g. the cookie clock used its own
  mechanism). Porting them means the `plugins.frostMode` config, per-widget
  `blurEnabled`, drag/position persistence, and screen-list gating all come for
  free and behave consistently (including on the lock screen).
- **One positioning/persistence system** (`PluginState`) instead of the bespoke
  per-widget config.
- **Simpler `Background.qml`** — drop the long `FadeLoader` list; every desktop
  widget is a plugin in the existing `Repeater model: PluginManager.availablePlugins`.

## Decisions taken

1. **Migration preserves what users have on.** A one-shot migration reads
   `background.widgets.*.enable` and appends matching plugin ids to
   `plugins.enabled`, guarded by `plugins.migratedDesktopWidgets` so it never
   runs twice. Letting everything fall to the `plugins.enabled: []` default
   would have silently removed the desktop clock from every existing install.
2. **The clock's settings and position migrate too.** `enable` alone is right
   for the other ten; the clock is the only built-in that shipped *on*, and its
   styles look nothing like one another, so carrying only the toggle would
   repaint every existing desktop with no setting the user could point at.
   `desktopClockOptionKeys` maps its legacy nested paths onto the plugin's flat
   option namespace, and the legacy `x`/`y` seed every monitor's
   `PluginState` position. This half has its own marker,
   `plugins.migratedDesktopWidgetOptions`, because installs that had already run
   the enable-only migration would otherwise be excluded from it forever.
   `PluginState` drains the batch and sets the marker only once the values are
   actually written, so a launch that dies in between retries rather than
   recording a migration that never happened.
3. **The clock ports for real and `clock_plugin` retires.** The bundled
   `clock_plugin` was the older declarative-JSON generation (manifest only, no
   `Widget.qml`); the built-in was 19 files with cookie, digital, pixel and
   quote styles. There must not be two clocks in the list.
4. **The clock is exempt from the grid.** Its shape places neatly without one,
   so its manifest omits `grid` and declares `defaultWidth`/`defaultHeight`,
   which `PluginWidget` already falls back to. `visualizer` (full-bleed) and
   `custom-image` (user-resizable, square) are exempt for their own reasons —
   see `docs/widget-grid.md`.

## Out of scope

- No visual redesign of the widgets.
- No change to the plugin API surface beyond what the built-ins need.

## Known gaps left open

Found during the ports, deliberately not fixed here, and each queued
separately. None of them blocks the merge; all of them evaporate if they are
not written down.

- **`WidgetsSubmenu.qml` has nothing left to list.** Its `widgetList` is now
  `[]`. The submenu still renders a working "Lock widget positions" toggle, so
  it is not broken — but its `Repeater` can only drive
  `background.widgets.<key>.enable`, which no widget uses any more. Replacing it
  with a plugin-driven list is the follow-up.
- **The notes dedup left a data orphan.** The deleted built-in persisted a JSON
  array of discrete notes at `~/.local/state/quickshell/user/desktopnotes.txt`
  (`services/Notes.qml` → `Directories.desktopNotesPath`); the surviving plugin
  uses a single plaintext scratchpad at `~/.local/state/quickshell/user/notes.txt`
  (`Directories.notesPath`). Neither reads the other. `services/Notes.qml` and
  `Directories.desktopNotesPath` therefore have **no consumer** and were left in
  place on purpose — they are what a migration would read. Do not delete them.
- **The resources dedup lost the Battery card on laptops.** The built-in swapped
  its third card to Battery when `Battery.available`; `DesktopSystemMonitorWidget`
  is always Disk.
- **Anchoring for full-bleed widgets is unsolved** (plan gap 6). The visualizer
  first-enables at the host's generic position, is draggable with no bounds, and
  its vertical position persists freely. It needs a host-side manifest
  `anchor`/`fullBleed` field.
- **`placementStrategy` is persisted by the host but has no UI**, so a widget
  set to a non-`free` strategy becomes free at its last position.
- **Plugin widgets render on every monitor.** The built-ins honoured
  `background.screenList`. This is the same trade for all seven ports.
- **`PixelClock.qml` reads `Config.options.background.widgets.enableShadows`**, a
  key the schema does not declare, so its drop shadow has never drawn.
  Pre-existing; carried over by the port unchanged.
- **`background.widgets.worldClock.timezones` is still live.** `services/WorldClock.qml`
  reads and writes it, so the ported plugin keeps its timezone list in the Config
  schema rather than in `PluginState` like every other plugin option.
