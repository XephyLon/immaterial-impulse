pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RowLayout {
    id: root

    property var hints: []
    property bool showKeys: true
    property color surface: Appearance.colors.colSurfaceContainerHigh
    property color onSurface: Appearance.colors.colOnSurface

    spacing: Appearance.spacing.space100

    Repeater {
        model: root.hints

        delegate: RowLayout {
            required property var modelData

            spacing: Appearance.spacing.space50

            StyledText {
                text: modelData.label ?? ""
                color: root.onSurface
                font.pixelSize: Appearance.font.pixelSize.smallest
            }

            KeyHint {
                visible: root.showKeys && (modelData.keys ?? []).length > 0
                keys: modelData.keys ?? []
                surface: root.surface
                onSurface: root.onSurface
            }
        }
    }
}
