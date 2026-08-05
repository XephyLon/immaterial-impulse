# Proposal: cursor settings section

> Implemented. See "Resolution" at the end for how the open questions landed.

## Goal

Add a **Cursor** section to the settings UI so the pointer theme, size, and
zoom behaviour are configurable from the shell instead of being hardcoded in
the Hyprland config.

## Current state

- The cursor theme and size are a hardcoded literal:
  `dots/.config/hypr/hyprland/execs.lua:28` runs
  `hyprctl setcursor Bibata-Modern-Classic 24` at startup. Changing either
  means editing the exec line by hand.
- `dots/.config/hypr/hyprland/general.lua:295` has a `cursor = { ... }` block
  (Hyprland's own cursor options) that no settings page surfaces.
- `dots/.config/hypr/hyprland/keybinds.lua:134-140` already drives
  `cursor:zoom_factor` from keybinds via `hl.config({ cursor = { ... } })`, so
  there is a working precedent for writing cursor settings at runtime.
- Nothing enumerates installed cursor themes.

## Why

- Cursor theme/size is one of the first things a user changes after install,
  and it is currently the only major appearance setting with no UI at all —
  `AppearanceConfig.qml` covers everything else.
- The hardcoded `setcursor` line silently overrides whatever the user sets
  through any other tool on every shell start, so the current behaviour is not
  just unconfigurable, it is actively sticky.
- Cursor size interacts with display scaling, which the shell already exposes.
  Setting one without the other produces a mismatched pointer.

## Approach

- New `modules/imi/settings/pages/CursorConfig.qml`, registered in
  `SettingsContent.qml`'s page list. Follow `AppearanceConfig.qml` for section
  and control conventions.
- Enumerate installed themes by scanning `~/.icons`, `~/.local/share/icons`,
  and `/usr/share/icons` for directories containing a `cursors/` subdirectory.
  Present them in a `ConfigSelectionArray`.
- Write changes through `hl.config({ cursor = { ... } })`, matching the
  keybinds precedent. Do **not** use `hyprctl keyword` — it does not work on
  this Hyprland fork.
- Replace the hardcoded `execs.lua:28` line with one that reads the configured
  values, so the shell stops clobbering the user's choice on every start.
- Expose: theme, size, `zoom_factor`, and `inactive_timeout`.

## Open questions

- Whether to also write `XCURSOR_THEME`/`XCURSOR_SIZE` into the environment for
  XWayland and GTK clients, which do not follow `hyprctl setcursor`. Doing so
  correctly requires the values to be set before clients launch, which means
  touching the session startup path rather than just runtime config.
- Whether hyprcursor themes (Hyprland's own format) should be listed separately
  from XCursor themes; they live in different directories and not every theme
  ships both.

## Out of scope

- Shipping or bundling any cursor theme.
- A cursor theme downloader or store.

## Resolution

Implemented as proposed, with the approach's pieces landing as:

- Schema: `Config.options.hyprland.cursor.{theme,size,zoomFactor,inactiveTimeout}`
  (defaults mirror the formerly hardcoded values, so first open changes nothing).
- Page: `modules/imi/settings/pages/CursorConfig.qml`, registered as **Cursor**
  after Appearance. Theme enumeration lives in
  `scripts/cursor/scan-cursor-themes.py` behind the `CursorThemes` singleton
  (the `IconThemes` pattern), unit-tested in `tests/test_scan_cursor_themes.py`.
- `zoom_factor` / `inactive_timeout` write through `HyprlandConfig.set` →
  `shellOverrides/main.lua` `hl.config(...)` lines, the keybinds precedent.
- Theme/size apply through `scripts/cursor/apply-cursor-theme.sh`
  (`hyprctl setcursor` + GTK 3/4 `settings.ini` + `~/.icons/default/index.theme`
  `Inherits` + best-effort gsettings); config records only on success.
- Startup: `execs.lua` now runs `scripts/apply_saved_cursor.sh`, which reads the
  shell config (legacy dir as fallback) and falls back to the old literals —
  the sticky hardcoded `setcursor` line is gone.
  Tests: `tests/test_cursor_theme_apply.py`, against a fake `hyprctl`.

Open questions resolved:

- **XWayland/GTK:** GTK clients follow the `settings.ini`/gsettings writes;
  X11/XWayland clients resolve the `~/.icons/default/index.theme` `Inherits`
  stub, the standard XCursor default-theme mechanism, without env vars.
  `XCURSOR_THEME`/`XCURSOR_SIZE` are still not exported — that would touch the
  session startup path for little gain over the stub, and stays out of scope.
- **hyprcursor vs XCursor:** listed together, not separately —
  `hyprctl setcursor` accepts both (hyprcursor preferred, XCursor fallback), so
  a split would leak an implementation detail into the picker. The scanner
  reports `xcursor`/`hyprcursor` flags per theme should the UI ever want them.
