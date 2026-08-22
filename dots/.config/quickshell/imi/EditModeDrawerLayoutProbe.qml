import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.modules.imi.editMode
import "modules/common/functions/edit_mode.js" as EditMode

/*
 * What the drawer's column gives its list, in pixels.
 *
 * The drawer is a ColumnLayout of three chrome rows and one ListView per
 * section. `QtQuick.Layouts` defaults `Layout.fillHeight` to TRUE for a Layout
 * nested in a Layout, so the header row, the section tabs and the bar's bucket
 * picker all fill unless they say otherwise - and they compete with the list,
 * whose own implicitHeight is 0. The tab row won: it took 831 of 936 px, the
 * list was left 24, and the toggled section chip - `leftRadius: height / 2` -
 * painted an 831px stadium down the whole panel.
 *
 * Nothing in the source shows it. Every binding involved is correct on its own,
 * the failure is a distribution, and it is only visible as a picture. So this
 * probe reads the geometry back out of a real EditModeChromeContent and
 * tests/test_edit_mode_drawer_layout.py asserts what the numbers must be.
 */
ShellRoot {
    FloatingWindow {
        id: win
        implicitWidth: 1500
        implicitHeight: 1200
        visible: true

        Component.onCompleted: {
            GlobalStates.editMode = true;
            GlobalStates.editDrawerOpen = true;
            GlobalStates.editProgress = 1;
        }

        EditModeChromeContent {
            id: chrome
            anchors.fill: parent
            card: Qt.rect(120, 120, 900, 900)
            area: Qt.rect(0, 0, win.width, win.height)
            drawer: Qt.rect(1100, 120, 370, 960)
            // This probe hands the chrome hand-written rects rather than a
            // geometry, so it states the split from the same two tokens the
            // geometry would have derived it from.
            bandFraction: EditMode.chromeBandFraction({
                margin: Appearance.sizes.editModeMargin,
                edgeMargin: Appearance.sizes.editModeEdgeMargin
            })
        }

        // The drawer's own column, found by shape rather than by id: the probe
        // reaches across a component boundary, and an id would be a second
        // copy of the drawer's internals to keep right.
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

        Timer {
            running: true
            interval: 2500
            onTriggered: {
                const column = win.columnOf(chrome.drawerItem);
                if (!column) {
                    console.log("[DRAWER] no column found");
                    Qt.quit();
                    return;
                }
                console.log("[DRAWER] column h=" + Math.round(column.height));
                for (const child of column.children) {
                    if (!child.visible)
                        continue;
                    console.log("[DRAWER] child " + child.toString().split("(")[0]
                        + " h=" + Math.round(child.height));
                }
                console.log("[DRAWER] done");
                Qt.quit();
            }
        }
    }
}
