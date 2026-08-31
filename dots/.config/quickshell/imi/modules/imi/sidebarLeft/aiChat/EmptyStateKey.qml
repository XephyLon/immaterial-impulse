pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

/**
 * One line of the empty state: what the key is, and what it does - keycap
 * chips and a label. The fork's EmptyStateKey, its hand-typed
 * rounding-as-spacing swapped for imi's spacing scale.
 */
Rectangle {
    id: root

    property var keys: []
    property string label: ""
    /** Set when pressing the row does the same thing the key does. */
    property bool actionable: false

    signal triggered

    implicitHeight: Math.round(Appearance.font.pixelSize.huge * 1.6)
    radius: Appearance.rounding.full
    color: rowMouse.containsMouse && root.actionable ? Appearance.colors.colLayer2Hover : "transparent"

    Behavior on color {
        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
    }

    MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.actionable
        cursorShape: root.actionable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.triggered()
    }

    RowLayout {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: Appearance.spacing.space100
        anchors.rightMargin: Appearance.spacing.space150
        spacing: Appearance.spacing.space100

        Repeater {
            model: ScriptModel {
                values: root.keys
            }

            // The cheatsheet's keycap, not a flat colLayer2 chip: on the
            // empty state's own layer the chip was a tone-on-tone rectangle
            // that read as plain text ("These key combinations should be
            // styled as keys").
            delegate: KeyboardKey {
                required property var modelData
                key: modelData
                pixelSize: Appearance.font.pixelSize.smaller
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.label
            elide: Text.ElideRight
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
