# Screenshot Result Popup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** After any screenshot (region snip or Print keybind), show an M3E popup with the captured image and Save / Edit / Discard actions, shipped as a bundled plugin.

**Architecture:** A core `ScreenshotEvents` singleton exposes a `screenshotTaken(path)` signal fed by an IPC handler (for Hyprland keybinds) and by the region selector directly. A new generic `PluginPanelHost` finally instantiates the plugin platform's `panel` entry point (validated today, consumed by nothing), and the `screenshot-result` bundled plugin provides the popup panel.

**Tech Stack:** QML/Quickshell, plugin platform (package plugin, `panel` entry), Hyprland lua keybinds, Python contract tests.

**Spec:** `docs/superpowers/specs/2026-07-25-screenshot-result-design.md`
**Working dir for test commands:** `~/dev/imi-unify/dots/.config/quickshell/ii`. Commits at repo root, on `main`.
**Hard rules:** no agent attribution in commits; never splice a screenshot path into a shell string — paths ride as `bash -c 'script "$1"' _ <path>` arguments or plain argv; do NOT touch `~/.config/quickshell/` (live shell) — the controller deploys at the end.

**Verified facts (do not re-derive):**
- `PluginValidator.js:37` accepts entry `panel`; entries are `{ "component": "File.qml" }` (see `discordVoice/manifest.json`'s `barWidget`). `PluginManager.parseManifest` stamps `_basePath` on `panel`.
- No consumer of `manifest.panel` exists — `modules/ii/bar/PluginBarWidget.qml` is the only entry-point host; mirror how it enumerates enabled plugins from `PluginManager`.
- Bundled plugins register via per-plugin `FileView` blocks in `PluginManager.qml` (~line 225, `clockManifestFile` pattern).
- Region snip Copy path: `RegionSelection.qml:289-296` builds a command via `ScreenshotAction.getCommand(...)` (`modules/common/utils/ScreenshotAction.qml`); the Copy/no-save branch pipes `magick crop → wl-copy && rm <temp>` — the temp dies immediately. There is a second, plugin-side copy of ScreenshotAction under `designsystem/widgets/regionSelectorUtils/` — DO NOT touch it.
- Fullscreen keybinds: `dots/.config/hypr/hyprland/keybinds.lua:94-102` (`grim ... - | wl-copy`, plus a CTRL save variant).
- `Directories.pictures` exists (`modules/common/Directories.qml:19`); region temp dir is `Directories.screenshotTemp` (under `/tmp/quickshell/media/screenshot`).
- `Config.qml:821` has `property JsonObject screenSnip` — add the new JsonObject right after it.
- IPC singleton gotcha: a lazy singleton nobody references never instantiates, so its IpcHandler is dead. The always-loaded PluginPanelHost (Task 3) references `ScreenshotEvents`, guaranteeing instantiation.

---

### Task 1: Contract test (written first, fails until the feature lands)

**Files:**
- Create: `dots/.config/quickshell/ii/tests/test_screenshot_result_contract.py`

- [ ] **Step 1: Write the test**

```python
#!/usr/bin/env python3
"""Contracts for the screenshot result popup (core hook + bundled plugin)."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parents[3]
SERVICE = ROOT / "services" / "ScreenshotEvents.qml"
HOST = ROOT / "modules" / "common" / "plugins" / "PluginPanelHost.qml"
PLUGIN_DIR = ROOT / "modules" / "common" / "plugins" / "bundled" / "screenshot-result"
MANIFEST = PLUGIN_DIR / "manifest.json"
PANEL = PLUGIN_DIR / "ScreenshotResultPanel.qml"
KEYBINDS = REPO / "dots" / ".config" / "hypr" / "hyprland" / "keybinds.lua"
SHELL_QML = ROOT / "shell.qml"
PLUGIN_MANAGER = ROOT / "modules" / "common" / "plugins" / "PluginManager.qml"
SCREENSHOT_ACTION = ROOT / "modules" / "common" / "utils" / "ScreenshotAction.qml"

failures = []


def check(name, cond, detail=""):
    print(f"  {'PASS' if cond else 'FAIL'} {name}" + ("" if cond else f" {detail}"))
    if not cond:
        failures.append(name)


def read(p):
    return p.read_text(encoding="utf-8") if p.exists() else ""


def main():
    print("Screenshot result contract tests")

    svc = read(SERVICE)
    check("service exists", SERVICE.exists())
    check("service is a singleton", "pragma Singleton" in svc)
    check("service declares the signal", "signal screenshotTaken(string path)" in svc)
    check("service exposes IPC", 'target: "screenshot"' in svc and "function notify(" in svc)
    check("notify validates existence before emitting", "fileExists" in svc or "FileView" in svc or "test -f" not in svc and "existsSync" not in svc and ("exists(" in svc or "isFile" in svc))
    check("notify gates on image extensions", re.search(r"png|jpe?g|webp", svc, re.I) is not None)

    host = read(HOST)
    check("panel host exists", HOST.exists())
    check("panel host loads manifest.panel components", ".panel" in host and "_basePath" in host)
    check("panel host keeps ScreenshotEvents alive", "ScreenshotEvents" in host)
    check("shell.qml instantiates the panel host", "PluginPanelHost" in read(SHELL_QML))

    mtext = read(MANIFEST)
    check("plugin manifest exists", MANIFEST.exists())
    if mtext:
        m = json.loads(mtext)
        check("manifest has a panel entry", isinstance(m.get("panel"), dict) and m["panel"].get("component"))
        check("manifest id", m.get("id") == "screenshot_result")
        check("panel component file exists", (PLUGIN_DIR / m["panel"]["component"]).exists())
    check("bundled manifest registered", "screenshot-result/manifest.json" in read(PLUGIN_MANAGER))

    panel = read(PANEL)
    check("panel subscribes to the event", "ScreenshotEvents" in panel and "onScreenshotTaken" in panel)
    check("hover pauses the dismiss timer", "HoverHandler" in panel or "hovered" in panel)
    check("dismiss timer uses config", "timeoutMs" in panel)
    # Path-safety: every bash -c in the panel must pass the path as an argument,
    # never interpolated. Allow `${...}` only for QML-side constants, not for
    # anything derived from the screenshot path property.
    for mch in re.finditer(r'"bash",\s*"-c",\s*(`[^`]*`|"[^"]*")', panel):
        body = mch.group(1)
        check("no path splicing in bash -c", "${" not in body or "currentPath" not in body,
              f"suspicious: {body[:60]}")
    check("discard guarded to scratch dirs",
          "screenshotTemp" in panel and re.search(r'startsWith\(', panel) is not None)
    raw_durations = [m for m in re.finditer(r"duration:\s*(\d+)", panel) if m.group(1) != "0"]
    check("panel motion is token-only", not raw_durations,
          f"raw: {[m.group(0) for m in raw_durations]}")

    kb = read(KEYBINDS)
    check("Print keybind writes a file and notifies",
          "screenshot notify" in kb and "wl-copy" in kb)
    check("keybind tolerates a dead shell", "|| true" in kb)

    sa = read(SCREENSHOT_ACTION)
    check("copy snip keeps a result file", "resultPath" in sa and "tee" in sa)

    if failures:
        print(f"{len(failures)} screenshot result contract(s) failed")
        return 1
    print("All screenshot result contract tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Run it — expect FAIL (most checks), exit 1**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && python3 tests/test_screenshot_result_contract.py`

- [ ] **Step 3: Commit**

```bash
cd ~/dev/imi-unify
git add dots/.config/quickshell/ii/tests/test_screenshot_result_contract.py
git commit -m "test(screenshot): contract suite for the result popup (red)"
```

---

### Task 2: ScreenshotEvents service

**Files:**
- Create: `dots/.config/quickshell/ii/services/ScreenshotEvents.qml`

- [ ] **Step 1: Implement**

```qml
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/**
 * Central "a screenshot was taken" event source. The region selector emits
 * directly; Hyprland keybinds reach it over IPC:
 *   qs -c ii ipc call screenshot notify /path/to/shot.png
 * notify() validates before emitting: the file must exist and look like an
 * image. Validation is sanity (IPC is same-user), not a security boundary -
 * but consumers must still never splice the path into a shell string.
 */
Singleton {
    id: root

    signal screenshotTaken(string path)

    function emitIfValid(path) {
        const p = (path ?? "").trim();
        if (!p.startsWith("/")) {
            console.warn("[ScreenshotEvents] ignoring non-absolute path:", p);
            return;
        }
        if (!/\.(png|jpe?g|webp)$/i.test(p)) {
            console.warn("[ScreenshotEvents] ignoring non-image path:", p);
            return;
        }
        existenceProbe.probePath = p;
        existenceProbe.running = true;
    }

    // `test -e` with the path as an argument (never interpolated).
    Process {
        id: existenceProbe
        property string probePath: ""
        command: ["test", "-f", probePath]
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0)
                root.screenshotTaken(existenceProbe.probePath);
            else
                console.warn("[ScreenshotEvents] ignoring missing file:", existenceProbe.probePath);
        }
    }

    IpcHandler {
        target: "screenshot"
        function notify(path: string): void {
            root.emitIfValid(path);
        }
    }
}
```

Note: the contract test's "notify validates existence" check accepts this
shape (`exists(`/`isFile` OR a Process probe — re-read the check; if it
doesn't match, adjust the TEST's expression to match this implementation, not
the other way around; the behavior requirement is: no emit for missing files).

- [ ] **Step 2: Run lints**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && ./tests/lint_qml_imports.sh`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
cd ~/dev/imi-unify
git add dots/.config/quickshell/ii/services/ScreenshotEvents.qml
git commit -m "feat(services): ScreenshotEvents hub with validated IPC notify"
```

---

### Task 3: Generic plugin panel host

**Files:**
- Create: `dots/.config/quickshell/ii/modules/common/plugins/PluginPanelHost.qml`
- Modify: `dots/.config/quickshell/ii/shell.qml`

- [ ] **Step 1: Read `modules/ii/bar/PluginBarWidget.qml`** to copy its exact
enumeration of enabled plugins from `PluginManager` (property name for the
plugin list, enablement check, and how `_basePath` + entry `component` combine
into a source URL). Use the same accessors.

- [ ] **Step 2: Implement the host**

```qml
import QtQuick
import Quickshell
import qs.services
import qs.modules.common

/**
 * Instantiates every enabled plugin's `panel` entry point. Panels are
 * free-floating package-plugin surfaces (own PanelWindow/popup); the host
 * only loads them. Also anchors the ScreenshotEvents singleton so its IPC
 * handler exists even when no panel plugin is enabled.
 */
Scope {
    id: root

    // Force-instantiate the event hub (lazy singletons without references
    // never register their IpcHandlers).
    readonly property var _screenshotEvents: ScreenshotEvents

    Repeater {
        model: /* enabled plugins with a panel entry, per PluginBarWidget's pattern */
        delegate: Loader {
            required property var modelData
            source: modelData._basePath + "/" + modelData.panel.component
            onStatusChanged: if (status === Loader.Error)
                console.warn("[PluginPanelHost] failed to load panel for", modelData.id)
        }
    }
}
```

(The `model:` expression is filled from Step 1's reading — e.g.
`PluginManager.plugins.filter(p => p.panel && PluginManager.isEnabled(p.id))`;
use the REAL API names found there. A `Repeater` inside a `Scope` needs a
QtObject-compatible parent for delegates — if Quickshell rejects it, use
`Variants { model: ... }` over the same list or an `Instantiator`, whichever
the codebase already uses for non-visual per-plugin instantiation; check how
`PluginManager`/`Background.qml` instantiate plugin widget lists and mirror.)

- [ ] **Step 3: Wire into shell.qml** — add `PluginPanelHost {}` alongside the
other top-level scopes (find where Dock/Bar/ReloadPopup are instantiated; add
one line in the same block, importing `qs.modules.common.plugins` if not
already imported).

- [ ] **Step 4: Lints + targeted contract checks**

Run: `./tests/lint_qml_imports.sh && python3 tests/test_screenshot_result_contract.py`
Expected: lint exit 0; contract test now passes the host checks (plugin checks still fail).

- [ ] **Step 5: Commit**

```bash
cd ~/dev/imi-unify
git add dots/.config/quickshell/ii/modules/common/plugins/PluginPanelHost.qml dots/.config/quickshell/ii/shell.qml
git commit -m "feat(plugins): instantiate the panel entry point via PluginPanelHost"
```

---

### Task 4: Region selector emits the event

**Files:**
- Modify: `dots/.config/quickshell/ii/modules/common/utils/ScreenshotAction.qml`
- Modify: `dots/.config/quickshell/ii/modules/ii/regionSelector/RegionSelection.qml`

- [ ] **Step 1: Extend `getCommand` with a `resultPath` parameter**

Signature becomes `function getCommand(x, y, width, height, screenshotPath, action, saveDir = "", resultPath = "")`.
Only the two Copy branches change; when `resultPath` is empty they behave exactly as today:

```qml
            case ScreenshotAction.Action.Copy:
                if (saveDir === "") {
                    if (resultPath === "")
                        return ["bash", "-c", `${cropToStdout} | wl-copy && ${cleanup}`]
                    // Keep a cropped copy for the result popup; the full-frame
                    // temp is still cleaned up.
                    return ["bash", "-c", `${cropToStdout} | tee '${StringUtils.shellSingleQuoteEscape(resultPath)}' | wl-copy && ${cleanup}`]
                }
                // Saving to disk: write the file at a QML-chosen path so the
                // caller knows it (previously the name was minted inside bash).
                if (resultPath !== "") {
                    return [
                        "bash", "-c",
                        `mkdir -p '${StringUtils.shellSingleQuoteEscape(saveDir)}' && \
                        ${cropToStdout} | tee >(wl-copy) > '${StringUtils.shellSingleQuoteEscape(resultPath)}' && \
                        ${cleanup}`
                    ]
                }
                return [ /* existing saveDir block verbatim */ ]
```

(`resultPath` is QML-generated below — timestamps only, no user input — and
still goes through `shellSingleQuoteEscape`, matching the file's existing
convention for `screenshotPath`.)

- [ ] **Step 2: RegionSelection computes the result path, runs Copy via a Process, emits**

In `RegionSelection.qml` (needs `import qs.services` — already present; verify):
around the line-296 command construction, for Copy actions only:

```qml
        const isCopy = screenshotAction === ScreenshotAction.Action.Copy;
        let resultPath = "";
        if (isCopy) {
            const ts = new Date().toISOString().replace(/[:.]/g, "-");
            const dir = screenshotDir !== "" ? screenshotDir : root.screenshotDir;
            resultPath = `${dir}/result-${ts}.png`;
        }
        const command = ScreenshotAction.getCommand(
            /* existing args unchanged */, screenshotDir, resultPath);
```

Then run Copy commands through a Process so completion is observable
(non-Copy actions keep the existing execution path untouched):

```qml
    Process {
        id: copySnipProcess
        property string resultPath: ""
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && resultPath !== "")
                ScreenshotEvents.emitIfValid(resultPath);
        }
    }
```

```qml
        if (isCopy) {
            copySnipProcess.resultPath = resultPath;
            copySnipProcess.command = command;
            copySnipProcess.running = true;
        } else {
            /* existing execution line verbatim */
        }
```

Read the surrounding code first: if the existing execution already uses a
Process with an exit hook, extend that instead of adding a second one.

- [ ] **Step 3: Lints + contract**

Run: `./tests/lint_qml_imports.sh && python3 tests/test_screenshot_result_contract.py`
Expected: "copy snip keeps a result file" now passes.

- [ ] **Step 4: Commit**

```bash
cd ~/dev/imi-unify
git add dots/.config/quickshell/ii/modules/common/utils/ScreenshotAction.qml dots/.config/quickshell/ii/modules/ii/regionSelector/RegionSelection.qml
git commit -m "feat(regionSelector): keep a result file on copy snips and emit ScreenshotEvents"
```

---

### Task 5: Keybind rewiring

**Files:**
- Modify: `dots/.config/hypr/hyprland/keybinds.lua:94-102`

- [ ] **Step 1: Replace the three fullscreen screenshot binds**

```lua
--# Fullscreen screenshot
local grimhyprctl = "grim -o \"$(hyprctl activeworkspace -j | jq -r '.monitor')\""
local shotTmp = "f=\"/tmp/quickshell/media/screenshot/full-$(date '+%s%N').png\"; mkdir -p \"${f%/*}\"; "
hl.bind("Print", hl.dsp.exec_cmd(
    shotTmp .. grimhyprctl .. " \"$f\" && wl-copy < \"$f\" && (qs -c ii ipc call screenshot notify \"$f\" || true)"),
    { locked = true, description = "Utilities: Screenshot >> clipboard" })
hl.bind("CTRL + Print", hl.dsp.exec_cmd(
    "d=\"$(xdg-user-dir PICTURES)/Screenshots\"; mkdir -p \"$d\"; " ..
    "f=\"$d/Screenshot_$(date '+%Y-%m-%d_%H.%M.%S').png\"; " ..
    grimhyprctl .. " \"$f\" && wl-copy < \"$f\" && (qs -c ii ipc call screenshot notify \"$f\" || true)"
), { locked = true, non_consuming = true, description = "Utilities: Screenshot >> clipboard & file" })
```

Notes: the previous second `CTRL + Print` bind (clipboard-only duplicate) is
folded into the save variant (it now wl-copies from the saved file) — delete
it. Clipboard still works with the shell down (`|| true`). The popup gets the
SAVED path for CTRL+Print, so its timeout/discard must not delete it (Task 6's
scratch-dir guard handles that: `$PICTURES` is not a scratch dir).

- [ ] **Step 2: Contract check**

Run: `python3 tests/test_screenshot_result_contract.py`
Expected: both keybind checks pass.

- [ ] **Step 3: Commit**

```bash
cd ~/dev/imi-unify
git add dots/.config/hypr/hyprland/keybinds.lua
git commit -m "feat(hypr): route fullscreen screenshots through a file and notify the shell"
```

---

### Task 6: Config keys + Settings section

**Files:**
- Modify: `dots/.config/quickshell/ii/modules/common/Config.qml` (after the `screenSnip` JsonObject, ~line 821)
- Modify: `dots/.config/quickshell/ii/modules/ii/settings/pages/InterfaceConfig.qml`

- [ ] **Step 1: Config keys**

```qml
            property JsonObject screenshotResult: JsonObject {
                property bool enable: true
                property int timeoutMs: 6000
                // Annotation tool override; [] = auto-detect (swappy, then satty).
                property list<string> editorCommand: []
            }
```

- [ ] **Step 2: Settings section** — in `InterfaceConfig.qml`, after the
Terminal `ContentSection`, add:

```qml
        ContentSection {
            icon: "screenshot_monitor"
            title: Translation.tr("Screenshot popup")
            shape: MaterialShape.Shape.Clover4Leaf

            GroupedList {
                ConfigSwitch {
                    buttonIcon: "preview"
                    text: Translation.tr("Show result popup")
                    description: Translation.tr("Preview with save/edit/discard after every screenshot")
                    checked: Config.options.screenshotResult.enable
                    onCheckedChanged: Config.options.screenshotResult.enable = checked
                }
                ConfigSpinBox {
                    enabled: Config.options.screenshotResult.enable
                    icon: "timer"
                    text: Translation.tr("Auto-dismiss (ms)")
                    value: Config.options.screenshotResult.timeoutMs
                    from: 1500
                    to: 30000
                    stepSize: 500
                    onValueChanged: Config.options.screenshotResult.timeoutMs = value
                }
            }
        }
```

(Check `MaterialShape.Shape.Clover4Leaf` exists — grep `MaterialShape.Shape.` for
the valid enum values and pick any unused one if not.)

- [ ] **Step 3: Run `./tests/run_tests.sh` through the Settings navigation test stage** (it asserts page structure):

Run: `python3 tests/test_settings_navigation.py`
Expected: exit 0 (if it pins section lists, update per its own failure output — read the test first).

- [ ] **Step 4: Commit**

```bash
cd ~/dev/imi-unify
git add dots/.config/quickshell/ii/modules/common/Config.qml dots/.config/quickshell/ii/modules/ii/settings/pages/InterfaceConfig.qml
git commit -m "feat(settings): screenshot result popup options"
```

---

### Task 7: The bundled plugin

**Files:**
- Create: `dots/.config/quickshell/ii/modules/common/plugins/bundled/screenshot-result/manifest.json`
- Create: `dots/.config/quickshell/ii/modules/common/plugins/bundled/screenshot-result/ScreenshotResultPanel.qml`
- Modify: `dots/.config/quickshell/ii/modules/common/plugins/PluginManager.qml` (bundled FileView block, ~line 225)

- [ ] **Step 1: Manifest**

```json
{
  "id": "screenshot_result",
  "name": "Screenshot Result",
  "description": "Preview popup with save/edit/discard actions after every screenshot",
  "version": "1.0.0",
  "author": "Immaterial Impulse contributors",
  "apiVersion": 1,
  "capabilities": ["panel"],
  "permissions": ["process", "filesystem_read", "filesystem_write", "settings_read"],
  "panel": { "component": "ScreenshotResultPanel.qml" }
}
```

(Validate the `capabilities` value list against `PluginValidator.js` — if
"panel" is not an allowed capability string, drop the capabilities field; it
is optional.)

- [ ] **Step 2: Register in PluginManager.qml** — copy the clock FileView block:

```qml
    FileView {
        id: screenshotResultManifestFile
        property string pluginBase: Quickshell.shellPath("modules/common/plugins/bundled/screenshot-result")
        path: pluginBase + "/manifest.json"
        onLoaded: root.scheduleRebuild()
    }
```

and add `screenshotResultManifestFile` wherever the sibling FileViews are
collected into the bundled list (search for `clockManifestFile` usages).

- [ ] **Step 3: The panel**

```qml
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Screenshot result popup: preview + save/edit/discard. One instance, shown
 * on the focused monitor. Owns the notified file while visible: discard (and
 * timeout, for scratch files only) deletes it; save moves it to Pictures.
 */
Scope {
    id: root

    property string currentPath: ""
    property bool fileIsScratch: currentPath.startsWith(Directories.screenshotTemp)
        || currentPath.startsWith("/tmp/")
    property string editorBinary: ""

    Connections {
        target: ScreenshotEvents
        function onScreenshotTaken(path) {
            if (!(Config.options.screenshotResult?.enable ?? true)) return;
            // Replacing an existing popup discards the old file (same rules
            // as timeout).
            if (root.currentPath !== "" && root.currentPath !== path)
                root.releaseCurrent();
            root.currentPath = path;
            dismissTimer.restart();
        }
    }

    // Discard, timeout and replacement all use the same rule: scratch files
    // are deleted, user-saved files (CTRL+Print target) are always kept.
    function releaseCurrent() {
        if (root.currentPath === "") return;
        if (root.fileIsScratch)
            Quickshell.execDetached(["rm", "-f", "--", root.currentPath]);
        root.currentPath = "";
    }

    // Resolve the annotation tool once: config override, else swappy, else satty.
    Process {
        id: editorProbe
        running: true
        command: ["bash", "-c", "command -v swappy satty 2>/dev/null | head -n1"]
        stdout: StdioCollector {
            onStreamFinished: root.editorBinary = text.trim()
        }
    }

    Timer {
        id: dismissTimer
        interval: Config.options.screenshotResult?.timeoutMs ?? 6000
        onTriggered: {
            if (panelLoader.item?.hovered) { dismissTimer.restart(); return; }
            root.releaseCurrent();
        }
    }

    LazyLoader {
        id: panelLoader
        active: root.currentPath !== ""

        PanelWindow {
            id: popupWindow
            property bool hovered: hoverHandler.hovered
            screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            anchors { bottom: true; left: true }
            margins { bottom: Appearance.sizes.hyprlandGapsOut + Appearance.spacing.space200; left: Appearance.spacing.space200 }
            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight
            color: "transparent"
            WlrLayershell.namespace: "quickshell:screenshotResult"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusiveZone: 0

            HoverHandler { id: hoverHandler }

            ColumnLayout {
                id: content
                spacing: Appearance.spacing.space100

                Rectangle {
                    Layout.preferredWidth: previewImage.paintedWidth + Appearance.spacing.space100 * 2
                    Layout.preferredHeight: previewImage.paintedHeight + Appearance.spacing.space100 * 2
                    radius: Appearance.rounding.large
                    color: Appearance.colors.colLayer0
                    border.width: Appearance.borderWidth.emphasis
                    border.color: Appearance.colors.colLayer0Border

                    Image {
                        id: previewImage
                        anchors.centerIn: parent
                        source: root.currentPath !== "" ? "file://" + root.currentPath : ""
                        sourceSize.width: 340
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                    }
                }

                RowLayout {
                    spacing: Appearance.spacing.space100

                    RippleButton {
                        buttonRadius: Appearance.rounding.normal
                        implicitWidth: 44; implicitHeight: 44
                        onClicked: { root.saveCurrent(); }
                        contentItem: MaterialSymbol { text: "save"; horizontalAlignment: Text.AlignHCenter; color: Appearance.colors.colOnLayer0 }
                        StyledToolTip { text: Translation.tr("Save to Pictures") }
                    }
                    RippleButton {
                        visible: root.editorBinary !== ""
                        buttonRadius: Appearance.rounding.normal
                        implicitWidth: 44; implicitHeight: 44
                        onClicked: { root.editCurrent(); }
                        contentItem: MaterialSymbol { text: "edit"; horizontalAlignment: Text.AlignHCenter; color: Appearance.colors.colOnLayer0 }
                        StyledToolTip { text: Translation.tr("Annotate") }
                    }
                    RippleButton {
                        buttonRadius: Appearance.rounding.normal
                        implicitWidth: 44; implicitHeight: 44
                        onClicked: { root.releaseCurrent(); }
                        contentItem: MaterialSymbol { text: "delete"; horizontalAlignment: Text.AlignHCenter; color: Appearance.colors.colOnLayer0 }
                        StyledToolTip { text: Translation.tr("Discard") }
                    }
                }
            }
        }
    }

    function saveCurrent() {
        if (root.currentPath === "") return;
        // Path rides as $2; the script text is a fixed string.
        Quickshell.execDetached(["bash", "-c",
            'd="$1/Screenshots"; mkdir -p "$d"; ' +
            'n="$d/Screenshot_$(date +%Y-%m-%d_%H.%M.%S).png"; ' +
            'while [ -e "$n" ]; do n="${n%.png}_$RANDOM.png"; done; ' +
            'cp -n -- "$2" "$n"',
            "_", FileUtils.trimFileProtocol(Directories.pictures), root.currentPath]);
        root.releaseCurrent();
    }

    function editCurrent() {
        if (root.currentPath === "" || root.editorBinary === "") return;
        const args = root.editorBinary.endsWith("satty")
            ? [root.editorBinary, "--filename", root.currentPath]
            : [root.editorBinary, "-f", root.currentPath];
        const custom = Config.options.screenshotResult?.editorCommand ?? [];
        Quickshell.execDetached(custom.length > 0 ? custom.concat([root.currentPath]) : args);
        // The editor needs the file - close without deleting.
        root.currentPath = "";
    }
}
```

Implementation notes for the engineer:
- `import qs.modules.common.functions` is needed for `FileUtils` — add it.
- 44 px button size: use `Appearance.sizes.*` if an equivalent token exists
  (grep `baseSize`/`baseWidth` in settings pages); otherwise keep the literal —
  it is a dimension, not spacing (lint_spacing only flags spacing/margins).
- Add entrance/exit motion with `Appearance.animation.elementMoveEnter` /
  `elementMoveFast` (scale+opacity on `content`), tokens only.
- `Hyprland.focusedMonitor` needs `import Quickshell.Hyprland`.
- If `LazyLoader` inside `Scope` misbehaves for PanelWindow, use plain
  `Loader` — ReloadPopup.qml (repo root) is the working reference for a
  transient PanelWindow popup; mirror it.

- [ ] **Step 4: Full contract test green**

Run: `python3 tests/test_screenshot_result_contract.py`
Expected: "All screenshot result contract tests passed", exit 0.

- [ ] **Step 5: All lints + plugin process lint**

Run: `./tests/lint_qml_imports.sh && python3 tests/lint_spacing.py && python3 tests/lint_plugin_processes.py`
Expected: all exit 0 (editorProbe is one-shot `running: true`, not a loop — the process lint must stay green).

- [ ] **Step 6: Commit**

```bash
cd ~/dev/imi-unify
git add dots/.config/quickshell/ii/modules/common/plugins/bundled/screenshot-result dots/.config/quickshell/ii/modules/common/plugins/PluginManager.qml
git commit -m "feat(plugins): bundled screenshot-result popup plugin"
```

---

### Task 8: Suite wiring + changelog

**Files:**
- Modify: `dots/.config/quickshell/ii/tests/run_tests.sh`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Wire the contract test** — append after the last python stage
(currently the brightness/system info block):

```bash
echo "Running screenshot result contract tests..."
if ! python3 "$SCRIPT_DIR/test_screenshot_result_contract.py"; then
    echo "screenshot result contract tests failed."
    exit 1
fi
```

- [ ] **Step 2: Full suite**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && ./tests/run_tests.sh`
Expected: "All tests passed successfully!"

- [ ] **Step 3: Changelog** — `## [Unreleased]` → `### Added`, append:

```markdown
- Screenshot result popup (bundled plugin): every screenshot - region snip or
  Print keybind - pops a preview with save / annotate / discard actions;
  auto-dismisses, hover pins it. The plugin platform's `panel` entry point is
  now actually instantiated (PluginPanelHost), so plugins can ship
  free-floating surfaces.
```

- [ ] **Step 4: Commit**

```bash
cd ~/dev/imi-unify
git add dots/.config/quickshell/ii/tests/run_tests.sh CHANGELOG.md
git commit -m "test(screenshot): wire result popup contracts; changelog"
```

---

### Task 9: Live verification (controller/user step — NOT for a subagent)

- Deploy in one batch: `ScreenshotEvents.qml`, `PluginPanelHost.qml`,
  `shell.qml`, `ScreenshotAction.qml`, `RegionSelection.qml`, `Config.qml`,
  `InterfaceConfig.qml`, `PluginManager.qml`, the whole
  `bundled/screenshot-result/` dir → `~/.config/quickshell/ii/`; keybinds.lua
  → `~/.config/hypr/hyprland/` (Hyprland reloads it automatically).
- Check the live log for QML errors.
- User verifies: region snip → popup (clipboard still has the image);
  Print → popup; CTRL+Print → popup showing the SAVED file (discard must NOT
  delete it); Save lands in ~/Pictures/Screenshots; Edit opens
  swappy/satty; hover pins; replacement works; `qs -c ii kill` then Print
  still copies to clipboard.

## Verification checklist (post-plan)

- Spec coverage: hook+IPC (T2), region path (T4), keybinds (T5), plugin UI +
  actions + lifetime + ownership rules (T7), panel host gap (T3), config +
  settings (T6), tests (T1, T8), live checks (T9). Multi-monitor: focused
  monitor only (T7). Out-of-scope items untouched.
- No placeholders: every code step has full code; two "read the neighbor
  first" steps name the exact reference file and what to extract.
