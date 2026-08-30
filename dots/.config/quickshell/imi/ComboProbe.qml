import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.widgets

ShellRoot {
    FloatingWindow {
        id: win
        title: "ComboProbe"
        implicitWidth: 420
        implicitHeight: 320
        color: "transparent"
        Rectangle { anchors.fill: parent; color: Appearance.colors.colLayer1 }
        ColumnLayout {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 24 }
            ConfigComboBox {
                id: combo
                Layout.fillWidth: true
                text: "Bitrate"
                buttonIcon: "speed"
                model: [ { displayName: "2 Mbps", value: 2 }, { displayName: "4 Mbps", value: 4 },
                         { displayName: "8 Mbps", value: 8, recommended: true }, { displayName: "16 Mbps", value: 16 } ]
                currentValue: 8
            }
        }
        Component { id: plainBg; Rectangle { radius: 20; color: Appearance.colors.colSecondaryContainer } }
        IpcHandler {
            target: "probe"
            function box(): string {
                const c = combo.comboBox ?? null;
                if (!c) return "nocombo";
                const p = c.mapToItem(null, 0, 0);
                return `${p.x} ${p.y} ${c.width} ${c.height} popup=${c.popup.visible} index=${c.currentIndex} pressed=${c.pressed}`;
            }
            function noScale(): string { combo.comboBox.transform = []; return "ok"; }
            function plainBackground(): string {
                combo.comboBox.background = plainBg.createObject(combo.comboBox);
                return "ok";
            }
            function reveal(): string {
                const pp = combo.comboBox.popup;
                return `${pp.visible} ${pp.reveal.toFixed(3)} ${pp.opacity.toFixed(3)}`;
            }
            function open(): string { combo.comboBox.popup.open(); return "ok"; }
            function close(): string { combo.comboBox.popup.close(); return "ok"; }
            function rows(): string {
                const c = combo.comboBox;
                const lv = c.popup.contentItem;
                let out = [];
                for (let i = 0; i < lv.count; i++) {
                    const it = lv.itemAtIndex(i);
                    if (!it) continue;
                    const p = it.mapToItem(null, 0, 0);
                    out.push(`${i}:${p.x},${p.y},${it.width},${it.height}`);
                }
                return out.join(" ");
            }
        }
    }
}
