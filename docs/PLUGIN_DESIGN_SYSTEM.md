# Material 3 Expressive plugin design system

This repository includes a shared Material 3 Expressive QML library adapted from
[nandoroid-shell](https://github.com/na-ive/nandoroid-shell/tree/main/dotfiles/.config/quickshell/nandoroid/widgets).
It is infrastructure for plugin and widget authors; it is deliberately **not** a plugin and has no
manifest of its own.

## Attribution

- Creator: **na-ive / nandoroid-shell**
- License: **AGPL-3.0** (see `modules/common/plugins/designsystem/LICENSE.nandoroid`)
- Imported revision: `4994e2d2a264a015d5a6dac4786c60cfe94e5d8a`
- Port and compatibility adapters: Immaterial Impulse contributors

The original creator remains recorded in `ComponentRegistry.qml` and in every independently
packaged widget manifest. New plugins must provide `author`; the settings catalog displays it.

## Imports

```qml
import qs.modules.common.plugins.designsystem
import qs.modules.common.plugins.designsystem.widgets as Expressive
import qs.modules.common.plugins.designsystem.widgets.clock as ExpressiveClock
import qs.modules.common.plugins.designsystem.widgets.shapes as ExpressiveShapes
```

Use `ExpressiveTokens` for the stable plugin-facing token surface:

```qml
Rectangle {
    radius: ExpressiveTokens.shape.large
    color: ExpressiveTokens.colors.colPrimaryContainer
}
```

The tokens delegate to the active Immaterial Impulse theme: `colors`, `m3colors`, `spacing`, `shape`,
`typography`, `motion`, `motionCurves`, and `scale`. Widgets may still import existing shell
components, but new plugin APIs should prefer these aliases to reduce coupling.

## Independent widget plugins

Nandoroid's six desktop widget entry points are separate bundled plugins:

- Nandoroid Clock
- Nandoroid At a Glance
- Nandoroid Media Player
- Nandoroid System Monitor
- Nandoroid Weather
- Nandoroid Currency

Each has its own ID, manifest, enable state, persisted desktop position, permissions, creator,
license, source URL, and upstream revision. Supporting controls, notification renderers, pickers,
clock internals, shapes, and canvases stay in the shared library rather than appearing as bogus
standalone plugins.

Each port also exposes its own persisted options through the Plugins settings page:

- Clock: style and date visibility.
- At a Glance: greeting, date, events, quote, alignment, and greeting size.
- Media Player: lyrics visibility and romaji preference.
- System Monitor: horizontal or vertical layout.
- Weather: compact, medium, or wide size.
- Currency: compact or wide size, base currency, and two quote currencies.

The package wrapper reads these values from `PluginState` and maps them to the compatibility config
used by the imported component. Future ports should follow the same pattern and add a structural
test that verifies every declared option is consumed by its entry point.

## Compatibility and safety

The port includes all 94 upstream QML widget types, clock/shape/weather/canvas submodules, required
calendar and screenshot helpers, quote data, and 60 Google Weather SVGs. Nandoroid-only background
services are adapted under `designsystem/services`:

- system metrics reuse Immaterial Impulse's `ResourceUsage`;
- currency data refreshes explicitly rather than through a persistent timer;
- optional CAVA, schedule, recording, search, and wallpaper-engine hooks have safe defaults.

Ported plugins must preserve their upstream nandoroid visual entry component. Compatibility wrappers
may adapt imports, services, and configuration injection, but must not substitute a redesigned UI.
Plugin manifests may set `startupSafe: false` to quarantine a problematic desktop entry without
removing its package or settings.

Do not copy nandoroid's always-running metric pollers into plugins. Extend the adapters or inject a
service explicitly, and follow the process lifecycle rules in `PLUGINS.md`.

## Validation

`DesignSystemCompile.qml` uses the real Quickshell engine to synchronously compile every library
component and all six plugin entry points without launching the desktop shell:

```bash
quickshell -p DesignSystemCompile.qml
```

`CurrencyRuntimeTest.qml` additionally renders the original Currency entry point for ten seconds,
exercising the scene graph that compile-only validation cannot cover.

`tests/test_expressive_design_system.py` protects the library/plugin boundary, full source and asset
inventory, independent package IDs, creator/license/source attribution, and per-widget settings
coverage.
