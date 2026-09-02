pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Row {
    id: root

    property var keys: ["Ctrl", "K"]
    property color surface: Appearance.colors.colSurfaceContainerHigh
    property color onSurface: Appearance.colors.colOnSurface
    property real pixelSize: Appearance.font.pixelSize.smallest

    spacing: Appearance.spacing.space25

    readonly property color keyFace: ColorUtils.mix(root.surface, root.onSurface, 0.86)
    readonly property color keyText: root.onSurface

    Repeater {
        model: root.keys

        delegate: Rectangle {
            required property string modelData

            implicitWidth: Math.max(label.implicitHeight + Appearance.spacing.space75, label.implicitWidth + Appearance.spacing.space125)
            implicitHeight: label.implicitHeight + Appearance.spacing.space75
            radius: Appearance.rounding.verysmall
            color: root.keyFace

            StyledText {
                id: label
                anchors.centerIn: parent
                text: modelData
                font.pixelSize: root.pixelSize
                font.family: Appearance.font.family.main
                font.weight: Font.Bold
                color: root.keyText
            }
        }
    }
}
