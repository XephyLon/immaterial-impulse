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

        // Which column members the wave can reach, named by INDEX rather than by
        // id: the probe reaches across a component boundary and an id list here
        // would be a second copy of the drawer's internals. The type plus the
        // fixed column order is enough to say which row a number belongs to,
        // and printing the participation separately is what makes a member
        // silently dropped from the wave distinguishable from one that simply
        // has nothing to do.
        function memberReport() {
            const column = win.columnOf(chrome.drawerItem);
            if (!column)
                return "no column";
            let out = "";
            for (let i = 0; i < column.children.length; i++) {
                const child = column.children[i];
                const type = child.toString().split("_")[0].split("(")[0];
                out += " " + i + ":" + type
                    + (child.appear === undefined ? ":no-appear"
                        : (child.visible ? ":in" : ":hidden"));
            }
            return out;
        }

        function sample() {
            const ms = Date.now() - win.t0;
            let appears = "";
            const column = win.columnOf(chrome.drawerItem);
            if (column) {
                for (let i = 0; i < column.children.length; i++) {
                    const child = column.children[i];
                    if (child.appear === undefined || !child.visible)
                        continue;
                    appears += " " + i + "=" + child.appear.toFixed(3);
                }
            }
            win.samples.push(ms + " " + chrome.drawerItem.x.toFixed(2)
                + " " + chrome.drawerItem.width.toFixed(2)
                + " " + win.editShift.toFixed(2)
                + " " + GlobalStates.editDrawerProgress.toFixed(5)
                + " |" + appears);
        }

        FrameAnimation {
            running: win.sampling
            onTriggered: win.sample()
        }

        function dump(tag) {
            console.log("[MOTION] " + tag + " members" + win.memberReport());
            console.log("[MOTION] " + tag + " begin");
            for (const line of win.samples)
                console.log("[MOTION] " + tag + " " + line);
            console.log("[MOTION] " + tag + " end");
            win.samples = [];
        }

        SequentialAnimation {
            running: true
            PauseAnimation { duration: 3000 }
            // The control: two frames with nothing running. Anything that
            // differs between these two is the instrument, not the motion -
            // a live-machine measurement without one measures something else.
            ScriptAction { script: { win.t0 = Date.now(); win.sample(); } }
            PauseAnimation { duration: 100 }
            ScriptAction { script: { win.sample(); win.dump("CONTROL"); } }
            PauseAnimation { duration: 200 }
            ScriptAction { script: { win.t0 = Date.now(); win.sampling = true;
                GlobalStates.editDrawerOpen = true; } }
            PauseAnimation { duration: 900 }
            ScriptAction { script: { win.sampling = false; win.dump("OPEN"); } }
            PauseAnimation { duration: 600 }
            ScriptAction { script: { win.t0 = Date.now(); win.sampling = true;
                GlobalStates.editDrawerOpen = false; } }
            PauseAnimation { duration: 900 }
            ScriptAction { script: { win.sampling = false; win.dump("CLOSE"); } }
            // ...and again over the Lock section, which is the one whose rows
            // the catalogue-row and lock-presence work rewrote. The Widgets
            // section above is four visible members; this one is four
            // different ones, two of which are `RippleButton`s that ride the
            // wave through the control's own `appear` rather than through the
            // three channels the drawer dresses its other members with.
            PauseAnimation { duration: 600 }
            ScriptAction { script: { chrome.drawerItem.section = "lock"; } }
            PauseAnimation { duration: 600 }
            ScriptAction { script: { win.t0 = Date.now(); win.sampling = true;
                GlobalStates.editDrawerOpen = true; } }
            PauseAnimation { duration: 900 }
            ScriptAction { script: { win.sampling = false; win.dump("LOCKOPEN");
                console.log("[MOTION] done"); } }
        }
    }
}
