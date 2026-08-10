# AGENT.md

Reference for coding agents (and humans) working in this repository. This file explains what the
project is, how it's put together, and where things live. See `CONTRIBUTING.md` for how to work in
it day to day.

> **Read this file and then `CONTRIBUTING.md` sequentially, in full, top to bottom, before any
> work — and again after a context compaction.** Grep hits and section jumps are not reading:
> the rules that get broken are the ones adjacent to the section someone jumped to, and that is
> how 5d4bfa773 ("feat(wallpaperEngine): reinstate activeStill, this time with a writer") shipped
> a regression this file had the material to prevent. Every point added to this file or
> `CONTRIBUTING.md` must cite the commit that motivated it as `<sha> ("<subject>")` — format and
> enforcement in `CONTRIBUTING.md` → "Keep AGENT.md in sync".

> **Repository layout.** This repo bundles more than the shell. The Quickshell theme lives under
> `dots/.config/quickshell/imi/`; the installer is `setup` + `sdata/`; project docs are in `docs/`.
> **Unless a path is written repo-relative (e.g. `dots/...`, `sdata/...`, `docs/...`), file paths in
> this document are relative to the theme root `dots/.config/quickshell/imi/`** (so `modules/...`,
> `services/...`, `shell.qml` mean `dots/.config/quickshell/imi/modules/...`, etc.).

## What this is

`Immaterial Impulse` (ImI) is a **Quickshell** shell configuration for **Hyprland** — a full desktop
UI (bar, docks, sidebars, on-screen displays, notifications, launchers, lock screen, etc.) written
entirely in QML and run by the [Quickshell](https://quickshell.org) runtime (`qs`), not a compiled
application.

It originated as a fork of [illogical-impulse](https://github.com/end-4/dots-hyprland) (by `end-4`)
by way of `pctrade`'s `end4-pC`, but **it is no longer a fork in any operational sense** — it is an
independent project that happens to share ancestry.

```
end-4/dots-hyprland  →  pctrade/end4-pC  →  Immaterial Impulse (independent as of 0.7.0)
```

**There is no upstream.** The `pctrade/end4-pC` and `end-4/dots-hyprland` remotes are gone and
neither is fetched, merged, or diffed against any more. Do not add them back, do not "check what
upstream does" when making a design decision, and do not preserve a shape purely because it keeps a
future merge tractable — that constraint no longer exists. `gh` is the publishing remote
(`XephyLon/immaterial-impulse`).

Attribution to `end-4` and `pctrade` stays in `LICENSE`, `licenses/`, and the README credits — the
project is GPL-3.0 and the ancestry is real. Independence is about direction, not erasure.

This directory is **not a standalone app repo** — it's dropped into `~/.config/quickshell/imi`
on a running Hyprland system and loaded by `qs -c imi`. ImI ships the whole suite, so it supersedes
a prior illogical-impulse install rather than coexisting with one: the companion Hyprland config
lives alongside it in this repo (installed separately to `~/.config/hypr/`) and provides the
keybinds, IPC event names, and layer-shell behavior assumptions this shell depends on.

## Before you restore something that was removed

**If code, a field, or a file is missing where you expected one, find out why it went before you put
it back.** "It looks like an oversight" is not a finding. The removal has a commit, and usually an
issue, and that reasoning is the requirement you are about to work against.

Concretely, before re-adding anything:

1. `git log -S '<the thing>' --all` for the commit that removed it, and read the **whole** message.
2. If it cites an issue or PR, read that too — `gh issue view N` / `gh pr view N`, not the title.
   These are separate: `gh pr view 103` fails on this repo because 103 is an **issue**.
3. Only then decide. If the reasoning still holds, the gap is intentional and your problem needs a
   different answer. If it no longer holds, say so explicitly in the commit message and address what
   the original removal was protecting against.

The worked example, because it cost a full day and shipped a regression:

`wallpaperSelector.wallpaperEngine.activeStill` (introduced by 6a0c19e45 ("feat(wallpapers):
render and cache a full-scene still per live wallpaper"), orphaned a day later by ce7e90327
("refactor(wallpaperEngine): gut runtime renderer to selector-only")) was removed by
[#103](https://github.com/XephyLon/immaterial-impulse/issues/103) — a stored path to a rendered
wallpaper still, with no writer after the Wallpaper Engine renderer moved in-process, frozen at
whatever project was active that day, and served to the SDDM greeter for months.
[#113](https://github.com/XephyLon/immaterial-impulse/issues/113) then reported the low-resolution
greeter background that #103 had **explicitly predicted and accepted** as the cost.

[#117](https://github.com/XephyLon/immaterial-impulse/pull/117) "fixed" #113 by re-declaring the
field and giving it a writer (5d4bfa773 ("feat(wallpaperEngine): reinstate activeStill, this time
with a writer")) — a subprocess that launched a **second** `linux-wallpaperengine` to photograph a
frame this shell was already rendering in-process. Nobody had read #103. Three things followed:

- the fix rebuilt the exact pre-embed mechanism the embedded renderer exists to eliminate;
- re-declaring the property re-armed the stale values still sitting in every saved preset (see the
  `JsonAdapter` note under [The Config system](#the-config-system-settings-page--persisted-json) —
  presets are separate files it never rewrites), so #103's bug came back;
- #103's actual fix direction ("derive it, don't store it") was sitting in the issue the whole time.

The correct answer was in the removal's reasoning. Reading it first would have skipped all of it —
the eventual fix (03b8b0298 ("fix(wallpaperEngine): derive the greeter's still path, do not store
it")) is #103's own fix direction, implemented a day and two reverted mechanisms late.

## Runtime model — read this before assuming anything about "building" or "compiling"

There is no build step. Every `.qml` file is interpreted live by the `qs` process. When any `.qml`
file under this directory changes on disk, **the entire shell hot-reloads** (you'll see
`[To Do] File loaded` / `[Notifications] File loaded` lines in the log when this happens — those
two singletons happen to log on every full reload, which makes them a convenient reload marker even
though the message text doesn't literally describe what changed).

Do not perform a long series of edits or file moves against this checkout while its live
Quickshell instance is running. Each write can trigger a full reload; repeated reloads during an
inconsistent module move have coincided with shell and whole-session starvation. Stop Quickshell
or use a worktree, validate headlessly, then perform one controlled live load.

- Entry point: `shell.qml` → loads a **panel family** (currently only `"imi"`, from
  `panelFamilies/ImmaterialImpulseFamily.qml`) which is a flat list of `PanelLoader { component: X {} }`
  entries, one per top-level feature module.
- Singletons (declared with `pragma Singleton`) are the shell's shared state and services. They are
  addressed by their QML type name directly (e.g. `Config`, `GlobalStates`, `Audio`) — no explicit
  import needed beyond the directory-level `import qs.services` / `import qs.modules.common`.
- QML singletons appear to **persist across most hot-reloads** rather than being torn down and
  recreated the same way scene components are — don't assume editing a singleton always produces
  an immediately-visible fresh instance; when in doubt, verify with a temporary `console.log` in an
  `onXChanged` handler (see CONTRIBUTING.md's verification workflow).
- **A singleton is constructed on first use, so a service whose only caller is a lazily-evaluated
  binding does not start when you think it does.** Anything a singleton kicks off at construction
  — a detection `Process`, a poll timer, a file read — is deferred until something actually reads
  one of its properties. `PrismLauncher` is reached only from `LauncherSearch`'s `results` binding,
  which does not evaluate until the user types, so its "run at startup" detection had in fact not
  started when the first query was answered: measured, the first search came back with no modpacks
  and only the second had them. If a service must be warm before its first consumer runs, construct
  it explicitly from a `Component.onCompleted` that does run early — reading any property is what
  constructs it. This is separate from the reactive-observation rule below: the binding was correctly
  reactive, it just had nothing to observe yet. (feat(search): launch Minecraft modpacks from the
  search bar.)

### Where to look when something goes wrong

The running `qs` process writes two logs per instance, found under
`/run/user/<uid>/quickshell/by-id/<hash>/`:

- `log.log` — human-readable, this is the one to `tail`/`grep`. Contains `DEBUG qml:` lines (your
  `console.log` output), `WARN scene:` (QML runtime errors/warnings with file:line), and other
  component warnings (D-Bus, desktop entries, etc.).
- `log.qslog` — a much larger structured/binary trace log. Rarely worth reading directly; `log.log`
  covers almost everything needed.

Find the current instance's log with:
```bash
ls -la /proc/$(pgrep -f 'qs -c imi')/fd | grep log.log
```

The process is named **`qs`**, not `quickshell` — `pgrep quickshell` returns nothing even while the
shell is running, which reads as "the shell is down" and leads to launching a second instance on top
of the user's. Always match on `qs`:
```bash
pgrep -af 'qs -c imi'
```

Do not leave the primary shell running through a rapid multi-file patch series. Each source change
hot-reloads QML and rebuilds the desktop-entry registry; large Wine/Steam application collections
can turn repeated reloads into millions of parses, multi-gigabyte RSS, and an apparent freeze. Kill
the one primary instance before the edit batch and start exactly one clean daemon after validation.

**Grep `ERROR`, not just `WARN`.** A `WARN scene:` line is a runtime warning in an otherwise
working shell; `ERROR: Failed to load configuration` means the config did not load *at all* and the
user has no panels. The error is reported as a cascade from `shell.qml` down to the file that
actually failed — the **last** `caused by` line is the real culprit:
```
ERROR: Failed to load configuration
ERROR:   caused by @shell.qml[50:20]: Type ImmaterialImpulseFamily unavailable
...
ERROR:   caused by @modules/imi/sidebarRight/calendar/CalendarHeaderButton.qml[13:5]: Cannot override FINAL property
```
Because a single bad widget takes down every panel that transitively reaches it, **confirm
`Configuration Loaded` appears after the reload** rather than only checking that no warnings did.

**`tests/run_tests.sh` cannot catch this class of bug.** The QML suite instantiates pure-logic
singletons and never builds these widgets, so a widget that fails to compile leaves the suite fully
green. Only a live load surfaces it.

**Gotcha — FINAL properties:** anything deriving from `RippleButton` (and so from QQC2 `Control`)
must not declare `horizontalPadding`, `verticalPadding`, `padding`, `spacing`, `font`, `palette`, or
`icon` as its own property; those are `FINAL` and overriding one is a hard compile failure. Pick a
distinct name (`labelInset`, not `horizontalPadding`). A plain `Item`/`Rectangle` has no such
restriction, which is why `property real padding` is fine in the many non-`Control` widgets here.

**Known quirk:** `console.log` output to `log.log` can appear noticeably delayed (stdio buffering) —
a print can sit unflushed for several seconds before showing up, sometimes interleaved with later
events in a way that looks like a stale/wrong value at first glance. If a debug print looks wrong,
wait and re-check before concluding the code is broken.

## External binaries the shell drives

Two non-obvious traps live here, both found the expensive way.

**`DT_RUNPATH` is not transitive, and `LD_LIBRARY_PATH` is.** The Wallpaper Engine build the shell
loads (`~/.cache/immaterial-impulse/prebuilt/<ver>/`) bundles its own libraries. Setting a correct
`RUNPATH` on the *executable* resolves only that executable's **direct** dependencies — a bundled
`liblinux-wallpaperengine-lib.so` looks up *its* dependencies (e.g. `libcef.so`, sitting in the same
directory) through **its own** `RUNPATH`, which was the build machine's. Every bundled `.so` must be
patched, not just the binary. The `LD_LIBRARY_PATH` fallback appears to work precisely because it
*is* transitive — and it leaks into every process the shell spawns, shadowing system libraries for
every application launched from the desktop. If you find yourself exporting it, the `RUNPATH` is
still wrong. `patchelf` rewrites in place, so patching a **running** executable fails with `ETXTBSY`;
copy, patch the copy, then `rename(2)` over the original. Learned across 156b4703b ("fix(install):
repair the RUNPATH via a rename, not in place") and 3e07c2a5d ("fix(install): repair the bundled
libraries' RUNPATH too, not just the binary") — the first shipped believing it was the whole fix.

**`gpu-screen-recorder` does not tonemap.** Handed an HDR surface with an SDR codec it encodes 8-bit
and tags the file `bt709`, so a PQ signal is decoded as gamma — flat, grey, desaturated, with nothing
in the logs. `scripts/videos/record.sh` therefore detects HDR and selects the `_hdr` codec variant.
The authoritative signal is Hyprland's `colorManagementPreset` (`hdr`/`hdredid`), **not**
`currentFormat`: a wide-gamut SDR monitor also reports `XBGR2101010`. H.264 cannot carry HDR at all,
so an explicit H.264 choice is respected and explained rather than silently overridden.
(307c8b4ae ("fix(record): pick the HDR codec when capturing an HDR monitor").)
The capture fix only moves the wash-out to the consumer's machine — a correct HDR10 file still
renders flat in anything that does not tonemap (VLC defaults, Discord, browsers). Delivery is the
opt-in `screenRecord.tonemapSdr`: `scripts/videos/tonemap-sdr.sh`, invoked from the `gsr-saved.sh`
hook on every save (recordings *and* replays — replays never pass through `record.sh`), probes and
tonemaps to bt709 in the background, replacing the file atomically (d7113f84c ("feat(record):
opt-in SDR tonemap after every save")). Probe trap from that commit: ffprobe's **CSV output grows
an extra field from a real recording's side data**, so a strict match on the transfer value
silently classifies every real HDR file as SDR — synthetic fixtures have no side data, which is why
only a live file catches it. Use value-only output (`-of default=nw=1:nk=1`) and trim delimiters.

Three more from the same pipeline (4a33f970e ("feat(record): capture SDR through the portal when
SDR delivery is on"), acb9b4906 ("perf(record): GPU encoder ladder, and the pipefail bug that hid
the GPU")):

- **Hyprland tonemaps screencopy for capture clients** — grim screenshots of an HDR desktop look
  right, and gsr's *portal* capture rides the same compositor path, yielding native SDR. Its KMS
  capture reads the scanout plane and gets raw PQ. **Portal restore tokens are opt-in and default
  OFF**: xdph only issues one when the share picker's "Allow a restore token" checkbox is ticked
  (`src/portals/Screencopy.cpp` gates `restore_data` on the picker's `r` flag), and
  `screencopy:allow_token_by_default = true` — shipped in `dots/.config/hypr/xdph.conf` — is what
  pre-checks it. Without that, `-restore-portal-session` is a silent no-op and the picker prompts
  on **every** recording; gsr's log line `saved restore token to cache ()` in that state is gsr
  echoing its own empty cache buffer, **not** an xdph response — an earlier version of this entry
  misread it as "xdph returns an empty token" and portal capture was removed on that misdiagnosis
  ("fix(record): drop portal capture - xdph returns an empty restore token"), then restored with
  the shipped config once a 22-byte token was demonstrated round-tripping live: second recording
  produced frames within one second, zero interaction. Lesson: a log line about a cache is
  evidence about the cache, not about the peer — read the source of *both* sides before blaming
  either.
- **`cmd | grep -q` under `set -o pipefail` reads as failed on success**: grep -q exits at the
  first match, the producer takes SIGPIPE, and the pipeline's status is the producer's 141. The
  converter's GPU detection was invisible-broken this way from its first version — every tonemap
  ran on the CPU, nothing logged. Capture to a variable and match on that.
- **NVENC's H.264 tops out at 4096px wide** and rejects wider frames with a misleading "No capable
  devices found" — at 5120x1440 the h264_nvenc rung can never succeed; use HEVC past 4096. And
  ffmpeg's `-encoders` list advertises build capability, not working hardware — try encoders for
  real, in a ladder with a CPU floor.

## Directory map

```
shell.qml                  Entry point, loads the active panel family
GlobalStates.qml            Singleton: ephemeral UI state (sidebar open?, bar open?, OSD open?, ...)
ReloadPopup.qml, welcome.qml, killDialog.qml   Misc top-level overlays

modules/common/             Shared, feature-agnostic building blocks
  Config.qml                 Singleton: the entire settings schema + JSON persistence (see below)
  Appearance.qml              Singleton: design tokens - colors (M3 color roles), font sizes,
                              rounding, spacing, border widths, animation curves/durations, sizes.
                              Every widget reads from here rather than hardcoding values.
  Directories.qml            Singleton: XDG paths + shell-specific cache/state paths
  Icons.qml, Images.qml       Icon/image lookup helpers
  Persistent.qml              Helper for persisting fixed-schema values outside Config's JSON
  WallpaperTransitions.qml   Singleton: the wallpaper switch transitions the shell ships, one
                              entry per shader in modules/imi/background/shaders. The random
                              pool, the settings combo and the desktop menu all read this
                              rather than each keeping a copy - which is how the menu ended up
                              offering four of eight
                              (f5fba110c ("refactor(background): give the wallpaper transitions one catalogue"))
  plugins/                    Declarative + package-QML plugin renderer/validator/manager. It scans
                              bundled and user-installed manifests; PluginState.qml keeps dynamic
                              per-plugin, per-monitor layout in raw plugin-state.json.
                              bundled/ is where every desktop widget the shell ships lives -
                              there are no built-in desktop widgets (see docs/PLUGINS.md).
  widgets/                   Shared UI components: StyledText, StyledComboBox, StyledSlider,
                              StyledToolTip(+Content), RippleButton, MaterialSymbol, ResourceCard,
                              PopupToolTip, StyledPopup, GroupedList, ConfigSwitch/ConfigSpinBox/
                              ConfigSelectionArray (settings-page form controls), DockIconMotion
                              (M3E feedback-motion wrapper for dock icons), SchemePaletteCircle
                              (a colour scheme drawn as its own palette), etc.
  functions/, models/, utils/, panels/   Supporting JS logic, list models, window-panel base classes

modules/imi/                 The "imi" (Immaterial Impulse) panel family - one directory per feature:
  bar/                        The top/bottom bar and everything docked in it (Resources, Media,
                              SysTray, Workspaces, clock, quick toggles, ...)
  sidebarLeft/, sidebarRight/ Slide-out panels (AI chat, quick settings, notifications, volume mixer)
  onScreenDisplay/            Transient toast/OSD popups (volume, brightness, gamma, keyboard
                              layout, audio device switches) - see "OSD system" below
  screenCorners/              Decorative fake screen-rounding + corner hover/click zones that open
                              the sidebars
  background/                 Desktop background + the canvas the draggable desktop widgets sit on.
                              The widgets themselves are all bundled plugins now (see
                              modules/common/plugins/bundled/); background/widgets/ holds only
                              AbstractBackgroundWidget.qml, which is the plugin host's base class.
  overview/                   Workspace/window overview (like GNOME Activities)
  notificationPopup/          Desktop notification popups
  settings/                   The in-shell settings UI (pages/ = one file per settings category)
  dock/, lock/, mediaControls/, overlay/, polkit/, regionSelector/, screenTranslator/,
  sessionScreen/, onScreenKeyboard/, wallpaperSelector/, verticalBar/, desktopMenu/

services/                  Singletons wrapping external state/processes - one per concern:
  Audio.qml                  PipeWire default sink/source wrapper (Quickshell.Services.Pipewire)
  ResourceUsage.qml           Polls /proc/meminfo, /proc/stat, df, nvidia-smi on a timer
  HyprlandData.qml            Polls `hyprctl clients/monitors/layers/workspaces -j` on Hyprland IPC
                              events - the source of truth for "what does hyprctl currently see",
                              since Quickshell's own Hyprland IPC bindings don't expose everything
                              (e.g. per-monitor special-workspace state)
  HyprlandXkb.qml              Tracks active keyboard layout via Hyprland's `activelayout` IPC event
  HyprlandKeybinds.qml         Parses hyprland/keybinds.lua + custom/keybinds.lua (via
                              scripts/hyprland/get_keybinds.py) into the cheatsheet's tree, then
                              rewrites it through the keyboard-shortcuts editor's override map
  HyprlandKeybindOverrides.qml Owns the keyboard-shortcuts editor's sidecar
                              (~/.config/immaterial-impulse/keybind-overrides.json, raw FileView on
                              the PluginState pattern) and regenerates the Lua shim
                              hypr/hyprland/shellOverrides/keybinds.lua through
                              scripts/hyprland/keybind_overrides.py. Never edits user keybind
                              files; refuses to touch a hand-edited shim (content hash). See
                              docs/proposals/keyboard-shortcuts-editor.md
  PrismLauncher.qml            Prism Launcher modpacks for the launcher search, enumerated by
                              scripts/prism/list_instances.py. Feature-detected (native binary or
                              flatpak): without Prism the script never runs, `available` stays
                              false, and the '%' prefix plus its settings row disappear. Launches
                              by instance FOLDER name, which is not the display name
  Notifications.qml            org.freedesktop.Notifications server + notification history
  Notes.qml                    The note store: a JSON array in Directories.notesPath. Sole owner -
                              the bundled `notes` desktop plugin (one instance per monitor) and the
                              overlay notes editor both go through it rather than opening the file,
                              and it imports the legacy desktopnotes.txt array once
                              (Config.options.notes.importedLegacyStore) without ever writing to it
  Clight.qml                   Clight daemon wrapper (busctl --json=short; the shell has no D-Bus
                              binding). Feature-detected: a machine without the clight binary never
                              spawns a busctl. While the daemon is up, Brightness.qml routes every
                              backlight write through it (IncBl/DecBl) so the daemon's next
                              recalculation does not revert the change; night-light ownership stays
                              with Hyprsunset.qml. See docs/proposals/clight-integration.md
  PhoneConnect.qml             Paired-phone state from KDE Connect or Valent, driven over
                              `busctl --json=short` Process calls (the shell has no D-Bus
                              binding) - backend detection from the bus name list, one
                              normalized device/battery model for both daemons, ring/ping/
                              clipboard actions. Its parser logic is kept byte-for-byte in
                              sync with a logic-only test double
                              (tests/test_phone_connect_contract.py enforces it)
  SchemePreview.qml            Per-scheme swatches for the scheme pickers: one venv run of
                              scripts/colors/scheme_preview.py quantizes the wallpaper once and
                              builds every Material variant from it. Cached against the wallpaper
                              and the dark/light mode, so refresh() is free while those hold and
                              nothing recomputes while no picker is on screen
  Brightness.qml, Battery.qml, Hyprsunset.qml, Network.qml, BluetoothStatus.qml, TrayService.qml,
  MprisController.qml, Weather.qml, Docker.qml, ... (one per integration)

panelFamilies/              PanelLoader.qml (thin LazyLoader) + ImmaterialImpulseFamily.qml (the
                            actual list of panels for the "imi" family)

scripts/                   Standalone helper scripts (Python/bash) invoked via Process/Quickshell.execDetached
translations/              i18n string tables (Translation.tr(...) singleton)
assets/                    Static images/fonts bundled with the shell
```

## The Config system (settings page ↔ persisted JSON)

`Config.qml` defines the **entire** settings schema as nested `JsonObject` properties (e.g.
`Config.options.bar.resources.alwaysShowCpu`). This is not just an in-memory tree — Quickshell's
`JsonAdapter`/`JsonObject` machinery automatically:

1. Loads `~/.config/immaterial-impulse/config.json` into `Config.options` on startup.
2. Persists any property write back to that file (debounced by `Config.readWriteDelay`, 50ms).

Consequences for making changes:

- Adding a new setting = add a `property <type> name: <default>` inside the right nested
  `JsonObject` in `Config.qml`. No migration code needed; missing keys just fall back to the QML
  default until the user's `config.json` gets the key written the first time it changes.
- The settings UI (`modules/imi/settings/pages/*.qml`) is hand-written QML, not generated from the
  schema — every setting needs a corresponding `ConfigSwitch`/`ConfigSpinBox`/`ConfigSelectionArray`/
  etc. row added manually in the relevant page, bound with `checked: Config.options.x.y` /
  `onCheckedChanged: Config.options.x.y = checked`.
- **A ranged control writes back from `onValueModified`, never `onValueChanged`.** `ConfigSpinBox`
  and `ConfigSlider` are the two controls with a `from`/`to`, and their `value` changes for reasons
  that are not edits: QQC2 bounds `SpinBox.value` to `[from, to]` when the component completes,
  `Slider` does the same, and `StyledSlider`'s `Behavior on value` animates through intermediate
  values. `Config.qml` declares no ranges at all, so a control's range is always narrower than what
  the schema accepts — and a write-back on `onValueChanged` meant *instantiating a settings page*
  clamped whatever the config held to the control's range and wrote it out, destroying hand-edited,
  restored and preset-supplied values with no user action. Both controls now expose
  `signal valueModified(newValue)`, raised only for a real interaction, and the write-back handler
  reads the signal's `newValue`. The same reasoning applies to any lossy display expression
  (`value: Config.options.x / 60000`): a write-back that fires on load round-trips the value through
  an `int` and loses it. `tests/test_config_control_write_back.py` guards both halves — a source
  contract over every call site, plus a real settings page opened against a real out-of-range config.
- The inner control's own range widens to admit an out-of-range stored value
  (`from: Math.min(root.from, root.value)`), so a spin box shows the number the config really holds
  rather than a plausible-looking lie, and the user can only move it back toward the sanctioned
  range. Don't "fix" that back to a plain `root.from`/`root.to`.
- Consumers read `Config.options.x.y` directly and reactively - no separate "load config" step.
- **The config `FileView` does not start until `Directories.configDirReady` is true**, which happens
  when `scripts/migrate-config-dir.sh` exits. `~/.config/illogical-impulse` -> `immaterial-impulse`
  is a runtime migration that refuses to migrate into a directory that already holds a `config.json`,
  so a Config load reaching the directory first wrote its defaults in and permanently disabled the
  move - the user silently kept none of their settings. The script used to be fired with
  `execDetached` (returns immediately), so the ordering was a timing accident. Anything else that
  writes into `Directories.shellConfig` on startup should think about the same gate; the three
  `mkdir`s in `Directories.qml` that live inside it are behind it, and the script defends itself with
  `mv -T` for the rest. If the migration hangs, `Config` gives up after 10s and comes up **read-only**
  (`configDirTimedOut`) rather than writing into a half-migrated directory. See
  `docs/UPSTREAM_MIGRATION.md` and `tests/test_config_dir_migration_runtime.py`, which forces the
  losing interleaving with `IMI_MIGRATE_DELAY` instead of hoping to observe it.
- **A key with no declared property is destroyed by the first write, not just hidden.** The
  `JsonAdapter` serializes exactly its declared properties, and `writeAdapter()` runs on essentially
  every launch, so an undeclared key present in `config.json` survives only until then - verified
  end to end against an isolated `XDG_CONFIG_HOME`, including on a launch that changed nothing.
  This is what makes a key rename lossy, and it is why `Config.qml`'s upstream migration reads
  `configFileView.text()` (the raw file) inside `onLoaded` rather than `Config.options`: by the time
  anything else could look, the old key is already gone. Any future migration that needs to read a
  removed key must run in that same `onLoaded`, before `ready`, on the raw text - and it gets exactly
  one launch to do it. See `docs/UPSTREAM_MIGRATION.md`.
  (The desktop-widget migration's "old keys are deliberately left on disk" note is not a
  counterexample: `background.widgets.*` are still *declared* in `Config.qml`, which is precisely why
  they persist.)
- **Presets are the exception to the rule above, and that makes re-declaring a removed key
  dangerous.** `writeAdapter()` strips undeclared keys from `config.json`, but preset files under
  `~/.config/immaterial-impulse/presets/` are separate JSON the adapter never rewrites — whatever was
  in a preset when it was saved is still in it. So a key removed from the schema is gone from the live
  config but **preserved in every preset**, lying dormant. Re-declaring that key re-arms all of them on
  the next preset apply. This is exactly how `activeStill` came back — re-armed by 5d4bfa773
  ("feat(wallpaperEngine): reinstate activeStill, this time with a writer"), disarmed by 03b8b0298
  ("fix(wallpaperEngine): derive the greeter's still path, do not store it"); see
  [Before you restore something that was removed](#before-you-restore-something-that-was-removed).
  Three of the six presets on the author's machine still name the wrong project. Removing a key is
  therefore not reversible by simply putting it back — either migrate the presets or, better, do not
  store derivable state in the first place.
- **Do not store a path that can be derived from state the config already holds.** Two fields that
  must agree will eventually disagree, and nothing reports it. The greeter's full-resolution Wallpaper
  Engine still is the canonical case (aa0772773 ("feat(background): grab the greeter's still off the
  live surface")): the background grabs it off the live surface into
  `~/.cache/quickshell/wallpaperengine-stills/<activeProject>.png` (`Background.captureGreeterStill`),
  and every consumer — including `imi-sddm-theme`, a separate process that cannot ask the shell
  anything — rebuilds that path from `activeProject`. A derived path cannot name a different project
  than `activeProject` does, needs no clearing in `WallpaperEngine.stop()`, and cannot be carried
  stale inside a preset.
- **`Config.readWriteDelay`'s 50ms debounce only covers the disk write - it does nothing to stop
  every keystroke from firing whatever else reactively reads that option.** A `ConfigTextArea`
  bound as `onValueChanged: Config.options.x.y = value` re-triggers every consumer of
  `Config.options.x.y` (e.g. the media widget's player-matching, or a quote re-render) once per
  keystroke, not once per edit. Where the option feeds something more than a simple display value,
  add a local `Timer` (600ms is the convention already used, see `BarConfig.qml`'s
  `mediaDebounceTimer` and `BackgroundConfig.qml`'s `quoteDebounceTimer`) that assigns to
  `Config.options.x.y` only after typing pauses, instead of assigning directly in `onValueChanged`.

`GlobalStates.qml` is the sibling singleton for state that should **not** persist (is this sidebar
currently open, is the bar in autoHide-triggered-show state, etc.) - don't add ephemeral UI state to
`Config`, and don't add persisted settings to `GlobalStates`.

## Hyprland integration

**Hyprland only.** `README.md`'s "Compositor support" section is policy, not aspiration: there are no
plans to support Niri or any other compositor, upstream's compositor-abstraction layer is kept *only*
as a thin Hyprland facade so merges stay tractable, and compositor-specific code for anything else is
**removed when it lands**. `services/HyprlandBackend.qml` is what "thin facade" means. The Niri
counterparts that arrived with the `78c58b84` merge - `NiriBackend`, `NiriXkb`, `NiriConfig`,
`NiriBackdrop`, `CompositorGlobalShortcut` - were all removed on landing, as the policy requires.

Do not read a leftover `niri` string as evidence that support exists, is wanted, or needs cleaning
up. Everything that still matches is Hyprland code *imitating* Niri: the `overview.style = "niri"`
look (`modules/imi/overview/NiriOverview.qml`, which imports `Quickshell.Hyprland` and reads
`HyprlandData`), the `"niri"` animation preset in `scripts/hyprland/hyprconfigurator.py` built from
`hl.curve`/`hl.animation`, their `"Niri Like"` labels, and a generic `pkill sway || pkill niri`
logout fallback. None of it is compositor support.

Two separate mechanisms are in play, for different reasons:

1. **Quickshell's native `Quickshell.Hyprland` IPC bindings** (`Hyprland`, `HyprlandMonitor`,
   `HyprlandWorkspace`, `HyprlandToplevel`, `Hyprland.workspaces`, `Hyprland.monitorFor(screen)`,
   `Connections { target: Hyprland; function onRawEvent(event) {...} }`) - reactive, bindable,
   preferred when the data you need is exposed through it.
2. **`services/HyprlandData.qml`**, which shells out to `hyprctl clients/monitors/layers/workspaces
   -j` on a `Process` every time a (non-excluded) Hyprland IPC event fires. This exists because some
   state genuinely isn't exposed via (1) - e.g. whether a monitor's special workspace is currently
   *shown* (`monitor.specialWorkspace.name`), which only `hyprctl monitors -j` surfaces. Expect
   ~0.5-1s latency on this path (event → spawn `hyprctl` → parse JSON → property update) since it's
   process-based, not a live subscription.

**This user's Hyprland config uses a Lua-based config layer** (`hl.bind(...)`, `hl.dsp....(...)` in
`~/.config/hypr/hyprland/*.lua`). This changes how `hyprctl dispatch` needs to be invoked manually
(e.g. from a terminal while debugging) - plain vanilla syntax like
`hyprctl dispatch togglespecialworkspace special` fails with a Lua parse error on this system.
The working form mirrors the Lua binding calls directly, e.g.:
```bash
hyprctl dispatch 'hl.dsp.workspace.toggle_special("special")'
```
This is purely a manual-testing/CLI concern - IPC events, layer-shell behavior, and everything the
QML code touches are unaffected by this; only raw `hyprctl dispatch <dispatcher> <args>` calls typed
by a human/agent need the Lua-call form on this particular machine.

**Rules registered at runtime through `hyprctl eval` do not survive, so don't build on them.**
`hyprctl reload` resets the Lua state - every global and every rule registered from it is gone.
The shell reapplies the Hyprland theme during its own startup, which reloads, so anything a QML
`Component.onCompleted` registers via `execDetached(["hyprctl", "eval", ...])` is destroyed seconds
after it is created. This fails silently and in a way that is easy to misread: registering the rule
by hand from a terminal to "verify" it works leaves a rule that *does* persist until the next
reload, so the feature looks correct while the shell's own registration has never once been live.
Verify by clearing the global, restarting the shell, and re-reading it - not by running the chunk
yourself.

`Settings.qml` used to float/size/center its window this way. It doesn't need to: a `FloatingWindow`
whose `minimumSize` equals its `maximumSize` is floated, sized and centred by Hyprland on its own,
purely from the fixed size hints. Prefer that over a runtime rule. It also keeps the window title
free to stay translated, since nothing is matching on it.

**hyprsunset has no state query at all, so the shell owns night light's on/off state.** Checked
against 0.4.0, not assumed: `hyprctl hyprsunset --help` lists exactly three requests -
`temperature <temp>`, `identity`, `gamma <gamma>` - bare `hyprctl hyprsunset` answers
`invalid command`, and the daemon's own socket
(`$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.hyprsunset.sock`) answers `invalid command`
to `state`, `status`, `info`, `enabled`, `active` and `matrix` too. Nothing reports the applied
matrix.

The bare `temperature` request looks like a getter and is not one: it echoes back the last
temperature the daemon was *told*, which `identity` (the "off" dispatch) never resets. Measured on
this machine - a daemon running as `hyprsunset --identity`, screen perfectly neutral, reports
`6000`; a daemon put into identity after `temperature 5000` still reports `5000`. "Off" and "on"
are indistinguishable through it.

`services/Hyprsunset.qml` used to infer active state by comparing that query against a hardcoded
`"6500"`. That number is not hyprsunset's - it is the `from:` end of the Intensity slider in
`modules/imi/sidebarRight/nightLight/NightLightDialog.qml` (6500K, the UI's idea of "neutral
daylight"), reused as if it were a daemon sentinel. The daemon's actual default is 6000 and its
actual neutral is `--identity`, not a temperature at all, so the check read "on" whenever the last
set temperature was not literally 6500 - including with the identity matrix applied and the screen
neutral. Don't query `hyprsunset` for state; track on/off intent yourself. `Hyprsunset.qml`
persists it in `Persistent.qml` (`night.temperatureActive`, alongside `idle.inhibit` and
`record.enable`) and **re-applies** it on startup - applied, not merely displayed, because after a
reboot the daemon is gone and within a session it may have been left in any state. The restore is
gated on `Persistent.ready && Config.ready` together: `Persistent` holds the state, `Config` holds
the temperature to restore it *at*, and restoring without the latter launches the daemon at the
fallback temperature. `tests/test_nightlight_state_runtime.py` pins all of this against a real
shell and fake `hyprsunset`/`hyprctl`/`pidof` binaries.

This exact fix was made once before and lost: it landed in `0168b1d1`, and the upstream Niri merge
`78c58b84` silently restored the query, the `6500` sentinel and the "sync with whatever is running"
doc comment on top of it. Anything reintroducing `fetchState()` is a regression, not a refinement.

**That same bare `--temperature 6000` default also bit the daemon's cold start, not just state
queries.** `Hyprsunset.qml` used to spawn `hyprsunset` with no flags (`pidof hyprsunset ||
hyprsunset`) and immediately fire a separate, fire-and-forget `hyprctl hyprsunset identity`/
`temperature` correction right after via `execDetached`. On a warm system that correction reaches
the already-running daemon fine, but on a cold start (nothing running yet) it races the daemon's
IPC socket coming up and can silently fail, leaving `hyprsunset` stuck at its own 6000K default
indefinitely - toggling night light off after a restart looked like it did nothing, and toggling it
on read as the tint "intensifying" (6000K → the configured, warmer temperature) rather than turning
on from neutral. Fixed by launching `hyprsunset` with the target state already as CLI flags
(`--temperature N` / `--identity`) instead of spawning bare and correcting after the fact - a
freshly-spawned daemon now starts in the right state with no window where it's wrong.

**A Hyprland setting migrated in `config.json` is not migrated.** `Config.options.hyprland.*` is a
*record* of what the settings page last chose; the compositor never reads it. The value reaches
Hyprland through `~/.config/hypr/hyprland/shellOverrides/main.lua`, generated by
`scripts/hyprland/hyprconfigurator.py` (via `services/HyprlandConfig.qml`), and the only thing that
regenerates that file is the Hyprland settings page's `Component.onCompleted` - an on-demand
`Loader` (`SettingsContent.qml`, `active: Config.ready && (currentPage === index || item !== null)`).
A user who never opens that page keeps the old value indefinitely, so the two files drift apart, and
the lua one is the one that matters.

Issue #69 is the worked example, and it shipped broken twice for this reason: a migration cleared a
stale `input.kbOptions = grp:win_space_toggle` from `config.json` and the compositor went on
toggling layouts regardless. When migrating a `hyprland.*` key, migrate `main.lua` too - and do not
gate the lua half on the config value, because once a config-only fix has shipped, the population
still broken is exactly the one whose config is already clean. `--reset-if KEY VALUE` exists for
this: it drops the managed line only while it still holds the stale value, so it is safe to run on
every load and cannot clobber a value the user has since chosen. Hyprland watches these files and
reloads on change, so no explicit `hyprctl reload` is needed - which is also why the writer must not
rewrite a file whose content did not change.

**Keybind overrides are another generated shellOverrides file, with one extra rule: a chord-level
unbind exists but a bind-level one does not.** The keyboard-shortcuts editor renders its JSON sidecar
into `~/.config/hypr/hyprland/shellOverrides/keybinds.lua` (sourced last by `hyprland.lua`, guarded
by `is_file_exists`), following the same discipline as `main.lua` — atomic writes, no rewrite when
content is unchanged — plus a content hash in the header: a shim that does not hash-match was
hand-edited and the generator refuses to write *or delete* it, surfacing `shimStatus: "foreign"`
instead of clobbering. Overriding a default works because `hl.bind()` returns a keybind object whose
`:unbind()` removes **every** bind matching that chord's modmask+key (`CKeybindManager::
removeKeybind`), so binding a throwaway function and unbinding it clears a chord *including its
hidden sibling binds* — there is no way to remove just one of several binds on a chord from the shim,
which is why a rebind re-emits the parsed primary action and the `qsIsAlive`-style fallbacks on that
chord are gone with it. Re-emission is gated by a literal-only params grammar; `function` binds and
params referencing `keybinds.lua` locals are remove-only. An updated shim is picked up by Hyprland's
own config watch, but a *created* one was not sourced at the last load (nothing watches it), so the
service issues `hyprctl reload` only for created/deleted results.
(cd6296659 ("feat(hypr): source the shell's keybind override shim last"), 08d11dd83
("feat(keybinds): sidecar-to-Lua override generator with hand-edit protection").)

**Markers on such migrations are a trap of their own.** A persisted "already migrated" flag records
that the check *ran*, not that the value was ever *seen*, and the two come apart whenever the config
it ran against was not the user's - most reliably when the config-directory migration declines and
`Config` loads the installer's default first. Prefer an unconditional, idempotent clear whenever the
stale value is one the shell cannot legitimately hold, and reserve markers for migrations that would
otherwise undo a choice the user has since made. `tests/test_kboptions_migration_runtime.py` pins
both halves against real files; neither failure mode is reachable from a unit test, which is why the
original fix passed review with no test at all.

## Layer-shell (wlr-layer-shell) gotchas

Widgets that are `PanelWindow`s pick a `WlrLayershell.layer` (`Background < Bottom < Top < Overlay`).
Two non-obvious behaviors have bitten this codebase before and are worth knowing:

- Hyprland renders **fullscreen windows above the `Top` layer** (this is why a bar on `Top` disappears
  under a fullscreen app by default), but **below `Overlay`**. A special workspace opened on top of a
  fullscreen window compounds this. Fixing "X becomes unclickable/invisible under fullscreen +
  special workspace" generally means conditionally promoting that surface to `Overlay` only in that
  specific combination (see `modules/imi/bar/Bar.qml`'s `WlrLayershell.layer` binding and
  `modules/imi/screenCorners/ScreenCorners.qml`'s `fullscreen` property for the reference
  implementation).
- **`visible: false` on a layer-shell `PanelWindow` does not hide it, it destroys it.** Window reuse
  is forbidden under `WlrLayershell`, so the surface is torn down and a new one (with a new
  scene-graph GL context) is built on the way back. `hideWhenFullscreen` was implemented this way
  once and every fullscreen transition rebuilt the embedded Wallpaper Engine renderer against a
  fresh context, leaving the desktop strobing at 30Hz - a photosensitive-seizure hazard, not a
  cosmetic bug. Keep the window mapped and switch off an `Item` inside it instead
  (`Background.qml`'s `suppressContents`). This applies to any route to that property, not just a
  declarative binding: `bgRoot.visible = false` from a handler, or a `Binding` object aimed at it,
  destroys exactly the same surface. `tests/test_background_fullscreen_suppression.py` fails on all
  three.
- **Same-layer surfaces resolve overlap by stacking order, not layer priority.** If two `PanelWindow`s
  end up on the same layer and physically overlap, whichever the compositor considers "on top" wins
  *all* input in the overlapping region - the other surface's mask in that area is simply unreachable.
  When this happens, don't fight the ambiguous stacking order; instead carve the contested rectangle
  out of the losing surface's own `mask` using a `Region { intersection: Intersection.Subtract; ... }`
  child region, sized/positioned to exactly exclude the other surface's hit-zone. See `Bar.qml`'s
  `mask:` property for the pattern (it excludes `ScreenCorners.qml`'s corner-open hit rects when both
  are forced to `Overlay`).
- **Compositor blur behind a surface depends on that surface's actual alpha clearing a per-namespace
  threshold**, not just on "blur" being enabled somewhere. The companion Hyprland config
  (`~/.config/hypr/hyprland/rules.lua`) sets `hl.layer_rule({ match = { namespace = "quickshell:.*" },
  ignore_alpha = 0.79 })` (plus a `blur = true` rule) - pixels with alpha below that threshold are
  *not* blurred, they just show plain unblurred transparency. This is why picking the right
  `Appearance.colors.colLayer*` token matters for a floating popup, not just picking "a" transparent
  one - see the Design language section below.
- **Blur is scoped per-panel now, and scoping it takes an edit in two different files.** The panels
  ported so far - bar, vertical bar, dock, both sidebars, the OSDs and the overview - each turn the
  catch-all whole-surface `blur` *off* for their namespace in
  `~/.config/hypr/hyprland/rules.lua` and publish a `WindowBlurRegion`
  (`modules/common/widgets/WindowBlurRegion.qml`) over just its painted body instead, so the
  compositor never blurs the shadow (#82, #89). A blur region is a plain rounded rect and knows
  nothing about `visible`, `opacity`, or a parent's `clip`, so each sub-region has to be gated on
  exactly the condition that *paints* its shape - covering an unpainted one frosts bare wallpaper -
  and `Appearance.rounding.full` (9999) is a "round me completely" sentinel that must be resolved to
  `Math.round(item.height / 2)` before it goes into a region. A body reached through a `Loader` is
  exposed to the window as a `backgroundItem`/`backgroundPainted` pair on the content component
  rather than reached into. Both halves are silent when only one lands: a region without the layer
  rule changes nothing at all, and the layer rule without a region leaves that panel with no blur
  whatsoever. `tests/lint_blur_region_pairing.py` pins the two together.
- **That whole mechanism applies to layer surfaces only, and a `PopupWindow` is not one.** An
  `ext-background-effect` region is attached to a layer surface; the tray menu, the dock context
  menu, the drag-apps popup and the tooltips are xdg-popups, so a `WindowBlurRegion` published from
  one is accepted and silently does nothing. Popups also carry no namespace of their own - they
  inherit the rules of the surface they belong to, so the only knob addressed at them is
  `blur_popups` on the parent's namespace, and turning that off costs the body its blur along with
  the shadow. Threshold by `ignore_alpha` instead: `colShadow` tops out at 0.3 and fades outward
  while a panel body sits at `1 - appearance.transparency.backgroundTransparency`, so a value
  between them blurs one and not the other. Note the failure direction - too high a threshold
  unblurs the *body*, which looks flat but harmless; too low re-frosts the shadow. Motivated by
  4a1b4f850 ("fix(blur): stop the compositor frosting drop shadows"), where a region
  was written, deployed and only shown to be inert by looking at it on screen; a region on a
  `PopupWindow` now fails `tests/lint_blur_region_pairing.py`. The threshold itself is *generated*,
  because where it falls moves with the user's transparency setting and a layerrule cannot read
  one: `services/PopupBlurThreshold.qml` writes
  `hypr/hyprland/shellOverrides/popupBlur.lua` and `rules.lua` `dofile`s it behind a `pcall` with a
  fallback for the first run. That rule is applied only to namespaces whose own `blur` is already
  off, so it reaches their popups and nothing else. Watch which way it fails: too high a threshold
  unblurs the *body*, which is flat but harmless; too low re-frosts the shadow.
- **`ignore_alpha` is one value per namespace, shared between a panel and its popups.** It is
  tempting to raise it on a namespace whose own `blur` is off, on the reasoning that only its popups
  can be affected. That is wrong: the panel's body is blurred *through the region*, and the region
  is subject to `ignore_alpha` too, so raising it above the body's alpha unblurs the panel itself.
  Doing exactly that took the blur off the bar, the dock and both sidebars at once. The threshold
  has to clear the faintest *panel* body as well as sit above the shadow, and the bar is usually the
  faintest because it thins `colLayer0` again by `bar.backgroundOpacity`. Motivated by 4a1b4f850
  ("fix(blur): stop the compositor frosting drop shadows").
- **`quickshell:popup` is already handled, and adding `blur = false` to it breaks it.** Its two
  surfaces (`StyledPopupMenu`, `StyledPopup` - `PanelWindow`s despite the name) paint opaque bodies,
  and the namespace carries `ignore_alpha = 1` from an older tooltip fix. That blurs the opaque body
  and skips the translucent shadow, which is the whole split the region mechanism exists to produce.
  Set `blur = false` there and the region becomes the only source of blur, which nothing reaches at
  alpha 1, so those surfaces go flat.
- **A blur region is published on the *timer* for panels built by a `LazyLoader`.**
  `Component.onCompleted` publishes, but there is no layer surface yet at that moment, so the first
  publish that takes effect is the settle timer's - which is a guaranteed ~96ms of surface-up-and-
  unblurred on every open. Publish immediately *and* keep the timer. Motivated by 4a1b4f850
  ("fix(blur): stop the compositor frosting drop shadows").
- **This whole area is invisible to the test suite.** Quickshell's plugin does not load in
  `qmltestrunner`, so `Region` cannot be constructed there and no test can see whether a region is
  empty, published, or ignored. Every bug in this section was found by looking at the screen, and
  two of them were misattributed first. Deploy, look, and prefer a frame-by-frame capture
  (`ffmpeg -fps_mode passthrough`) over an impression for anything that lasts under ~200ms.
- **A stored config value beats the QML default, so changing a default is invisible without a
  migration.** `Config.qml` defaults only apply to keys that are absent from the user's
  `config.json`, and every key the shell has ever written is present. Flipping a default therefore
  changes nothing for anyone who has run the shell - which is a silent no-op, not an error. Pair it
  with a one-shot migration guarded by its own `migrated*` flag, as `migrateDeadParallaxSwitches`
  and `migrateSplitCheatsheetButtons` do. Motivated by 65bd7696a ("feat(cheatsheet): draw a chord as
  one keycap per key").
- **The region selector intentionally takes exclusive focus.** Dismissable panels normally close
  when `GlobalFocusGrab` is cleared, but the selector first sets
  `GlobalStates.settingsHeldForRegionSelector` so Settings can remain visible in screenshots without
  racing surface creation. Because clearing the grab also empties its dismissable list, Settings
  must re-register itself when selection ends even though its own `visible` property never changed.

## State propagation is reactive, or it is a bug waiting

**"When X changes, refresh Y" must observe X — a property binding, a `Connections` handler, or an
explicit completion poke — never piggyback on an unrelated trigger that happens to fire often
enough.** The shell is an observer system end to end; a consumer wired as a callback of something
else's event inherits two defect classes at once: it goes stale for every X-change that does not
happen to fire the borrowed trigger, and it races every asynchronously-produced input it cannot
wait for.

The worked case is the SDDM greeter sync. Its inputs were refreshed only as a side effect of
matugen's color generation, so WE scaling changes never reached the login screen, and the
full-resolution still — grabbed a second *after* the config change that announced it — could be
produced after the copy and miss the greeter until the next unrelated color event. The fix
(a605450fd ("feat(greeterSync): observe the greeter's inputs instead of borrowing matugen's
trigger"); `services/GreeterSync.qml`, spec in
`docs/superpowers/specs/2026-08-05-reactive-greeter-sync-design.md`)
observes the greeter-relevant leaves and is poked by the grab's completion, with the expensive side
gated by an output diff so over-observation costs a hash, not a root copy. That gate is the general
enabler: make firing cheap, then observe generously — under-observation is the staleness bug,
over-observation is free.

If you find yourself adding a second caller to an existing hook "because it also needs to run
then", stop: name the input that actually changed, and observe it.

**A transient consumer observes by poking a cache, not by owning the producer.** The scheme
swatch preview was a `Process` plus a debounce living inside the settings page, which is fine
for a surface that exists for as long as the user keeps it open. Its second consumer is the
desktop menu's Wallpaper & style submenu — created and destroyed on every hover — so neither
option was available: copying the producer in re-quantizes a wallpaper per hover, and making
the producer a freely-running singleton burns a venv quantize on every wallpaper change for the
rest of the session whether or not anything is showing. `services/SchemePreview.qml` caches
against the inputs that produced the result (`sourcePath + mode`) and exposes a `refresh()` that
returns immediately while that key is unchanged, so a consumer coming on screen calls it
unconditionally and pays only when it would have been wrong. That is the same "make firing cheap,
then observe generously" gate as above, applied to a producer rather than a consumer.
(2b5ea4ce5 ("refactor(settings): make the scheme preview reusable outside the settings page").)

## Dynamic/data-driven QML gotchas

Relevant to anything that instantiates QML components from external data (JSON manifests, config
arrays, etc.) rather than static declarations - e.g. the plugin system in
`modules/common/plugins/`:

- **`item[propName] = value` (JS bracket assignment) only resolves real top-level property names.**
  It does not walk a dotted path into a grouped property - `item["anchors.centerIn"] = parent` or
  `item["font.pixelSize"] = 20` will not do what it looks like it should; the real properties are
  `item.anchors.centerIn` and `item.font.pixelSize`, which bracket-notation string keys don't
  resolve into. If a data-driven schema needs to set grouped properties, either give the renderer
  explicit dot-path-splitting logic, or keep the schema flat and avoid grouped-property keys
  entirely.
- **A component-type/binding-target whitelist and the renderer that's supposed to honor it are two
  separate lists that can drift apart.** `PluginValidator.js`'s `componentWhitelist` and
  `PluginNode.qml`'s renderer `switch` need to name exactly the same set of component types - a type
  present in one but not the other means either "validates fine but silently renders nothing" or (if
  the renderer's list is the wider one) an unvalidated type reaching the renderer. Treat this the
  same as the Config-schema/settings-page two-sidedness described above: a change to one side isn't
  done until the other side matches.
- Bundled plugins that need behavior the data-only node tree cannot express may use a narrowly
  scoped renderer type, as `bundled/atAGlance/AtAGlance.qml` does for date formatting, timed quote
  rotation, and quote-file loading. Add that type to both the validator and renderer, and keep
  arbitrary processes or script evaluation out of manifests.
- **`Text` inherits `Text.AutoText`, which sniffs HTML-ish content and renders it as markup — so
  any widget displaying an attacker-controlled string is a rich-text injection site unless
  something pins its `textFormat`.** Installed plugin manifests are exactly that:
  `PluginValidator.js` type-checks `manifest.name` and nothing else, and manifest strings (name,
  description, author, option labels, icons, placeholders) reach the screen through `StyledText`,
  so `<img src=...>` in a manifest field rendered as an image. The per-site
  `textFormat: Text.PlainText` fix had been applied five separate times and still kept missing
  sites, so both `StyledText` definitions (mainline and the plugin design system's copy) now
  default to `Text.PlainText`, and rich text is a per-site opt-in reviewed into
  `tests/lint_rich_text_optin.py`'s allowlist — a new opt-in fails the suite until someone confirms
  no untrusted string reaches it unescaped (d782c2170 ("fix(widgets): default StyledText to
  PlainText, make rich text opt-in"), f224ec6b7 ("test(lint): pin the PlainText default and
  reviewed rich-text opt-ins")). Two corners that default cannot reach: the Basic Controls style
  (pinned by `pragma Env QT_QUICK_CONTROLS_STYLE=Basic`) draws `placeholderText` through its own
  `PlaceholderText` child *inside Qt* — still `AutoText`, fed `optionData.placeholder` straight
  from the manifest — so `ConfigTextArea` walks the field's children at completion and pins every
  `Text` to `PlainText` (dce31aa98 ("fix(widgets): force ConfigTextArea's style placeholder to
  plain text")); and the vendored `scripts/plugins/registry_validate.py` is a separate copy of the
  QML surface vocabulary that had drifted, letting an overlay-widget-only registry entry skip the
  screenshot requirement — `test_registry_validate.py` now pins its `VISUAL_CAPABILITIES` to
  `PluginManager.surfaceCapabilities` (6a359273a ("fix(plugins): require a screenshot for
  overlay-widget registry entries")). Do not "sanitise" manifest strings at parse time instead:
  stripping markup on the way in corrupts legitimate text containing `<`; the render site is the
  defence.
- **`FileView` (`Quickshell.Io`) loads asynchronously - `.text()` right after calling `.reload()`
  is not guaranteed to return the new content.** The correct pattern (used throughout this codebase
  - `MaterialSymbolsSearch.qml`, `Notifications.qml`, `Emojis.qml`, `Profile.qml`) is to read
  `.text()` from inside the `onLoaded` handler, not immediately after `reload()`. A `PluginManager`
  rewrite that called `fileView.reload(); const text = fileView.text();` back-to-back silently got
  an empty string every time, with no error - only a `console.log` inside the failure branch (which
  never fired, since nothing *failed*, it just wasn't ready yet) would have revealed it.
- **`FileView.blockWrites` makes writes synchronous; it does not suppress them.** The whole
  `block*` family (`blockLoading`, `blockAllReads`, `blockWrites`) is about blocking the calling
  thread, not about blocking the operation - the names read like a permission switch and are not
  one. Setting `Config.blockWrites = true` to stop the shell touching `config.json` looks right,
  passes review, and writes the file anyway (`Config.qml`'s watchdog was written that way first;
  only `tests/test_config_dir_migration_runtime.py` reading the file back caught it). To actually
  not write, gate the call sites - `writeAdapter()` in `onLoadFailed` and the debounced write timer.
- **An unset `FileView.path` is a real "no file" state, and a useful one.** With `path: ""` the view
  emits neither `loaded` nor `loadFailed`, and `writeAdapter()` on it writes nothing - so
  `path: someGate ? realPath : ""` holds an entire `JsonAdapter` off the disk until the gate opens,
  rather than merely delaying a read. That is how `Config.qml` waits for the config-directory
  migration. Verified against a real `qs` instance; do not assume an empty path errors or creates
  a file somewhere.
- **`Repeater` only auto-binds a model item to a `required property` declared on the delegate's
  *root* object, not on a descendant.** `required property var modelData` on a widget nested a level
  or two inside the actual delegate root throws `Required property modelData was not initialized`
  for every instance. Put the `required property` on the outermost delegate item and forward it down
  as an ordinary (non-required) property if a nested child needs it.
- **`qs` is not a usable JS object from inside a `Qt.binding(function() {...})` closure.** It's a
  module-namespace prefix the QML engine resolves at compile time for declarative bindings, not a
  runtime global - `qs.modules.common.Appearance.colors[colorName]` inside an imperative closure
  throws `ReferenceError: qs is not defined`, silently leaving that binding's target property
  undefined (no crash, so it's easy to miss unless you actually watch the log with a plugin
  enabled). Import the singleton directly (`import qs.modules.common`) and reference it by its bare
  name (`Appearance.colors[colorName]`) instead. This one went unnoticed through two prior plugin
  merges (clock, battery) because `plugins.enabled` in the shared config was empty the whole time -
  the manifests were validated and rendered structurally, but never with `Appearance.colors.*`/
  `Appearance.rounding.*` bindings actually resolving against a real running instance.
- **Never `anchors.fill: parent` a `Loader` whose *own* size is meant to be derived from the loaded
  item's implicit size.** `Loader` forces the loaded item to match the Loader's size whenever the
  Loader itself has an explicit size (anchors count as explicit sizing) - but if the wrapping
  `Item`'s `implicitWidth`/`implicitHeight` are themselves bound to `loader.item.implicitWidth`,
  that's a direct cycle (item forced to match wrapper, wrapper's size derived from item) and Qt logs
  `Binding loop detected for property "implicitWidth"` and gives up re-evaluating it. Leave the
  Loader unanchored so it mirrors the item's natural size instead; set explicit width/height via the
  item's own properties (e.g. manifest `props`) when a fixed size is actually wanted.
- **Do not put dynamic object maps in a `JsonAdapter`, including through a `property var`.** Plugin
  ids and monitor names are not known when QML compiles, while `JsonObject` only supports declared
  properties. Writing undeclared children caused `JsonAdapter::deserializeRec` to segfault on the
  following config reload; declaring a `property var` map also segfaulted while loading it. Keep
  dynamic plugin layout in `PluginState.qml`, which parses and writes `plugin-state.json` with a raw
  `FileView`. Fixed-schema user settings still belong in `Config.qml`.
- Plugin manifests may declare a constrained top-level `options` array (`boolean`, `choice`, or
  `number`). `PluginOptions.qml` renders those controls and `PluginState.qml` persists their dynamic
  values. Desktop backdrop blur is also per-plugin state: a manifest opts into its default with
  `desktopWidget.blur: true`, while the generated **Blur background** option always lets the user
  override it. Do not make `PluginWidget` blur every plugin unconditionally.
- **"The frost is gated on the toggle" is not "the surface is gated on the toggle."**
  `appearance.transparency.enable` removed every desktop widget's blur — `PluginWidget`'s blur
  `Repeater` reads the flag — while the widgets' panel alpha kept coming from
  `plugins.blurOpacity` and four hardcoded `0.1` literals, which do not. Turning transparency
  **off** therefore left fourteen widgets ~10% opaque over a now-**sharp** wallpaper: a worse
  result than leaving it on, while the dock and the settings window correctly went opaque. Opacity
  and blur were two settings and only one knew about the switch. The derivation now lives in
  `PluginState.effectiveBackgroundOpacity(pluginId, base)` — the only place that can see both the
  toggle and the per-plugin opt-out (`keepTranslucent`), since the generic
  `designsystem/widgets/Desktop*Widget.qml` have no `PluginWidget` root in scope and a host-side
  property could never have reached them. When adding anything that paints its own alpha, ask what
  it looks like with the toggle off, and route it through the derivation rather than repeating the
  conditional; `tests/test_widget_transparency_opacity.py` reddens on a call site that reads
  `plugins.blurOpacity` directly. The exemption gates the frost too — a widget excused from the
  opaque default but still denied its blur is exactly the hole this removed.
  **The plugins were not the only ones**, and the audit that found the other two is the point:
  `Appearance.colors.colBarBackground` thinned the (already gated) `colLayer0` by an ungated
  `bar.backgroundOpacity`, and `DropShelfPanel` painted an ungated `dropShelf.backgroundOpacity`
  — the shelf shipped 50% see-through with transparency off, in the default config. Both defaults
  (`1`, and a panel most people never open) are why nobody reported them. Neither routes through
  `PluginState`: that function resolves a *per-plugin* opt-out from a manifest seed, so a panel
  would pass an empty id forever and drag the plugin state store into an unrelated module for a
  one-line conditional. The generalising abstraction for a non-plugin surface is the one
  `Appearance.qml` already had — a transparency *amount* declared beside `backgroundTransparency`
  / `contentTransparency` that collapses to `0` when the switch is off. Keep new amounts there,
  where "is every one of them gated?" is answerable by looking.
  b259288b2 ("feat(plugins): derive desktop-widget opacity from the transparency toggle"),
  3088bbaed ("fix(plugins): route every widget panel opacity through the derivation"),
  e4f3a095e ("fix(appearance): gate the bar's own opacity on the transparency switch"),
  b47935a65 ("fix(dropShelf): gate the shelf's frost on the transparency switch").
- Desktop plugin delegates are retained for every available manifest and gated through an animated
  `FadeLoader`, rather than repeating only the enabled ids. Removing a model delegate destroys it
  immediately and makes an M3 exit transition impossible; keep disabled loaders dormant until their
  fade-and-scale exit reaches zero opacity.
- **`MouseArea.drag` cannot accurately drag a target the MouseArea itself follows.** QQuickDrag
  rebases its press origin when the grab is established, silently swallowing the arming move's
  delta — a few threshold pixels under a real pointer, invisible behind the widget lattice's 12px
  snap, but measured as half the gesture under a sparse synthetic drag — and a live binding on the
  drag target (the old `Item { x: root.x }` drag proxy) re-yanks the target after every internal
  write, measured as +168 applied for a +96 eight-step gesture. Where a drag must be pixel-exact
  (the desktop widgets' group drag preserves follower offsets), compute it by hand instead: map the
  press point and each move through the (moving) item into its static parent frame — the current
  transform, press scale included, cancels out — and set the target to pressStart + delta, as
  `widgetCanvas/AbstractWidget.qml` now does. d2ebb5aeb ("fix(widgetCanvas): compute the drag by
  hand - MouseArea.drag cannot track it").
- **A `Process`'s `onExited` handler that ignores its `exitCode` argument will happily act on stale
  data.** `TempScreenshotProcess` writes to a deterministic path (`image-${screen.name}`), so a failed
  `grim` run used to leave the *previous* successful capture sitting there untouched - the region
  selector/screen translator would silently proceed against stale image data with no error, since
  nothing actually "failed" from QML's perspective. Always check `exitCode` in `onExited` before
  trusting the process's output exists or is fresh; `rm -f`-ing the target path before launching the
  process (see `TempScreenshotProcess.qml`) turns a silent stale-reuse into an honest empty-file
  failure instead.
- **An overlay `Item` placed on top of an interactive control (e.g. a decorative `Flickable`-based
  mask drawn over a `TextField`/`TextArea`) will silently eat the clicks meant to focus that
  control**, unless the overlay is `enabled: false`. `ConfigTextArea`'s `password: true` mode draws
  `PasswordChars` (a `Flickable`) directly over the real field to render Material-shape dots in
  place of the native glyphs; without `enabled: false` on that overlay's `Loader`, clicking the
  field just fed the click to the Flickable instead, so the field never focused and typing appeared
  to do nothing. This only surfaces where focus is obtained by clicking - `LockSurface.qml`'s
  password box uses the identical overlay structure but never hit this, since it
  `forceActiveFocus()`s itself programmatically instead of depending on a click.
- **`enabled: false` on a `MouseArea` disables that area and nothing under it.**
  `QQuickMouseArea` declares its own `enabled` property, which shadows `Item.enabled` — so the
  usual "`enabled` cascades to the whole subtree" intuition, which is true of a plain `Item`, is
  false here. `AbstractBackgroundWidget` (a `MouseArea` via `AbstractWidget`) used `enabled:
  !clickThrough` as its entire click-through mechanism: it correctly stopped the host's own drag
  and right-click, and left every `MouseArea` a widget drew inside itself fully live, so a
  "click-through" widget still swallowed clicks aimed at the desktop behind it. The fix is a plain
  `Item` wrapper carrying the gate, with the children routed into it via a `default property alias`
  (`contentData: contentItem.data`) — anchored `fill: parent` so it takes no part in sizing and
  cannot reintroduce the `Loader` binding loop above. Both gates are needed; neither covers the
  other. Whenever the disabled thing is a `MouseArea`, `Control`, or anything else that redeclares
  `enabled`, check what you actually disabled with a probe rather than assuming the cascade.
- **The disabled dim is expressed at exactly one layer, because `opacity` composites.** The
  sibling trap to the one above: `enabled` cascading correctly is what makes it *easy* for two
  components in the same subtree to each write `opacity: enabled ? 1 : 0.4` and produce 0.16.
  `ConfigSwitch` is rooted on a `RippleButton`, which dims the whole control, and then repeated
  the binding on its icon, label, description and two of its three content slots — so every
  disabled settings row rendered at roughly a sixth opacity, and `trailingContent` (which never
  had the second binding) sat at 0.4 half a row away from `titleContent` at 0.16. Keep the dim on
  the layer that covers the whole control: it is the only one reaching a child with no dim of its
  own (`StyledSwitch`'s track), and on `RippleButton` it is the binding `ExpandablePanel`'s
  stagger is built around — the stagger animates `appear` rather than `opacity` precisely so it
  cannot destroy it. The other settings controls (`ConfigSpinBox`, `ConfigComboBox`,
  `ConfigTextArea`, `ConfigSelectionArray`) are rooted on a plain `RowLayout` and were already
  correct; `ConfigSwitch` was the only doubled one. `tests/lint_disabled_opacity.py` fails any
  `enabled`-conditioned opacity nested inside a component whose root type already dims.
  (8f83b2e16 ("fix(widgets): a disabled ConfigSwitch dims once, not twice").)
- **A QML property binding that calls a C++ invokable method (not a property read) will not
  re-evaluate when that method's underlying data changes.** `DesktopEntries.applications` takes a
  few seconds to populate after `qs` starts. `DragApps.qml`'s pinned-app launcher bound
  `deskEntry: appEntry ? DesktopEntries.heuristicLookup(appId) : null` once at delegate creation -
  since `heuristicLookup()` is a plain invokable, not a property, the binding engine can't see it
  depends on `applications`, so `deskEntry` came back `null` (evaluated before the scan finished)
  and then never updated. Any pinned app that wasn't already running at shell startup became
  permanently unlaunchable for that session - clicking it silently no-op'd via `deskEntry?.execute()`.
  `DockAppButton.qml` and `DocktoPanel.qml` had independently worked around this with their own
  `Connections { target: DesktopEntries; function onApplicationsChanged() { ... } }`, but
  `DragApps.qml` was missing the same fix - this was three copies of the same fragile pattern with
  one left unpatched. Consolidated into `modules/common/widgets/LiveDesktopEntry.qml`, a small
  non-visual `Item` that takes an `appId` and exposes a live-refreshing `entry`; all three call
  sites now use it (`deskEntry: liveDeskEntry.entry` instead of duplicating the `Connections`).
  Covered by `tests/tst_live_desktop_entry.qml` against a mock `DesktopEntries`
  (`tests/mocks/Quickshell/DesktopEntries.qml`) that can simulate `applications` populating late via
  `mockSetEntries()`. When a binding depends on the result of an invokable rather than a property,
  add an explicit `Connections` re-fetch on the relevant `*Changed` signal instead of trusting the
  binding to track it - and prefer extracting it into a reusable, testable component over
  re-inlining the same fix at each call site.

**Wallpaper parallax is one oversized viewport, not a per-layer effect.**
`Background.qml` draws every wallpaper layer inside `parallaxViewport`, an item sized to
`screen * parallax.workspaceZoom` whose `x`/`y` are the effect; the maths lives in
`modules/common/functions/parallax.js` so it can be tested without a compositor. Keep new wallpaper
layers **inside** that viewport and `anchors.fill: parent` - that is the only reason Wallpaper
Engine parallaxes at all, since the WE surface, the frozen switch stills and the peel shaders are
all sized to the same item and therefore pan together. Anything that must stay screen-sized (the
widget canvas, the desktop right-click area) is a *sibling* of the viewport and needs its own copy
of the `suppressContents` fullscreen gate, which the viewport carries for its own children.
Sizing is deliberately screen-derived rather than wallpaper-derived: a live WE project reports no
intrinsic size, and `PreserveAspectCrop` already covers a still, so one rule serves both.
(feat(background): revive wallpaper parallax, for stills and Wallpaper Engine.)

**A feature that was config-only cannot be revived on its stored values.** The parallax knobs
shipped for the whole life of this shell with nothing reading them, so every `config.json` holds
values that predate the feature doing anything - on the author's machine every switch was `false`.
Turning the code back on against those values ships the feature dead for everyone who has ever
written a config, which is everyone, and no unit test sees it: the QML default says `true`, the
stored config says `false`, and the adapter's answer is the one that runs. Reviving dead config
therefore needs a one-shot migration with a marker (`migrateDeadParallaxSwitches`), and a runtime
test that seeds a real config directory. Reset only the switches - a tuned number is a plausible
preference and usually cannot disable the feature by itself.
(fix(config): revive the parallax switches every stored config turned off.)

**Treat repeated binding exceptions as potential resource runaways, not harmless log noise.** A
sidebar media-player binding called `filterDuplicatePlayers()` without defining the helper in that
component. The visible log only gained an occasional `ReferenceError` when MPRIS state changed, but
the `qs` main thread eventually spun at 100% CPU while anonymous resident memory grew past 30 GiB,
freezing the shell and threatening to freeze the whole machine. If the shell becomes unresponsive,
inspect the live process before restarting it (`ps -p <pid> -o stat,%cpu,%mem,rss,vsz,nlwp,wchan` and
`pmap -x <pid>`): a runnable main thread plus rapidly growing anonymous memory points to a QML
evaluation/allocation loop. Correlate the last `WARN scene` entries with reactive bindings, and
verify that every locally-called helper exists in that component or comes from an explicitly
imported singleton/module.

**Do not bind an image source directly to `SystemTrayItem.icon`.** Tray properties are backed by a
third-party StatusNotifierItem over D-Bus. A broken Electron tray provider repeatedly failed its
`IconName` getter; the direct `IconImage.source: item.icon` binding then drove the GUI thread to
100% CPU while anonymous memory grew by gigabytes. `modules/imi/bar/SysTrayItem.qml` deliberately
debounces icon change signals into `stableIconSource`, retains the last non-empty URL, and uses a
fallback glyph for missing/error states. Keep that mediation in place; `tests/lint_systray_icon_binding.sh`
guards the critical source binding.

**Shared chrome must not branch on a specific widget or plugin identifier.** When one overlay widget
needed a brand logo instead of a Material Symbol, the first version taught `OverlayTaskbar.qml` to
check `identifier === "discordVoice"` and imported that plugin's package into generic overlay chrome.
Every later branded widget would have added another branch. The registry entry carries the exception
instead: `OverlayContext.availableWidgets` entries accept an optional `iconComponent`, and the taskbar
renders whatever it is given and binds `toggled` on it. The same rule produced
`StyledOverlayWidget.titleIconComponent`. If shared code needs to know *which* widget it is drawing,
the data model is missing a field.

**A widget whose size inputs are user-configurable cannot have a fixed implicit size on either axis.**
The Discord overlay derived `implicitHeight` from its content but left `implicitWidth` hardcoded, while
avatar size (32-80) and count (1-12) both remained settings — a full row reached ~960px inside a 344px
box. Derive the growing axis too, but compute it *arithmetically* from the inputs rather than reading a
child layout's `implicitWidth`: the content is anchored to this item's width, so reading its implicit
size back would bind width to itself. Cap the result and let the grid wrap instead of growing forever.

## Design language

The shell follows **Material 3 / Material 3 Expressive**. `Appearance.qml` is the single source of
design tokens - color roles (`Appearance.colors.col*`, `Appearance.m3colors.m3*`), font sizes
(`Appearance.font.pixelSize.*`), rounding (`Appearance.rounding.*`), spacing
(`Appearance.spacing.*`), border widths (`Appearance.borderWidth.*`), animation curves/durations
(`Appearance.animation.*`). New UI should pull from these rather than hardcoding colors/sizes/
durations, both for dark/light theme correctness and for consistency with the rest of the shell.
`Appearance.spacing.*` follows Material 3's system scale (`0, 2, 4, 6, 8, 10, 12, 14, 16, 20, 24,
32, 36, 40, 48, 56, 64, 72`), named `space0` through `space900`; `space100` (8px) is the base unit.
Prefer multiples of 8 for the main rhythm and the recommended intermediate tokens for nested
spacing. Use canonical `spaceNNN` names directly; semantic aliases are not supported.
`Appearance.borderWidth.*` is `1/2/4`. Snap raw spacing/padding/margin to the nearest spacing token -
`tests/lint_spacing.py` (run by `tests/run_tests.sh`) enforces declarations and assignments.

**Any `.qml` that references `Appearance` (or any other `qs.modules.common` singleton) as a bareword
must `import qs.modules.common`.** That import is *not* transitive - a file that only has
`import qs.modules.common.widgets` does not get `Appearance` in scope, and the reference silently
throws `ReferenceError: Appearance is not defined` on every binding evaluation. This is not just a
cosmetic error: when the missing token feeds a positioner's `spacing`/`margin`, the binding yields
`undefined` -> NaN geometry, and QtQuick relayout never converges - it pegs a core at 100% CPU and
freezes the shell (this is exactly what a bulk token migration did to `ConfigRow.qml`,
`NotificationListView.qml`, `PluginOptions.qml`, and `StyledPopupMenu.qml`). `tests/lint_qml_imports.sh`
(run by `tests/run_tests.sh` and CI) guards against reintroducing it.

**Strict UI Guidelines:** See [`docs/M3_GUIDELINES.md`](docs/M3_GUIDELINES.md) for the definitive rules on tokens, rounding, layering, and expressive motion that all new components must follow.

**The sidebar's bottom widget group has a fixed height, and that is load-bearing.**
`BottomWidgetGroup.qml`'s `expandedHeight` is a constant (352) rather than a binding on its
content, because the group and the notification list share the sidebar column: every pixel the
group grows is a pixel the notification list loses. Making it content-sized (`Math.max(350,
tabStack.implicitHeight + ...)`) looks like a harmless fix for the calendar being clipped, but it
silently hands ~36px of the notification list to the calendar, and once the group is above the
floor no amount of tightening the calendar's own spacing changes anything visible - the number
just moves around above the threshold. Size the *tab* to the budget instead. The calendar's
`dayCellSize` (36), `CalendarHeaderButton.implicitHeight` (32), the column's `space75` gaps and
`contentPadding` (`space150`) are chosen together so the total is exactly 350 inside 352.

`CalendarWidget`'s column is top-anchored at `contentPadding`, not `anchors.centerIn: parent`. The
parent is stretched to the group's fixed height, so centring drifts the header row down by half
the leftover space and knocks the month pill and the ‹ › buttons off the navigation rail's collapse
button. The rail's `Layout.topMargin` and the calendar's `contentPadding` must stay equal, and the
header button and the rail button must stay the same height, or that shared centre line breaks.

Shared building blocks to reach for before writing something from scratch: `StyledText`,
`StyledComboBox`/`StyledComboBoxSearch`, `StyledSlider`, `StyledToolTip`/`StyledToolTipContent`,
`RippleButton`, `MaterialSymbol`, `ResourceCard`, `GroupedList` + `ConfigSwitch`/`ConfigSpinBox`/
`ConfigSelectionArray`/`ConfigComboBox`/`ConfigTextArea` (settings rows), `StyledPopup`,
`StyledRectangularShadow`, `DockIconMotion` (wraps a dock icon's visuals with hover-lift /
press-squish / launch-bounce / appear-pop feedback, driven by `services/DockLaunchTracker`),
`SchemePaletteCircle` (an Android 12-style palette circle for a colour scheme, fed from
`services/SchemePreview`, with the scheme's glyph as the fallback while the colour venv has not
answered). All in `modules/common/widgets/`.

**A colour scheme is shown as its colours, not as a glyph.** The desktop menu's nine scheme
presets were nine abstract Material Symbols sitting directly above a list of transition
animations drawn the same way, so the grid read as more animations
([#142](https://github.com/XephyLon/immaterial-impulse/issues/142)). A preset's colours cannot be
known without running the quantize — that is what `SchemePreview` is for — so the glyph stays as
the fallback rather than as the design.
(782be8329 ("feat(desktopMenu): draw each scheme preset as the palette it produces").)

`ConfigTextArea` is the text-entry counterpart to `ConfigSwitch` (icon + label/description on the
left, a bordered `TextArea` field on the right) and is the standard single-line settings field -
prefer it over building a raw `TextField`/`TextArea` row by hand. Set `password: true` for masked
input - this draws the lockscreen's `PasswordChars` Material-shape dots over the field instead of
the native glyphs (`TextArea` has no `echoMode`, unlike `TextField`, so masking is done purely by
making the real glyphs transparent), and shows an optional reveal toggle (`revealButton`, defaults
to `password`). There used to be a separate pill-shaped `ConfigInput` for this; it was removed and
folded into `ConfigTextArea` once `ConfigTextArea` became the de facto standard across the settings
pages - don't reintroduce a second single-line text-entry widget.

`GroupedList` normally separates and subtly rounds each row. Set `cohesive: true` when several
controls form one continuous semantic unit (for example, the fields and actions for a single custom
AI provider). Cohesive mode removes internal spacing and corner rounding while retaining the outer
group corners. Controls rendered inside a group should rely on the group's inset; avoid adding a
second horizontal inset that misaligns their icons or labels with neighboring rows.

**`colLayer0` vs `colLayer1`/`colLayer2`/...** - these are not interchangeable "just pick one that
looks transparent enough" tokens:
- `colLayer0`'s alpha comes from `backgroundTransparency` (gated by
  `Config.options.appearance.transparency.enable`, ~0.89 opacity by default) - use it for the
  **outermost** background of a standalone floating surface (a popup/toast/OSD that sits directly on
  a `PanelWindow { color: "transparent" }` with nothing else behind it). See `MediaControls.qml` and
  `OsdTextIndicator.qml`.
- `colLayer1` and above derive from `contentTransparency` (~0.43 default, also gated by the same
  `enable` toggle) and are meant for **cards nested inside an already-opaque parent surface** (e.g.
  a list item inside the sidebar, which itself already provides a `colLayer0` backing). Used at the
  top level of a standalone popup, this token's alpha is low enough to visibly show
  through-but-unblurred transparency without ever clearing the `ignore_alpha` threshold above.
