# Proposal: NixOS flake

> In progress. The first pass is implemented on `feat/nixos-flake`: a root
> `flake.nix` with `packages.<system>.immaterial-impulse`,
> `homeManagerModules.default` and `devShells.default`, the three-tier
> declarative/mutable split as designed below, and the nested
> `sdata/dist-nix` flake marked superseded. See "Sketch" for the per-item
> status and "Open questions" for what the implementation resolved.

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

Status per item, now that the first pass exists:

1. **Root `flake.nix`** — done, with one deliberate omission:
   - `packages.<system>.immaterial-impulse` — **done** (`nix/package.nix`):
     the `dots/.config/quickshell/imi` tree, whole, as a store path.
     `packages.<system>.quickshell-wrapped` sits beside it, importing the
     nested flake's `quickshell.nix` (Qt bundling reused, not rewritten).
   - `homeManagerModules.default` — **done** (`nix/hm-module.nix`): enable
     option, package overrides, and the three-tier split below implemented
     exactly — tier 1 symlinked from the store, tier 2 seeded by an
     activation script only when absent (`seedConfig` gates the
     `config.json` half), tier 3 refused, with warnings when the
     surrounding home-manager configuration manages a matugen output.
     No panel-family option: the shell has exactly one family today.
   - `nixosModules.default` — **omitted, deliberately**, rather than
     stubbed. The home-manager module covers the shell itself; the
     system-level pieces (SDDM theme, plymouth, polkit rules, services)
     have no flake story yet and stay under "Open questions".
   - `devShells.default` — **done** (`nix/dev-shell.nix`): qmltestrunner
     via `qt6.qtdeclarative`, python3 with PIL/numpy, weston, dbus and the
     wrapped quickshell, so `tests/run_tests.sh` can run under
     `nix develop`. The dev shell itself evaluates (`nix flake check`
     covers it); `run_tests.sh` under `nix develop` has not been run yet.
2. **What is declarative vs mutable — settled and implemented.** The
   split is three-way, not two-way, and the third tier is the one that decides
   whether a `home-manager switch` quietly destroys the user's colours.
3. **Reconcile with the existing `sdata/dist-nix` tree** — done, by marking
   `--via-nix` superseded (`sdata/dist-nix/README.md`) rather than deleting
   the nested flake: that flake plus `install-deps.sh` is the whole working
   path for non-NixOS distros via standalone home-manager, and nothing in
   the root flake replaces it yet. The one file they would duplicate,
   `quickshell.nix`, is shared — the root flake imports it in place.
4. **Unpin quickshell** — done: the root flake's input has no commit in
   its URL; the pin lives in the committed `flake.lock` (nixpkgs at
   nixos-25.11, quickshell following the mirror's default branch).
5. **CI**: `nix flake check` on push is the only thing that keeps a flake
   honest. **TODO — not in this pass.** It has been run by hand, and
   passes; see "Validated so far" below.

## Validated so far

Run via rootless `nix-portable` (nix 2.20.6) on the authoring machine,
which has no system nix:

- `nix flake check` — green. First run caught a real bug: fixupPhase's
  shebang patcher aborts on `generate_colors_material.py`'s `env -S`
  venv-activating interpreter directive; the package now sets
  `dontPatchShebangs` and ships the tree byte-identical.
- `nix build .#immaterial-impulse` — green; output tree verified verbatim
  (VERSION, exotic shebang intact, `defaults/config.json` and bundled
  plugins present).
- A consumer-side home-manager eval (home-manager `release-25.11`):
  `homeManagerConfiguration` with the module enabled **builds a full
  generation**, its activation script contains the seed-once logic, and a
  probe config that manages `xdg.configFile."gtk-3.0/gtk.css"` — a matugen
  output — makes the module emit exactly the tier-3 warning.

- A NixOS VM test (`testers.runNixOSTest`, qemu/KVM): a full NixOS guest
  with the module enabled boots, activation succeeds, and in-guest
  assertions hold — both tier-1 symlinks resolve into a read-only store,
  `config.json` seeds byte-equal to the package's defaults as a real
  file, a user overwrite of it **survives a service restart** (seed-once
  proven live, not just read from the script), no matugen output is
  store-managed, and `qs --version` runs from the user profile. The test
  flake needs a home-manager input the root flake deliberately lacks, so
  it lives outside the tree for now; folding it into CI is part of the
  CI TODO above.

Not yet validated: running the shell's Wayland session from the store
path (needs a compositor in the guest), and `tests/run_tests.sh` under
`nix develop`.

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

Also out of the first pass, still TODO here:

- a replacement for Settings → Update Dots (`exp-update`) under a flake —
  see "Open questions";
- the CI `nix flake check` workflow (Sketch item 5);
- `flake.lock` generation and the first real `nix flake check` /
  `nix build .#immaterial-impulse` run (Sketch item 4).

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
- Single-user vs system-wide — **resolved for the first pass**: home-manager
  alone covers the shell, so the flake ships `homeManagerModules.default` and
  no `nixosModules.default` at all (omitted, not stubbed). What stays open is
  the system half the installer does today — SDDM theme, plymouth, polkit
  rules, services — which is where a NixOS module would earn its existence
  if it ever does.

## Prior art

`sdata/dist-nix/home-manager/quickshell.nix` already solved the Qt-wrapping
problem for quickshell itself and should be reused rather than rewritten. The
upstream dots-hyprland project's Nix community packaging is the other obvious
reference.
