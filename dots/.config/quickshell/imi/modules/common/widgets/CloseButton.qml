import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

/**
 * The close affordance of a whole surface (the Settings window, the
 * cheatsheet, the Modes manager): IconButton with the `close` glyph and a
 * "Close" tooltip. Placement (anchors, margins) is the caller's.
 */
IconButton {
    buttonIcon: "close"
    tooltip: Translation.tr("Close")
    colText: Appearance.colors.colOnLayer0
}
