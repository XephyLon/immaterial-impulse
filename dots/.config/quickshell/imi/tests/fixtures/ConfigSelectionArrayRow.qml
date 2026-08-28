import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: host
    property alias row: sel
    property int hostWidth: 660
    width: hostWidth
    ColumnLayout {
        width: parent.width
        ConfigSelectionArray {
                id: sel
                Layout.fillWidth: true
                // The host's width is only a constraint if the row is
                // told it cannot exceed it: a QQuickLayout hands a child
                // its implicit width when nothing caps it, so without
                // this the "narrow" case is not narrow at all.
                Layout.maximumWidth: host.hostWidth - Appearance.spacing.space400
                text: "Bar position"
                icon: "swap_vert"
                currentValue: "top"
                options: [
                    {"displayName": "Top", "icon": "arrow_upward", "value": "top"},
                    {"displayName": "Left", "icon": "arrow_back", "value": "left"},
                    {"displayName": "Bottom", "icon": "arrow_downward", "value": "bottom"},
                    {"displayName": "Right", "icon": "arrow_forward", "value": "right"}
                ]
        }
    }
}
