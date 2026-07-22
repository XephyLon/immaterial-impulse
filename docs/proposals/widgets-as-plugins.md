# Proposal: port all built-in desktop widgets to bundled plugins

> Draft / tracking proposal. Not scheduled.

## Goal

Unify the desktop widget system by porting the built-in background widgets to
**bundled plugins** (the same model as `nandoroid_*`), so every desktop widget
goes through one code path (`PluginManager` → `PluginWidget` → `PluginNode`)
instead of the current split between hardcoded `FadeLoader` widgets in
`Background.qml` and dynamically-loaded plugins.

## Built-in widgets to port

From `modules/ii/background/Background.qml` (the `FadeLoader` blocks inside
`WidgetCanvas`):

- [ ] Clock (`ClockWidget` / cookie clock)
- [ ] Weather (`WeatherWidget`)
- [ ] Media (`MediaWidget`)
- [ ] Calendar (`CalendarWidget`)
- [ ] World clock (`WorldClockWidget`)
- [ ] Visualizer (`VisualizerWidget`)
- [ ] Resources (`ResourcesWidget`)
- [ ] User card (`UserCardWidget`)
- [ ] Custom image (`CustomImage`)
- [ ] Image converter (`ImageConverterWidget`)

## Why

- **One frost/blur path.** The in-shell Wallpaper Engine frost
  (`WallpaperBlurSurface` via `PluginWidget`) is wired for plugins; the built-in
  widgets each frost differently (e.g. the cookie clock uses its own mechanism).
  Porting them means the `plugins.frostMode` config, per-widget `blurEnabled`,
  drag/position persistence, and screen-list gating all come for free and behave
  consistently (including on the lock screen).
- **One positioning/persistence system** (`PluginState`) instead of the bespoke
  per-widget config.
- **Simpler `Background.qml`** — drop the long `FadeLoader` list; every desktop
  widget is a plugin in the existing `Repeater model: PluginManager.availablePlugins`.

## Approach

- Port per widget, each in its own commit, so every step is independently
  revertable and visually verifiable.
- Bundled plugins live under `modules/common/plugins/bundled/<id>/`
  (`manifest` + `Widget.qml`), matching the `nandoroid_*` layout.
- Keep the same visuals; this is a structural refactor, not a redesign.
- The clock frosts via its own path today — porting it is what fixes that
  inconsistency and lets it use the shared `frostMode`.

## Out of scope

- No visual redesign of the widgets.
- No change to the plugin API surface beyond what the built-ins need.
