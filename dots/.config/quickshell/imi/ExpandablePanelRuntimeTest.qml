import QtQuick
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

/**
 * Builds ExpandablePanel for real and drives it through expand and collapse.
 * The source contract only greps; neither it nor the QML suite can prove the
 * height actually animates or that collapsed content is disabled.
 */
ShellRoot {
    id: harness

    property int failures: 0
    property real collapsedHeight: 0

    function check(label, ok) {
        console.log(`[ExpandablePanel] ${label}: ${ok ? "ok" : "FAIL"}`);
        if (!ok)
            harness.failures++;
    }

    // Qt's `enabled` reads an item's OWN value, not the effective state
    // inherited from ancestors, so asking a content child whether it is
    // enabled always answers true. Find the clipped panel itself instead -
    // it is the item that carries `enabled: root.expanded`.
    function clippedPanel(item, depth) {
        if (!item || depth > 6)
            return null;
        const kids = item.children ?? [];
        for (let i = 0; i < kids.length; i++) {
            if (kids[i].clip === true)
                return kids[i];
            const found = harness.clippedPanel(kids[i], depth + 1);
            if (found)
                return found;
        }
        return null;
    }

    FloatingWindow {
        visible: true
        implicitWidth: 420
        implicitHeight: 260
        color: "transparent"

        ExpandablePanel {
            id: panel
            anchors.centerIn: parent
            width: 360
            outline: true

            header: [
                StyledText {
                    text: "Header"
                    color: Appearance.colors.colOnLayer1
                }
            ]

            Rectangle {
                implicitHeight: 80
                implicitWidth: 200
                color: "transparent"
            }
        }
    }

    Timer {
        interval: 600
        running: true
        onTriggered: {
            harness.collapsedHeight = panel.implicitHeight;
            harness.check("collapsed content is disabled",
                          harness.clippedPanel(panel, 0)?.enabled === false);
            panel.expanded = true;
        }
    }

    Timer {
        interval: 1600
        running: true
        onTriggered: {
            harness.check("expanding grows the panel",
                          panel.implicitHeight > harness.collapsedHeight);
            harness.check("expanded content is enabled",
                          harness.clippedPanel(panel, 0)?.enabled === true);
            panel.expanded = false;
        }
    }

    Timer {
        interval: 2600
        running: true
        onTriggered: {
            harness.check("collapsing returns to the original height",
                          Math.abs(panel.implicitHeight - harness.collapsedHeight) < 2);
            harness.check("collapsed content is disabled again",
                          harness.clippedPanel(panel, 0)?.enabled === false);
            Qt.exit(harness.failures === 0 ? 0 : 1);
        }
    }
}
