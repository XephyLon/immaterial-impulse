import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.imi.phone
import qs.modules.imi.sidebarLeft.phone
import Quickshell.Io

ShellRoot {
    FloatingWindow {
        id: win
        implicitWidth: 440
        implicitHeight: 520
        color: "transparent"
        Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer1 }

        readonly property var galaxy: ({ id: "g", name: "Galaxy S23 Ultra", type: "phone", paired: true, reachable: true,
            cellularNetworkType: "LTE", reachableAddresses: [], batteryAvailable: true, batteryCharge: 75, batteryCharging: false })
        readonly property var laptop: ({ id: "l", name: "Laptop", type: "laptop", paired: false, reachable: false, batteryAvailable: false })

        IpcHandler {
            target: "probe"
            function buttons(): string {
                const out = [];
                function walk(o) {
                    const n = `${o}`.split("(")[0];
                    if (n.startsWith("NotificationActionButton") || n.startsWith("ToolbarTextField")) {
                        const p = o.mapToItem(null, 0, 0);
                        out.push(`${n.replace(/_QMLTYPE.*/, "")} x ${p.x.toFixed(0)} y ${p.y.toFixed(0)} w ${o.width.toFixed(0)} h ${o.height.toFixed(0)} iw ${o.implicitWidth.toFixed(0)} vis ${o.visible} op ${o.opacity.toFixed(2)} en ${o.enabled}`);
                    }
                    for (const c of o.children ?? []) walk(c);
                }
                walk(win.contentItem);
                return out.join("\n");
            }
        }
        ColumnLayout {
            anchors { top: parent.top; left: parent.left; margins: Appearance.spacing.space200 }
            width: 380
            spacing: Appearance.spacing.space150

            PhoneHeader { id: header; Layout.fillWidth: true; device: win.galaxy; rosterOpen: true }

            GroupedList {
                Layout.fillWidth: true
                model: [win.galaxy, win.laptop]
                rowDelegate: Component {
                    PhoneDeviceItem {
                        property var modelData: null
                        device: modelData
                        active: modelData?.id === "g"
                    }
                }
            }

            NotificationItem {
                id: card
                Layout.fillWidth: true
                expanded: true
                replying: true
                controller: PhoneNotificationController {}
                notificationObject: ({ publicId: "1", appName: "Peachy", summary: "Lmao", body: "Test eh msh fahem",
                    urgency: 0, replyId: "r1", actions: [], image: "", appIcon: "", time: Date.now(), notificationId: 1 })
            }
            Item { Layout.fillHeight: true }
        }
    }
}
