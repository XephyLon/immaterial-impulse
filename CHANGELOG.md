# Changelog

All notable changes to Immaterial Impulse are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/), and the project follows
[Semantic Versioning](https://semver.org/) (currently pre-1.0: `0.x` may make
breaking changes on a minor bump).

The version is stored in `VERSION` (a symlink to the shell's
`dots/.config/quickshell/ii/VERSION`, so it deploys with the config and the
About page can read it). The companion `qs-wallpaperengine` is versioned in its
own repo; the installer pins which revision it builds.

## [Unreleased]

## [0.1.0] — 2026-07-23

First versioned release of the unified suite (the `Immaterial Impulse` fork of
illogical-impulse), collecting the work done to date:

### Added
- Unified repo: the Quickshell shell, full Hyprland config, and a `whiptail`
  installer in one tree, superseding a prior illogical-impulse install (with
  first-run config-dir + keyring migration).
- Optional installer components: Wallpaper Engine (custom Quickshell build) and
  the `ii-sddm-theme` SDDM login theme.
- Plugin platform (declarative + package plugins), Material You theming extended
  to cava/tmux, and the Caelestia animation preset.
- Wallpaper Engine wallpaper picker with type-filter chips.
- Automatic Hyprland animation-preset loading; restored keybind cheatsheet
  (`Super`+`/`).
- This changelog and versioning.

[Unreleased]: https://github.com/XephyLon/end4-pC/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/XephyLon/end4-pC/releases/tag/v0.1.0
