import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

RowLayout {
    id: root
    spacing: Appearance.spacing.verysmall

    // These shouldn't be needed but it would be a terrible waste of space to follow the spec
    Layout.margins: -Appearance.spacing.small
    Layout.topMargin: 0
}
