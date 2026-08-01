# Widgets page IA — design

**Date:** 2026-08-01
**Status:** approved, ready for planning
**Scope:** Cycle 1 of the widget-unification initiative (see "Relationship to other work")

## Goal

Turn the Plugins settings page into a **Widgets** page with a search field and
capability filter chips, and promote the store's page-local `FilterChip` into a
shared component so the two surfaces cannot drift.

This is user-facing IA and component-sharing work only. It ships independently,
touches no plugin data, and requires no config migration.

## Motivation

Three problems, all visible today:

1. **The page is named for the mechanism, not the thing.** Users look for
   "widgets"; the settings entry says "Plugins". A recurring support complaint
   is that widgets "can't be turned off" because people never find the Plugins
   page. Defaulting `plugins.enabled` to `[]` (v0.10.0) removed the symptom for
   new installs but not the discoverability problem.
2. **No way to narrow the list.** Every installed plugin renders in one flat
   column. Once the built-in desktop widgets are ported (Cycle 2, ~10 more
   entries) that list becomes unusable.
3. **`FilterChip` is trapped in a gated-off page.** `PluginStorePage.qml:99`
   defines `component FilterChip: RippleButton` as a page-local type. The store
   is gated off behind `Config.options.plugins.storeEnabled`, so the one place
   this project has a working filter-chip implementation is a place users cannot
   reach. This is the same bespoke-component anti-pattern already corrected for
   the Docker plugin via the shared `ExpandablePanel`.

## Non-goals

- Porting the 10 hardcoded `FadeLoader` widgets in `Background.qml` to bundled
  plugins. That is Cycle 2 and carries a config migration.
- Flipping `Config.options.plugins.storeEnabled`. The store stays gated; the
  public registry does not exist yet.
- Renaming any type, file, config key, or service. See "Renaming policy".
- Adding a `category` manifest field (the DMS reference's second facet axis).
  Deferred — it needs a schema bump, a backfill across all 8 bundled plugins,
  and a fallback for third-party manifests that omit it. Revisit if the entry
  count after Cycle 2 justifies a second axis.

## Design

### 1. Shared `FilterChip`

Create `modules/common/widgets/FilterChip.qml`, moving the body of
`PluginStorePage.qml:99`'s page-local `component FilterChip: RippleButton`
unchanged. Delete the page-local definition; `PluginStorePage` picks the type up
from its existing `import qs.modules.common.widgets`.

`modules/common/widgets/` has **no `qmldir`** — it is a directory import, so a
new file needs no registration entry. It does need a full `qs` restart to be
picked up; hot reload will not register a new type.

Public API is whatever the existing component already exposes (`label`,
`chipIcon`, `toggled`, `clicked`) — this is a move, not a redesign. Do not add
properties speculatively.

### 2. Canonical capability vocabulary

`capabilityOptions` is currently hardcoded at `PluginStorePage.qml:39` and lists
three values. It is wrong in two ways: it omits `overlay-widget`, which
`discordVoice` actually declares, and it is duplicated the moment a second page
needs it.

Expose the list once, from `PluginManager`, as `surfaceCapabilities`:

| value | label | icon |
|---|---|---|
| `desktop-widget` | Desktop | `widgets` |
| `bar-widget` | Bar | `toast` |
| `overlay-widget` | Overlay | `layers` |
| `panel` | Panel | `side_navigation` |

Both `PluginStorePage` and the Widgets page read from it.

**`settings` is deliberately excluded.** It appears in `docker` and
`discordVoice` manifests but means "this plugin has options", not "this plugin
draws on surface X". It is not a facet.

**Fallback rule for manifests with no `capabilities`:** a manifest that declares
no `capabilities` array but does have a `desktopWidget` block is treated as
`desktop-widget` for filtering. Without this rule `clock` — whose manifest is
the older declarative-JSON generation (`desktopWidget` with a type/props/children
tree and no `capabilities` key) — matches no chip and disappears from every
filtered view.

### 3. Widgets page

`PluginsPage.qml`'s `ContentSection` gains, above the existing plugin list:

- A search field: `ConfigTextArea` with `buttonIcon: "search"`,
  `singleLine: true`. Note `ConfigTextArea.text` is the **label**; the typed
  value is `ConfigTextArea.value` (an alias to `textArea.text`). The store reads
  it this way at `PluginStorePage.qml:46`.
- A `Flow` of `FilterChip`s, one per `PluginManager.surfaceCapabilities` entry,
  plus a trailing `Third-party` chip.

Filtering applies to `PluginManager.availablePlugins`:

- **Search:** case-insensitive substring match against plugin name and
  description, on the trimmed query. Empty query matches everything.
- **Capability:** single-select, click-active-chip-to-clear. This mirrors the
  store's existing expression at `PluginStorePage.qml:193`
  (`filter === value ? "" : value`) exactly, so the shared chip needs no new
  selection semantics.
- **Third-party:** boolean chip. A plugin is third-party when
  `modelData._origin === "installed"` — the same condition the existing
  third-party badge uses at `PluginsPage.qml:294`. Bundled plugins ship with the
  shell and have a different `_origin`.
- Filters combine with AND.

When filters exclude everything, show an empty-state line rather than a blank
section.

### 4. Renaming policy

**User-facing strings only.**

| Location | From | To |
|---|---|---|
| `SettingsContent.qml:147` `name` | `Plugins` | `Widgets` |
| `SettingsContent.qml:147` `icon` | `extension` | `widgets` |
| `SettingsContent.qml:147` `sections` | `Available Plugins` | `Available Widgets` |
| `PluginsPage.qml` `ContentSection.title` | `Available Plugins` | `Available Widgets` |
| `PluginStorePage` user-facing strings | "plugin(s)" | "widget(s)" |

Store strings are included so the surface is consistent whenever `storeEnabled`
is eventually flipped, even though it is off today.

**Unchanged:** `PluginManager`, `PluginStore`, `PluginWidget`, `PluginNode`,
`PluginState`, `PluginValidator.js`, `PluginsPage.qml`, `PluginStorePage.qml`,
the `plugins.*` config keys, and the `plugins.enabled` array.

Renaming config keys would break every existing install for no user benefit.
Renaming types and files while the services keep `Plugin*` names would leave the
codebase half-and-half, which is worse than either consistent choice. The
mechanism stays "plugins"; the user-facing noun becomes "widgets".

### 5. Security note

`PluginStorePage`'s existing contract is that every registry-sourced string
renders with `textFormat: Text.PlainText`, so a malicious index cannot inject
rich text (pinned by `tests/test_plugin_store_contract.py`). The Widgets page
renders **locally installed** manifest strings, which are attacker-controlled in
the same way a malicious shared preset is.

The page does not render them directly. `PluginsPage.qml:244` and `:249-257`
feed `modelData.name`, `.description`, `.author` and `.version` into a
`ConfigSwitch`, and `ConfigSwitch.qml:34-47` renders both through `StyledText`.
`StyledText` sets no `textFormat`, so it inherits Qt's default `Text.AutoText`,
which auto-detects and renders rich text — a manifest named `<img src=…>`
renders as markup today.

The fix therefore belongs in `ConfigSwitch`, which closes the hole for every
settings surface rather than this page alone. It is safe: all 168 `ConfigSwitch`
call sites pass plain strings, and this codebase opts *into* rich text
explicitly where it wants it (`modules/common/widgets/NotificationItem.qml:174`
sets `textFormat: Text.StyledText`).

## Testing

**Contract test** — `tests/test_widgets_page_filters.py`, in the style of
`tests/test_expandable_panel.py` (source-greppable pins on things that fail
silently):

- `FilterChip.qml` exists at `modules/common/widgets/FilterChip.qml`.
- `PluginStorePage.qml` no longer declares `component FilterChip`.
- `PluginManager` declares `surfaceCapabilities`, and it contains all four
  values including `overlay-widget`.
- `surfaceCapabilities` does **not** contain `settings`.
- The no-`capabilities` → `desktopWidget` fallback exists.
- Plugin name and description render with `Text.PlainText` on the Widgets page.

**Runtime check** — via `qs -p`, on a full restart (new type registration):

- Filtering by `Desktop` returns `clock` (proves the fallback rule works — this
  is the one that silently regresses).
- Filtering by `Bar` returns `docker`.
- Filtering by `Overlay` returns `discordVoice`.
- Clicking the active chip clears the filter.
- Search narrows by name and by description.

## Relationship to other work

This is Cycle 1 of three. The cycles are independent deliverables:

- **Cycle 1 (this spec)** — Widgets page IA. No data migration.
- **Cycle 2** — port the 10 hardcoded `FadeLoader` widgets in `Background.qml`
  to bundled plugins. Must also reconcile that `clock` and `notes` currently
  exist *twice* (as bundled plugins and as hardcoded widgets driven by
  `Config.options.background.widgets.{clock,notes}.enable`, `Background.qml:794-819`),
  unify the two manifest generations, and migrate
  `background.widgets.*.enable` → `plugins.enabled`. That migration is
  load-bearing: `plugins.enabled` now defaults to `[]`, so a naive port would
  silently switch off widgets users currently have enabled.
- **Cycle 3** — flip `storeEnabled` when the public registry exists.

Cycle 1 first because it is independent, has no migration risk, and gives
Cycle 2 a filterable page to land 10 new entries in rather than a wall of rows.

The original PR #11 (`proposal/widgets-as-plugins`, `docs/proposals/widgets-as-plugins.md`)
is the Cycle 2 proposal. It is docs-only and remains open.

## Critical files

- `modules/common/widgets/FilterChip.qml` — new, moved from the store page
- `modules/common/plugins/PluginManager.qml` — `surfaceCapabilities`
- `modules/imi/settings/pages/PluginsPage.qml` — search + chips + filtering
- `modules/imi/settings/pages/PluginStorePage.qml` — drop local `FilterChip`,
  read shared vocabulary, string rename
- `modules/common/widgets/ConfigSwitch.qml:34-47` — plain-text hardening
- `modules/imi/settings/SettingsContent.qml:147` — nav entry rename
- `tests/test_widgets_page_filters.py` — new contract test
