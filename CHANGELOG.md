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
- Upstream feature sweep (first batch, from the `end-4/dots-hyprland` tracker):
  - GPU usage/temperature now works on AMD/Intel too (hwmon/sysfs fallback);
    the NVIDIA path is unchanged.
  - Bluetooth connect/disconnect button shows a "Connecting…"/"Disconnecting…"
    pending state while the operation is in flight.
  - Calendar: configurable first day of week (Monday/Saturday/Sunday).
  - Bar: option to show only the current monitor's workspaces
    (`bar.workspaces.showAllMonitors`).
  - Weather: provider choice (OpenWeatherMap or keyless wttr.in) and a
    user-settable OWM API key (falls back to the built-in key when empty).
  - Caps Lock / Num Lock on-screen display (toggle: `osd.lockKeys`).
  - Clipboard pinning: pin entries so they stay on top and survive "wipe all".
  - File/folder search in the launcher (`~`-prefixed query, fd/find backed).
  - Lock screen: previous/play-pause/next controls on the media widget.
  - OLED screensaver (Settings → Interface): idle overlay with a full-black or
    a slowly-drifting dim clock mode; off by default.
  - NetworkManager VPN toggles in the right sidebar plus a bar status icon.
  - Automatic dark/light theme switching by time — sunrise/sunset or fixed
    times (Settings → Wallpaper & Colors); off by default.
  - ICS calendar: load events from local `.ics` files and remote ICS URLs and
    mark days that have events in the sidebar calendar.
  - Bar "Timer" pill (add via Settings → Bar): a dynamic-island pill showing a
    running pomodoro/stopwatch, opening the sidebar on click.
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
- README translations: Simplified Chinese (`README.zh-CN.md`) and Japanese
  (`README.ja.md`), with a language switcher linking all three.
- Dock feedback motion (M3 Expressive): hover lift, press squish, a launch
  bounce that runs until the app's window appears, an appear pop for new
  icons, and springing active-window dots — consistent across pinned and
  running apps, all on Appearance motion tokens.

- Test coverage sweep: 16 new suites covering the installer's destructive
  paths (rsync --delete sandboxing, legacy package removal, cancel traps),
  the color pipeline (lock/desktop palette parity, scheme detection,
  generator goldens), the keybind cheatsheet parser, momentum scrolling,
  and always-on services (Battery, Bluetooth, Updates, Brightness,
  SystemInfo, ConflictKiller, Polkit, Ydotool) - plus three previously
  orphaned suites now actually running in CI.
- Screenshot result popup (bundled plugin): every screenshot - region snip or
  Print keybind - pops a preview with save / annotate / discard actions;
  auto-dismisses, hover pins it. The plugin platform's `panel` entry point is
  now actually instantiated (PluginPanelHost), so plugins can ship
  free-floating surfaces.
- Centered Wallpaper now shows live Wallpaper Engine content inside its shape
  (centre-cropped from the same surface the blur/lock shaders sample, so no
  second renderer), falling back to the static/thumbnail image when no live WE
  surface is drawing.
- Experimental updater (`./setup exp-update`) now reports how many updates are
  available before pulling and prints the new CHANGELOG entries under a
  "What's New" heading after a successful update.
- Plugins settings: each plugin and its options are now one unified rounded
  card (header, hairline divider, then its option toggles as part of the same
  surface) with clear gaps between plugins, and the plugin name is larger and
  heavier so it reads as the card's heading.

### Fixed
- "Keep system awake" sometimes still let the session lock and hibernate: the
  idle inhibitor was bound to a 0×0 surface that maps unreliably, so Hyprland's
  ext-idle-notify (read by hypridle) intermittently ignored it. It now uses a
  reliably-mapped 1×1 transparent background-layer surface.
- Upstream bug sweep (audited `end-4/dots-hyprland`'s tracker against our fork,
  fixed the ones still present):
  - Sidebars/panels no longer "blink" open then instantly shut — a transient
    focus-grab clear from a ToplevelHandle activation is now debounced.
  - Launcher/app search no longer pegs a core: the app list is deduped in O(n)
    instead of O(n²) on every desktop-entry change.
  - Hyprland data refresh is debounced, so spawning apps (e.g. kitty) or fast
    workspace switches no longer stutter the UI by spawning `hyprctl` per event.
  - The battery widget no longer flaps in/out and no longer fires false
    low-battery notifications (or auto-suspend) when UPower transiently swaps its
    display device.
  - A fully-bracketed song title (e.g. `[BLEED BLOOD]`) shows the real title
    instead of "No media".
  - The cheatsheet no longer double-lists a keybind defined in both the default
    and custom Lua configs; custom now overrides default.
  - An offline random-wallpaper fetch can no longer corrupt config by persisting
    a truncated/missing wallpaper path.
  - Base installs (without Wallpaper Engine) now also launch the shell with the
    threaded render loop, so a GPU-saturating process can't freeze it.
  - Notification popups wait a short grace period before hiding on unfocus, so a
    brief cursor flicker no longer dismisses them.
  - With bar auto-hide on, the media box and tray-overflow popup are no longer
    orphaned above a hidden bar (new `bar.autoHide.dismissPopups` option).
  - The screen-corner "absolute corner" hover no longer opens the sidebar when
    "Hover to trigger" is turned off (it is a sub-option of it).
- Experimental updater failed to detect/report updates that existed: its change
  detection keyed off the reflog's `HEAD@{1}`, which a preceding stash or
  detached-HEAD checkout silently repointed. It now captures a stable pre-pull
  baseline SHA and counts incoming commits straight from refs (`git fetch` +
  `git rev-list --count`).
- Terminal background settings note that the pattern applies to the Kitty
  terminal only.
- Lock-screen palette could differ from the desktop's for the same image: lock
  color generation passed `--smart` (silently swapping the configured scheme to
  neutral on low-chroma images) and hardcoded tonal-spot for `auto` instead of
  running the same image-based detection as the desktop.
- Wallpaper Engine wallpapers were permanently mute: the embedded renderer
  hardcoded `--silent` and the selector's volume button toggled a flag nothing
  read. The button now drives the new `audioEnabled` surface property (toggling
  reloads the wallpaper - audio is a load-time decision inside WE).
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
