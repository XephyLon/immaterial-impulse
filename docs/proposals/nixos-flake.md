# Proposal: NixOS flake

> Draft / tracking proposal. Not scheduled.

## Goal

Expose Immaterial Impulse as a first-class Nix flake at the repository root — a
`nixosModule`, a `homeManagerModule`, and a buildable package — so a NixOS user
adds the shell declaratively instead of running an imperative installer that
copies files into `~/.config`.

## Current state

There is already Nix support, but it is upstream-inherited, marked WIP, and is
not what a NixOS user would expect.

`sdata/dist-nix/README.md` says it in one line:

```
# Install scripts using Nix to achieve cross-distros
- This directory is currently WIP.
```

What exists:

- `sdata/dist-nix/home-manager/flake.nix` — a flake **nested inside the repo's
  data directory**, not at the root. It pins `nixpkgs/nixos-25.11`,
  home-manager `release-25.11`, and quickshell at a **hardcoded commit**
  (`7511545e…`).
- `sdata/dist-nix/home-manager/quickshell.nix` — a `stdenv.mkDerivation` wrapper
  that bundles Qt deps around the upstream quickshell package. Carries commented-out
  `nixGL` plumbing.
- `sdata/dist-nix/home-manager/home.nix`, plus a `flake.lock`.
- `sdata/dist-nix/install-deps.sh` — sourced by the installer's `--via-nix`
  path. It **installs Nix itself** (via the experimental installer), installs
  home-manager via `nix-channel`, then runs
  `home-manager switch --flake .#immaterial_impulse`.
- `sdata/dist-nix/outdate-detect-mode` contains the single word `WIP`.

The flake reads `./username.nix` — a file that is not in the tree — so the
existing configuration is not usable as-is without generating that first. And
`install-deps.sh` warns the user directly:

```
If you are already using home-manager,
it may override your current config,
```

Meanwhile the actual install path is `get.sh` → `setup` → whiptail TUI →
`sdata/subcmd-install`, which copies `dots/` into `~/.config` and runs
permission/service setup. That is the supported path on Arch, Fedora and Gentoo
(`sdata/dist-arch`, `dist-fedora`, `dist-gentoo`), and Nix is bolted onto the
side of it rather than being an alternative to it.

## Why

- **The imperative installer and Nix are opposed.** `setup install-files` copies
  a tree into `~/.config/quickshell/imi` and `~/.config/immaterial-impulse`. On
  NixOS that is the wrong shape: those paths want to be managed by
  home-manager, and anything the installer writes is invisible to the system
  configuration and lost on rollback.
- **The current flake is not addressable.** A flake at `sdata/dist-nix/home-manager/`
  cannot be consumed as `inputs.immaterial-impulse.url = "github:XephyLon/immaterial-impulse"`.
  A root flake can.
- **The dependency list already exists in a machine-readable form** —
  `sdata/deps-info.md` plus the per-distro `dist-*` directories. Deriving a Nix
  package's `buildInputs` from the same source keeps them from drifting.
- **A known hazard this would fix**: the dots-hyprland-style update flow *deletes*
  `~/.config/quickshell` before reinstalling. Declarative management removes that
  class of accident entirely.

## Sketch

Rough shape, not a design:

1. **Root `flake.nix`** with, at minimum:
   - `packages.<system>.immaterial-impulse` — the shell tree as a derivation
     (the `dots/.config/quickshell/imi` contents plus scripts), so it can be
     referenced by store path rather than copied.
   - `homeManagerModules.default` — options for enabling the shell, choosing a
     panel family, and seeding `~/.config/immaterial-impulse/config.json`.
   - `nixosModules.default` — the system-level pieces the installer currently does
     in `install-setups`: services, polkit rules, greeter/SDDM theme, plymouth.
   - `devShells.default` — quickshell + Qt + the Python test deps, so
     `tests/run_tests.sh` runs under `nix develop`.
2. **What is declarative vs mutable — settled, see the section below.** The
   split is three-way, not two-way, and the third tier is the one that decides
   whether a `home-manager switch` quietly destroys the user's colours.
3. **Reconcile with the existing `sdata/dist-nix` tree** — either promote it to
   the root and delete the nested flake, or keep `--via-nix` as a legacy path and
   mark it superseded. Do not ship two flakes.
4. **Unpin quickshell** from the hardcoded commit, or at least move the pin
   somewhere it is obviously a pin.
5. **CI**: `nix flake check` on push is the only thing that keeps a flake honest.

## Declarative vs mutable — settled

Checked against the tree at `4b43790`, not assumed.

### The QML tree can be a read-only store path

Nothing writes into it. Every consumer of `writeAdapter` / `setText`
(`modules/common/Config.qml`, `Persistent.qml`, `plugins/PluginState.qml`,
`services/{Notifications,Cliphist,Todo,FirstRunExperience}.qml`) targets the
config or state directory. The only `path: Quickshell.shellPath(...)` bindings
in the tree are **reads** — the two bundled plugin `manifest.json` files, and
`VERSION` from the About page and the plugin store.

So `dots/.config/quickshell/imi` can be a store path, which is the whole premise
of the flake, and no part of the shell has to be relaxed to allow it.

### Three tiers, not two

| tier | what | where it lives |
|---|---|---|
| immutable | the QML tree, `scripts/`, matugen **templates** | store path, symlinked |
| seeded once | `config.json`, `plugin-state.json`, `plugins/<id>/` | real files under `~/.config/immaterial-impulse`, written by an activation script only when absent |
| **never managed** | every matugen **output** | plain files, owned by the running shell |

That third tier is the trap. `dots/.config/matugen/config.toml` declares 11
output paths that matugen **rewrites on every wallpaper change**, and six of them
are ordinary dotfiles a home-manager user would reasonably expect to be
declarative:

```
~/.config/hypr/hyprland/colors.lua      ~/.config/gtk-3.0/gtk.css
~/.config/hypr/hyprlock/colors.conf     ~/.config/gtk-4.0/gtk.css
~/.config/kitty/colors-matugen.conf     ~/.config/fuzzel/fuzzel_theme.ini
```

plus five under `~/.local/state/quickshell/user/generated/` (`colors.json`,
`color.txt`, `apps/cava.ini`, `apps/tmux.conf`, `wallpaper/path.txt`).

If the module writes any of those with `home.file`, home-manager makes them
symlinks into the store. Matugen then either fails against a read-only target or
replaces the symlink with a regular file — and the next `home-manager switch`
reverts the user's generated colours with no error. Both outcomes are silent.

**Rule: manage the templates, never the outputs.** A user who wants their
Hyprland colours declarative wants a different feature (a static palette with
matugen off), not this one, and the module should make that an explicit option
rather than an accident of which files it happened to link.

### Consequence for the module

`homeManagerModules.default` therefore owns the immutable tier outright, seeds
the second tier idempotently, and must *refuse* to touch the third. Options that
seed `config.json` need `lib.mkDefault` semantics — the file is the user's after
first write, and a switch must not stamp on it.

## Out of scope for the first flake

The embedded Wallpaper Engine renderer. `qs-wallpaperengine` builds a patched
Quickshell against `linux-wallpaperengine`, which is not in nixpkgs and pulls
CEF, mpv and SDL; the installer's fast path is a prebuilt tarball made in an
Arch container. A Nix user gets the shell with static wallpapers, and
`wallpaperSelector.wallpaperEngine` stays inert. Packaging that dependency tree
is its own proposal.

## Open questions

- Does the plugin system work under Nix? Partly answered: **bundled** plugins are
  read through `Quickshell.shellPath()` and are fine in a store path, and
  **installed** plugins live in `~/.config/immaterial-impulse/plugins/<id>/`,
  which the table above puts in the seeded-once tier. What is still open is
  whether a plugin installed at runtime can load from a mutable directory while
  the rest of the tree is immutable, and what `PluginState.qml` does when its
  state file names a plugin the current generation no longer ships.
- The installer's update path (`exp-update`, `exp-merge`) uses `git rebase`
  against a checkout. That has no meaning under a flake. What replaces
  Settings → Update Dots for a Nix user?
- `scripts/` shells out to a lot of binaries (`matugen`, `grim`, `slurp`,
  `hyprctl`, `ffmpeg`, ImageMagick, `cava`, `ydotool`…). Each is a `makeWrapper`
  `PATH` entry that has to be enumerated — the per-distro dep lists are the
  starting point, but they are package names, not binary names.
- Single-user vs system-wide, and whether the NixOS module is genuinely needed
  or whether home-manager alone covers it.

## Prior art

`sdata/dist-nix/home-manager/quickshell.nix` already solved the Qt-wrapping
problem for quickshell itself and should be reused rather than rewritten. The
upstream dots-hyprland project's Nix community packaging is the other obvious
reference.
