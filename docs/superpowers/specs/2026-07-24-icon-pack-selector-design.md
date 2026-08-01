# Icon Pack Selector — Design

**Status:** approved 2026-07-24. Next step: implementation plan (superpowers:writing-plans).

## Goal

Let the user pick a system-wide icon pack from a visual grid in the shell's
settings. Applying a pack changes the icon theme for GTK/Qt apps *and* the shell
itself, with the shell auto-restarting to pick it up.

## Decisions (from brainstorming)

- **Scope: system-wide.** Writes GTK 3/4 `settings.ini`, `kdeglobals`, and
  gsettings so every app follows, not just the shell.
- **Shell refresh: auto-restart.** GTK/Qt apps update live via the gsettings
  signal; the shell relaunches (~1s flash) to match, since its Qt icon theme is
  fixed at process launch (see Constraint below).
- **Selector UX: preview grid.** Cards rendering real sample icons pulled from
  each theme by file path, so a non-active theme still previews correctly.

## Hard constraint discovered

Quickshell sets its icon theme once, at process launch, via
`QIcon::setThemeName()` driven by a `//@ pragma IconTheme <name>` in `shell.qml`
or the `QS_ICON_THEME` env var (`launch.cpp:134`). There is **no runtime QML API**
to change it, and `Quickshell.reload(true)` (QML hot-reload) does **not**
re-apply it. So the shell can only adopt a new icon theme on a full process
respawn. `shell.qml` currently sets no `IconTheme` pragma, so the shell's Qt
icon theme falls back to the active Qt platform theme's resolution.

## Existing theming pipeline (verified 2026-07-24)

How the shell already applies theming, and why the design fits without conflict:

- `scripts/colors/switchwall.sh` is the canonical theming entry (runs on
  wallpaper change and light/dark toggle). It applies GTK theming the live way:
  `gsettings set org.gnome.desktop.interface gtk-theme …` and `color-scheme …`.
  The icon-theme apply mirrors this exact idiom with the `icon-theme` key.
- **matugen** (`dots/.config/matugen/config.toml`) regenerates only **`gtk-3.0/gtk.css`
  and `gtk-4.0/gtk.css` (colors)**, plus KDE colors into a *state* dir
  (`~/.local/state/quickshell/user/generated/`). It does **not** write GTK
  `settings.ini` or `kdeglobals [Icons]`. Therefore writing `gtk-icon-theme-name`
  into `settings.ini` and `Theme=` into `kdeglobals` is **not clobbered** by the
  next wallpaper/color run — this was the main risk and it is cleared.
- `settings.ini` is user-local and unmanaged by the pipeline (currently
  `gtk-icon-theme-name=breeze-plus-dark`, matching gsettings). Safe to own.

Net: the three write targets (GTK `settings.ini`, `kdeglobals`, gsettings
`icon-theme`) are all safe and consistent with the existing pipeline. The apply
script stays standalone (icon theme is user-selected, orthogonal to the
wallpaper-derived color run), styled after switchwall's gsettings idiom.

## Components

### 1. `services/IconThemes.qml` (Singleton — detection)
- Scans `/usr/share/icons`, `~/.local/share/icons`, `~/.icons`.
- Parses each `index.theme`. Keeps an entry only if it has an `[Icon Theme]`
  section and a `Directories=` list containing real icon directories. **Excludes
  cursor-only packs** (Directories is only `cursors`, or the theme name ends in
  "cursors"). Also skips `default`/`hicolor` as selectable packs.
- Exposes `themes: [{ id, name, path, sampleIcons: [absolutePath, …] }]` where
  `id` is the theme's **directory name** (filesystem-safe, used as the applied
  value), `name` is the `Name=` field (display), `path` is the theme dir.
- `sampleIcons`: for a small fixed list of well-known names
  (`firefox`, `folder`, `text-editor`, `system-settings` — with graceful
  fallback to whatever the theme actually ships), resolve each to a concrete
  file inside the theme dir by walking its `Directories` (prefer a large
  scalable or 48px `apps`/`places` dir). Loading these by absolute path is what
  lets a card preview a theme that is not the currently active one.

### 2. Config
- Add `Config.options.appearance.iconTheme` (string, default `""` = system
  default / no override).

### 3. `modules/ii/settings/pages/IconPackSelector.qml` (UI)
- A new section in the **Interface** settings page (`InterfaceConfig.qml`),
  alongside the existing "Tint app icons" control.
- A responsive grid of cards. Each card:
  - 3–4 `Image { source: "file://" + samplePath }` sample icons from that theme,
  - the theme's display name,
  - an "active" check when `id === Config.options.appearance.iconTheme` (or, when
    that is `""`, when `id` matches the currently resolved system theme).
- Clicking a card applies that theme (see flow below).

### 4. `scripts/icons/apply-icon-theme.sh <id>` (system-wide apply)
Writes, idempotently:
- `~/.config/gtk-3.0/settings.ini` → set/replace `gtk-icon-theme-name=<id>`
  under `[Settings]`.
- `~/.config/gtk-4.0/settings.ini` → same.
- `~/.config/kdeglobals` → set/replace `Theme=<id>` under `[Icons]`.
- `gsettings set org.gnome.desktop.interface icon-theme "<id>"` (emits the live
  change signal GTK/Qt apps listen to). If the schema is missing, skip and
  continue.

**Security:** the `id` is validated **before** any use — it must match one of the
ids `IconThemes.qml` detected AND match `^[A-Za-z0-9 ._+-]+$`. It is passed as a
positional argv element to every command (never spliced into a `bash -c`
string), consistent with the injection hardening in commit 75ef1aec. This blocks
path traversal and command injection through a crafted directory name.

### 5. Auto-restart
- After the apply script exits 0, QML writes `Config.options.appearance.iconTheme`
  and triggers a shell relaunch via `Quickshell.execDetached` of a small
  relauncher (`qs kill` then `qs -c ii`), double-forked so it outlives the
  process it is killing.
- GTK/Qt apps are already updated live by the gsettings step; the relaunch only
  exists so the shell's own icons match.

## Persistence across normal launches (verify during implementation)

The written `kdeglobals` / gsettings / GTK config persist across reboots. The
open question is whether the relaunched shell (and future normal launches from
Hyprland's exec) actually adopt the chosen theme:
- **Preferred path:** the active Qt platform theme (`QT_QPA_PLATFORMTHEME`, e.g.
  `qt6ct`/kde) makes Quickshell's default `QIcon` theme follow `kdeglobals` /
  gsettings on launch — no pragma or env needed.
- **Fallback (if the shell does not follow reliably):** have the relauncher and
  the normal shell launch command export `QS_ICON_THEME=<id>` read from config,
  guaranteeing the shell matches regardless of platform theme.

The plan must include a step that empirically checks which path holds on this
machine and wires the fallback only if needed.

## Data flow

click card → validate `id` against detected set →
run `apply-icon-theme.sh <id>` (argv) → script writes GTK/kdeglobals/gsettings →
on exit 0: set `Config.options.appearance.iconTheme = id` →
`execDetached` relauncher → new shell process reads the theme →
grid re-marks the active card.

## Error handling

- Unknown / malformed `id`: rejected in QML before the script runs; no-op with a
  console warning.
- Missing `gsettings` or schema: skip that step, continue (the `settings.ini` /
  `kdeglobals` writes still take effect on each app's next launch).
- Apply script is idempotent (re-selecting the same theme is a safe no-op that
  still restarts).

## Testing

- **apply-icon-theme.sh** (bash/python test in a temp `$HOME`): asserts
  `gtk-3.0`/`gtk-4.0` `settings.ini` and `kdeglobals` receive the correct key;
  asserts a bad name / `../` traversal / injection attempt is rejected and writes
  nothing.
- **IconThemes detection**: fixture `index.theme` files → asserts a real app
  icon theme is kept and a cursor-only pack is excluded.
- No rendered-visual automated test (repo convention; `qmltestrunner` covers
  logic only). Manual spot-check of the grid + one apply + restart.

## Files

- Create: `services/IconThemes.qml`,
  `modules/ii/settings/pages/IconPackSelector.qml`,
  `scripts/icons/apply-icon-theme.sh`,
  `tests/test_icon_theme_apply.py` (+ detection fixture/test).
- Modify: `modules/common/Config.qml` (add `appearance.iconTheme`),
  `modules/ii/settings/pages/InterfaceConfig.qml` (host the selector section).
- Verify/maybe-modify: shell launch command (only if the `QS_ICON_THEME`
  fallback is needed).
