# Research: making all widgets headless by design

Feasibility study, 2026-08-07. No code changes; this document records what "headless by design"
would mean for this shell, how much of it already exists, what blocks the rest, and a phased route
if the direction is adopted. Paths are relative to the theme root `dots/.config/quickshell/imi/`
unless written repo-relative.

## Verdict

**Plausible, and closer than it looks — this is a completion of an existing direction, not a
rewrite.** The shell is already ~70% headless by accident of good architecture: every service
singleton is visual-free, the widget base classes carry no window types, and the repo already
instantiates real widget trees with no layer surface in its own test harnesses. The remaining work
is bounded and enumerable: roughly 8 files with logic fused to their visual roots, 7 single-file
panels where surface/service/state are fused, two missing mock modules, and one upstream ceiling
(Quickshell itself cannot run truly windowless). The recommended posture is incremental — adopt a
per-widget contract and migrate opportunistically, the way the widgets-as-plugins port
(`docs/proposals/widgets-as-plugins.md`, PR #11) was done — not a big-bang framework.

## What "headless" means here

Two joined senses, and the design should serve both:

1. **Logic/presentation separation.** A widget's non-visual logic (state machines, parsers,
   process spawning, persistence) lives in a `pragma Singleton` service or a `.pragma library`
   JS module; the visual component owns only view state and bindings.
2. **Instantiable without a real shell.** The visual component itself is a plain `Item` (or
   `MouseArea`) whose host context is injected through duck-typed properties, so it can be built
   under the headless-weston harnesses — or, where the Qt-version blocker below is lifted, under
   plain `qmltestrunner` — without `Background.qml`, a `PanelWindow`, or a live Hyprland session.

The payoff targets three documented pain points:

- **The green-suite blind spot.** "The QML suite instantiates pure-logic singletons and never
  builds these widgets, so a widget that fails to compile leaves the suite fully green"
  (`AGENT.md` → Runtime model). `DesignSystemCompile.qml` narrows this to ~139 files
  (design system, bundled `Widget.qml`s, settings pages) but compiles only — it never
  instantiates, and nothing under `modules/imi/bar/`, `sidebarRight/` etc. is in its sweep.
- **The live-verification hazard.** Rapid edits against the live shell risk reload storms and
  session starvation (`AGENT.md` → Runtime model); the more that can be proved headlessly first,
  the smaller the one controlled live load has to carry.
- **Duplication regressions.** The resources dedup lost the laptop Battery card; the notes dedup
  flattened the data model (`docs/proposals/widgets-as-plugins.md` → Known gaps). Both are costs
  of the same logic living twice because it could not be shared across surfaces.

## What already exists (evidence)

### The services layer is already the headless core

All 78 `services/*.qml` files are visual-free — a sweep for root-level visual types returns zero
hits. 46 of them own `Process` spawning, versus 2 of 39 bundled-plugin QML files. The offscreen
`qmltestrunner` suite (32 `tst_*.qml`, `QT_QPA_PLATFORM=offscreen`) already proves this layer:
`ResourceUsage.parseMeminfo()`, `Battery` against a mock UPower, `Notes`, the PhoneConnect parser
contract. `services/Notes.qml` is the blessed shape, named in `docs/PLUGINS.md`: "a service
singleton owning the file, the widget owning only its view of it."

### The widget base classes need no surface

- `modules/common/widgets/widgetCanvas/AbstractWidget.qml` is a plain `MouseArea`. It finds its
  canvas by a duck-typed parent walk (`isWidgetCanvas === true`) and probes for every canvas
  method before calling it.
- `AbstractBackgroundWidget.qml` adds six **scalar** required geometry properties
  (`screenWidth`, `wallpaperScale`, …) — numbers, not screen objects, trivially injectable.
- `PluginNode.qml` is a plain `Item`; its entire host bridge (down: `screenName`, `hostX`,
  `hostColText`, `hostInteractionLocked`, …; up: `visibleWhenLocked`, `blurRegions`,
  `managesBlurTint`, …) is duck-typed on property existence, so a headless host satisfies it by
  declaring the same names.
- The surface lives entirely above them: `Background.qml`'s `Variants → PanelWindow →
  WidgetCanvas → Repeater → PluginWidget`.
- Aggregate surface coupling across all 14 bundled plugins is five grep hits: two
  `HyprlandFocusGrab` lines in `docker/DockerWidget.qml` and two null-guarded
  `Quickshell.screens.find` lookups (`clock`, `visualizer`).

### The repo already instantiates real widgets headlessly

- `WidgetInteractionRuntimeTest.qml` builds four real `PluginWidget`s on a real `WidgetCanvas`
  inside a `FloatingWindow`, from synthetic inline manifests — no `Background.qml`, no
  `PluginManager` — under self-spawned headless weston
  (`weston --backend=headless --renderer=pixman`). `WidgetGroupDragRuntimeTest.qml` and
  `NotesSurfacesRuntimeTest.qml` do the same.
- `DockerBarHostRuntimeTest.qml` hosts the **entire real `BarContent`** in a `FloatingWindow` —
  the strongest existing proof that the bar's content tree needs no layer surface. (Manually
  gated behind `RUN_DOCKER_RUNTIME_MEMORY_TEST=1`.)
- `QuickTogglesLayoutRuntimeTest.qml` instantiates the real `AndroidQuickPanel` inside a bare
  `Item` — no window at all — with 25+ toggles resolving against `Network`/`Bluetooth`/`Audio`
  singletons and no live daemons.
- `ConfigControlWriteBackRuntimeTest.qml` builds the real `SidebarsPanelsConfig` settings page
  under weston and reads `config.json` back off disk.

### Multi-surface reuse already has three working precedents

- **discordVoice** — one `Widget.qml` renders in the overlay (`DiscordVoiceOverlay.qml` is 30
  lines of chrome around `contentItem: DiscordPackage.Widget {}`) and a sibling `BarWidget.qml`
  in the bar; all three views read one `services/DiscordVoice.qml`.
- **volumeMixer** — `overlay/volumeMixer/VolumeMixer.qml` (80 lines) instantiates the sidebar's
  `VolumeDialogContent` inside overlay chrome. This is the pattern to generalise.
- **The bar widget set is already dual-host**: `VerticalBarContent.qml` resolves the same 21
  widget files by path (`Qt.resolvedUrl("../bar/" + Name + ".qml")`) that `BarContent.qml` does.
  43 of the 44 files under `bar/` are ordinary `Item`s; only `Bar.qml` owns a surface.
- `StyledOverlayWidget`'s `contentItem` slot contract (content reparented into host chrome) is
  itself a headless-core/host split, independently arrived at.

## What is not headless today

### Logic fused to visual roots — the extraction backlog (bounded: ~8-10 files)

| File | Trapped logic |
|---|---|
| `modules/imi/bar/NetworkSpeed.qml` | `/proc/net/dev` parser, rate state, `FileView` + poll `Timer` — no service exists |
| `modules/imi/bar/UpdatesCount.qml` | spawns the upgrade terminal, then a 5s post-upgrade outcome state machine + `notify-send` |
| `modules/imi/bar/Media.qml` | album-art `curl` download inside the bar item |
| `sidebarRight/quickToggles/classicStyle/CloudflareWarp.qml` | three `Process`es + `warp-cli` output parsing; the whole WARP integration (same pattern, smaller: `GameMode.qml`) |
| `bundled/calendar/Widget.qml` | month-matrix/week computation (617 lines, no service) |
| `bundled/image-converter/Widget.qml` | batch queue, two `Process`es, 5-state machine, all in the widget root |
| `bundled/clock/CookieClock.qml` | `FileView` + AI styling-preset logic inside the clock face |
| `overlay/notes/NotesContent.qml` | 430 lines re-implementing editing behaviour the 307-line notes plugin implements differently over the same `Notes` service |

The blessed extraction patterns already exist in-tree: plugin-local singletons
(`bundled/docker/DockerService.qml`, registered in the package `qmldir`) and `.pragma library`
modules with direct unit tests (`ThirdCard.js`, `ParticipantVisualState.js`, `CurrencyMath.js`).

### Panels where surface, services, and state are fused (7 files)

`NotificationPopup.qml` is the sharpest: `PanelWindow` visibility bound to
`Notifications.popupList.length && !GlobalStates.screenLocked` and `screen` bound to
`Hyprland.focusedMonitor` — service, global state, compositor, and surface in two lines.
`MediaControls.qml` and `OnScreenDisplay.qml` are the same shape; `Dock.qml`, `VerticalBar.qml`,
and the two sidebars are partially split already (content components exist; the window files
still carry some logic). The fix shape is the one the bar already has: a surface-owning
`X.qml` + a surface-free `XContent.qml`, with the OSD's data-driven indicator dispatch
(`OnScreenDisplay.qml`'s URL array; the 9 `indicators/` files use no surfaces and no
`GlobalStates`) showing the split is half-done there.

### The overlay has no plugin host

`overlay-widget` is advertised in `PluginManager.surfaceCapabilities` but is presentation
metadata only — there is no `overlay` entry point and no `PluginOverlayHost`. The overlay is a
closed registry of three parallel hardcoded lists (`OverlayContext.builtInWidgets`, the
`DelegateChooser`'s eight `DelegateChoice`s, the `Persistent.states.overlay.*` schema), with
discordVoice special-cased by relative-path import inside `OverlayContext.qml`. A
`PluginOverlayHost` is the single highest-leverage change for multi-surface reuse — it is what
makes "one headless core, N surfaces" expressible in a manifest rather than by editing three
lists.

## Blockers and ceilings

1. **Quickshell cannot run windowless.** `QT_QPA_PLATFORM=offscreen` fails with
   `No PanelWindow backend loaded` once the services tree loads
   (`docs/superpowers/plans/2026-08-02-widgets-as-plugins.md`, gap 11). "Headless" in this repo
   therefore means **headless weston**, which the harnesses already stand up. This is an
   upstream ceiling, not an architectural one, and it is acceptable: weston bring-up is ~1s,
   and the harnesses cap runs at 180-240s.
2. **Weston has no wlr-layer-shell** (`docs/tests-README.md`), so nothing about a real
   `PanelWindow`'s stacking/masking/exclusion can ever be proved headlessly. Headless-by-design
   moves the *content* under test; the thin surface files remain live-load territory. This is a
   scope boundary to state, not a reason not to do it.
3. **`StyledText` pins the qmltestrunner ceiling.** `StyledText.qml`'s `font.variableAxes`
   needs Qt 6.7 while the suite runs distribution Qt (`tests/test_shared_widget_contracts.py`),
   so **no text-rendering widget can be built under `qmltestrunner` at all** — which is why
   `tests/imports/.../widgets/qmldir` exposes 1 of 179 shared widgets. Options: gate the
   binding on a Qt-version check, or accept that widget instantiation lives in the weston layer
   and `qmltestrunner` keeps the pure-logic layer. The second is the cheaper and honest choice
   until the distro Qt catches up.
4. **`Quickshell.Hyprland` (55 imports) and `Quickshell.Wayland` (48 imports) have no mocks.**
   The mock mechanism is already module-granular (`tests/mocks/Quickshell/qmldir` shadows the
   real C++ plugin wholesale), so nothing prevents adding them — but the surface is large
   (`Hyprland` singleton, `GlobalShortcut`, `WlrLayershell` attached types, `PanelWindow`,
   `Variants`, `ShellScreen`, …). The cheaper lever: `services/WM.qml` is already a compositor
   facade, but only ~5 call sites use it; widening its adoption shrinks the mock surface to one
   file. Direct `Quickshell.Hyprland` imports inside *content* files (`bar/SysTray.qml`,
   `bar/HyprlandXkbIndicator.qml`, the sidebar dialogs) are the anti-pattern to migrate.
5. **One host implementation cannot be assumed.** `PluginBarWidget.qml`'s header records that
   routing bar packages through `PluginNode` caused perpetual relayout and runaway memory; the
   Docker sections of `docs/PLUGINS.md` document repeated multi-GB RSS incidents around bar
   hosting. A headless-core contract must stay host-agnostic (properties in, properties out) and
   each surface keeps its own thin host — do not unify hosts, unify the *content contract*. Any
   change near bar hosting keeps the existing memory harnesses and lints.
6. **Discovery is hardcoded** (a `FileView` per bundled plugin + an id in
   `rebuildFromLoadedFiles()`, guarded by `tests/test_widget_plugin_migration.py`) — a
   registration burden every extracted core inherits, worth knowing, not worth fixing as part
   of this.

## Phased route, if adopted

Each phase is independently valuable; stopping after any of them leaves the tree better.

- **Phase 1 — extract the trapped logic** (~8-10 files, the table above). Service singletons or
  `.pragma library` per the Notes/Docker/ThirdCard patterns, each with the unit test the logic
  never had. No visual change, no new mechanism, no AGENT.md mechanism update needed beyond
  directory-map lines. This is where most of the testability payoff lives, at the least risk.
- **Phase 2 — de-fuse the seven fused panels** into surface + content pairs, in the bar's
  existing shape. Start with `NotificationPopup.qml` (1 file, sharpest fusion) and the OSD
  (already half-split). Each split makes that panel's content reachable by the weston harness
  and `DesignSystemCompile`-style sweeps.
- **Phase 3 — widen the `WM` facade** so content files stop importing `Quickshell.Hyprland`
  directly, then (optionally) add `Quickshell.Hyprland`/`Wayland` mock modules to
  `tests/mocks/`, which unlocks bar/sidebar content under plain `qmltestrunner` — modulo the
  `StyledText` Qt 6.7 ceiling, which stays until the suite's Qt catches up.
- **Phase 4 — `PluginOverlayHost` + registry-driven overlay**, replacing the three hardcoded
  lists, making `overlay-widget` a real entry point, and letting the notes/resources
  duplications collapse the way volumeMixer's already did. Largest phase, and the only one that
  adds mechanism; it should get its own proposal if reached.

A "headless by design" rule for *new* widgets (logic in a service or library; content component
is a surface-free `Item` with injected host context; host files stay thin) can be adopted in
CONTRIBUTING.md from Phase 1 onward — the migration of existing widgets then proceeds
opportunistically, per widget, the way the plugin ports did.

## Costs and risks

- **Live-reload hazard during migration.** Phases 1-2 touch many live-loaded files; the
  documented reload-storm discipline applies (stop the shell or use a worktree, validate
  headlessly, one controlled live load).
- **Extraction can change behaviour.** Moving a parser out of a `MouseArea` looks mechanical,
  but this repo's history (the `Audio.ready` gate, the `hyprctl eval` verification trap) says
  every extraction needs the drive-a-real-state-change verification loop, not just green tests.
- **Two-list drift.** Every new contract (a content component's expected properties, a host's
  provided ones) is a validator/renderer-style pair that can drift; each needs its pinning
  test the way `lint_blur_region_pairing.py` pins its pair.
- **What this does not buy:** layer-shell behaviour, blur thresholds, input routing across
  surfaces, and anything else weston cannot express stay live-load-only. Headless-by-design
  shrinks that territory; it cannot empty it.
