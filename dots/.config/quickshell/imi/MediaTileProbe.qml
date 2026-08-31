import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common

ShellRoot {
    FloatingWindow {
        id: win
        title: "MediaTileProbe"
        implicitWidth: 480
        implicitHeight: 300
        color: "transparent"
        Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer0 }
        // File-URL Loaders, not a directory import: the plugin dir is
        // hyphenated ("nandoroid-media"), which is not a legal QML module
        // segment - lint_qml_module_dirs.py is right to refuse it.
        Loader {
            id: tileLoader
            x: 24; y: 24
            source: Qt.resolvedUrl("modules/common/plugins/bundled/nandoroid-media/Widget.qml")
            onLoaded: item.hostGridSize = "1x1"
            width: item ? item.implicitWidth : 0
            height: item ? item.implicitHeight : 0
        }
        Loader {
            id: compactLoader
            x: 180; y: 24
            source: Qt.resolvedUrl("modules/common/plugins/bundled/nandoroid-media/Widget.qml")
            onLoaded: item.hostGridSize = "2x1"
            width: item ? item.implicitWidth : 0
            height: item ? item.implicitHeight : 0
        }
        IpcHandler {
            target: "probe"
            function geo(): string {
                const p = win.contentItem.mapFromItem(tileLoader, 0, 0);
                return `tile ${p.x} ${p.y} ${tileLoader.width} ${tileLoader.height}`;
            }
            function span(s: string): string {
                if (tileLoader.item) tileLoader.item.hostGridSize = s;
                return "ok";
            }
        }
    }
}
