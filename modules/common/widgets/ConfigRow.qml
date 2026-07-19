import QtQuick
import QtQuick.Layouts
import qs.modules.common

RowLayout {
    property bool uniform: false
    spacing: Appearance.spacing.space50
    uniformCellSizes: uniform
}
