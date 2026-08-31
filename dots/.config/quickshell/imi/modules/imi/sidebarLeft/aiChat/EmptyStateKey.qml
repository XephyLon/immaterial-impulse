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

            // Two kinds of token, two dressings. A real key wears the
            // cheatsheet's keycap (face, border, weighted bottom edge - the
            // flat colLayer2 chip read as plain text on this ground). A
            // COMMAND is not a key ("this isn't a key"): actionable rows
            // carry /key and +, pressed as a row rather than held as a
            // chord, and their token wears a quiet pill instead.
            delegate: Item {
                id: tokenSlot
                required property var modelData
                implicitWidth: root.actionable ? commandChip.implicitWidth : keyFace.implicitWidth
                implicitHeight: root.actionable ? commandChip.implicitHeight : keyFace.implicitHeight

                Rectangle {
                    id: commandChip
                    visible: root.actionable
                    implicitWidth: chipLabel.implicitWidth + Appearance.spacing.space100 * 2
                    implicitHeight: chipLabel.implicitHeight + Appearance.spacing.space25 * 2
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colSecondaryContainer
                    StyledText {
                        id: chipLabel
                        anchors.centerIn: parent
                        text: tokenSlot.modelData
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnSecondaryContainer
                    }
                }
                KeyboardKey {
                    id: keyFace
                    visible: !root.actionable
                    key: tokenSlot.modelData
                    pixelSize: Appearance.font.pixelSize.smaller
                }
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
