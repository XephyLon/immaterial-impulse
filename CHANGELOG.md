# Changelog

All notable changes to Immaterial Impulse are documented here. The format is
based on [Keep a Changelog](https://keepachangelog.com/), and the project follows
[Semantic Versioning](https://semver.org/) (currently pre-1.0: `0.x` may make
breaking changes on a minor bump).

The version is stored in `VERSION` (a symlink to the shell's
`dots/.config/quickshell/imi/VERSION`, so it deploys with the config and the
About page can read it). The companion `qs-wallpaperengine` is versioned in its
own repo; the installer pins which revision it builds.

## [Unreleased]

### Changed
- The **Docker plugin popup** is built from the shell's own M3 Expressive
  components instead of widgets it defined for itself: `SecondaryTabBar`
  over a `SwipeView` for the Containers/Compose switch, `StyledRectangle`
  cards, `FlowButtonGroup` + `RippleButtonWithIcon` action rows,
  `StyledFlickable` scrolling, `IconToolbarButton` header actions,
  `MaterialLoadingIndicator` for refresh, and `PagePlaceholder` empty
  states. Card expansion animates through a `Revealer` rather than
  toggling visibility, so neighbouring cards no longer jump.

### Fixed
- Quick page: the scheme-preview command lost its virtualenv fallback to
  QML's template substitution (`${...}` is QML syntax too), which broke
  the whole binding and left the palette swatches without a command.
- The Docker popup is the 480px wide it always declared. The width sat on
  a `ColumnLayout`, which overwrites its own `implicitWidth` from its
  children, so the popup had been silently content-sized.

## [0.7.0] — 2026-08-01

Immaterial Impulse is an independent project now, not a fork that tracks
its ancestors. Nothing is pulled from `pctrade/end4-pC` or
`end-4/dots-hyprland` any more, and the code and naming that existed to
keep those merges tractable is gone.

### Changed
- **The shell is `imi`, not `ii`.** It installs to
  `~/.config/quickshell/imi` and runs as `qs -c imi`; the QML module
  namespace is `qs.modules.imi.*` and the panel family identifier is
  `"imi"`. `ii` was illogical-impulse's abbreviation. Existing installs
  are handled: a `panelFamily` of `"ii"` in an already-written config
  still resolves (without that, the shell would start with no panels at
  all), and the installer clears a leftover `~/.config/quickshell/ii`
  once the new directory is in place.
- The Python virtualenv variable is `IMMATERIAL_IMPULSE_VIRTUAL_ENV`.
  Every consumer falls back to `ILLOGICAL_IMPULSE_VIRTUAL_ENV` and
  `env.lua` exports both, so a Hyprland session started before the update
  keeps generating colors and thumbnails until the next login.
- The welcome screen's Usage, Configuration and GitHub buttons open this
  project's own docs instead of end-4's wiki, which describes a shell
  this one has diverged from. The sponsor button now says whose page it
  opens, and the repository's GitHub Sponsor button no longer routes to
  end-4.
- README and AGENT.md describe the fork relationship in the past tense.
  Attribution to end-4 and pctrade stays in `LICENSE`, `licenses/` and
  the credits — the project is GPL-3.0 and the ancestry is real.

### Removed
- The compositor abstraction. `WM` absorbed `HyprlandBackend` (its API is
  unchanged, so no call site moved), `CompositorGlobalShortcut` gave way
  to `GlobalShortcut` directly, and the 25 `WM.compositor === "hyprland"`
  branches are gone.
- With them, an entire unreachable sidebar entrance implementation: both
  sidebars defined `animatedEntrance` as permanently false and carried a
  slide-in animation, a delayed-close timer, a full-window mask and a
  click-outside-to-dismiss area behind it. Open/close behavior is
  unchanged — that path never ran.

### Fixed
- The repo-root `VERSION` symlink, which the directory rename left
  dangling.

## [0.6.1] — 2026-07-31

### Fixed
- Quick page: the scheme grid ran a little taller than the wallpaper
  preview. The right column is now height-locked to the preview
  (56px light/dark row + three 66px chip rows + gaps = 280), and the
  palette circles were re-proportioned (34px slot, tighter label gap) so
  the shorter chips keep even outer padding.

## [0.6.0] — 2026-07-31

### Added
- Snagit-style **annotation bar** on region screenshots: releasing a
  rectangular Copy selection now pauses on an Annotate phase with a
  toolbar under the region - draw (freehand), arrow, box and ellipse
  tools, six colors, three stroke widths, undo and clear - then Copy
  (Enter) or Cancel (Esc). Annotated snips are composited at native
  resolution via grabToImage and go through the observable copy pipeline
  (clipboard + screenshot popup); an untouched selection falls back to
  the original lossless magick crop. Right-click edit, circle mode, OCR/
  Lens/QR and recordings keep their instant flows.

### Added
- Per-plugin **"Keep settings across presets"** toggle (pin switch at the
  top of every plugin's options): a flagged plugin's options, desktop
  positions and enabled state survive preset application; the flag itself
  is never captured into presets. Covered by an end-to-end presets.sh
  behavior test.

### Fixed
- Bar/overlay-only plugins (Discord Voice, Docker) no longer show a dead
  "Blur background" toggle - host blur is a desktop-widget mechanism, so
  the injected row now appears only for plugins with a `desktopWidget`
  entry point.

### Changed
- Drop Shelf and Screenshot Result are core shell modules again, not
  bundled plugins: always loaded by the panel family, options in the shell
  config (`dropShelf.*` with the blur knobs, `screenshotResult.*`) and in
  Settings (Drop shelf under Sidebars & Panels; Screenshot popup was
  already under Capture). Plugin-state options migrate is manual-free: the
  live install's preferences were carried over. `PluginPanelHost` stays
  for third-party panel plugins.

## [0.5.1] — 2026-07-31

### Fixed
- Super+Alt+Space (float toggle) also switched the keyboard layout when the
  Settings' layout-switch shortcut was set to Super+Space: xkb `grp:`
  toggles fire even with extra modifiers held. The Super+Space layout
  switch is now a real compositor bind in keybinds.lua (exact modifier
  matching, no-op with a single layout), and the Settings selector no
  longer offers the colliding xkb value - it is relabeled "Extra layout
  switch (xkb)" with only None/Alt+Shift left.

## [0.5.0] — 2026-07-31

### Changed
- Settings reorganized domain-first (per `docs/settings-ux-research.md`,
  Option A). The "Interface" junk-drawer page is gone; every section moved
  to a concrete home, none were altered:
  - **Appearance**: Icon pack, Fonts, Terminal (incl. background image),
    Color generation
  - **Wallpaper & Desktop** (was Desktop): + Wallpaper selector
  - **Bar & Dock** (was Bar): + Dock; − Notifications
  - **Sidebars & Panels** (new): both sidebars + quick toggles/sliders/
    corner-open (from General), Overview, Overlay/Crosshair/Floating
    image, On-screen display (from Interface)
  - **Notifications** (new): promoted out of Bar
  - **Lock & Idle** (new): Lock screen, Screensaver, Keep awake (from
    Interface), Work safety (from General)
  - **Capture** (new): Screen recorder + Instant replay, Save paths (from
    Services), Screenshot popup, Region selector (from Interface)
  - **Services** keeps only the outward-facing ones: AI, Networking,
    Music recognition, Search, Updates, Weather
  - **General** keeps the true globals: Time, Battery, Audio, Sounds,
    Language. Quick is unchanged.
  The nav search metadata is now generated from the pages' actual section
  titles, and the navigation test's page map covers all 13 pages.

## [0.4.0] — 2026-07-31

### Fixed
- Privacy pill named Electron apps "Chromium" (Vesktop's mic use showed as
  Chromium): when a stream's `application.name` is a known-generic
  Electron/WebRTC alias, the capitalized `application.process.binary`
  (e.g. "Vesktop") is shown instead - specific names like "OBS Studio"
  still win. Applied to both the JSON and legacy-text pactl parsers and
  the byte-synced test double.

### Removed
- All Niri compositor support from the upstream merge - this fork targets
  Hyprland exclusively. Deleted: NiriBackend/NiriXkb/NiriConfig services,
  the Niri settings page, NiriBackdrop, the niri monitor-config model, and
  every `WM.compositor === "niri"` branch (session actions, lock, night
  light's wlsunset path, workspace model, wallpaper selector, sidebar
  reload, settings gates, record.sh). Upstream's `WM` and
  `CompositorGlobalShortcut` remain as thin Hyprland-only facades so the
  30+ consumer files stay merge-compatible with upstream. The "Niri Like"
  overview *style* (a layout option on Hyprland) is unrelated and kept.
  SystemTheming (orphaned by the Niri page removal) and FastBlurred
  (unreferenced) removed too.

### Added
- Upstream merge (`pctrade/end4-pC`, decrypted from commits `ns`/`cf`/`nl`/
  `lw`x2 + PR #27):
  - **Niri compositor support**: a `WM` abstraction service (compositor
    detection, workspaces, windows, shortcuts) with `HyprlandBackend`/
    `NiriBackend`, `CompositorGlobalShortcut` wrapper, `NiriXkb`, a Niri
    settings page (config editing via `niri msg`), `NiriBackdrop`, and
    niri-gated behaviors (lock wallpaper/overview disabled, wlsunset night
    light, workspace model branching, logout via `niri msg action quit`).
    The Hyprland/Niri settings pages are now pushed compositor-gated into
    the (still section-annotated) pages list.
  - Bar M3 clock pill: robust against locales/formats with seconds
    (splits on am/pm markers instead of fixed part positions) - PR #27 by
    Reazndev.
  - Night light rework adopted: on startup the service syncs with what is
    actually running instead of force-enabling inside the night window;
    our cold-start launch-flags fix is re-grafted on top.
  - Background clock quote now only shows for pixel/cookie clock styles.
  - Discarded: upstream's full clipboard wipe (would destroy our pinned
    entries - our pins-aware wipe stays), upstream's lock workspace-move
    niri gating (our lock pushes content visually and never touches
    compositor workspaces), upstream's removal of the VPN/Tailscale quick
    toggles. Upstream literals tokenized onto the spacing scale per merge
    policy; record.sh's monitor detection gained the niri branch inside
    our gpu-screen-recorder implementation.

## [0.3.1] — 2026-07-31

### Fixed
- Session screen: "Reboot into..." was unreachable by keyboard (no
  downward path led to it) and sat orphaned on its own row. The grid is
  now a symmetric 3x3 - session actions on top, power actions
  (Shutdown / Reboot / Reboot into...) on the bottom row - with a full
  arrow-key navigation map. The boot-entry pills themselves are now
  keyboard-navigable too, and the picker was restyled twice over: entries
  now stack under the grid clamped to its width (the pill row overflowed
  sideways), Down walks the list / Up returns to "Reboot into...", the
  focused entry fills primary (the current OS stays tonal), Enter reboots
  into it, and the opener button shows a toggled state while open.

## [0.3.0] — 2026-07-31

### Added
- **Selective EFI reboot** in the session screen: a "Reboot into..." action
  (shown only when the firmware exposes more than one permanent boot entry)
  expands a picker of EFI boot entries - transient USB/CD/network entries
  filtered out, current entry marked - and picking one sets `BootNext` via
  `pkexec efibootmgr -n` (polkit prompt) before rebooting straight into
  that OS. Firmware-level, so it works with GRUB, systemd-boot and Windows
  Boot Manager alike; parser covered by node-executed contract tests.
- **Plymouth boot splash** (opt-in installer component, Arch/mkinitcpio):
  a minimal Material-style theme (`sdata/plymouth-theme/immaterial-impulse`)
  with the suite wordmark, a rotating arc spinner, and a text-free LUKS
  password prompt (lock glyph + bullets - no fragile label-plugin dependency
  inside the initramfs). `setup` gains a PLYMOUTH component /
  `INSTALL_PLYMOUTH=1`: installs plymouth, copies the theme, adds the
  mkinitcpio hook (with backup and self-restore), and rebuilds the
  initramfs; the kernel-cmdline `quiet splash` change is printed, never
  auto-applied.

### Changed
- Scheme picker chips preview the colors they would apply, Android-12
  style: a new `scheme_preview.py` quantizes the current wallpaper once
  and derives primary/secondary/tertiary swatches for every Material
  scheme variant (~0.2 s in the color venv); each chip renders them as a
  segmented palette circle (top half primary, quarters secondary/
  tertiary) with the full scheme name below and a ring + check badge on
  the selected one. Refreshed on wallpaper and dark/light changes; falls
  back to the scheme icon when the venv is unavailable.
- Quick settings' Wallpaper & Colors section restyled: scheme chips are
  uniform tonal cards with centered icon+label (no more diagonal
  icon/label scatter), selection animates color and relaxes into a pill,
  the Light/Dark pair matches the same container family with horizontal
  content, and the cramped 2px gaps grew into the spacing scale.
- Screen recorder rebuilt on **gpu-screen-recorder** (GPU encode - NVENC/VAAPI,
  ShadowPlay-style), replacing wf-recorder's CPU x264 path:
  - Same interfaces as before (bar record button, region-selector record
    actions, `Super+Shift+R` / `Ctrl+Alt+R` binds, `record.sh --region/
    --fullscreen/--sound/--path`), now driven by config: quality preset,
    codec (auto/H.264/HEVC/AV1), FPS, framerate mode, cursor, desktop audio
    and optional mic merge - all in Settings → Services → Screen recorder.
  - **Instant replay** (`ScreenRecord` service): a persistent ring-buffer
    daemon keeps the last N seconds (default 120, RAM or disk); save a clip
    with `Alt+F10`, the bar button that appears while replay is armed, or
    `qs -c imi ipc call record replaySave`; toggle with `Shift+Alt+F10`, the
    settings switch, or IPC. Enablement is persisted config, so replay
    survives restarts; a failing daemon disables itself instead of
    respawn-looping.
  - Recording pause/resume (`Ctrl+Alt+R` family unchanged; pause via
    `quickshell:screenRecordPause` global or `record pause` IPC, SIGUSR2).
  - One-shot recordings and the replay daemon are separate gsr processes;
    the record toggle and pause are pidfile-scoped so they can never kill
    the replay buffer. Saved-file notifications come from gsr's `-sc` hook
    with the real path (replay clips included).
  - Suite dependency lists switched from `wf-recorder` to
    `gpu-screen-recorder` (arch/fedora/gentoo/nix).
  - The bar's privacy pill now also shows shell-owned captures: a
    `screen_record` icon while a recording runs (with pause state in the
    hover popup) and a `replay` icon while the instant-replay buffer is
    armed. An **Instant replay** quick toggle joins both right-sidebar
    styles (Android grid: drag it in from the unused set; classic panel:
    always present) - toggle to arm, long-press to save a clip.

## [0.2.0] — 2026-07-31

### Fixed
- Selected icon pack reset by "Update Dots": the dots sync ships a
  `kdeglobals` with `[Icons] Theme=breeze-dark`, overwriting the theme the
  user picked in Settings → Interface → Icon pack (the selection itself
  survives in the shell config; it just never got re-applied). The installer
  now re-applies `appearance.iconTheme` via `apply-icon-theme.sh` after
  every file sync, best-effort.
- About page PC-spec cards stuck on "Loading..." until visiting another
  section: the specs refresh fired on a hardcoded page index (7) that went
  stale when the Plugins page shifted About to 8. The trigger now targets
  the last page by position, and a test pins SettingsContent against
  hardcoded `currentPage` indexes.
- Broken icons (raw "VIDEO_TE□LATE"-style ligature text) in the desktop menu's
  Live Wallpaper entry, the live-wallpaper folder setting and the sidebar
  settings' Media Player card: the SDDM theme ships an older Material Symbols
  Rounded copy that fontconfig can pick over the system font, and it predates
  the `video_template`/`music_note_2` names. Renamed to `animated_images` /
  `music_note`, and a new lint (`tests/lint_material_icons.py`) validates
  every literal icon name against the GSUB ligatures of EVERY installed copy
  of the font so stale-font breakage can't sneak back in.

### Added
- About page "What's new" card: renders the changelog of the installed suite
  checkout (`~/.local/share/immaterial-impulse/src/CHANGELOG.md`, the copy
  get.sh refreshes on Update Dots) as collapsible Markdown, bounded to the
  newest two sections, with a Full-changelog link to GitHub. Hidden when the
  checkout or file is absent.
- Drop Shelf is now a bundled **plugin** (`drop_shelf`, enabled by default)
  with Dropover-style summoning (see `docs/dropshelf-shake-research.md`):
  - **Mid-drag summon**: `Super+U` (Hyprland `quickshell:dropShelfSummon`
    global shortcut) or `qs -c imi ipc call dropShelf toggle` opens the shelf
    under the cursor — works while dragging files, so the in-flight drag can
    be dropped straight onto it.
  - **Drag-to-bar reveal**: dragging files onto the bar pops the shelf out
    below it (the Wayland-native trigger — a `DropArea` learns of a drag the
    moment it crosses a shell surface); dropping on the bar itself also
    stashes the files.
  - **Shake to summon** (opt-off by default): a helper polls the Hyprland
    request socket (raw socket, ~0.03 ms/query at 60 Hz) and recognizes
    ≥3 fast horizontal direction reversals with extrema-based leg tracking
    (`scripts/dropshelf/shake_detector.py`, pure-logic detector covered by
    `tests/test_dropshelf_summon.py`). Paused while locked or a fullscreen
    app is focused. Wayland offers no global "drag in progress" signal, but
    every pointer drag holds the primary button — the gesture is armed only
    while BTN_LEFT is down (global state read via the `EVIOCGKEY` evdev
    ioctl; needs `input`-group membership, degrades to always-armed
    without it), so shaking a free cursor does nothing.
  - A summoned shelf **auto-dismisses** (default 5 s, configurable) unless
    hovered, dropped on, or holding items.
  - **Blur-able background**: the shelf tint's opacity is configurable and
    the compositor blurs behind every `quickshell:*` layer, so lowering it
    frosts the shelf; both knobs live in the plugin's settings along with
    bar-reveal, shake, sensitivity and auto-dismiss options.
  - The desktop-menu "DropShelf" entry and the bar reveal hide when the
    plugin is disabled; the shelf window is created lazily on open.
- Discord voice: one-shot companion installer
  (`scripts/discordVoice/install_companion.sh`) — auto-detects Vesktop and
  Equibop (`--client` to pick), clones and builds the matching mod (Vencord /
  Equicord, same plugin API) with the End4DiscordVoice user plugin, and
  points the client's custom-mod location at the build (backing up
  `state.json` first). The Discord Voice popup gains a one-click **Install
  voice companion** button that runs the installer and streams its progress
  whenever the bridge reports the companion is missing; the bridge error
  also names the script. Official Discord still needs nothing; Legcord
  remains unsupported (bundled Vencord, no custom-location picker).
- Upstream merge (`pctrade/end4-pC`):
  - Desktop Notes widget: a flip-card notes list on the background (add, edit,
    swipe to delete; persisted in the shell state dir), toggle in
    Settings → Background widgets.
  - Live wallpaper preview (opt-in via `background.enableWallpaperPreview`):
    single-click or arrow-key navigation previews the wallpaper on the real
    background, double-click applies; preset apply clears any pending preview.
  - Dock-to-panel bar widget: drag-to-reorder pinned apps with animated slot
    translation.
  - Dock: the pinned-apps section and its separators hide when nothing is
    pinned; drag-ghost polish.
  - Screenshot while recording snips via plain grim+slurp instead of the
    region-selector UI (which doubles as the recording control), and the record
    keybind now stops a running recording. (Hardened over upstream: the save
    directory is passed as an argv element instead of interpolated shell text.)
  - Bar settings: the divider space-width spinbox is only enabled for the
    "space" divider style.
- Upstream feature sweep (first batch, from the `end-4/dots-hyprland` tracker):
  - GPU usage/temperature now works on AMD/Intel too (hwmon/sysfs fallback);
    the NVIDIA path is unchanged.
  - Bluetooth connect/disconnect button shows a "Connecting…"/"Disconnecting…"
    pending state while the operation is in flight.
  - Bluetooth device battery (upstream PR #3538): the quick-toggle tile status
    and tooltips now show the connected device's battery percentage (when the
    device reports one), matching the device-list dialog.
  - Calendar: configurable first day of week (Monday/Saturday/Sunday).
  - Bar: option to show only the current monitor's workspaces
    (`bar.workspaces.showAllMonitors`).
  - Weather: provider choice (OpenWeatherMap or keyless wttr.in) and a
    user-settable OWM API key (falls back to the built-in key when empty).
  - Caps Lock / Num Lock on-screen display (toggle: `osd.lockKeys`).
  - Clipboard pinning: pin entries so they stay on top and survive "wipe all".
  - Clipboard clear buttons (upstream PR #3546): the launcher's clipboard view
    gains a header with "Clear results" (deletes only the entries matching the
    current filter) and "Clear all" buttons, plus an empty-state hint; both
    respect pinned entries, and deletions go to `cliphist delete` over stdin.
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
  - Privacy indicator (in the default right bar): an alert pill that appears
    only while an app is using the microphone, camera, or sharing/recording the
    screen, listing the source in a hover popup. Each signal's icon and the pill
    ease in and out.
  - Notes plugin (bundled desktop widget): a persistent, autosaving notepad
    that shares the notes scratchpad with the overlay notes editor.
  - Hyprland submap indicator (upstream PR #2225, in the default right bar): a
    pill with a keyboard icon and the submap name that appears while a keybind
    submap (e.g. resize) is active and eases out when it resets; icon-only in
    the vertical bar. Tracked by the new `HyprlandSubmap` service.
  - Dock: right-click context menu on app icons (upstream PR #3045) —
    desktop-entry actions (e.g. "New Window"), open new instance, move all of
    an app's windows to a workspace, pin/unpin, and close window(s). Window
    previews are suppressed and the dock stays revealed while the menu is open.
    (Drag-to-reorder of pinned apps, the PR's other half, already exists here.)
  - Tailscale (upstream PR #3501, reworked for the sidebar): a quick toggle
    next to the VPN toggles (both classic and Android styles) that brings
    Tailscale up/down, plus an exit-node dialog (right-click / tile menu)
    listing peers that advertise themselves as exit nodes — online first, with
    a "None (direct)" row — applied via `tailscale set --exit-node=…` with a
    one-shot `pkexec` fallback for non-operator users. Backed by the new
    `Tailscale` service polling `tailscale status --json`; hidden entirely
    when the CLI isn't installed.
  - OpenRGB accent sync (upstream PR #3415, reworked as a plain CLI call): an
    opt-in toggle (Settings → Quick) that applies the Material You accent
    color to RGB hardware whenever the palette changes, debounced, via
    `openrgb --mode static`; silently inert when the binary is missing.
    Individual devices can be excluded from the sync with per-device switches
    under the toggle (`appearance.openrgb.excludedDevices`, keyed by device
    name so paired hardware like RAM sticks toggles as one).
    An optional ambient mode (`appearance.openrgb.colorSource: "monitor"`)
    instead follows the focused monitor's dominant on-screen color — by
    default only while a fullscreen app runs (games, video), snapping back to
    the accent on exit. Sampling is a low-rate grim capture reduced by
    Quickshell's ColorQuantizer, with a deadband and optional smoothing so
    near-static scenes produce no device writes; needs `grim`, silently inert
    without it. The shell manages an `openrgb --server` for the streaming
    writes (serverless CLI calls re-detect hardware every time, resetting
    devices to white), and excluded devices are kept out of OpenRGB's own
    detector list so the server never claims them — a claimed device loses
    its firmware lighting even without a single color write. GPU lighting is
    excluded from ambient writes by default (`monitorExcludedTypes`): GPU RGB
    rides the graphics i2c bus, and streaming to it mid-game stalls
    rendering; the ambient loop also scans devices once per activation
    instead of before every write. The bar's privacy indicator filters the
    sampler's once-a-second capture pulses (`bar.privacyIndicator.
    ignoreAmbientCapture`, default on) — real screen shares still show, since
    they hold their state past the pulse window.
- Component grid for desktop plugins: formalizes the nandoroid design-system
  grid (a 132×108 cell with a 12px gap) as `Appearance.sizes.widgetGridSpanX/Y`
  with an opt-in manifest `grid: { cols, rows }` that sizes a widget to whole
  cells so it tiles flush with the built-in widgets; the Notes widget is now a
  true 2×2 tile (276×228). Documented in `docs/widget-grid.md`.
  - Settings → Plugins now badges third-party (externally installed) plugins.
  - Presets: an Overwrite action on each preset card saves the current setup
    over that preset (two-tap confirm).
- Media plugin: the Next/Previous cog buttons now spin like cassette reels
  while media is playing (both clockwise, icons stay upright), easing back to
  rest on pause.
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
- Plugin store (Settings → Plugins → Browse plugins): browse, search, and
  filter a curated catalog of community plugins and install or update them in
  one click through the existing hardened installer. Entries come from a new
  registry repo (`XephyLon/imi-plugin-registry`) whose CI cross-checks each
  entry's metadata against the plugin's actual manifest, so the permissions
  shown in the install confirmation dialog are verified, not self-reported.
  Update badges (semver against the installed version) appear on the Plugins
  page and on installed plugins' cards, with an "Update all" queue in the
  store. The installer gains `--upgrade` (stage, verify, then atomic swap with
  rollback) and writes a `.store.json` provenance sidecar after every install.
  The store UI ships gated off behind `plugins.storeEnabled` (config-file-only,
  default false) until the public registry goes live. Documented in
  `docs/PLUGIN_STORE.md`.

### Fixed
- Bar and dock media widgets broke on Arabic (RTL) track metadata: the text
  auto-aligned to the right edge away from the artwork, and Arabic's taller
  line box overflowed the fixed-height card, clipping the lines top and
  bottom. Text is now left-anchored with fixed, vertically-centered line
  slots so every script lays out like Latin.
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

[Unreleased]: https://github.com/XephyLon/immaterial-impulse/compare/v0.7.0...HEAD
[0.7.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.5.1...v0.6.0
[0.5.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.5.0...v0.5.1
[0.5.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/XephyLon/immaterial-impulse/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/XephyLon/immaterial-impulse/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/XephyLon/immaterial-impulse/releases/tag/v0.1.0
