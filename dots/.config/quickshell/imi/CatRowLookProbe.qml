import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.plugins
import qs.modules.imi.editMode
import qs.modules.imi.settings.pages
import "modules/common/functions/edit_mode.js" as EditMode

// Throwaway: photographs the three catalogue surfaces so the shared row can be
// looked at rather than reasoned about.
ShellRoot {
    id: probe

    readonly property string outDir: "/tmp/claude-1000/-home-xephy--config-quickshell-end4-pC/c753f5a7-f08a-4445-bbee-d47e734906f0/scratchpad/"
    property int shots: 0

    function shoot(name, item) {
        item.grabToImage(result => {
            result.saveToFile(probe.outDir + name + ".png");
            console.log("[LOOK] saved " + name + " " + Math.round(item.width)
                + "x" + Math.round(item.height));
            probe.shots += 1;
            if (probe.shots >= 3) {
                console.log("[LOOK] done");
                Qt.quit();
            }
        });
    }

    FloatingWindow {
        id: drawerWin
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
            area: Qt.rect(0, 0, drawerWin.width, drawerWin.height)
            drawer: Qt.rect(1100, 120, 370, 960)
            bandFraction: EditMode.chromeBandFraction({
                margin: Appearance.sizes.editModeMargin,
                edgeMargin: Appearance.sizes.editModeEdgeMargin
            })
        }
    }

    FloatingWindow {
        id: settingsWin
        implicitWidth: 900
        implicitHeight: 1100
        visible: true

        Rectangle {
            anchors.fill: parent
            color: Appearance.m3colors.m3background

            PluginsPage {
                id: pluginsPage
                anchors.fill: parent
                anchors.margins: 16
            }
        }
    }

    FloatingWindow {
        id: storeWin
        implicitWidth: 900
        implicitHeight: 1100
        visible: true

        Rectangle {
            anchors.fill: parent
            color: Appearance.m3colors.m3background

            PluginStorePage {
                id: storePage
                anchors.fill: parent
                anchors.margins: 16
            }
        }
    }

    Timer {
        running: true
        interval: 2500
        onTriggered: {
            // The registry is a network fetch this probe must not make, so the
            // cards are drawn from a seeded catalogue instead.
            PluginStore.entries = [
                {
                    id: "aurora-clock", name: "Aurora Clock", version: "2.4.1",
                    author: "someone", icon: "schedule", featured: true,
                    description: "A clock that follows the wallpaper's palette, with a depth cutout.",
                    capabilities: ["desktop-widget", "bar-widget"],
                    permissions: ["network"],
                    manifestUrl: "https://example.invalid/manifest.json"
                },
                {
                    id: "a-widget-with-a-considerably-longer-name-than-fits",
                    name: "A widget with a considerably longer name than fits on one line",
                    version: "0.1.0",
                    author: "somebody with a long byline / and a contributors note",
                    icon: "extension",
                    description: "Second card, to show two of them next to each other.",
                    capabilities: ["overlay-widget"], permissions: [],
                    manifestUrl: "https://example.invalid/two.json"
                }
            ];
        }
    }

    Timer {
        running: true
        interval: 5000
        onTriggered: {
            probe.shoot("catrow-drawer", chrome.drawerItem);
            probe.shoot("catrow-settings", pluginsPage);
            probe.shoot("catrow-store", storePage);
        }
    }
}
