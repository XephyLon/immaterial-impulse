import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * A small non-interactive pill: optional leading icon plus a label. Used to
 * mark a card with a fact about itself (which surfaces a widget draws on,
 * whether it came from an external source).
 *
 * Distinct from FilterChip, which looks similar on purpose but is a control:
 * a chip carries selection state and reacts to clicks, a badge is read-only.
 * Keeping them separate stops a badge from growing hover and toggle states it
 * has no use for.
 */
Rectangle {
    id: badge

    property string label
    property string badgeIcon: ""
    property color colBackground: Appearance.colors.colSecondaryContainer
    property color colText: Appearance.colors.colOnSecondaryContainer

    implicitWidth: badgeRow.implicitWidth + Appearance.spacing.space150
    implicitHeight: badgeRow.implicitHeight + Appearance.spacing.space50
    radius: Appearance.rounding.full
    color: badge.colBackground

    RowLayout {
        id: badgeRow
        anchors.centerIn: parent
        spacing: Appearance.spacing.space25

        MaterialSymbol {
            visible: badge.badgeIcon.length > 0
            text: badge.badgeIcon
            iconSize: Appearance.font.pixelSize.small
            color: badge.colText
        }
        StyledText {
            text: badge.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: badge.colText
            // Badge text can come from an installed manifest.
            textFormat: Text.PlainText
        }
    }
}
