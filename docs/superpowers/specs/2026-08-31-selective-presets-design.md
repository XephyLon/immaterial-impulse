# Selective preset application — design

Approved 2026-08-31. Applies to the preset system in
`dots/.config/quickshell/imi` (`services/Presets.qml`, `scripts/presets.sh`,
Settings > Profile's preset cards).

## Problem

Apply is all-or-nothing: a preset is a full `config.json` snapshot plus
`_pluginState`, and applying one replaces the look, the layout, the widget
arrangement, and the `apps.*` launch commands in one stroke. The maintainer
wants to mix presets ("apply this one's wallpaper and colors over that one's
layout") — and, with online preset sharing planned, applying a preset's
shell-executed `apps.*` strings silently is a standing injection hazard
(see memory/AGENT notes on preset `apps.*` injection).

## Decisions (made with the maintainer)

- Partition grain: **medium, ~6 groups** plus a separated commands row.
- Flow: **Apply always opens the popup**, ordinary groups preselected, so
  Enter ≈ today's behaviour; partial apply is always discoverable.
- Security: **App launch commands are their own row, never preselected**,
  whatever the preset's origin. "Select all" never selects it. Imported
  presets later inherit this posture for free.
- Approach: **script-side filtering** (A). One merge path; the popup passes
  resolved section names; jq filters the preset before the existing merge.

## Units

### 1. `preset_groups.js` (pure, the single partition definition)

Location: `modules/common/functions/preset_groups.js`.

- `GROUPS`: ordered list of `{ id, icon, label-key, sections: [..],
  defaultOn }` where `sections` entries are either a top-level config key
  (`"background"`) or a dotted `appearance.*` subsection
  (`"appearance.palette"`). The commands group is
  `{ id: "commands", sections: ["apps"], defaultOn: false }`.
- Membership:
  - wallpaper: `background`, `wallpaperSelector`
  - theming: `appearance.palette`, `appearance.autoTheme`,
    `appearance.wallpaperTheming`, `appearance.transparency`,
    `appearance.extraBackgroundTint`, `appearance.fakeScreenRounding`, `light`
  - fonts: `appearance.fonts`, `appearance.iconTheme`,
    `appearance.clockFonts`, `appearance.terminal`
  - panels: `bar`, `dock`, `sidebar`, `tray`, `osd`, `overview`, `panelFamily`
  - widgets: `_pluginState`, `plugins`, `appearance.clock`,
    `appearance.atAGlance`, `appearance.mediaWidget`,
    `appearance.currencyWidget`, `appearance.weatherWidget`,
    `appearance.systemMonitor`, `appearance.openrgb`, `appearance.motion`,
    `appearance.lyrics`
  - commands: `apps`
  - everything-else: implicit — every preset key no other group claims.
- `groupOf(sectionKey)` → group id, falling to `"rest"`; a key can never be
  unclaimed, so a future config section cannot escape the popup.
- `sectionsFor(preset, selectedGroupIds)` → the concrete argument list for
  the script: top-level keys plus `appearance:<sub>` spellings for partial
  appearance, plus `_pluginState` iff widgets selected. Only sections
  actually present in the preset are returned.
- `presentCounts(preset)` → per-group section counts for the popup's
  subtitles (0 → the row renders disabled, "not in this preset").

### 2. `scripts/presets.sh --apply <name> [--only <spec,...>]`

- No `--only`: exactly today's behaviour (back-compat; old callers, tests).
- With `--only`: before the existing merge, the preset JSON is filtered by a
  jq program built from the spec list:
  - a bare key keeps that top-level section;
  - `appearance:<sub>` keeps only the named `appearance` subsections
    (deep-merged over the live `appearance` rather than replacing it);
  - `_pluginState` is included only when named; the `presetPersist`
    machinery inside the existing merge is untouched.
- `_presetMeta` never applies (it is card metadata).
- One jq write to config.json as today — atomicity unchanged.

### 3. `services/Presets.qml`

- `apply(name, sections)` — `sections` a list from
  `PresetGroups.sectionsFor`; passed as one comma-joined `--only` argv
  element (section names are config keys, sanitized by construction; still
  passed as its own argv element, never shell-spliced).
- The wallpaper reset (`Wallpapers.confirmedPath = ""` etc.) runs only when
  the wallpaper group is among the selections — an unticked wallpaper group
  must not clear the current wallpaper.

### 4. The popup (`modules/imi/settings/pages/PresetApplyDialog.qml`)

- The shell's standard dialog surface, opened by the card's Apply.
- Header: preset name + description + wallpaper thumbnail (the card already
  extracts it).
- One `ConfigSwitch` row per group: icon, label, subtitle "N sections";
  disabled with "not in this preset" when N = 0.
- Divider, then the commands row: warning subtitle ("Runs shell commands
  from the preset — review before enabling"), error-toned icon, always off
  on open.
- Footer: Cancel / Apply (Apply disabled when nothing is selected).
- Keyboard: Enter applies, Escape cancels.

## Error handling

- Old/partial presets: filtered jq yields fewer keys; the merge keeps live
  values for everything omitted (existing, proven semantics).
- Unknown group spec in `--only`: the script exits non-zero without writing.
- Preset file unparseable: the popup shows the card's existing failure path
  (log + no dialog data); Apply falls back to disabled rows.

## Tests

- `tst_preset_groups.qml`: every key of a captured real preset fixture is
  claimed by exactly one group; `apps` is claimed by `commands` and
  `defaultOn` is false there and only there; `sectionsFor` includes
  `_pluginState` iff widgets selected; unknown keys land in `rest`.
- `tests/test_presets_apply_only.py`: runs `presets.sh --apply --only`
  against fixture config + preset in a temp `$XDG_CONFIG_HOME`: only the
  chosen sections change; `apps` survives untouched unless named;
  `--apply` without `--only` produces today's full merge byte-for-byte.
- Popup: structural pins (commands row not preselected, select-all excludes
  it) in the settings contract tests.

## Out of scope

Online preset import/sharing itself; per-preset remembered selections;
sanitizing `apps.*` contents (the fence here is "never applied unasked").
