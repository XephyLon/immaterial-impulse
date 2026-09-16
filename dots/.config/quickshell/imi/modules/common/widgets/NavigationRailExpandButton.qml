import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

IconButton {
    id: root
    Layout.alignment: Qt.AlignLeft
    Layout.leftMargin: Appearance.spacing.space100
    iconSize: Appearance.font.pixelSize.huge
    buttonIcon: root.parent.expanded ? "menu_open" : "menu"
    downAction: () => {
        parent.expanded = !parent.expanded;
    }

    rotation: root.parent.expanded ? 0 : -180
    Behavior on rotation {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }
}
