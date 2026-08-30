import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

// The real Quick page, built the way the settings host builds it (across
// frames), so a Flow that latches narrow latches here too.
ShellRoot {
    FloatingWindow {
        title: "QuickPageProbe"
        implicitWidth: 980
        implicitHeight: 665
        color: "transparent"
        Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer0 }
        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 16
            contentHeight: pageLoader.item?.implicitHeight ?? 0
            clip: true
            Loader {
                id: pageLoader
                width: flick.width
                asynchronous: true
                source: Qt.resolvedUrl("modules/imi/settings/pages/QuickConfig.qml")
            }
        }
        IpcHandler {
            target: "probe"
            function flows(): string {
                const out = [];
                function walk(item, depth) {
                    if (!item) return;
                    if (item.naturalWidth !== undefined)
                        out.push(`w=${item.width.toFixed(0)} h=${item.height.toFixed(0)} natural=${item.naturalWidth.toFixed(0)} lines=${Math.round(item.height / 35)}`);
                    for (let i = 0; i < item.children.length; i++) walk(item.children[i], depth + 1);
                }
                walk(pageLoader.item, 0);
                return out.length ? out.join(" | ") : "no flows (page built: " + (pageLoader.item !== null) + ")";
            }
        }
    }
}
