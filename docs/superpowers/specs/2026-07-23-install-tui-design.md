# C — Install TUI (+ D: qs-wallpaperengine bundling): design

> Sub-project **C** of the Immaterial Impulse initiative, folding in **D**
> (qs-wallpaperengine). Runs on the A-unified + B-rebranded tree. Depends on
> A and B (done). See the handoff doc for the decomposition.
>
> Status: **design, pending review.** Next after approval: `writing-plans`.

## Scope

Turn the absorbed dots-hyprland installer (`setup` + `sdata/`) into the ImI
plug-and-play installer: a menu-driven TUI over the existing multi-distro
pipeline, a **runtime-only** config deploy, an **optional** qs-wallpaperengine
build (D), and a migration path for existing `illogical-impulse` users.

**In scope:** the TUI front-end, the deploy filter, the WE build/install step,
the illogical→immaterial migration, and surfacing the existing extras as menu
choices.

**Out of scope:** rewriting the per-distro dependency logic (arch/fedora/gentoo/
nix already work — C wraps it). Re-designing the shell itself.

## Architecture

`whiptail`-based menu wrapping `sdata/subcmd-install/*`. Chosen over gum because
whiptail ships on virtually every distro — a gum installer would have to install
gum first. The menu collects choices, exports them as the flags/env the existing
steps already read (`options.sh`, `--fontset`, `--via-nix`, etc.), then runs the
pipeline. `setup install` stays as the non-interactive path; the TUI is the
default when run with no subcommand / `setup` alone.

Launch model (unchanged): Hyprland runs `qs -c $qsConfig` with `qsConfig=ii`
(`dots/.config/hypr/hyprland/execs.lua`). So "which quickshell" is purely a
PATH question — see D.

## Components

### C1 — TUI menu (`sdata/subcmd-install/tui.sh`, new)
```
Immaterial Impulse installer
[x] Core config        [x] Dependencies
[ ] Wallpaper Engine   (builds a custom quickshell)
Extras:  Fontset: (none ▾)   [ ] fcitx5 IME
distro: arch (auto)          [ Install ]
```
Each toggle maps to an existing flag/step. "Wallpaper Engine" gates C3. Fontset
is a picker over `dots-extra/fontsets/`. Multi-select checklist via
`whiptail --checklist`; the fontset via `--menu`.

### C2 — Runtime-only deploy
The config copy (`sdata/subcmd-install/3.files*.sh`, which syncs
`dots/.config/quickshell/ii → ~/.config/quickshell/ii`) gets an **exclude list**
so dev artifacts never land in the deployed dir:
`tests/`, `docs/`, `screenshots/`, `AGENT.md`, `CONTRIBUTING.md`,
`PLUGINS.md`, `PLUGIN_DESIGN_SYSTEM.md`, `README.md`, `.qmlformat.ini`,
`.gitignore`, `*RuntimeTest.qml`, `DesignSystemCompile.qml`.
Implement as rsync `--exclude` (the newer `3.files.sh` already uses rsync) or an
explicit filter for the legacy path. The files stay in the repo (needed for the
pctrade subtree + CI); only the deploy skips them.

### C3 — qs-wallpaperengine (D), optional
New step `sdata/subcmd-install/4.wallpaperengine.sh`, run only if the WE toggle
is set:
1. Add the WE build deps per distro (linux-wallpaperengine's deps + Qt6/CMake) —
   declared alongside the existing per-distro dep lists.
2. Clone `https://github.com/XephyLon/qs-wallpaperengine` (pinned ref) into a
   build dir, run its `bootstrap.sh` + build to produce the patched
   `quickshell` (the one carrying the `Quickshell.WallpaperEngine` module).
3. Install that binary + its runtime libs to a PATH location that shadows the
   distro quickshell (e.g. `/usr/local/bin/quickshell` + `qs` symlink, libs to
   `/usr/local/lib` or a wrapper that sets `LD_LIBRARY_PATH`).
If the toggle is off: nothing — the distro's stock `quickshell` is used and WE
wallpapers degrade to static (the theme already handles this via the
source-URL Loader fallback).

### C4 — Migration (illogical → immaterial)
Detect an existing install and transition it:
- **Packages:** if `illogical-impulse-*` packages are installed (per-distro
  query: `pacman -Qq`, `dnf list installed`, …), offer to install the
  `immaterial-impulse-*` set and remove the old one.
- **Config dir:** the runtime **M1** (`migrate-config-dir.sh`, built in B) moves
  `~/.config/illogical-impulse → ~/.config/immaterial-impulse` on first shell
  start; the installer additionally backs up existing target dirs before
  overwrite (reuse `install_file__auto_backup`).
- **qsConfig:** ensure the Hyprland `qsConfig` env is `ii` (B already renamed the
  dir); a prior `end4-pC` value is rewritten.

### C5 — Extras as menu choices
Surface the existing situational overlays (from `dots-extra/`) as TUI options
rather than a single toggle: the fontset picker (`--fontset`), fcitx5 IME, the
swaylock/emacs/nix bits gated as they already are. No new install logic — the
TUI just sets the flags `options.sh` already consumes.

## Custom-quickshell wiring (D detail)

Because Hyprland launches `qs -c ii`, enabling WE only requires the custom
`quickshell`/`qs` to win on `PATH`. The installer places it in `/usr/local/bin`
(ahead of `/usr/bin`) or ships a small `~/.local/bin/qs` wrapper that runs the
custom binary with the right `LD_LIBRARY_PATH`. No config edits needed for the
launch; the wallpaper selector already drives WE project selection. Uninstalling
WE = remove the custom binary; stock quickshell takes over again.

## Scope boundary

C wraps and extends the existing installer. It does not touch the per-distro
dependency resolution, the theme, or B's migrations beyond invoking them.

## Verification

1. `setup` with no args opens the whiptail menu; selections drive the right steps.
2. After a core install, `~/.config/quickshell/ii` contains **no** `tests/`,
   `docs/`, `AGENT.md`, etc. — only runtime files; the shell launches.
3. WE toggle on (in a VM/container with build deps): the build produces a
   `quickshell` with the WE module; `qs -c ii` uses it and a WE wallpaper renders
   live. WE toggle off: stock quickshell, static wallpaper, no build attempted.
4. On a machine with `illogical-impulse-*` installed and `~/.config/illogical-impulse`
   present: the installer offers the package transition; first shell start moves
   the config dir (M1); nothing is lost.
5. Non-interactive `setup install` still works unchanged (TUI is additive).
