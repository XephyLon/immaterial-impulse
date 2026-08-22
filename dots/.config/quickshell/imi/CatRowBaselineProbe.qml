import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets

// Throwaway: reads ConfigSwitch's geometry back out of a real window so the
// CatalogueRow extraction can be proven not to move a single settings row.
ShellRoot {
    FloatingWindow {
        id: win
        implicitWidth: 700
        implicitHeight: 900
        visible: true

        ColumnLayout {
            id: column
            anchors.fill: parent
            spacing: 0

            ConfigSwitch {
                id: plain
                Layout.fillWidth: true
                text: "Plain row"
                checked: true
            }
            ConfigSwitch {
                id: described
                Layout.fillWidth: true
                buttonIcon: "grid_4x4"
                text: "Row with an icon and a description"
                description: "A description long enough to wrap onto a second line when the window is only seven hundred pixels wide."
                checked: false
            }
            ConfigSwitch {
                id: informed
                Layout.fillWidth: true
                buttonIcon: "blur_on"
                text: "Row with info and trailing"
                infoText: "An explanation"
                trailingContent: [
                    MaterialSymbol { text: "upgrade"; iconSize: 20 }
                ]
                titleContent: [
                    StyledText { text: "v1.2.3"; font.pixelSize: Appearance.font.pixelSize.smaller }
                ]
                detailContent: [
                    Badge { label: "Desktop"; badgeIcon: "widgets" }
                ]
            }
            ConfigSwitch {
                id: disabled
                Layout.fillWidth: true
                enabled: false
                buttonIcon: "opacity"
                text: "Disabled row"
                description: "Short."
            }
            Item { Layout.fillHeight: true }
        }

        function report(name, row) {
            console.log("[CATROW] " + name
                + " implicitH=" + row.implicitHeight.toFixed(2)
                + " h=" + row.height.toFixed(2)
                + " contentH=" + row.contentItem.implicitHeight.toFixed(2)
                + " contentW=" + row.contentItem.width.toFixed(2)
                + " opacity=" + row.opacity.toFixed(3));
        }

        Timer {
            running: true
            interval: 2000
            onTriggered: {
                win.report("plain", plain);
                win.report("described", described);
                win.report("informed", informed);
                win.report("disabled", disabled);
                console.log("[CATROW] done");
                Qt.quit();
            }
        }
    }
}
