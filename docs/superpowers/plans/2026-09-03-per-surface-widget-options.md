# Per-surface widget options — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Revised after review:** Tasks 3 and 4 were withdrawn (no per-card switch; the clock keeps `styleLocked`). Settings rows pass `PluginState.desktopSurface` explicitly. See the spec's Revision note.

**Goal:** A widget's settings fork per surface (desktop / lock screen) the way its position, span and presence already do, with a Settings switch to reach the lock's values and the clock's hand-rolled `styleLocked` folded in.

**Architecture:** `lockOptions[pluginId][key]` beside `pluginOptions` in `plugin-state.json`; absence of a key is per-key inheritance from the desktop. The pure rules live in `layout_surfaces.js`; `PluginState.option/setOption` gain a trailing `surface` defaulting to `currentSurface`, so every existing caller follows the look. `PluginOptions` owns a Desktop / Lock screen switch and passes the surface explicitly. A one-shot migration moves the clock's `styleLocked` into the overlay.

**Tech Stack:** Quickshell QML, `.pragma library` JS, qmltestrunner, Python unittest contracts, jq in `scripts/presets.sh`.

Spec: `docs/superpowers/specs/2026-09-03-per-surface-widget-options-design.md`. Paths under `dots/.config/quickshell/imi/` unless noted.

---

### Task 1: The pure rules (TDD in `tst_layout_surfaces.qml`)

**Files:** `modules/common/plugins/layout_surfaces.js`, `tests/tst_layout_surfaces.qml`

- [ ] Tests: `rawOption` reads the lock key when stored, reads through when absent, answers the desktop for `DESKTOP`; a shared key (`positionLocked`) reads the desktop even on `LOCK`; `withOption(LOCK)` writes `lockOptions` only and leaves `pluginOptions` untouched; `withOption(LOCK, shared key)` writes `pluginOptions`; `withOption(LOCK, null)` deletes the lock key so it re-inherits; `withOption(DESKTOP, null)` deletes the desktop key (today's semantics); `isOptionsForked`; `withoutLockOptions` drops one plugin's map and returns the same object when nothing to drop.
- [ ] Run red → implement (code in the spec's Store section; `SHARED_OPTION_KEYS`, `isSharedOptionKey`, `rawOption`, `withOption`, `isOptionsForked`, `withoutLockOptions`) → run green.
- [ ] Commit: `feat(plugins): widget options fork per surface in the pure store rules`

### Task 2: PluginState carries and serves it (TDD in `tst_plugin_state.qml`)

**Files:** `modules/common/plugins/PluginState.qml`, `tests/tst_plugin_state.qml`, `tests/imports/qs/GlobalStates.qml` (add `property bool lockLookActive: false`, `property bool editLockPreview: false`)

- [ ] Tests: `option(id, key, fb, LOCK)` inherits then overrides after `setOption(..., LOCK)`; desktop unchanged; default surface follows `GlobalStates.lockLookActive`; `lockOptionsForked` / `resetLockOptions`; `loadText` keeps a `lockOptions` map and drops a list; the `clockStyleLocked` migration (differs / equal / absent) through a pure `stateWithClockStyleMigrated(state)`.
- [ ] Implement: `emptyState.lockOptions`, `loadText`, `option(pluginId, key, fallback, surface)`, `setOption(pluginId, key, value, surface)` via `Surfaces.withOption`, `lockOptionsForked`, `resetLockOptions`, `stateWithClockStyleMigrated` + `runClockStyleMigration()` called from `loadText` after `ready` (guarded by `migrationRan("clockStyleLocked")`).
- [ ] Commit: `feat(plugins): PluginState.option and setOption take a surface`

### Task 3: Settings switch

**Files:** `modules/common/plugins/PluginOptions.qml`

- [ ] `property string surface: PluginState.desktopSurface`; `ConfigSelectionArray` "Applies to" (Desktop `desktop_windows` / Lock screen `lock`) shown when `manifest.desktopWidget !== undefined`; caption / "Reset to desktop" button; every `option`/`setOption` passes `root.surface`; shared behaviour toggles, preset-persist toggle and size rows hidden on the lock surface.
- [ ] Lints: `lint_spacing`, `lint_material_icons`, `lint_qml_imports`, `lint_icon_glyph_alignment`.
- [ ] Commit: `feat(settings): a Desktop / Lock screen switch on every widget's options`

### Task 4: Clock folds `styleLocked` in

**Files:** `modules/common/plugins/bundled/clock/manifest.json`, `.../clock/Widget.qml`, `docs/PLUGINS.md`, `tests/test_clock_options_contract.py`

- [ ] Remove the `styleLocked` row; rewrite every `visibleWhen: {anyOf:[{key:style,in:[S]},{key:styleLocked,in:[S]}]}` to `{key: "style", in: [S]}`; `clockStyle: PluginState.option("clock", "style", "cookie")`, drop `styleLocked`; contract `SHARED` and `matches()` updated; PLUGINS.md sentence updated.
- [ ] Commit: `refactor(clock): the lock's style is the style option on the lock surface`

### Task 5: Presets carry `lockOptions`

**Files:** `scripts/presets.sh`, `tests/test_presets.py`

- [ ] `lockOptions: (.lockOptions // {})` in both save shapes, the apply `has()` rule, the empty fallbacks, and the persist carve-out (`.lockOptions[$id]` kept / deleted like `.pluginOptions[$id]`). Test: round trip + old preset keeps the overlay + persist shields it.
- [ ] Commit: `feat(presets): a preset carries the lock screen's widget options`

### Task 6: Contracts

**Files:** `tests/test_layout_surfaces_contract.py`

- [ ] `option`/`setOption` signatures carry `surface`; `PluginOptions` passes `root.surface` on every `PluginState.option(`/`setOption(`; `presets.sh` names `lockOptions` in save and apply; `loadText` parses it; `PluginWidget` still reads `positionLocked`/`clickThrough` with no surface (shared).
- [ ] Commit: `test(plugins): pin the surface on every widget option read and write`

### Task 7: Docs, suite, deploy, PR

**Files:** `AGENT.md`, `CHANGELOG.md`

- [ ] AGENT.md entry after the PRESENCE entry + directory-map line; CHANGELOG Added + Changed. Commit `docs: widget options fork per surface`.
- [ ] Suite via `setsid -f`; deploy; drive live: Settings > Plugins > System Monitor → Lock screen → toggle Vertical; lock preview shows the change, desktop does not; Reset to desktop re-inherits.
- [ ] Push, PR with `Docs: updated ...` and `Changelog: updated`.
