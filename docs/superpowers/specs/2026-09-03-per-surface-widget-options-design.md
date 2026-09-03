# Per-surface widget options — design

Approved 2026-09-03. Report: "the resource monitor / GPU monitor desktop
widgets do not maintain separate configurations between desktop and
lockscreen."

## Root cause

`plugin-state.json` forked position (`lockPositions`), span (`gridSize` in
the lock record) and presence (`lockPresence`) per surface, but a widget's
own settings stayed in the flat `pluginOptions[pluginId][key]` map, and
`PluginState.option()` / `setOption()` are the only accessors in that file
that take no `surface`. The lock screen has no widget host of its own: the
desktop builds one widget per plugin per screen and cross-fades it when the
lock look is active, so the desktop and lock "copies" are one object reading
one key. The two monitors declare no `grid`, so `vertical` is their whole
shape and it is shared. The only per-surface setting today is the clock's
hand-rolled `style` / `styleLocked` pair.

## Decisions (user)

1. Surface-scoped option store, not per-manifest opt-in, not a second copy
   of the clock's hack.
2. Host keys: look keys fork (`blurEnabled`, `keepTranslucent`,
   `followParallax`); policy keys stay shared (`positionLocked`,
   `clickThrough`, and `__gridSize`, which has its own surface path).
3. Settings > Plugins: a Desktop / Lock screen segmented switch per plugin
   card; the rows below read and write that surface.
4. The clock's `styleLocked` is retired onto the new store by a one-shot
   migration that preserves what every user sees today.

## Store: `lockOptions`

A sibling map `lockOptions[pluginId][key]` beside `pluginOptions`, shaped
like it. Absence is inheritance, per KEY: a key present in
`lockOptions[id]` is the lock's own value; a key absent there reads through
to `pluginOptions[id][key]`. This differs from the layout fork, which
snapshots a whole screen on first edit, on purpose: a user who rotates the
monitor on the lock screen still wants its blur to follow the desktop, and
"which keys I changed for the lock" is the model the Settings switch shows.
Removing a lock key (writing `null`) re-inherits it.

No migration for the map itself: its absence is the correct upgrade state
(the argument `lockPositions` and `lockPresence` recorded).

`layout_surfaces.js` (pure, tested bare) gains:

- `SHARED_OPTION_KEYS = ["positionLocked", "clickThrough", "__gridSize"]`
  and `isSharedOptionKey(key)` — keys that always live in `pluginOptions`
  whatever surface is asked.
- `rawOption(state, surface, pluginId, key)` → the stored value or
  `undefined` (the read-through rule above).
- `withOption(state, surface, pluginId, key, value)` → next state; on the
  desktop, or for a shared key, it is today's `setOption` body; on the lock
  it writes `lockOptions`, `null`/`undefined` deleting the key.
- `isOptionsForked(state, pluginId)` — any lock key stored for the plugin.
- `withoutLockOptions(state, pluginId)` — drop the plugin's lock map
  (identity-returning no-op when absent, like `withoutLockLayout`).

`PluginState.qml`:

- `emptyState()` and `loadText()` carry `lockOptions` (map or `{}`).
- `option(pluginId, key, fallback, surface)` and
  `setOption(pluginId, key, value, surface)` take a trailing `surface` with
  the same `surface ?? root.currentSurface` default as `position()`. Every
  existing caller keeps its call shape and follows the look: the monitor's
  rotate button on the Lockscreen tab or on a real lock writes the lock's
  `vertical`; `PluginWidget`'s `blurEnabled` / `keepTranslucent` /
  `followParallax` bindings re-evaluate when `currentSurface` flips, exactly
  as `position()` already does; `positionLocked` and `clickThrough` are
  shared keys and land in `pluginOptions` from either surface.
- `lockOptionsForked(pluginId)` and `resetLockOptions(pluginId)`.
- `effectiveBackgroundOpacity` reads `keepTranslucent` through `option()`
  and therefore follows the look; unchanged.
- The Config→PluginState drain and the sizeMode migration keep writing
  `pluginOptions` directly: both are desktop data.

Presets (`scripts/presets.sh`): `lockOptions` is captured and applied under
the same `has()` rule as `lockPositions`, and the `presetPersist` carve-out
keeps the current plugin's `lockOptions[id]` alongside its `pluginOptions[id]`.

`scripts/colors/switchwall.sh` keeps reading the clock's desktop
`cookieAiStyling`; documented, not changed.

## Clock: retire `styleLocked`

One-shot migration `clockStyleLocked` in `PluginState` (run on load, guarded
by `migrations`): let `desktop = pluginOptions.clock.style ?? "cookie"` and
`locked = pluginOptions.clock.styleLocked ?? "cookie"`; if `locked !==
desktop`, write `lockOptions.clock.style = locked`; delete
`pluginOptions.clock.styleLocked`; mark. A user with desktop `pixel` and no
stored `styleLocked` saw `cookie` on the lock, and still does.

Clock manifest: the `styleLocked` row goes; every `visibleWhen` that read
`anyOf [style, styleLocked]` reads `style` alone, since the Settings switch
now evaluates the rule against the selected surface. Clock widget:
`clockStyle` is `PluginState.option("clock", "style", "cookie")` and follows
the look through `currentSurface`; the widget's own `lockLook` stays for
centring, presence and the caption. `docs/PLUGINS.md` and
`test_clock_options_contract.py` follow (`SHARED` loses `styleLocked`,
`matches()` expects a single-key rule).

## Settings UI: `PluginOptions.qml`

- `property string surface: PluginState.desktopSurface`, owned by the card.
- A `ConfigSelectionArray` "Applies to" with Desktop / Lock screen, shown
  only when the manifest has a `desktopWidget` (bar-only plugins have no
  lock face). Beneath it on the lock surface, a caption: "Follows the
  desktop until you change a setting here", replaced by a "Reset to desktop"
  `RippleButton` when `PluginState.lockOptionsForked(id)`.
- Every `PluginState.option(...)` / `setOption(...)` in the file passes
  `root.surface` explicitly (`readOption` included, so visibility rules
  follow the selected surface).
- On the lock surface the behaviour bar hides the shared toggles
  (`positionLocked`, `clickThrough`, and "Keep settings across presets",
  which is not an option at all) and the desktop-only size row; the look
  toggles stay.

## Tests

- `tst_layout_surfaces.qml`: read-through, per-key independence, shared keys
  never fork, `null` re-inherits, reset drops the plugin's map only,
  identity no-op.
- `tst_plugin_state.qml`: `option`/`setOption` with an explicit surface;
  the default surface follows `GlobalStates.lockLookActive` (the mock gains
  the property); `loadText` accepts and rejects `lockOptions` shapes; the
  clock migration's three cases (differs → overlay written and key deleted;
  equal → key deleted only; absent → nothing, marker set).
- `test_layout_surfaces_contract.py`: `option`/`setOption` signatures carry
  `surface` and fall back to `currentSurface`; `PluginOptions` passes
  `root.surface` on every read and write; `presets.sh` names `lockOptions`
  beside `lockPositions` in save and apply; `loadText` parses it.
- `test_clock_options_contract.py` updated; `test_presets.py` gains a case
  for `lockOptions` surviving apply and the persist carve-out (following
  its existing `lockPositions` cases).
- Existing pins unchanged: `test_expressive_design_system.py`'s
  `onVerticalRequested` string (the wrapper's call shape does not change).

## Docs

AGENT.md: the "PRESENCE forks" entry gains a sibling: options fork per key
under `lockOptions`, which keys are shared and why, the Settings switch, the
clock migration, and the rule "a widget setting that must differ between
the desktop and the lock is a `lockOptions` key, never a second manifest
key". Directory-map line for `layout_surfaces.js` updated. CHANGELOG:
Added (per-surface widget settings) and Changed (clock's second style row
folded in).

## Out of scope

Per-screen options (options are per plugin, like presence); a whole-plugin
"fork everything" action; Edit Mode UI beyond the in-widget knobs that
already write the current surface.
