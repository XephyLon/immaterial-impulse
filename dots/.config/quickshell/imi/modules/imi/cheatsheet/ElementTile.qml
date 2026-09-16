import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick

RippleButton {
    id: root
    required property var element
    opacity: element.type != "empty" ? 1 : 0
    implicitHeight: 70
    implicitWidth: 70
    colBackground: Appearance.colors.colLayer2
    buttonRadius: Appearance.rounding.small
    // The corner badges' plate, named once: the tile is already layer 2, so
    // the pills sit on a washed-out copy of it rather than a second tone.
    readonly property color colBadge: ColorUtils.transparentize(Appearance.colors.colLayer2)

    // The two corner facts are read-only pills, so they are the shared badge.
    // It also sizes to its label, which the hand-rolled circle did not: a
    // weight wider than its own 20px square used to spill out of the pill.
    Badge {
        anchors {
            top: parent.top
            left: parent.left
            topMargin: Appearance.spacing.space50
            leftMargin: Appearance.spacing.space50
        }
        label: root.element.number
        colBackground: root.colBadge
        colText: Appearance.colors.colOnLayer2
    }

    Badge {
        anchors {
            top: parent.top
            right: parent.right
            topMargin: Appearance.spacing.space50
            rightMargin: Appearance.spacing.space50
        }
        label: root.element.weight
        colBackground: root.colBadge
        colText: Appearance.colors.colOnLayer2
    }

    StyledText {
        id: elementSymbol
        anchors.centerIn: parent
        color: Appearance.colors.colSecondary
        font.pixelSize: Appearance.font.pixelSize.huge
        text: root.element.symbol
    }

    StyledText {
        id: elementName
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom
            bottomMargin: Appearance.spacing.space50
        }
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: Appearance.colors.colOnLayer2
        text: root.element.name
    }
}
