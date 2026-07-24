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

### Added
- Curated default configuration: fresh installs now seed `config.json` from the
  maintainer's tuned setup (sanitized of machine-specific state) instead of the
  bare upstream fallback defaults; existing configs are never touched.
- Icon pack selector (Settings → Interface): preview-grid cards rendering each
  theme's real icons, system-wide apply (GTK 3/4 `settings.ini`, `kdeglobals`,
  gsettings) with validation, and an automatic shell relaunch to adopt the pack.
- Verified-prebuilt Wallpaper Engine install path: on x86_64 the installer
  downloads a checksum-verified release tarball (seconds) and falls back to the
  source build on any mismatch; companion release CI lives in qs-wallpaperengine.
- Quiet-mode install is now cancellable (Ctrl-C cleanly stops the whole build).
- Frost mode toggle (tint vs true blur) for plugin backdrops in Settings → Plugins.
- README: palette showcase screenshots (Green / Study / Red).

### Fixed
- Multi-second shell freezes on wallpaper/preset switches, root-caused to three
  compounding issues: Qt's basic render loop on NVIDIA/Wayland blocking the GUI
  thread on embedded-WE video GL (fixed via `QSG_RENDER_LOOP=threaded` in the WE
  wrapper); kde-material-you re-applying the unchanged icon theme every switch
  (dropped `iconslight`/`iconsdark`); and Quickshell rescanning every `.desktop`
  file on any parent-directory churn, stalling the UI in multi-second QML GC
  pauses (patched in qs-wallpaperengine's bundled Quickshell). Cycling all four
  presets went from 11 UI stalls (up to ~4.8 s) to none.
- MPRIS artwork, favicon, weather, wallpaper-download and AI-request fetches no
  longer splice external values into `bash -c` strings (command-injection
  hardening; values now passed as arguments).
- Cookie clock (and other draggable desktop widgets) follow preset position
  changes again instead of ignoring them or snapping back while dragging.

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

[Unreleased]: https://github.com/XephyLon/immaterial-impulse/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/XephyLon/immaterial-impulse/releases/tag/v0.1.0
