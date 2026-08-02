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
2. **Decide what config is declarative vs mutable.** The shell writes to
   `~/.config/immaterial-impulse/config.json` and `plugin-state.json` **at
   runtime** — widget positions, plugin options, enabled plugins. Those cannot
   be read-only store paths. The likely split: the QML tree is declarative and
   immutable; the user state directory is seeded once and then mutable. This is
   the central design question and should be settled before any code.
3. **Reconcile with the existing `sdata/dist-nix` tree** — either promote it to
   the root and delete the nested flake, or keep `--via-nix` as a legacy path and
   mark it superseded. Do not ship two flakes.
4. **Unpin quickshell** from the hardcoded commit, or at least move the pin
   somewhere it is obviously a pin.
5. **CI**: `nix flake check` on push is the only thing that keeps a flake honest.

## Open questions

- Does the plugin system work under Nix? Bundled plugins load by absolute path
  through Quickshell's `qs:` URL scheme, and **installed** plugins live in
  `~/.config/immaterial-impulse/plugins/<id>/` — a mutable directory by design.
  Third-party plugin install is inherently imperative; the flake has to leave
  room for it.
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
