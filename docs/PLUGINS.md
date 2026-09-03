# Plugin packages

For the shared plugin-author component library and the independently packaged nandoroid widgets,
see [PLUGIN_DESIGN_SYSTEM.md](PLUGIN_DESIGN_SYSTEM.md).

Immaterial Impulse supports two complementary plugin formats:

- **Declarative plugins** describe a tree of approved shell components in `manifest.json`.
- **Package plugins** point entry points at QML files stored beside the manifest, enabling richer
  bar widgets, desktop widgets, popups, and settings using native shell components and tokens.

Installed packages live at `~/.config/immaterial-impulse/plugins/<plugin-id>/`. The manager scans
that directory for `manifest.json`; installed packages override bundled packages with the same id.

## Bundled packages

**There are no built-in desktop widgets.** Every desktop widget the shell ships is a bundled
plugin under `modules/common/plugins/bundled/<dir>/`, loaded through the one host path
(`PluginManager` → `PluginWidget` → `PluginNode`) and enabled from Settings → Widgets. The
hardcoded `FadeLoader` widgets that used to live in `modules/imi/background/Background.qml` are
gone; the only `FadeLoader` left there is the plugin `Repeater`'s.

| directory | id | name | capabilities |
| --- | --- | --- | --- |
| `calendar` | `calendar` | Calendar | desktop-widget |
| `clock` | `clock` | Clock | desktop-widget |
| `custom-image` | `custom-image` | Custom Image | desktop-widget |
| `discordVoice` | `discord_voice` | Discord Voice | bar-widget, overlay-widget, settings |
| `docker` | `docker_plugin` | Docker Manager | bar-widget, settings |
| `image-converter` | `image-converter` | Image Converter | desktop-widget |
| `nandoroid-currency` | `nandoroid_currency` | Currency | desktop-widget |
| `nandoroid-media` | `nandoroid_media` | Media Player | desktop-widget |
| `nandoroid-system-monitor` | `nandoroid_system_monitor` | System Monitor | desktop-widget |
| `nandoroid-weather` | `nandoroid_weather` | Weather | desktop-widget |
| `notes` | `notes` | Notes | desktop-widget |
| `user-card` | `user-card` | User Card | desktop-widget |
| `visualizer` | `visualizer` | Visualizer | desktop-widget |
| `world-clock` | `world-clock` | World Clock | desktop-widget |

`clock`, `calendar`, `world-clock`, `visualizer`, `user-card`, `custom-image` and
`image-converter` are ports of former built-ins; the old declarative `clock_plugin` was retired by
the port rather than kept alongside it. The former built-in resources, media, weather and notes
widgets were duplicates and were deleted in favour of `nandoroid_system_monitor`,
`nandoroid_media`, `nandoroid_weather` and `notes`. A dedup is only a dedup where the survivor is a
superset: the built-in resources widget swapped its third card to the battery on a laptop and
`nandoroid_system_monitor` did not, so that branch was ported into the plugin (its **Battery
instead of disk** option) rather than lost.

The `notes` dedup was the other place the survivor was not a superset: the built-in kept a list of
discrete notes, the plugin kept one plaintext scratchpad, and the dedup flattened the model. Notes
are a JSON array again, and the plugin does **not** own that file — `services/Notes.qml` does, and
the plugin (one instance per monitor) and the overlay notes editor both read and write it through
that singleton. A desktop widget that needs shared, multi-surface state should take the same shape:
a service singleton owning the file, the widget owning only its view of it. A `FileView` in the
widget is one writer per monitor.

Bundled packages are **not** auto-discovered. `PluginManager.qml` needs both a `FileView` per
package and that view's id inside `rebuildFromLoadedFiles()`; miss either half and the plugin
silently never exists. `tests/test_widget_plugin_migration.py` guards both halves. Adding a package
directory also requires a full `qs` restart — hot reload will not register it.

Existing installs carried their desktop widgets in `background.widgets.*.enable`. A one-shot
migration in `Config.qml` translates those into `plugins.enabled` (marker:
`plugins.migratedDesktopWidgets`), a second one carries the clock's own settings and position into
`PluginState` (marker: `plugins.migratedDesktopWidgetOptions`), and a third carries the world
clock's timezone list (marker: `plugins.migratedWorldClockTimezones`). The old schema keys are
deliberately still declared — deleting them would break the migration for anyone who has not run
it yet.

Each half needs its own marker: an install that has already run an earlier migration has that
marker set, and reusing it would permanently exclude exactly the installs the new half exists for.
The later halves share one pending batch, so each contributes only what its own marker still says
is outstanding, and `PluginState.drainPendingConfigOptions()` stops only once every marker it
discharges is set. A key already present for a plugin always wins over the legacy value being
migrated onto it, so a preference the user has since changed in the widget is never clobbered.

## Directory naming

A bundled package directory that any QML file imports *as a directory* -
`import "../../common/plugins/bundled/discordVoice" as Pkg` - must be named in lowerCamelCase.
Quickshell's scanner reads that directory name as a QML module name, and anything outside letters,
digits and underscore makes it log `Module path contains invalid characters for a module name` on
every scan. The import still resolves, so the only symptom is a log filling up on each reload.
`tests/lint_qml_module_dirs.py` enforces this.

The manifest `id` is independent and stays `snake_case` (`discord_voice`), as does the
`~/.config/immaterial-impulse/plugins/<plugin-id>/` install path. Packages that are only ever loaded
dynamically by path, such as the hyphenated `nandoroid-*` ports, are unaffected - keep their
upstream names.

## Manifest entry points

An entry point is either a declarative node:

```json
"desktopWidget": {
  "type": "StyledText",
  "bindings": { "text": "DateTime.time" }
}
```

or a package component:

```json
"barWidget": { "component": "DockerWidget.qml" },
"desktopWidget": { "component": "DockerDesktopWidget.qml", "blur": true }
```

Component paths must be relative, remain inside the package, and must not contain `..`. Supported
entry points are `barWidget`, `desktopWidget`, `controlCenterWidget`, `launcherProvider`, `panel`,
and `settingsUi`. Bar entries use the stable `plugin:<id>` layout identifier.

`barWidget` is drawn by both bars — the horizontal one and the vertical one share
`Config.options.bar.layouts.*`, so a widget placed on one is placed on the other. The whole
orientation API is one duck-typed property: declare `property bool vertical: false` on the entry
point's root and the host writes it (`true` in the vertical bar), as `docker`'s `DockerWidget.qml`
and `discordVoice`'s `BarWidget.qml` do. There is nothing to opt out of — a widget that declares no
`vertical` is still rendered in a vertical bar, laid out as it was written, because a widget the
user placed and then cannot find is exactly the failure this replaced.

`desktopWidget` additionally takes three optional booleans — `blur`, `locked` and `clickThrough`.
None of them is a setting: each **seeds the default** of the matching per-plugin option in
`plugin-state.json` (`blurEnabled`, `positionLocked`, `clickThrough`), so a widget can ship an
opinion the user can still overturn from Settings → Widgets. A non-boolean is rejected by
`PluginValidator.js` and the whole manifest then fails to parse. See
[Lock and click-through](#lock-and-click-through).

## Desktop widget size

Desktop-widget plugins should declare their size on the shared **component grid** with a
top-level, optional `grid` field — `"grid": { "cols": 2, "rows": 2 }` — instead of hardcoded
pixels. The host sizes the widget to `spanX(cols) x spanY(rows)` and tiles it on the cell+gap
rhythm (a 132x108 cell, 12px gap — a 2x2 tile is 276x228); omitting `grid` keeps the legacy
content-sized behaviour. See [widget-grid.md](widget-grid.md) for the model, the
`spanX`/`spanY` formulas, the span→pixel table, and authoring guidance.

Package manifests should declare `apiVersion`, `capabilities`, and permissions. Supported
permissions are `process`, `network`, `filesystem_read`, `filesystem_write`, `settings_read`, and
`settings_write`. These declarations aid review and future enforcement; QML is code, so only
install package plugins from sources you trust.

Every plugin should declare an `author` naming its creator or maintainers. The plugin catalog shows
this attribution below the description; legacy manifests without it are labeled “Unknown creator”.
Ports should also retain `sourceUrl`, license information, and upstream revision where practical.

## Discord Voice

The bundled `discord_voice` package provides a Material 3 Expressive widget in
the shell's `Super+G` overlay canvas and a clickable bar widget. It connects to Discord's local RPC
socket through the single standard-library Python bridge in
`scripts/discordVoice/`. Official Discord uses its native local RPC and requires
explicit authorization; the resulting token is stored below the XDG cache
directory with mode `0600`. Vesktop/Vencord uses the bundled
`vencord-companion` user plugin because arRPC does not implement the voice RPC
scopes. Its installation instructions are in that companion directory.

The bridge is shared by all views and uses capped exponential restart backoff.
Do not instantiate it from widget components or replace the native bar route
with nested loaders. The bar popup is click-only and closes through
`HyprlandFocusGrab`.

The companion speaks to the bridge over a Unix socket at
`$XDG_RUNTIME_DIR/end4-discord-voice-vencord.sock`, bound under a restrictive
umask so it is never briefly readable by other users. There is no
shared-directory fallback: without `XDG_RUNTIME_DIR` the companion channel
disables itself rather than falling back to a world-writable path. The bridge
treats that socket as untrusted input — a malformed or oversized frame is
skipped rather than tearing down the session, and a companion that stops
reading is dropped after `COMPANION_WRITE_TIMEOUT` so it cannot stall the
bridge's stdin loop.

A companion fault emits `companion_error`, not `error`. Discord's own RPC
backend stays usable, so the UI must show the reason without offering an
authorization button the user cannot act on.

Manifest options support `boolean`, `choice`, `shape`, `color`, `number`, and `text`. Text options use
the shell's native `ConfigTextArea`; `placeholder`, `maxLength`, and `uppercase` may be supplied for
short values such as currency codes.

`shape` takes the same `choices` array as `choice` but renders each entry as the Material shape it
names rather than as a text chip, via `ConfigSelectionShapeArray`. Values must be `MaterialShape.Shape`
enum names (`Cookie4Sided`, `Heart`, …); an unrecognised name falls back to `Cookie4Sided`. Use it
whenever the value *is* a shape — a 31-entry name-chip row is unreadable even wrapped.

Options that belong together take a `"group": "<heading>"` and, on any of them, a `"groupIcon"`.
Consecutive options with the same group render under one header - a hairline, then the icon and the
name - shown only while one of its rows is, so the heading carries the shared word and the labels do
not ("Cookie clock" over `Sides`, `Hour marks`, `Dial style`, rather than eleven labels each starting
"Cookie:"). Inside a group the rows pack: consecutive booleans two to a line, everything else a full
row; a choice row keeps its label beside its chips and stacks them beneath only when they cannot fit.
Give every `choice` an `icon`: a choice whose options all carry one renders DENSE - icon-only chips
that name themselves on hover, with the current option's name beside the row's label - which is what
lets four or five options sit on one line with the label. One option without an icon and the whole
row falls back to text chips. Keep a group's options together in the
manifest: the grouping is by run, and the same name twice apart is two headers. Order booleans next
to each other if you want them paired.

An option can be shown only while another option has a given value. `"visibleWhen"` takes a
rule — `{ "key": "style", "in": ["cookie"] }`, `{ "key": "quoteEnable", "equals": true }`, a bare
`{ "key": "flag" }` for truthiness, or `{ "anyOf": [...] }` / `{ "allOf": [...] }` over those —
read against the plugin's current values with the manifest's own defaults filled in, so a rule
against a default the user never changed still reads what the widget is using. A rule the evaluator
cannot read (no `key`) shows the row: a wrongly hidden row is a setting the user cannot reach and
nothing logs. The older `"enabledWhen": "<booleanKey>"` is the same thing for one boolean and, despite
its name, hides rather than greys — both fields go through `option_visibility.js`, and when both are
present both must pass. The clock is the worked example: every `digital*` / `cookie*` / `pixel*` row
is gated on its style being chosen for the desktop **or** the lock screen, since the two can differ
(`tests/test_clock_options_contract.py` holds that; `tests/tst_option_visibility.qml` holds the
evaluator).

`color` renders a row of palette swatches (`ColorSelectionArray`) instead of chips. Its `choices` are
`Appearance.colors` role names without the `col` prefix (`primary`, `secondaryContainer`, `layer0`, …).
The empty string is a legal choice and draws an "automatic" slot rather than a swatch — use it when
the widget has a sensible colour of its own and the option is an override, so the way back to that
default is one more swatch rather than a second switch sitting beside the row saying the same thing.

## Multi-file packages

A package whose `Widget.qml` is split across several files needs a **`qmldir`** in the directory
naming every component:

```
module ClockDesktopWidget
Widget 1.0 Widget.qml
ClockText 1.0 ClockText.qml
```

That file is what makes the siblings types. No `import` is needed for same-directory siblings once
it exists; a **subdirectory** is its own module and needs its own `qmldir` plus an explicit
`import "subdir"` in the parent. Subdirectory names must be legal QML module segments, so no
hyphens (`tests/lint_qml_module_dirs.py` guards this).

This is not the usual Qt behaviour and it is easy to lose an afternoon to. A package is loaded by
absolute path through Quickshell's `qs:` URL scheme, under which Qt adds no usable implicit import
for the containing directory; and `bundled/` is not scanned into the `qs.modules.*` tree either, so
`import qs.modules.common.plugins.bundled.<pkg>` does not resolve. Without the `qmldir` every
sibling reference fails with `X is not a type` — but only the *first* one per file is reported, so
it reads as one broken component rather than the whole package failing. The bundled `docker` and
`clock` packages are the two multi-file examples.

## Host context and host opt-ins

A component-backed `Widget.qml` is a grandchild of the `AbstractBackgroundWidget` that hosts it, so
anything that has to influence the host's own geometry, visibility or wallpaper sampling has to be
declared as a property and picked up by `PluginNode`. Every one of these is optional; a widget that
declares none of them behaves exactly as it does today.

Handed **down** to the widget (the host writes them):

| property | meaning |
|---|---|
| `screenName` | name of the monitor this instance lives on (see below) |
| `hostX`, `hostY` | the widget's position on that monitor |
| `hostColText` | the host's wallpaper-adaptive text colour (see `needsColText`) |
| `wallpaperSafetyTriggered` | the background is suppressing the wallpaper |
| `hostInteractionLocked` | the host's resolved lock (see below) — gate any resize/toggle grip on this |

Read **back** off the widget (the host obeys them):

| property | effect |
|---|---|
| `visibleWhenLocked: true` | stay visible while the screen is locked regardless of `lock.showWidgets` |
| `forceCenter: true` | centre on the monitor for as long as it is set, without disturbing the persisted position |
| `needsColText: true` | run the least-busy-region pass so `hostColText` tracks the wallpaper under the widget |

These exist for widgets that draw straight onto the wallpaper with no panel of their own. The
bundled Clock uses all of them: it is the lock screen's only clock, it has always centred itself
there, and its digital style is bare text that has to stay readable over whatever it sits on.

## Lock and click-through

Every desktop-widget plugin gets two host toggles of its own next to `Blur background`, both
persisted per plugin in `plugin-state.json`:

| option | manifest seed | effect |
|---|---|---|
| `positionLocked` | `desktopWidget.locked` | this widget alone stops being draggable |
| `clickThrough` | `desktopWidget.clickThrough` | this widget stops receiving pointer input at all |

They are two capabilities, not one. *Locked but clickable* is a real state — a pinned widget whose
controls still work — so the lock does not imply click-through. The converse does hold: dragging
**is** pointer input, so a click-through widget is always locked as well, and the host folds
`clickThrough` into its lock the same way it folds in the global switch.

`background.widgetsLocked` ("Lock widget positions", the desktop Widgets submenu) still exists and
**ORs** with the per-widget lock. It can only ever lock further; flipping the global switch off
never unlocks a widget the user deliberately pinned.

Click-through is implemented as `enabled: false`, not as a Wayland input region. Every desktop
widget shares one layer-shell surface (`Background.qml`), so masking that surface would blind all of
them at once. The click continues to whatever is behind the widget *inside the same surface* — which
on the background is the desktop's own right-click area. Turning click-through off restores
dragging, which is the way to reposition a widget that ships with it on.

It takes **two** gates on `AbstractBackgroundWidget`, because the same property name means two
different things there and neither covers the other:

| gate | what it disarms |
|---|---|
| `enabled: !clickThrough` on the host | the host's own `MouseArea`: the drag, and the right-click that toggles the global lock |
| `enabled: !clickThrough` on the `contentItem` wrapper | everything the widget draws for itself |

`AbstractBackgroundWidget` is a `MouseArea` (via `AbstractWidget`), and `MouseArea.enabled` is
`MouseArea`'s own property shadowing `Item.enabled` — setting it false stops that one area handling
events and leaves every item under it live. A plain `Item` with `enabled: false` *does* disable its
whole subtree, so the base class declares
`default property alias contentData: contentItem.data` and puts the second gate on that wrapper.
Everything a subclass declares — `PluginWidget`'s `PluginNode` and its blur surfaces, and through
`PluginNode` every loaded `Widget.qml` — lands inside it and goes inert together.

The wrapper is `anchors.fill: parent` and takes no part in sizing: `PluginWidget` still derives its
own width and height from `PluginNode`'s implicit size, and `PluginNode`'s `Loader` stays unanchored
(anchoring it is a binding loop).

The gate is `clickThrough`, not the resolved `interactionLocked`: pinning a widget must not deaden
its controls, which is the whole reason the lock and click-through are two switches. A widget that
wants a *particular* control dead whenever it is pinned reads `hostInteractionLocked` instead — see
below.

Both halves are driven with real mouse events in `WidgetInteractionRuntimeTest.qml` (run by
`tests/test_widget_interaction_runtime.py`), including a real bundled widget: the notes widget's
per-note delete button, under click-through and then again with it off.

### Grips and other in-widget interaction

`PluginNode` hands a component-backed `Widget.qml` the host's **resolved** lock as
`hostInteractionLocked` — `positionLocked || clickThrough || background.widgetsLocked`, the same
value that decides whether the widget is draggable. Anything the widget draws that changes its own
geometry (the Calendar's and Custom Image's resize corners, the World Clock's size toggle) gates on
it:

```qml
property bool hostInteractionLocked: false   // no host, e.g. a bare `qs -p` probe

Rectangle {
    id: resizeHandle
    visible: opacity > 0 && !root.hostInteractionLocked
    MouseArea { anchors.fill: parent /* ... */ }
}
```

`visible: false` is what makes the grip *dead* rather than merely invisible — Qt does not route
mouse events into an invisible item, so hiding the rectangle disarms the `MouseArea` inside it.

The resolved value is deliberately what is forwarded, not the three terms separately: a grip should
be inert whenever the widget is pinned, and it has no business caring which lock is holding it. A
widget that genuinely needs to tell them apart can read `Config.options.background.widgetsLocked`
itself and subtract it — but nothing does, and doing so would mean a grip that outlives its own
widget's lock, which is the bug this exists to prevent.

`clickThrough` sits in that OR belt-and-braces: the `contentItem` wrapper above already makes the
whole widget inert under click-through, so a grip is dead twice over there. It stays because the
grip must also be dead when the widget is merely *pinned* — which the wrapper deliberately is not.

The bundled Visualizer is the case this exists for: it is full-bleed (see below), so it covers a
whole monitor's width, has nothing on it to click, and would otherwise both swallow the desktop
menu and be draggable off-screen with no bounds. Its manifest ships `"clickThrough": true`.

## Drop Shelf and Screenshot Result

Both were bundled `panel` plugins and are now core shell modules
(`modules/imi/dropShelf/`, `modules/imi/screenshotResult/`), loaded by the
panel family and configured through the shell config (`dropShelf.*`,
`screenshotResult.*`) rather than plugin options. `PluginPanelHost` remains
for third-party `panel`-capability packages.

## Desktop blur surfaces

Every desktop plugin receives a `Blur background` setting. When enabled, a `Background opacity`
slider controls the tint above the sampled wallpaper; both values are persisted per plugin. A
package component can optionally expose a `blurRegions` property when its visual consists of
separate cards rather than one continuous surface:

```qml
readonly property var blurRegions: [
    { x: firstCard.x, y: firstCard.y,
      width: firstCard.width, height: firstCard.height, radius: firstCard.radius },
    { x: secondCard.x, y: secondCard.y,
      width: secondCard.width, height: secondCard.height, radius: secondCard.radius }
]
```

Coordinates are local to the package component. The host uses all regions as one mask over a
single blurred wallpaper texture, keeping gaps transparent without multiplying blur effects. An
absent property retains the full-widget rounded-rectangle fallback; an explicit empty list declares
that the component has no background surface and disables host blur. Components that own their
background tint can expose `managesBlurTint: true` and apply the persisted opacity to that internal
fill, preventing the host from adding a second generic scrim. The nandoroid System Monitor,
Currency, Media, and Weather widgets are reference implementations.

## Knowing which monitor you are on

A package component may declare `property string screenName: ""`. When it does, the host
(`PluginWidget` → `PluginNode`) binds it to the name of the monitor that instance of the widget
lives on. Resolve the `ShellScreen` from it with the same lookup the rest of the shell uses:

```qml
readonly property var widgetScreen: Quickshell.screens.find(s => s.name === root.screenName) ?? null
```

This is how a full-bleed widget sizes itself: the bundled Visualizer omits `grid` from its manifest
(the grid caps at 12 columns / 1716px, a third of a 5120px display) and binds
`implicitWidth` to `widgetScreen.width`, so the host's content sizing gives it the whole monitor.
Full-bleed still does not mean edge-anchored: the host restores a persisted free position, and a
full-bleed widget that is neither locked nor click-through is dragged like any other, with no
bounds. The Visualizer opts out of that with `clickThrough` (see
[Lock and click-through](#lock-and-click-through)); an anchoring concept that would decide *where*
such a widget lands does not exist yet. See [widget-grid.md](widget-grid.md).

## Remote installation

The Widgets settings page accepts an HTTPS manifest URL. This is the power-user path; the curated
path is the in-shell plugin store (Settings → Widgets → Browse widgets), which feeds
registry-vetted manifest URLs into this same installer — see
[PLUGIN_STORE.md](PLUGIN_STORE.md). A remotely installable manifest adds:

```json
"package": {
  "baseUrl": "https://example.org/example/",
  "files": [
    { "path": "Widget.qml", "sha256": "<optional sha256>" },
    "assets/icon.svg"
  ]
}
```

Files are downloaded into a staging directory, checked for path traversal and optional SHA-256
integrity, then atomically installed. Existing packages are not overwritten implicitly: the
installer refuses when the target directory exists, unless invoked with `--upgrade`, which requires
the installed `manifest.json` to parse and carry the same plugin id, stages and verifies the new
version completely, then swaps it over the old one atomically (the old version is restored if the
swap fails).

After every successful install or upgrade the installer writes a provenance sidecar,
`<plugin dir>/.store.json`, recording the manifest URL, installed version, and timestamp. Package
files can never claim that name (dot-prefixed paths are rejected), so a package cannot forge or
clobber its own provenance. The shell uses it to tell store-installed plugins from manually
URL-installed ones and to offer updates — see [PLUGIN_STORE.md](PLUGIN_STORE.md).

An installed package is QML executed inside the shell process, so the transport is enforced:

* the manifest URL, `baseUrl`, and every per-file `url` must use `https://`, and must all resolve
  to the same host and port — a manifest cannot pull code from a third-party origin;
* a package may declare at most 64 files, each at most 8 MiB, 32 MiB in total, so a hostile or
  broken host cannot exhaust memory during install;
* package paths may not be absolute, contain `..`, begin with `.`, or contain `:`, which also
  rejects the string form being abused to carry an absolute URL.

Supplying `sha256` per file is still recommended: it is the only check that survives the file host
and the manifest host being different systems.

## Removal

Each installed package has a delete button in its Plugins-page row, shown only for installed
packages (bundled plugins ship with the shell) and enabled only while the plugin is disabled, so a
running plugin is never pulled out from under itself. Deleting prompts for confirmation, then removes
`~/.config/immaterial-impulse/plugins/<plugin-id>/` through `scripts/plugins/uninstall_plugin.py`. That
script re-validates the id and refuses to remove anything that resolves outside the install root; a
symlink planted at the plugin path is unlinked rather than followed. Removal is idempotent - a plugin
whose files are already gone (a listed-but-dirless entry left by an out-of-band deletion or a stale
scan) still counts as removed, so such a row can always be cleared rather than being trapped behind an
error. The id is also dropped from `plugins.enabled` so a stale entry cannot re-enable a package that
no longer exists.

## Overlay surfaces and fullscreen windows

A plugin that maps a wlr-layer-shell surface on the **Overlay** layer — itself, or through a
process it spawns — blocks the compositor's fullscreen fast path for as long as that surface exists,
at any size. Hyprland names it in `hyprctl monitors`: `solitaryBlockedBy: other overlays`. With
the fast path blocked the compositor composites every frame; with it open it hands the fullscreen
window the output and does nothing. On the maintainer's machine the bundled Activate Linux
watermark — a 340×120 Overlay surface from `/usr/bin/activate-linux` — was the last thing between
a fullscreen game and that path, worth ~8 fps and all of the compositor's remaining GPU time.

If your plugin needs an Overlay surface, stand it down while a fullscreen window is up. Read the
fact off `HyprlandData` — `hasfullscreen` on each monitor's active workspace, the same field the
shell's bar and dock gate on — not by walking `Hyprland.workspaces[..].toplevels` in a binding,
whose nested `.values` reads do not re-evaluate when a workspace changes underneath them. The
Activate Linux plugin's `ActivateLinuxHost.qml` is the reference: `fullscreenSomewhere` folds into
`desiredCommand()`, and the process is stopped and relaunched through the same debounced `apply()`
every other option change goes through.

## Process lifecycle safety

Never bind a streaming process such as `docker events`, `nmcli monitor`, or `journalctl -f`
directly to a persistent boolean unless it has explicit exit backoff and a retry ceiling. An
unsupported command that exits instantly can otherwise become a tight respawn loop and starve the
shell session.

Prefer bounded polling with a `Timer` and an imperatively started one-shot `Process`. Bundled
plugins are checked by `tests/lint_plugin_processes.py`; an intentionally restart-safe stream must
contain `process-lifecycle: restart-safe` in its `Process` block and document its backoff.

The bundled Docker manager is intentionally bar-only. Its desktop entry point was removed after
the background-host path repeatedly drove Quickshell into multi-gigabyte anonymous-memory growth.
Do not restore automatic desktop loading until that interaction has a bounded-memory reproducer.

Package bar components are loaded through a single sizing boundary in `PluginBarWidget.qml`.
Do not route them through `PluginNode` or add another nested loader: competing implicit and
layout-assigned geometry previously collapsed the visible widget to a one-pixel line while driving
Quickshell above 5 GB RSS in roughly two minutes. Preserve the corresponding lint check and use a
guarded live run with RSS sampling when changing package-host geometry.

Do not make the package loader fill that implicit-size host. Doing so made the Docker content
visible but restored the allocation loop (3.8 GB RSS before termination). Bundled native plugins
such as Docker should use a direct bar adapter, as `DockerPlugin.qml` does, while installed packages
remain behind the non-filling generic host.

Docker refreshes once at service startup, when its popup opens, and after container actions. Do not
restore an automatic polling timer: repeated refreshes reproduced roughly 400 MB of RSS growth per
cycle and eventually froze the shell. The process-lifecycle lint guards this restriction.

The Docker Manager popup is click-only. Keep `hoverEnabled: false`; constructing the full
interactive container and Compose delegate tree from pointer entry reproduced another complete
Quickshell freeze. `hoverTarget` is retained only as the `StyledPopup` positioning anchor. Opening
the manager and its on-demand refresh belong to the explicit click path. The entire popup stays
behind a click-driven `Loader` and is destroyed when closed. Do not animate layout-derived
`implicitHeight` in its cards; use bounded opacity, scale, color, and icon animations to avoid
geometry allocation loops.

The native Docker bar entry follows WeatherBar's content-driven implicit sizing. Do not add forced
`width`, `height`, or host `Layout.preferredWidth` bindings: those competing geometry owners caused
the one-pixel rendering failure and allocation runaway. `DockerRuntimeTest.qml` exercises idle,
open, close, and repeated-open cycles; run it through a transient user service with `MemoryMax` and
`MemorySwapMax=0` before changing Docker geometry, popup ownership, or lifecycle behavior.

The native entry is enabled in `BarContent` after both isolated and complete bar-host harnesses
passed the hard memory ceiling. Keep `DockerBarHostRuntimeTest.qml` representative of the production
layout, and never use an uncapped live shell as the first memory test after changing this path.
Click-away dismissal uses a bounded `HyprlandFocusGrab`: resolve the popup window imperatively,
assign the window list once, and clear both `active` and `windows` when closing. Do not bind the grab's
window list directly to `popupLoader.item?.item`; that reactive object graph drove the genuine bar
host into rapid unbounded growth. The integration test defaults to a 1.5 GB ceiling because the
complete no-Docker bar can transiently exceed 512 MB on this configuration.

Avoid editing many live-loaded QML files in rapid succession. Quickshell reloads the configuration
for each change, and moving service/module files during those reloads can impose severe session
load. Stop Quickshell or develop in a worktree, run headless tests, then do one controlled live load.

On HDR/10-bit outputs, verify `grim` independently before debugging the region selector. A compositor
screencopy regression can return a successful but fully transparent or black frame even when
`misc:screencopy_force_8b` is enabled. The selector cannot recover pixels the compositor did not
provide; changing monitor color mode during capture is intentionally not automated because it can
blank or flicker the display.
