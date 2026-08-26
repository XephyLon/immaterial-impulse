import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.imi.sidebarRight.notifications
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property int entranceTrigger: -1
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer1

    // The column hands this section whatever height is left after the
    // fixed-height ones - banner, toggles, sliders, the media player, the
    // bottom group expanded - and that can be nothing. The list inside kept
    // painting its unclipped parts around a rectangle with no area: the
    // empty state's bell and "Nothing", and the "0 notifications" pill,
    // drawn over the media player and the bottom group's tabs. Clipped now,
    // and the list stands down below the height at which it could show its
    // status row and one line above it, so a sliver never shows a cut pill.
    clip: true
    NotificationList {
        id: list
        anchors.fill: parent
        anchors.margins: Appearance.spacing.space100
        visible: root.height >= list.minimumUsefulHeight + Appearance.spacing.space100 * 2
        entranceTrigger: root.entranceTrigger
    }
}
