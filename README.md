# Immaterial Impulse

A Material 3 Expressive desktop suite for **Hyprland**: Quickshell shell,
full Hyprland config, plugin platform, and a whiptail installer in one tree.
Fork of [end4-pC](https://github.com/pctrade/end4-pC) (itself a fork of
end-4's illogical-impulse).

## Install / update

```sh
curl -fsSL https://raw.githubusercontent.com/XephyLon/immaterial-impulse/main/get.sh -o /tmp/imi-get.sh && bash /tmp/imi-get.sh
```

The installer is idempotent - re-running it updates an existing install
(also available as the About page's **Update Dots** button). Optional
components: Wallpaper Engine integration, the imi-sddm-theme login theme,
and a Plymouth boot splash.

### NixOS (experimental)

The repository root is a Nix flake. Instead of the installer, a
home-manager user adds:

```nix
inputs.immaterial-impulse.url = "github:XephyLon/immaterial-impulse";
```

and imports `inputs.immaterial-impulse.homeManagerModules.default` with
`programs.immaterial-impulse.enable = true`. The module symlinks the
shell tree and the matugen config from the store, seeds
`~/.config/immaterial-impulse` once, and refuses to manage matugen's
generated outputs (it warns if your home-manager config does).

What does not work yet: wallpaper-driven colour generation (the scripts
need a Python venv the module does not provide) and the Wallpaper Engine
integration. Design, validation status, and open questions are in
[docs/proposals/nixos-flake.md](docs/proposals/nixos-flake.md).

## Compositor support

**Hyprland only.** There are no plans to support Niri or any other
compositor - I don't use anything else and don't intend to. Upstream's
compositor-abstraction layer is kept only as a thin Hyprland-facade so
merges stay tractable; compositor-specific code for anything else is
removed when it lands.

## More

- [CHANGELOG.md](CHANGELOG.md) - what ships in each release (also shown in
  the shell's About page after an update)
- [docs/](docs/) - plugin platform, design system, testing notes
- [CONTRIBUTING.md](CONTRIBUTING.md)
