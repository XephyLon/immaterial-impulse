# Dock Feedback Motion (M3 Expressive) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the dock M3-Expressive feedback motion — hover lift, press squish, launch bounce, appear pop, and springing active-state dots — via one shared motion component used by both pinned and unpinned app buttons.

**Architecture:** A new presentation-only wrapper (`DockIconMotion.qml`) owns all icon transforms (scale + translate, never layout size), driven by declarative props. A new singleton (`DockLaunchTracker.qml`) tracks click→window-map launch state with a 10 s timeout and an appeared-once registry that gates the appear pop so full-model rebuilds don't replay it. `DockAppButton.qml` (running unpinned apps) and `DragApps.qml` (pinned apps) both consume the wrapper.

**Tech Stack:** QtQuick/QML (Quickshell), tokens from `Appearance.animation` / `Appearance.animationCurves` / `Appearance.spacing`, Python contract tests wired into `tests/run_tests.sh`.

**Spec:** `docs/superpowers/specs/2026-07-25-dock-motion-design.md`

**Working directory for all commands:** `dots/.config/quickshell/ii` inside the repo (`~/dev/imi-unify`). Commits happen at repo root. Work lands on `main` per this repo's established workflow (no worktree).

**Repo hard rules:** no agent attribution in commits; granular commits; token-only durations/curves (lint enforces spacing tokens); editing the live config at `~/.config/quickshell/ii` hot-reloads the user's shell — do NOT copy files there mid-task, only at the final verification step.

---

### Task 1: DockLaunchTracker service

**Files:**
- Create: `dots/.config/quickshell/ii/services/DockLaunchTracker.qml`
- Test: `dots/.config/quickshell/ii/tests/test_dock_motion.py` (new file, first half)

- [ ] **Step 1: Write the failing contract test**

Create `dots/.config/quickshell/ii/tests/test_dock_motion.py`:

```python
#!/usr/bin/env python3
"""Contract tests for dock feedback motion (M3 Expressive).

Static checks, same style as the other suites here: read the QML sources and
assert the structural contracts that keep the dock's motion token-driven and
consistent across pinned (DragApps) and unpinned (DockAppButton) buttons.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TRACKER = ROOT / "services" / "DockLaunchTracker.qml"
MOTION = ROOT / "modules" / "common" / "widgets" / "DockIconMotion.qml"
DOCK_APP_BUTTON = ROOT / "modules" / "common" / "widgets" / "DockAppButton.qml"
DRAG_APPS = ROOT / "modules" / "common" / "widgets" / "DragApps.qml"

failures = []


def check(name, cond, detail=""):
    if cond:
        print(f"  PASS {name}")
    else:
        print(f"  FAIL {name} {detail}")
        failures.append(name)


def read(path):
    return path.read_text(encoding="utf-8") if path.exists() else ""


def main():
    print("Dock motion contract tests")

    # --- DockLaunchTracker ---
    tracker = read(TRACKER)
    check("tracker exists", TRACKER.exists())
    check("tracker is a singleton", "pragma Singleton" in tracker)
    for fn in ("markLaunching", "isLaunching", "clearLaunching", "firstAppearance"):
        check(f"tracker defines {fn}", f"function {fn}(" in tracker)
    check("tracker has a timeout", "timeoutMs" in tracker and "Timer" in tracker)
    check(
        "tracker clears on window map",
        "onAppsChanged" in tracker and "TaskbarApps" in tracker,
    )

    # --- DockIconMotion ---
    motion = read(MOTION)
    check("motion component exists", MOTION.exists())
    for prop in ("hovered", "pressed", "launching", "dragging"):
        check(f"motion has {prop} input", f"property bool {prop}" in motion)
    check("motion has playAppear", "function playAppear(" in motion)
    raw_durations = [
        m
        for m in re.finditer(r"duration:\s*(\d+)", motion)
        if m.group(1) != "0"
    ]
    check(
        "motion durations are token-only",
        not raw_durations,
        f"raw literals: {[m.group(0) for m in raw_durations]}",
    )
    check(
        "motion curves are token-only",
        "bezierCurve" not in motion
        or "Appearance.animationCurves" in motion,
    )
    check(
        "motion never animates layout size",
        "Behavior on implicitWidth" not in motion
        and "Behavior on implicitHeight" not in motion
        and "Behavior on width" not in motion
        and "Behavior on height" not in motion,
    )

    # --- Consumers ---
    dab = read(DOCK_APP_BUTTON)
    da = read(DRAG_APPS)
    check("DockAppButton uses DockIconMotion", "DockIconMotion" in dab)
    check("DragApps uses DockIconMotion", "DockIconMotion" in da)
    check("DockAppButton marks launches", "DockLaunchTracker.markLaunching" in dab)
    check("DragApps marks launches", "DockLaunchTracker.markLaunching" in da)
    check("DragApps suppresses motion while dragging", "dragging:" in da)
    check(
        "DockAppButton dots spring (width)",
        "Behavior on implicitWidth" in dab,
    )
    check("DockAppButton dots spring (color)", "Behavior on color" in dab)
    check("DragApps dots spring (width)", "Behavior on implicitWidth" in da)
    check("DragApps dots spring (color)", "Behavior on color" in da)

    if failures:
        print(f"{len(failures)} dock motion contract(s) failed")
        return 1
    print("All dock motion contract tests passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: Run it to make sure it fails**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && python3 tests/test_dock_motion.py`
Expected: FAIL — "tracker exists", "motion component exists", consumer checks all FAIL; exit code 1.

- [ ] **Step 3: Implement the tracker**

Create `dots/.config/quickshell/ii/services/DockLaunchTracker.qml`:

```qml
pragma Singleton

import QtQuick
import Quickshell
import qs.services

/**
 * Tracks dock app launches between the launch click and the window mapping,
 * plus an appeared-once registry so the dock's appear animation only plays
 * the first time an app shows up (TaskbarApps rebuilds its whole model on
 * any toplevel change, recreating every delegate - without this gate the
 * appear pop would replay on all icons every time any window opens/closes).
 */
Singleton {
    id: root

    readonly property int timeoutMs: 10000
    // appId (lowercased) -> Timer; bump revision on every mutation so
    // isLaunching() bindings re-evaluate.
    property var pendingLaunches: ({})
    property var seenAppIds: ({})
    property int revision: 0

    function markLaunching(appId) {
        const key = (appId ?? "").toLowerCase();
        if (!key)
            return;
        if (root.pendingLaunches[key])
            root.pendingLaunches[key].restart();
        else
            root.pendingLaunches[key] = timeoutTimerComponent.createObject(root, { appId: key });
        root.revision++;
    }

    function clearLaunching(appId) {
        const key = (appId ?? "").toLowerCase();
        const timer = root.pendingLaunches[key];
        if (!timer)
            return;
        delete root.pendingLaunches[key];
        timer.destroy();
        root.revision++;
    }

    function isLaunching(appId) {
        void root.revision; // reactive dependency
        return !!root.pendingLaunches[(appId ?? "").toLowerCase()];
    }

    // True exactly once per appearance of an app in the dock. The registry is
    // pruned when the app leaves the dock, so the next open animates again.
    function firstAppearance(appId) {
        const key = (appId ?? "").toLowerCase();
        if (!key || root.seenAppIds[key])
            return false;
        root.seenAppIds[key] = true;
        return true;
    }

    Component {
        id: timeoutTimerComponent
        Timer {
            property string appId
            interval: root.timeoutMs
            running: true
            onTriggered: root.clearLaunching(appId)
        }
    }

    Connections {
        target: TaskbarApps
        function onAppsChanged() {
            // A pending launch resolves as soon as its app has a real window.
            for (const key of Object.keys(root.pendingLaunches)) {
                const entry = TaskbarApps.apps.find(a => a.appId === key && a.toplevels.length > 0);
                if (entry)
                    root.clearLaunching(key);
            }
            // Prune the appeared-once registry for apps that left the dock.
            const present = new Set(TaskbarApps.apps.map(a => a.appId));
            for (const key of Object.keys(root.seenAppIds)) {
                if (!present.has(key))
                    delete root.seenAppIds[key];
            }
        }
    }
}
```

- [ ] **Step 4: Run the test again**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && python3 tests/test_dock_motion.py`
Expected: all tracker checks PASS; motion/consumer checks still FAIL (exit 1 — fine, they belong to later tasks).

- [ ] **Step 5: Commit**

```bash
cd ~/dev/imi-unify
git add dots/.config/quickshell/ii/services/DockLaunchTracker.qml \
        dots/.config/quickshell/ii/tests/test_dock_motion.py
git commit -m "feat(dock): add DockLaunchTracker service for launch-pending state"
```

---

### Task 2: DockIconMotion component

**Files:**
- Create: `dots/.config/quickshell/ii/modules/common/widgets/DockIconMotion.qml`
- Test: `dots/.config/quickshell/ii/tests/test_dock_motion.py` (already written in Task 1)

- [ ] **Step 1: Confirm the motion checks currently fail**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && python3 tests/test_dock_motion.py`
Expected: "motion component exists" FAIL.

- [ ] **Step 2: Implement the component**

Create `dots/.config/quickshell/ii/modules/common/widgets/DockIconMotion.qml`:

```qml
import QtQuick
import qs.modules.common

/**
 * M3 Expressive feedback motion for a dock icon. Wrap the icon's visuals in
 * this and drive it with declarative state; it owns transforms only (scale +
 * vertical translate), never layout size, so the dock row width cannot churn.
 *
 * Priority: dragging suppresses everything; press squish beats hover lift;
 * the launch bounce runs independently on its own translate offset.
 */
Item {
    id: root

    property bool hovered: false
    property bool pressed: false
    property bool launching: false
    property bool dragging: false

    property real hoverScale: 1.15
    property real pressScale: 0.92

    default property alias content: contentContainer.data

    readonly property real targetScale: dragging ? 1.0 : pressed ? pressScale : hovered ? hoverScale : 1.0

    // Hover lift target; springs via its own Behavior.
    property real liftOffset: (!dragging && hovered && !pressed) ? -Appearance.spacing.space50 : 0
    Behavior on liftOffset {
        NumberAnimation {
            duration: Appearance.animation.elementMoveSmall.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveFastSpatial
        }
    }

    // Launch bounce rides a separate offset so it composes with the lift.
    property real bounceOffset: 0
    SequentialAnimation {
        running: root.launching && !root.dragging
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation {
            target: root
            property: "bounceOffset"
            to: -Appearance.spacing.space100
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
        NumberAnimation {
            target: root
            property: "bounceOffset"
            to: 0
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
        PauseAnimation {
            duration: Appearance.animation.elementMoveFast.duration
        }
    }

    // One-shot appear pop; consumer calls playAppear() (gated by
    // DockLaunchTracker.firstAppearance) from its Component.onCompleted.
    property real appearScale: 1
    property real appearOpacity: 1
    function playAppear() {
        appearAnimation.restart();
    }
    ParallelAnimation {
        id: appearAnimation
        NumberAnimation {
            target: root
            property: "appearScale"
            from: 0.6
            to: 1
            duration: Appearance.animation.elementMoveEnter.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
        }
        NumberAnimation {
            target: root
            property: "appearOpacity"
            from: 0
            to: 1
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
    }

    Item {
        id: contentContainer
        anchors.fill: parent
        scale: root.targetScale * root.appearScale
        opacity: root.appearOpacity
        transform: Translate {
            y: root.liftOffset + root.bounceOffset
        }
        Behavior on scale {
            enabled: !root.dragging && !appearAnimation.running
            NumberAnimation {
                // Fast, non-bouncy on the way into a press; springy overshoot out.
                duration: root.pressed ? Appearance.animation.elementMoveFast.duration
                                       : Appearance.animation.elementMoveSmall.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: root.pressed ? Appearance.animationCurves.expressiveEffects
                                                 : Appearance.animationCurves.expressiveFastSpatial
            }
        }
    }
}
```

Note for the implementer: `emphasizedDecel` already exists in
`Appearance.animationCurves` (used by `elementMoveEnter`) — verify with
`grep -n emphasizedDecel modules/common/Appearance.qml` and if the exported
name differs, use the exact existing name.

- [ ] **Step 3: Run the test**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && python3 tests/test_dock_motion.py`
Expected: all tracker + motion checks PASS; only consumer checks still FAIL.

- [ ] **Step 4: Syntax-check via the QML import lint**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && ./tests/lint_qml_imports.sh`
Expected: exit 0 (DockIconMotion references `Appearance.*` and imports `qs.modules.common`).

- [ ] **Step 5: Commit**

```bash
cd ~/dev/imi-unify
git add dots/.config/quickshell/ii/modules/common/widgets/DockIconMotion.qml
git commit -m "feat(dock): add DockIconMotion expressive feedback wrapper"
```

---

### Task 3: Wire DockAppButton (running unpinned apps)

**Files:**
- Modify: `dots/.config/quickshell/ii/modules/common/widgets/DockAppButton.qml`

Current structure (for orientation): `DockButton` (a `RippleButton`) with a
hover `MouseArea` Loader (active when the app has windows), `onClicked` /
`middleClickAction` launch paths, and a `contentItem` Loader containing the
icon (`iconImageLoader`), an optional monochrome overlay, and the count-dot
`RowLayout`.

- [ ] **Step 1: Enable hover and wrap the content in DockIconMotion**

In `DockAppButton.qml`:

a) After the `enabled: !isSeparator` line (line ~23), add:

```qml
    hoverEnabled: true
```

(`RippleButton` is a QQC2 `Button`; `root.hovered` then tracks the pointer, and
the button's own background hover tint follows — same pattern DragApps'
DockButton already uses.)

b) Replace the `contentItem` Loader's `sourceComponent: Item { ... }` wrapper so
everything sits inside a `DockIconMotion`. The full new `contentItem` block:

```qml
    contentItem: Loader {
        active: !isSeparator
        sourceComponent: DockIconMotion {
            id: iconMotion
            anchors.fill: parent
            hovered: root.hovered
            pressed: root.down
            launching: DockLaunchTracker.isLaunching(root.appToplevel.appId)

            Component.onCompleted: {
                if (DockLaunchTracker.firstAppearance(root.appToplevel.appId))
                    playAppear();
            }

            Item {
                anchors.centerIn: parent
                width: root.iconSize
                height: root.iconSize

                Loader {
                    id: iconImageLoader
                    anchors {
                        left: parent.left
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                    }
                    active: !root.isSeparator
                    sourceComponent: IconImage {
                        source: Quickshell.iconPath(AppSearch.guessIcon(appToplevel.appId), "image-missing")
                        implicitSize: root.iconSize
                    }
                }

                Loader {
                    active: Config.options.dock.monochromeIcons
                    anchors.fill: iconImageLoader
                    sourceComponent: Item {
                        Desaturate {
                            id: desaturatedIcon
                            visible: false // There's already color overlay
                            anchors.fill: parent
                            source: iconImageLoader
                            desaturation: 0.8
                        }
                        ColorOverlay {
                            anchors.fill: desaturatedIcon
                            source: desaturatedIcon
                            color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                        }
                    }
                }

                RowLayout {
                    spacing: Appearance.spacing.space50
                    anchors {
                        top: iconImageLoader.bottom
                        topMargin: Appearance.spacing.space25
                        horizontalCenter: parent.horizontalCenter
                    }
                    Repeater {
                        model: Math.min(appToplevel.toplevels.length, 3)
                        delegate: Rectangle {
                            required property int index
                            radius: Appearance.rounding.full
                            implicitWidth: (appToplevel.toplevels.length <= 3) ?
                                root.countDotWidth : root.countDotHeight // Circles when too many
                            implicitHeight: root.countDotHeight
                            color: appIsActive ? Appearance.colors.colPrimary : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                            Behavior on implicitWidth {
                                animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                            }
                            Behavior on color {
                                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                            }
                        }
                    }
                }
            }
        }
    }
```

Notes:
- The inner `Item` previously used `anchors.centerIn: parent` with implicit
  size from children; giving it explicit `width/height: root.iconSize` keeps
  the icon centered inside the motion wrapper (which is `anchors.fill`ed) —
  behavior unchanged, dots still hang below via their own anchor.
- The monochrome overlay stays inside the wrapper so it transforms with the
  icon (spec guard).
- `DockLaunchTracker` needs no new import: `DockAppButton.qml` already has
  `import qs.services`.

- [ ] **Step 2: Mark launches in both launch paths**

In `onClicked` (currently `if (appToplevel.toplevels.length === 0) { root.desktopEntry?.execute(); return; }`) and `middleClickAction`, add the tracker call:

```qml
    onClicked: {
        if (appToplevel.toplevels.length === 0) {
            DockLaunchTracker.markLaunching(appToplevel.appId);
            root.desktopEntry?.execute();
            return;
        }
        lastFocused = (lastFocused + 1) % appToplevel.toplevels.length
        appToplevel.toplevels[lastFocused].activate()
    }

    middleClickAction: () => {
        DockLaunchTracker.markLaunching(appToplevel.appId);
        root.desktopEntry?.execute();
    }
```

- [ ] **Step 3: Run the contract test**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && python3 tests/test_dock_motion.py`
Expected: all DockAppButton checks PASS; only the DragApps checks still FAIL.

- [ ] **Step 4: Run the QML lints**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && ./tests/lint_qml_imports.sh && python3 tests/lint_spacing.py`
Expected: both exit 0.

- [ ] **Step 5: Commit**

```bash
cd ~/dev/imi-unify
git add dots/.config/quickshell/ii/modules/common/widgets/DockAppButton.qml
git commit -m "feat(dock): expressive feedback motion on running-app buttons"
```

---

### Task 4: Wire DragApps (pinned apps)

**Files:**
- Modify: `dots/.config/quickshell/ii/modules/common/widgets/DragApps.qml`

- [ ] **Step 1: Wrap the pinned delegate's contentItem**

In the `DockButton { id: dockBtn ... }` delegate, replace its `contentItem`
(currently `Item { IconImage; monochrome Loader; dots RowLayout }`) with:

```qml
                contentItem: DockIconMotion {
                    id: pinnedIconMotion
                    anchors.fill: parent
                    hovered: dockBtn.hovered
                    pressed: dockBtn.down
                    dragging: root._dragging
                    launching: DockLaunchTracker.isLaunching(slotItem.appId)

                    Component.onCompleted: {
                        if (DockLaunchTracker.firstAppearance(slotItem.appId))
                            playAppear();
                    }

                    Item {
                        anchors.centerIn: parent
                        width: 33
                        height: 33

                        IconImage {
                            id: appIcon
                            anchors.centerIn: parent
                            source: Quickshell.iconPath(
                                AppSearch.guessIcon(slotItem.appId),
                                "image-missing")
                            implicitSize: 33
                        }

                        Loader {
                            active: Config.options.dock.monochromeIcons
                            anchors.fill: appIcon
                            sourceComponent: Item {
                                Desaturate {
                                    id: desaturatedIcon
                                    visible: false
                                    anchors.fill: parent
                                    source: appIcon
                                    desaturation: 0.8
                                }
                                ColorOverlay {
                                    anchors.fill: desaturatedIcon
                                    source: desaturatedIcon
                                    color: ColorUtils.transparentize(Appearance.colors.colPrimary, 0.9)
                                }
                            }
                        }

                        RowLayout {
                            spacing: Appearance.spacing.space50
                            anchors {
                                top: appIcon.bottom
                                topMargin: Appearance.spacing.space25
                                horizontalCenter: parent.horizontalCenter
                            }
                            Repeater {
                                model: Math.min(slotItem.appEntry?.toplevels?.length ?? 0, 3)
                                delegate: Rectangle {
                                    required property int index
                                    radius:         Appearance.rounding.full
                                    implicitWidth:  (slotItem.appEntry?.toplevels?.length ?? 0) <= 3
                                                    ? 10 : 4
                                    implicitHeight: 4
                                    color: slotItem.appActive
                                           ? Appearance.colors.colPrimary
                                           : ColorUtils.transparentize(Appearance.colors.colOnLayer0, 0.4)
                                    Behavior on implicitWidth {
                                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                                    }
                                    Behavior on color {
                                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                                    }
                                }
                            }
                        }
                    }
                }
```

(The `33` icon size and `10/4` dot sizes are the file's existing literals —
keep them as-is; retokenizing them is the separate standardization initiative,
not this task.)

- [ ] **Step 2: Mark launches in both pinned launch paths**

```qml
                onClicked: {
                    const entry = slotItem.appEntry
                    if (!entry || entry.toplevels.length === 0) {
                        DockLaunchTracker.markLaunching(slotItem.appId)
                        slotItem.deskEntry?.execute()
                        return
                    }
                    const next = (slotItem._lastFocused + 1) % entry.toplevels.length
                    slotItem._lastFocused = next
                    entry.toplevels[next].activate()
                }

                middleClickAction: () => {
                    DockLaunchTracker.markLaunching(slotItem.appId)
                    slotItem.deskEntry?.execute()
                }
```

(`DragApps.qml` already has `import qs.services` — no import change.)

- [ ] **Step 3: Run the contract test — everything green**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && python3 tests/test_dock_motion.py`
Expected: "All dock motion contract tests passed", exit 0.

- [ ] **Step 4: Run the QML lints**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && ./tests/lint_qml_imports.sh && python3 tests/lint_spacing.py`
Expected: both exit 0.

- [ ] **Step 5: Commit**

```bash
cd ~/dev/imi-unify
git add dots/.config/quickshell/ii/modules/common/widgets/DragApps.qml
git commit -m "feat(dock): expressive feedback motion on pinned-app buttons"
```

---

### Task 5: Suite wiring, full test run, live verification, changelog

**Files:**
- Modify: `dots/.config/quickshell/ii/tests/run_tests.sh`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Wire the new test into run_tests.sh**

In `dots/.config/quickshell/ii/tests/run_tests.sh`, after the "default config
tests" block, add:

```bash
echo "Running dock motion contract tests..."
if ! python3 "$SCRIPT_DIR/test_dock_motion.py"; then
    echo "Dock motion contract tests failed."
    exit 1
fi
```

- [ ] **Step 2: Run the full suite**

Run: `cd ~/dev/imi-unify/dots/.config/quickshell/ii && ./tests/run_tests.sh`
Expected: "All tests passed successfully!", exit 0.

- [ ] **Step 3: Changelog entry**

In `CHANGELOG.md` under `## [Unreleased]` → `### Added`, append:

```markdown
- Dock feedback motion (M3 Expressive): hover lift, press squish, a launch
  bounce that runs until the app's window appears, an appear pop for new
  icons, and springing active-window dots — consistent across pinned and
  running apps, all on Appearance motion tokens.
```

- [ ] **Step 4: Commit**

```bash
cd ~/dev/imi-unify
git add dots/.config/quickshell/ii/tests/run_tests.sh CHANGELOG.md
git commit -m "test(dock): wire dock motion contracts into suite; changelog"
```

- [ ] **Step 5: Live verification (controller/user step — NOT for a subagent)**

Deploy the four changed/new QML files to the live config in one batch (single
hot reload), then visually verify:

```bash
rsync -a ~/dev/imi-unify/dots/.config/quickshell/ii/services/DockLaunchTracker.qml ~/.config/quickshell/ii/services/
rsync -a ~/dev/imi-unify/dots/.config/quickshell/ii/modules/common/widgets/DockIconMotion.qml ~/.config/quickshell/ii/modules/common/widgets/
rsync -a ~/dev/imi-unify/dots/.config/quickshell/ii/modules/common/widgets/DockAppButton.qml ~/.config/quickshell/ii/modules/common/widgets/
rsync -a ~/dev/imi-unify/dots/.config/quickshell/ii/modules/common/widgets/DragApps.qml ~/.config/quickshell/ii/modules/common/widgets/
```

Check the live log for QML errors: `tail -n 50 /run/user/1000/quickshell/by-id/*/log.log`

Ask the user to confirm: hover lift, press squish, launch bounce on a
slow-starting app (stops when the window maps; never exceeds ~10 s), appear
pop when a new app opens (and no mass re-pop when a second window opens),
dots springing on focus change, drag-reorder unaffected.
```

---

## Verification checklist (post-plan)

- Spec coverage: hover lift (T2+T3+T4), press squish (T2), launch bounce +
  tracker + timeout (T1+T2), appear pop + replay gate (T1+T2+T3+T4),
  active-dot springs (T3+T4), drag suppression (T4), monochrome overlay
  inside wrapper (T3+T4), token-only motion (contract test), run_tests.sh
  wiring (T5). Exit animation for removed buttons: out of scope per spec.
- All commits follow repo convention, no agent attribution.
