# Plugin packages

For the shared plugin-author component library and the independently packaged nandoroid widgets,
see [PLUGIN_DESIGN_SYSTEM.md](PLUGIN_DESIGN_SYSTEM.md).

end4-pC supports two complementary plugin formats:

- **Declarative plugins** describe a tree of approved shell components in `manifest.json`.
- **Package plugins** point entry points at QML files stored beside the manifest, enabling richer
  bar widgets, desktop widgets, popups, and settings using native shell components and tokens.

Installed packages live at `~/.config/illogical-impulse/plugins/<plugin-id>/`. The manager scans
that directory for `manifest.json`; installed packages override bundled packages with the same id.

## Directory naming

A bundled package directory that any QML file imports *as a directory* -
`import "../../common/plugins/bundled/discordVoice" as Pkg` - must be named in lowerCamelCase.
Quickshell's scanner reads that directory name as a QML module name, and anything outside letters,
digits and underscore makes it log `Module path contains invalid characters for a module name` on
every scan. The import still resolves, so the only symptom is a log filling up on each reload.
`tests/lint_qml_module_dirs.py` enforces this.

The manifest `id` is independent and stays `snake_case` (`discord_voice`), as does the
`~/.config/illogical-impulse/plugins/<plugin-id>/` install path. Packages that are only ever loaded
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
`scripts/discordVoice/`. Initial use requires explicit authorization in
Discord; the resulting token is stored below the XDG cache directory with mode
`0600`.

The bridge is shared by all views and uses capped exponential restart backoff.
Do not instantiate it from widget components or replace the native bar route
with nested loaders. The bar popup is click-only and closes through
`HyprlandFocusGrab`.

Manifest options support `boolean`, `choice`, `number`, and `text`. Text options use the shell's
native `ConfigTextArea`; `placeholder`, `maxLength`, and `uppercase` may be supplied for short values
such as currency codes.

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

## Remote installation

The Plugins settings page accepts an HTTPS manifest URL. A remotely installable manifest adds:

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
integrity, then atomically installed. Existing packages are not overwritten implicitly.

An installed package is QML executed inside the shell process, so the transport is enforced:

* the manifest URL, `baseUrl`, and every per-file `url` must use `https://`, and must all resolve
  to the same host and port — a manifest cannot pull code from a third-party origin;
* a package may declare at most 64 files, each at most 8 MiB, 32 MiB in total, so a hostile or
  broken host cannot exhaust memory during install;
* package paths may not be absolute, contain `..`, begin with `.`, or contain `:`, which also
  rejects the string form being abused to carry an absolute URL.

Supplying `sha256` per file is still recommended: it is the only check that survives the file host
and the manifest host being different systems.

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
