# Screenshot Result Popup — Design

**Goal:** After any screenshot, show a small popup with the captured image and
three actions — Save, Edit, Discard — styled M3 Expressive, shipped as a
bundled plugin.

**Decisions (user-confirmed):**
- Triggers on ALL capture paths: region-selector snips and the fullscreen
  Print keybinds.
- Buttons: Save (to Screenshots dir), Edit (annotation tool), Discard.
- Packaging: bundled plugin (default-on, removable), not a core module; the
  core only gains a small screenshot event hook.
- Lifetime: auto-dismiss ~6 s; hovering pauses the timer; configurable.

## Architecture

Three parts: a core event hook, keybind rewiring, and the plugin UI.

### 1. Core hook — `services/ScreenshotEvents.qml` (new singleton)

```qml
signal screenshotTaken(string path)

IpcHandler {
    target: "screenshot"
    function notify(path: string): void   // validate, then emit
}
```

- `notify` validates before emitting: file exists, extension is
  png/jpg/jpeg/webp. Bad paths are ignored (log a warning). IPC is same-user
  local, so validation is sanity, not a security boundary — but the path must
  NEVER be spliced into a shell string (repo hard rule; all consumers use
  argv arrays).
- The region selector's screenshot (Copy) action emits `screenshotTaken` with
  its captured file. Investigate at plan time exactly where the temp file
  lives in `RegionSelection.qml`'s Copy flow and who deletes it; ownership of
  the file transfers to the popup (see Lifecycle below). If the Copy flow's
  temp is unsuitable (deleted immediately), the action writes a copy to
  `Directories.screenshotTemp` first.

### 2. Keybind rewiring — `dots/.config/hypr/hyprland/keybinds.lua`

The fullscreen Print bindings currently pipe `grim - | wl-copy` (clipboard
only, no file). Rewrite to: grim → temp file → `wl-copy < file` → `qs -c ii
ipc call screenshot notify <file>`. Clipboard behavior is preserved when the
shell is down (the trailing IPC call fails silently; `|| true`). The
save-to-file Print variant additionally keeps its existing target path and
notifies with that path instead of a temp.

### 3. Plugin — `modules/common/plugins/bundled/screenshot-result/`

Package plugin with a `panel` entry (same registration mechanism as existing
bundled plugins; mirror whichever bundled plugin already ships a panel — the
plan phase pins the exact manifest shape against `PluginManager.qml`'s entry
types).

UI (per mockup): a `PopupWindow`/layer surface anchored bottom-left with
margin, containing:
- Rounded preview thumbnail (border + `Appearance.rounding` tokens, width
  capped ~360 px, aspect preserved).
- Button row of three `RippleButton`s with MaterialSymbols: `save`,
  `edit` (annotation), `delete`.
- Motion: expressive slide-in + spring (Appearance.animation tokens only);
  shrink+fade out. New screenshot while visible replaces the content and
  restarts the timer.
- Auto-dismiss: `Timer` with `Config` duration (default 6000 ms), paused
  while a `HoverHandler` reports containment.

Actions (all argv arrays via `Quickshell.execDetached` / `Process`, never
`bash -c` with the path):
- **Save**: copy the file to `$(xdg-user-dir PICTURES)/Screenshots/`
  as `Screenshot_YYYY-MM-DD_HH.MM.SS.png` (resolve the Pictures dir via the
  existing Directories service if it exposes it; else `xdg-user-dir` once at
  startup). Name collisions get a `_N` suffix. Popup closes.
- **Edit**: open the image in the first available annotation tool:
  `swappy -f <file>` → `satty --filename <file>` → user-configured command
  (config array, executed as argv with the path appended). Button hidden when
  nothing resolves. Popup closes; the temp file survives (the editor needs
  it) — cleanup falls to the tmpdir.
- **Discard**: delete the temp file (only if it lives under a temp/screenshot
  scratch dir — never delete files outside those), close.
- **Timeout**: same as Discard except the file is NOT deleted if the source
  was a user-saved path (keybind save variant).

### Lifecycle / ownership

The popup owns the notified file while visible. Replacement by a newer
screenshot discards the old one under the same rules as timeout. The popup
never deletes files outside `Directories.screenshotTemp` (or `/tmp/...`
scratch paths).

### Config

`Config.options.screenshotResult`: `enable` (true), `timeoutMs` (6000),
`editorCommand` ([] = auto-detect). Surfaced in Settings → Interface as a
small section (switch + spinbox + text field), following the existing
ConfigSwitch/ConfigSpinBox patterns.

Disabled ⇒ the plugin panel never shows; the core hook still emits (cheap,
other consumers possible later).

## Multi-monitor

Popup appears on the focused monitor (`Hyprland.focusedMonitor`), one
instance total (not per-screen Variants).

## Error handling

- notify with missing/non-image path → ignored + warning.
- Save target dir missing → created (`mkdir -p` equivalent).
- Editor launch failure → popup already closed; nothing further (tool prints
  to log).
- Shell restart mid-popup → popup gone, temp file orphaned in tmpdir
  (acceptable; tmpdir is transient).

## Testing

- `tests/test_screenshot_result_contract.py`:
  - plugin manifest parses and its entry type is one the platform accepts;
  - `ScreenshotEvents.qml` IPC handler shape (`target: "screenshot"`,
    `notify`), validation present (existence + extension check);
  - no `bash -c` anywhere in the plugin/service with `${...}` path splicing
    (argv arrays only);
  - discard/delete guarded by the scratch-dir check (assert the guard
    expression);
  - keybinds.lua Print bindings contain the file→wl-copy→notify chain and
    `|| true` shell-down tolerance;
  - motion/spacing token-only (no raw durations except 0; reuse the
    test_dock_motion.py pattern).
- Existing lints cover the rest automatically (`lint_plugin_processes.py`,
  `lint_qml_imports.sh`, `lint_spacing.py`).
- Live verification: both capture paths, hover-pin, replace-while-visible,
  all three buttons, shell-down keybind still copies to clipboard.

## Out of scope

- Screenshot history/gallery.
- Recording results (video) — screenshots only.
- Per-screen popups.
- OCR/search actions (already exist elsewhere in the shell).
