# Plugin packages

end4-pC supports two complementary plugin formats:

- **Declarative plugins** describe a tree of approved shell components in `manifest.json`.
- **Package plugins** point entry points at QML files stored beside the manifest, enabling richer
  bar widgets, desktop widgets, popups, and settings using native shell components and tokens.

Installed packages live at `~/.config/illogical-impulse/plugins/<plugin-id>/`. The manager scans
that directory for `manifest.json`; installed packages override bundled packages with the same id.

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

Avoid editing many live-loaded QML files in rapid succession. Quickshell reloads the configuration
for each change, and moving service/module files during those reloads can impose severe session
load. Stop Quickshell or develop in a worktree, run headless tests, then do one controlled live load.
