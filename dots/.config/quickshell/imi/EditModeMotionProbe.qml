import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.imi.editMode
import "modules/common/functions/edit_mode.js" as EditMode

/*
 * The drawer's reveal and the desktop's sideways travel, sampled per frame.
 *
 * Edit Mode has no IPC handler and is entered from the desktop's right-click
 * menu, so nothing outside the shell can drive it. This builds the REAL
 * `EditModeChromeContent` against the REAL `edit_mode.js` geometry, driven by
 * the REAL `GlobalStates.editDrawerProgress` Behavior on its real tier - only
 * the trigger is synthetic. It writes the singleton the menu writes.
 *
 * Two channels per frame, because the defect is that they disagree: the
 * drawer's own left edge (what the panel does) and `editShift` (what the
 * desktop does). The clamp inside `drawerRect` used to freeze the first while
 * the second was still overshooting.
 */
ShellRoot {
    FloatingWindow {
        id: win
        // Fixed size, so the geometry a run reports is the geometry the next
        // run reports: a FloatingWindow whose minimumSize equals its
        // maximumSize is floated and sized by Hyprland from the size hints
        // alone (AGENT.md, Hyprland integration).
        implicitWidth: 1600
        implicitHeight: 900
        minimumSize: Qt.size(1600, 900)
        maximumSize: Qt.size(1600, 900)
        visible: true
        color: "#101014"

        readonly property var viewport: EditMode.viewportGeometry({
            screenWidth: win.width,
            screenHeight: win.height,
            drawerWidth: Appearance.sizes.editModeDrawerWidth,
            margin: Appearance.sizes.editModeMargin,
            edgeMargin: Appearance.sizes.editModeEdgeMargin,
            chromeThickness: Appearance.sizes.toolbarHeight
        })
        readonly property real editShift: EditMode.drawerTravel(win.viewport)
            * GlobalStates.editDrawerProgress

        property real t0: 0
        property bool sampling: false
        property var samples: []

        Component.onCompleted: {
            GlobalStates.editMode = true;
            GlobalStates.editProgress = 1;
        }

        EditModeChromeContent {
            id: chrome
            anchors.fill: parent
            card: EditMode.cardRect(win.viewport, GlobalStates.editProgress,
                win.width, win.height, win.editShift)
            drawer: EditMode.drawerRect(win.viewport, GlobalStates.editProgress,
                GlobalStates.editDrawerProgress, win.width, win.height)
            area: EditMode.areaRect(win.viewport, GlobalStates.editProgress,
                win.width, win.height)
            bandFraction: EditMode.chromeBandFraction(win.viewport)
        }

        // The drawer's own column, found by shape rather than by id: the probe
        // reaches across a component boundary, and an id would be a second copy
        // of the drawer's internals to keep right.
        function columnOf(item) {
            for (const child of item.children) {
                if (child.toString().startsWith("QQuickColumnLayout"))
                    return child;
                const found = win.columnOf(child);
                if (found)
                    return found;
            }
            return null;
        }

        FrameAnimation {
            running: win.sampling
            onTriggered: {
                const ms = Date.now() - win.t0;
                let appears = "";
                const column = win.columnOf(chrome.drawerItem);
                if (column) {
                    for (const child of column.children) {
                        if (child.appear === undefined || !child.visible)
                            continue;
                        appears += " " + child.appear.toFixed(3);
                    }
                }
                win.samples.push(ms + " " + chrome.drawerItem.x.toFixed(2)
                    + " " + chrome.drawerItem.width.toFixed(2)
                    + " " + win.editShift.toFixed(2)
                    + " " + GlobalStates.editDrawerProgress.toFixed(5)
                    + " |" + appears);
            }
        }

        function dump(tag) {
            console.log("[MOTION] " + tag + " begin");
            for (const line of win.samples)
                console.log("[MOTION] " + tag + " " + line);
            console.log("[MOTION] " + tag + " end");
            win.samples = [];
        }

        SequentialAnimation {
            running: true
            PauseAnimation { duration: 3000 }
            ScriptAction { script: { win.t0 = Date.now(); win.sampling = true;
                GlobalStates.editDrawerOpen = true; } }
            PauseAnimation { duration: 900 }
            ScriptAction { script: { win.sampling = false; win.dump("OPEN"); } }
            PauseAnimation { duration: 600 }
            ScriptAction { script: { win.t0 = Date.now(); win.sampling = true;
                GlobalStates.editDrawerOpen = false; } }
            PauseAnimation { duration: 900 }
            ScriptAction { script: { win.sampling = false; win.dump("CLOSE");
                console.log("[MOTION] done"); } }
        }
    }
}
