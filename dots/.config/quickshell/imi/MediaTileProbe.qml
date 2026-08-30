import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import "modules/common/plugins/bundled/nandoroid-media" as Media

ShellRoot {
    FloatingWindow {
        id: win
        title: "MediaTileProbe"
        implicitWidth: 480
        implicitHeight: 300
        color: "transparent"
        Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer0 }
        Media.Widget {
            id: tile
            x: 24; y: 24
            hostGridSize: "1x1"
            width: implicitWidth
            height: implicitHeight
        }
        Media.Widget {
            id: compact
            x: 180; y: 24
            hostGridSize: "2x1"
            width: implicitWidth
            height: implicitHeight
        }
        IpcHandler {
            target: "probe"
            function geo(): string {
                const p = win.contentItem.mapFromItem(tile, 0, 0);
                return `tile ${p.x} ${p.y} ${tile.width} ${tile.height}`;
            }
            function span(s: string): string { tile.hostGridSize = s; return "ok"; }
        }
    }
}
