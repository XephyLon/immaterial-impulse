# AGENT.md

Reference for coding agents (and humans) working in this repository. This file explains what the
project is, how it's put together, and where things live. See `CONTRIBUTING.md` for how to work in
it day to day.

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
  plugins/                    Declarative + package-QML plugin renderer/validator/manager. It scans
                              bundled and user-installed manifests; PluginState.qml keeps dynamic
                              per-plugin, per-monitor layout in raw plugin-state.json.
                              bundled/ is where every desktop widget the shell ships lives -
                              there are no built-in desktop widgets (see docs/PLUGINS.md).
  widgets/                   Shared UI components: StyledText, StyledComboBox, StyledSlider,
                              StyledToolTip(+Content), RippleButton, MaterialSymbol, ResourceCard,
                              PopupToolTip, StyledPopup, GroupedList, ConfigSwitch/ConfigSpinBox/
                              ConfigSelectionArray (settings-page form controls), DockIconMotion
                              (M3E feedback-motion wrapper for dock icons), etc.
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
  Notifications.qml            org.freedesktop.Notifications server + notification history
  Notes.qml                    The note store: a JSON array in Directories.notesPath. Sole owner -
                              the bundled `notes` desktop plugin (one instance per monitor) and the
                              overlay notes editor both go through it rather than opening the file,
                              and it imports the legacy desktopnotes.txt array once
                              (Config.options.notes.importedLegacyStore) without ever writing to it
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
- **The region selector intentionally takes exclusive focus.** Dismissable panels normally close
  when `GlobalFocusGrab` is cleared, but the selector first sets
  `GlobalStates.settingsHeldForRegionSelector` so Settings can remain visible in screenshots without
  racing surface creation. Because clearing the grab also empties its dismissable list, Settings
  must re-register itself when selection ends even though its own `visible` property never changed.

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
- Desktop plugin delegates are retained for every available manifest and gated through an animated
  `FadeLoader`, rather than repeating only the enabled ids. Removing a model delegate destroys it
  immediately and makes an M3 exit transition impossible; keep disabled loaders dormant until their
  fade-and-scale exit reaches zero opacity.
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
press-squish / launch-bounce / appear-pop feedback, driven by `services/DockLaunchTracker`).
All in `modules/common/widgets/`.

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
